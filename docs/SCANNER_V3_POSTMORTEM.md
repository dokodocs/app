# Scanner V3 — Phase 0 Postmortem

**Date:** 2026-07-06. **Status:** audit complete; instrumentation landed.
**Companions:** `docs/SCANNER_AUDIT.md` (V1), `docs/SCANNER_V2_PLAN.md` (V2).

Client complaints: single scans lag; multi-page scanning is painfully slow;
UI/UX below expectations. This document maps the real V2 data flow, verifies
each suspected root cause **in code**, and records the baseline.

## Baseline

- `flutter analyze`: clean. Test suite: **31/31 pass**.
- `ScanPerf` instrumentation added (`lib/core/perf/scan_perf.dart`), wrapping:
  live loop (`live.gray`, `live.rotate`, `live.pngEncode`,
  `live.detectIsolate`), per-page post-capture (`page.read`, `page.decode`,
  `page.detectCv`, `page.warpCv`), render (`render.total`, `render.decode`,
  `render.enhanceCv`, `render.redecodeCv`, `render.enhanceDart`,
  `render.encode`), and `save.pdfBuild`. Toggle: `ScanPerf.enabled`
  (auto-on outside release). `ScanPerf.dump()` gives per-stage n/avg/last.
- **On-device numbers pending** — no Android device/emulator attached to this
  workstation. The instrumentation prints `[ScanPerf] stage: Nms` on the next
  profile run; the cost analysis below is code-verified (what runs, on which
  thread, how many codec passes) rather than wall-clock-measured.

## Actual data flow (as implemented today)

### Live detection (camera_scanner_screen.dart `_onFrame`)
1. Throttle to ≥350 ms between frames (≈2.8 fps detection ceiling).
2. `grayscaleFromCameraImage` — Y-plane subsample to ~320 px (UI thread).
3. `img.copyRotate` by sensor orientation (UI thread).
4. **`img.encodePng(gray)` on the UI thread**.
5. `compute(detectQuadCvForIsolate, png)` — **spawns a fresh isolate per
   frame**, which `cv.imdecode`s the PNG (a second codec pass), then
   blur → auto-Canny → morph-close → contours → approxPolyDP.
6. Normalise, smooth (5-frame rolling average), setState.

