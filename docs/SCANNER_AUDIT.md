# DokoDocs Scanner — Technical Audit

**Type:** analysis only (no code was changed to produce this).
**Date:** 2026-07-05. **Branch:** main. **Scope:** the scan/capture/enhance/save path.

This is a factual audit of what is actually in the codebase today, to ground
future work in evidence rather than assumptions. Every claim cites a file.

---

## 1. Current technology stack (dependencies actually used by the scanner)

| Package | Resolved | Role in the scanner | Notes |
| --- | --- | --- | --- |
| `cunning_document_scanner` | 2.5.0 | **Primary** capture + detection + crop. Wraps Google ML Kit Document Scanner (Android, `SCANNER_MODE_FULL`) and Apple VisionKit (iOS). | Maintained; native, closed-source engines. Only exposes final image paths — no corners/contours/confidence. |
| `camera` | 0.11.4 | **Fallback** custom camera (`camera_scanner_screen.dart`) when ML Kit is unavailable. | Flutter-team plugin. Gives lens control + image stream. |
| `image` | 4.9.1 | All post-capture pixel work: filters, enhancement, perspective warp, PDF image decode. Pure Dart. | The quality ceiling for our own processing (no SIMD/GPU). |
| `image_picker` | 1.2.3 | Gallery multi-select import. | `preferredCameraDevice` hint is unreliable — that's why the old camera fallback opened the front lens. |
| `pdf` | 3.13.0 | PDF assembly (`core/pdf/pdf_builder.dart`). | Runs in an isolate. |
| `pdfrx` | 2.4.4 | PDF viewing. | — |
| `printing` | 5.15.0 | Share/print. | — |
| `permission_handler` | 12.0.3 | Camera permission + rationale. | — |
| `drift` | 2.34.0 | Local DB (documents/pages/folders). | `ocr_text` column exists but is unused (see §7). |
| `share_plus` | 13.2.0 | Share sheet. | — |
| `path_provider` | 2.1.6 | App/temp directories. | — |

**Not present:** no OpenCV, no TensorFlow/ML model files, no OCR engine, no
separate detection SDK. Detection/crop on the primary path is 100% native
(ML Kit / VisionKit).

---

## 2. Current scanner pipeline

```
Home / folder / empty-state  ──►  startScanFlow()            scan_capture.dart
        │
        ▼  unified chooser: single camera | batch camera | gallery
        │
   ┌────┴─────────────────────────────────────────────┐
   │ CAMERA path                                        │ GALLERY path
   ▼                                                    ▼
 CunningDocumentScanner.getPictures()            image_picker.pickMultiImage()
 (ML Kit SCANNER_MODE_FULL / VisionKit:                  │
  live detect + border + crop + perspective)      normalizeImageForPipeline()
   │  success → cropped image paths                (HEIC/odd-JPEG → PNG; skip
   │                                                undecodable) image_normalizer.dart
   │  FAILURE (no Play services / ML Kit):                │
   ▼                                                      │
 CameraScannerScreen  camera_scanner_screen.dart          │
  • strict rear lens, full preview                        │
  • live border: detectDocument() throttled ~350ms       │
    document_detector.dart  (green/orange/red by conf.)   │
  • temporal smoothing (5-frame avg), auto-capture ~700ms │
   │  capture (ResolutionPreset.max, YUV420)              │
   ▼                                                      │
 autoDetectAndCrop()  document_detector.dart (compute)    │
  • FULL-RES re-detect + confidence gate                  │
  • high conf → auto crop+perspective (rectifyDocument)   │
  • else → CropEditorScreen (draggable corners)           │
   │                                                      │
   └───────────────┬──────────────────────────────────────┘
                   ▼
       scanSessionProvider (in-memory pages)   providers/scan_session_provider.dart
                   ▼
       ScanReviewScreen  scan_review_screen.dart
        • reorder / retake / delete / add page
        • per-page filter chip (12 modes) filter_picker.dart
        • crop, rotate, revert
                   ▼
       saveScanSessionAsDocument()  document_builder.dart
                   ▼
       _renderPageIsolate()  core/render/page_renderer.dart  (compute)
        • filter/enhancement (image_enhancer.dart)
        • rotate • corner watermark
        • encode JPEG(q) / PNG
                   ▼
       ExportFormat.pdf → pdf_builder.dart (compute)   or   image files
                   ▼
       drift DB rows (Documents + Pages) + files in app documents dir
```

---

## 3. Camera analysis

- **Primary (ML Kit/VisionKit):** camera config is entirely inside Google/Apple.
  We cannot set resolution/focus/exposure there — by design.
- **Fallback (`camera` pkg):** `camera_scanner_screen.dart` uses
  `ResolutionPreset.max`, `enableAudio:false`, `imageFormatGroup: yuv420`, and
  **explicitly selects `CameraLensDirection.back`** (fixes the earlier front-camera
  bug). Flash Off/Auto/Torch. Autofocus/exposure are the plugin defaults (continuous).
- **Gallery:** `image_picker`, no camera.

---

## 4. Detection analysis

- **Primary:** ML Kit / VisionKit, real-time, native. **The app receives only
  final cropped images — no corner coordinates, no confidence, no contours.**
  This is the single most important architectural constraint (§14).
- **Fallback:** our own `detectDocument()` (`document_detector.dart`), pure Dart:
  downscale → bright/low-saturation mask → extreme-point corners, with
  strict guards (reject full-frame, too-small, low fill-ratio, skewed) and a
  0–1 confidence. Runs live (throttled, on downscaled grayscale from the
  camera stream) **and** on the full-resolution still after capture.

---

## 5. Crop analysis

- **Primary:** native (ML Kit/VisionKit) automatic crop + perspective, plus
  their own manual corner UI.
- **Fallback:** `autoDetectAndCrop()` re-detects on the full-res still and, when
  confident, warps the quad flat via `rectifyDocument()` (`crop_processor.dart`,
  `image.copyRectify` in an isolate) with a ~2.5%/side safety margin.
  `CropEditorScreen` gives draggable corners + live outline + Reset for
  medium/low confidence or gallery images.
- **Confidence gate** (`scan_capture.dart`): high (`≥0.86`) → auto-crop, skip
  editor; medium (`≥0.70`) → auto-crop then editor; low → editor.

---

## 6. Image enhancement

Implemented in `core/render/image_enhancer.dart` (modular, isolate-safe):

- ✅ Illumination/shadow removal (divide by blurred background) — **paper whitening**
- ✅ Adaptive contrast, brightness lift
- ✅ Unsharp-mask text sharpening
- ✅ Saturation (magic mode), grayscale (bw/receipt)
- **12 filter modes** wired: original, grayscale, bw, lighten, enhance,
  high_contrast, warm, auto, magic, color, professional, hd, extreme_clarity,
  receipt, book, bw_text.
- ⚠️ Not implemented as distinct stages: true denoise, histogram equalization,
  gamma curve, white-balance correction (partially approximated by the above).

---

## 7. OCR