### Single capture (scan_capture.dart `_autoCropOrEdit`)
1. `takePicture()` at full resolution (now `ultraHigh`).
2. `compute(autoDetectAndCrop, …)` — new isolate: read file, `img.decodeImage`
   (full-res, pure Dart), `detectDocumentCvBytes` (decodes the *same bytes
   again* in OpenCV), warp via `warpQuadCv` (third decode of the source, then
   JPEG encode #1).
3. Review screen → save → `renderPage` in another fresh isolate: read + decode
   (pure Dart, #4), filter (`enhanceBytesCv` = OpenCV decode #5 + encode #2,
   then `img.decodeImage` of that output, #6), rotate/watermark (pure Dart),
   `img.encodeJpg` (pure Dart, encode #3), write.
4. PDF build embeds the JPEG (no re-encode — already good).

**A single page passes through up to 6 decodes and 3 encodes across 3+
short-lived isolates**, with the pure-Dart `image` codec (no SIMD) doing the
most expensive full-res passes.

### Batch capture
- Camera stays open per shot (good), **but nothing processes during
  capture**: after "Done", `_captureWithCustomCamera` runs `_autoCropOrEdit`
  **sequentially, awaited, one page at a time** before the review screen even
  opens. Ten pages ≈ ten full-res detect+warp cycles back-to-back on exit —
  exactly the "painfully slow multi-page" complaint.
- Save then re-renders every page (bounded parallel ×3, still full pure-Dart
  decode/encode per page).

## Suspected causes — verdicts

| # | Suspicion | Verdict | Evidence |
|---|---|---|---|
| 1 | Live loop PNG-encodes then re-decodes | **CONFIRMED** | `_onFrame`: `img.encodePng` (UI thread) → `detectQuadCvForIsolate` → `cv.imdecode`. Pure-Dart PNG encode of a ~320px image plus decode, ~3×/s, plus per-frame isolate spawn. Explains preview stutter + laggy overlay. |
| 2 | Full-res enhancement on pure-Dart `image` | **CONFIRMED (partial)** | Scan modes go through OpenCV (`enhanceBytesCv`, capped 2600px) — but plain filters, rotation, watermark and the **final JPEG encode** are pure Dart at full working res; and the CV path pays encode→re-decode to get back into `img.Image`. |
| 3 | Multi-page sequential/blocking | **CONFIRMED** | `_captureWithCustomCamera`: `for (final shot in shots) { await _autoCropOrEdit(...) }` after Done; zero processing overlap with capture. |
| 4 | Stages exchange encoded bytes | **CONFIRMED** | Up to 6 decodes / 3 encodes per page (trace above). Encoding should happen exactly once. |
| 5 | Per-call `compute()` isolates | **CONFIRMED** | `compute` in `_onFrame` (per frame!), `_autoCropOrEdit`, `renderPage`. No long-lived worker, no `TransferableTypedData`; PNG bytes are copied across the isolate boundary each frame. |

### Symptom mapping
- "Single scan lags": causes 2+4 (redundant full-res codec passes at capture
  and again at save) + cause 5 (isolate spawn latency per step).
- "Multi-page painfully slow": cause 3 (sequential post-capture wall) on top
  of 2/4/5 per page.
- "Scanner feels unresponsive / overlay laggy": cause 1 (UI-thread PNG encode,
  350 ms throttle, per-frame isolate spawn) — worsened before this week by the
  orientation/cover-fit overlay bugs (fixed 2026-07-06).

## Already fixed during this audit window (pre-V3)
- Overlay orientation (sensor rotation) + BoxFit.cover mapping.
- 2600 px render cap on all filter paths; capture preset `max → ultraHigh`.

## Phase 1 — DONE (2026-07-06): hot-path rewrite

Behind `kUseScannerV3` (`lib/core/flags.dart`, compile-time const, default on;
flip to false → V2 path, dead branch tree-shakes).

- **`lib/core/cv/cv_worker.dart`** — ONE long-lived OpenCV worker isolate per
  camera session. Raw grayscale frames travel via `TransferableTypedData`
  (zero-copy). Latest-only mailbox: ≤1 in flight + ≤1 queued; a newer frame
  replaces the queued one (superseded futures resolve null). No wall-clock
  throttle — detection self-paces to device speed.
- **`grayBytesFromCameraImage`** (camera_frame_utils.dart) — subsampled ~500px
  raw gray bytes straight from the Y plane / BGRA, no `img.Image`, no codec.
- **`detectDocumentCvGray`** (document_detector_cv.dart) — builds the Mat
  directly from raw bytes (`Mat.fromList`, CV_8UC1), rotates natively by
  sensor orientation (`cv.rotate`), runs the shared quad pipeline
  (`_detectQuadOnGrayMat`, also now backing `detectDocumentCvBytes`).
- **Scanner screen** — `_onFrameV3` (worker path) vs `_onFrameLegacy`
  (V2: 350 ms throttle + UI-thread PNG + per-frame compute). Shared
  `_applyDetection` for smoothing/stability/auto-capture. `RepaintBoundary`
  around the overlay painter so quad repaints never invalidate the preview.
- **Eliminated per frame:** UI-thread PNG encode (pure Dart), PNG decode
  (OpenCV), isolate spawn+teardown, PNG byte copy across the boundary, and
  the 350 ms cap (~3 fps → worker-paced 10–15+ fps expected).
- **Tests:** `test/cv_worker_test.dart` — gray detector (page found, uniform
  null, 90° rotation space), worker round-trip, rotated dims, latest-only
  supersession, dispose safety. CV-dependent cases skip on hosts without the
  dartcv native library (discovered: `dartcv.dll` absent on the Windows dev
  host — meaning host tests never exercised OpenCV; they run on-device/CI).
  Suite: 32 pass / 6 skip; analyze clean.
- **On-device verification pending** (no device attached): confirm
  `[ScanPerf] live.*` timings, overlay tracking rate, auto-capture behaviour.

## What V3 must change (feeds Phase 2+)
1. ~~Kill all codecs in the live loop~~ — DONE (Phase 1, above).
2. ~~Capture-first queue~~ — DONE (Phase 2, below).
3. ~~One decode, one encode per page~~ — DONE (native render path, below).
4. Per-call `compute` for FULL-RES jobs (crop/render) remains — acceptable:
   these are seconds-apart one-shots, not per-frame; the live loop uses the
   persistent worker.

## Phase 2 — DONE (2026-07-06): capture-first pipeline + queue

- Capture (single/batch/add/retake/gallery) returns RAW paths immediately;
  full-res re-detect + `warpPerspective` crop runs in the BACKGROUND
  (`autoCropSessionPagesInBackground`), swapping each page in place when
  ready. Path-keyed (`replacePath`) so delete/reorder mid-crop can never
  touch the wrong page (unit-tested: supersede, delete, reorder races).
- `ScanPage.processing` drives a per-thumbnail spinner badge; save waits for
  in-flight crops (bounded 20 s) then re-reads the session.
- Crop-editor stop REMOVED from the flow; manual crop remains as an action.
- Auto-capture OFF by default; 5-consecutive-consistent-frames gate; status
  pill only from medium confidence.

## Detection rebuild — DONE (see docs/DETECTION_POSTMORTEM.md for the full
trace-driven history)

Scored candidate system over three sources (median auto-Canny+close, Otsu
OPEN, centre/tap-seeded fixed-range flood fill), hard filters (area 5–95%,
convexity w/ hull retry, angles 62–118°, opposite-sides ≤3, rectangularity
≥0.6 with minAreaRect snap for occluded corners), five-factor scoring (edge
support w/ ±2px tolerance, rectangularity, |brightness| contrast, interior
uniformity, log-area; card-sized candidates reweighted), graduated border
penalty, cornerSubPix corner refinement (≤2% drift), honest confidence
(high 0.65 / medium 0.50), JSON trace sink + offline harness
(`test/detection_harness_test.dart` → `docs/detection_results/`).

**Tap-to-target** (client request "only draw the green in that object"):
tapping the preview seeds the flood fill at that point and multiplies
candidate scores ×1.25 if they contain the tap / ×0.25 if not; 5 s lifetime;
green ring feedback. This is the reliable path for small cards/licenses on
cluttered desks.

## Save pipeline — DONE (2026-07-06)

- **Root-cause crashes:** two native double-frees in the enhancer (`out =
  sharp` alias + VecMat/channel double dispose) — latent for months, only
  fired once real natives shipped. Fixed; all CV files audited for aliases.
- **Native render fast path** (`renderDocumentCv`): decode → 2600px cap →
  filter → rotate → watermark → JPEG entirely in OpenCV. The pure-Dart
  pipeline (12 MP Dart decode + Dart JPEG encode ≈ 20 s/page on budget
  hardware — the ">2 min for 5 pages" complaint) survives only as the
  fallback for legacy filters and PNG export.
- **One-step UX:** no save button, no format/name dialogs — capture →
  background crop → auto-save as PDF (`dokodocs_<ts>`) → the PDF opens
  directly (brief spinner while crops+save finish). Render concurrency 2
  (3 GB RAM budget).

## Root cause #0 of everything (found late, fixes all on-device history)

The APK NEVER contained the OpenCV natives: the project depended on
`dartcv4` (pure-Dart bindings, no bundled `.so`) instead of `opencv_core`.
Every `cv.*` call on-device threw and fell back to weak pure-Dart paths.
Swapped to `opencv_core ^1.4.5` + forced library compileSdk 36; verified
`libdartcv.so` in the APK. Full detail: `docs/DETECTION_POSTMORTEM.md`.

## Current status vs the V3 targets

| Target | Status |
|---|---|
| 60 fps preview, zero codec in live loop | Done (worker isolate, raw Y-plane, latest-only mailbox) |
| Live detection ≤30 ms | ~17–23 ms at work res on desktop; device numbers via ScanPerf HUD pending |
| Shutter → next shot ≤150 ms perceived | Done (raw path returns instantly, crops backgrounded) |
| Full-res warp+enhance+encode ≤1.5 s | Native end-to-end; measure on device |
| 20-page PDF ≤1 s | PDF embeds pre-encoded JPEGs (no re-encode) |
| OCR ≤2 s/page | NOT STARTED (Phase 4) |

## Remaining / next

- **ML segmentation hybrid (Step 3 / Phase 3):** bundled TFLite doc-seg
  model for automatic (no-tap) detection of cards in clutter — the one
  scenario classical CV cannot fully solve. Tap-to-target covers it today.
- Phase 4: OCR (bundled), undo/redo, annotations, PDF encryption.
- Phase 5 polish: skeleton loaders, guidance text l10n, Hero transitions.
- On-device ScanPerf numbers for the targets table; iOS on-device
  validation (BGRA frame path compiles, untested on hardware).
- Watermark on the native path is text-only (Hershey); logo bitmap remains
  in the Dart fallback — unify if the logo matters.