- ❌ **Not implemented.** There is only a nullable `ocrText` column reserved for
  a future phase (`core/database/tables/documents.dart`: *"stays null until
  Phase 4 (OCR)"*). No OCR engine, no text recognition dependency.
- **The assumption of "existing OCR" in prior prompts is incorrect.**

---

## 8. PDF generation

- `core/pdf/pdf_builder.dart`, runs in a `compute` isolate.
- Decodes each image once to validate, then embeds bytes via `pw.MemoryImage`.
- Quality inherited from the JPEG produced by `page_renderer` (no second recompress).

---

## 9. Storage

- Files under the app documents directory (`getApplicationDocumentsDirectory`).
- Rendered pages encoded JPEG (quality configurable) or PNG.
- Temp crops/imports written to the temp dir (`autocrop_*`, `crop_*`, `import_*`).
- ⚠️ Temp files are not proactively cleaned up (minor disk hygiene item).

---

## 10. Performance

- Heavy work is off the UI thread: page render, PDF build, crop warp, gallery
  normalize all use `compute` isolates. ✅
- Live detection runs **on the UI isolate** (camera stream buffers aren't
  sendable), but is throttled to ~350 ms on a ~320px grayscale — cheap. ✅
- Known duplicate decode: PDF builder decodes to validate then re-reads bytes;
  minor.
- Not yet profiled with real device timings (would require on-device runs).

---

## 11. UI workflow

Chooser → (native scanner OR fallback camera OR gallery) → review tray
(reorder/retake/delete/add/filter/crop/rotate) → format+name → post-save sheet
(Open/Share/Close). No dead-end screens found; back navigation present throughout.

---

## 12. vs. professional apps (CamScanner / Adobe Scan / Lens / Drive)

| Capability | DokoDocs primary (native) | DokoDocs fallback | Pro apps |
| --- | --- | --- | --- |
| Live detection + border | ✅ (ML Kit/VisionKit) | ✅ (our detector) | ✅ |
| Auto-capture | ❌ (native decides) | ✅ (~700ms stable) | ✅ |
| Perspective correction | ✅ native | ✅ ours | ✅ |
| Crop refinement | ✅ native | ✅ full-res re-detect | ✅ |
| Enhancement/filters | ✅ our layer | ✅ our layer | ✅ |
| OCR | ❌ none | ❌ none | ✅ |
| Detection quality | ✅ best-in-class | ⚠️ modest (pure Dart) | ✅ |

---

## 13. GitHub comparison (ideas only — no code copied)

- **jachzen/cunning_document_scanner** — this *is* our capture layer; kept as-is.
- **ishaquehassan/document_scanner_flutter** — inspired the multi-mode filter set
  and post-capture editing UX, re-implemented in `image_enhancer.dart` /
  `filter_picker.dart`. Its detection is comparable-tier to our fallback; not
  worth swapping in.

---

## 14. Limitations, separated by cause

**Caused by ML Kit / VisionKit (closed-source, cannot change):**
- Cannot customise the native green border, edge detector, or auto-capture on the
  primary path. The app only receives final images — **no corners/confidence** —
  so we can't refine the native crop or drive a custom border there.

**Caused by the pure-Dart `image` package (our processing):**
- No GPU/SIMD → per-pixel ops are CPU-bound; large-radius blur is approximated on
  a downscaled copy. Fine for save-time, too heavy for 60fps live processing.

**Caused by current implementation (fixable without new tech):**
- Fallback detector is a simple bright-mask heuristic → modest accuracy on
  white-on-white / busy backgrounds; live overlay mapping unverified across
  device orientations. Temp-file cleanup absent. No real device profiling yet.

**Genuinely needs different CV tech (only if required):**
- Best-in-class *custom* live edge detection on the fallback path (to match ML
  Kit when Play Services is absent) would need OpenCV or an on-device ML model —
  explicitly out of scope per project constraints.

---

## 15. Improvement opportunities (prioritised, no rewrite)

**Can be improved immediately (no architecture change):**
- Temp-file cleanup after save; profile on a real device; tune enhancement params.

**Moderate refactor (no package replacement):**
- Extract enhancement params to a config object; unify the two fallback
  capture call-sites; add golden tests for filter output.

**Scanner-module extension (still Flutter):**
- Improve the fallback detector (gradient/edge-based instead of bright-mask;
  quadrilateral fitting) — bounded, self-contained.

**Requires new technology (only if truly needed):**
- OpenCV / on-device ML for CamScanner-grade detection **on the fallback path
  only**. Not recommended unless devices without Play Services are a priority
  segment — the native path already meets the bar where it's available.

---

## 16. Performance post-mortem — why 3 pages take ~90 s (evidence)

A two-agent code trace confirmed the slowness is **implementation, not ML Kit**:

1. **Sequential, UI-blocking save.** `document_builder.dart` rendered pages in a
   `for` loop, each `await`ed; the review screen held a spinner until render-all
   + PDF + DB finished. `compute` spawns an isolate per page, but serial `await`
   meant only one ran at a time.
2. **Wasted second full decode per page.** `pdf_builder` decoded each page image
   in full **only to read width/height**, then discarded it (the PDF embeds the
   raw JPEG bytes).
3. **Logo re-decoded per page** in the render isolate.
4. **Fallback path double-processes:** `_captureWithCustomCamera` awaited a
   full-res decode + `autoDetectAndCrop` **per page before the camera reopened**;
   save then decoded full-res again. (Native ML Kit returns all pages at once —
   fast.)
5. **OCR is not in the pipeline** (unimplemented) — not a bottleneck.

### Phase 2 changes applied (this pass)
- **Bounded-parallel render** (`_mapBounded`, cap `kMaxRenderConcurrency = 3`) in
  `document_builder.dart` for both PDF and image save paths — real parallelism
  via the existing per-page isolates, order preserved, memory bounded.
- **`renderPage` returns `RenderedPage{path,width,height}`**; new
  `buildPdfFromSources` sizes pages from those dims → **eliminates the second
  decode** on the save path. Path-only `buildPdfFromImages` retained for editor/
  version/merge callers.
- **Fallback-path SnackBar** ("Using built-in camera…") so the active scanner
  path is visible.
- Tests: 3-page order under parallel render (`scan_pipeline_test`), PDF dims path
  (`pdf_builder_test`).

**Still deferred to Phase 3:** returning the camera immediately and processing
in the background (the per-page fallback capture blocking, finding #4) — a
UX/architecture change, out of scope for this low-risk perf pass.

## 17. Phased roadmap

| Phase | Scope | Complexity | Risk | Expected gain |
| --- | --- | --- | --- | --- |
| 1 Audit | this document | — | — | evidence-grounded decisions |
| 2 Optimize (done) | parallel save, kill duplicate decode, path diagnostic | Low–Med | Low | save time cut substantially, no ML Kit change |
| 3 Modularize | camera returns immediately; background processing; per-page progress | Med | Med | perceived-instant capture |
| 4 Replace only fallback detection | OpenCV / on-device ML for the fallback path | High | Med–High | CamScanner-grade edges without Play Services |
| 5 Professional | multi-frame HDR, advanced shadow removal, OCR phase | High | High | full feature parity |

## Final recommendation

The current stack is sound and should be **maximised, not rewritten**. The
primary (ML Kit/VisionKit) path already matches professional apps for detection,
crop, and perspective. Our biggest realistic wins are (1) enhancement/filter
tuning and (2) improving the *fallback* detector — both inside the existing
architecture. The only hard ceiling is native detectors being closed-source
(can't refine their crop) and the pure-Dart processing being CPU-bound; neither
justifies replacing the scanner. The one genuine feature gap vs. pro apps is
**OCR**, which is already planned as a later phase, not a scanner concern.
