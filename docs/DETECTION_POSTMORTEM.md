# Detection Postmortem — wrong quads, broken PDF pages (2026-07-06)

Observed on device: live border locks onto a KEYBOARD at 75–88% confidence,
quads touch the frame border, exported PDF has uncorrected/tilted pages and
washed-out illegible pages (~2 of 6 acceptable). Detect time 61–77 ms.

## Root cause #0 (the big one): OpenCV natives were NEVER in the APK

Proven by unzipping the shipped APK: **no `libdartcv.so`** under `lib/<abi>/`.
The project depended on **`dartcv4`** — the pure-Dart FFI *bindings* package,
which does NOT bundle native libraries in a Flutter app (that's the job of
`opencv_core`/`opencv_dart`). First proof came from host tests:
`Failed to load dynamic library 'dartcv.dll'` — the same failure happens on
every Android device.

Consequence: **every `cv.*` call ever made on a device threw immediately**
and was swallowed by the defensive `catch` blocks, silently falling back to:

| Stage | Intended (OpenCV) | What ACTUALLY ran on device |
|---|---|---|
| Live detection | auto-Canny + contours + quad | pure-Dart `detectDocument` (weak) |
| Full-res re-detect at capture | `detectDocumentCvBytes` | pure-Dart again |
| Perspective warp | `warpPerspective` | pure-Dart bilinear `copyRectify`, or skipped |
| Enhancement | CLAHE/unsharp/adaptive | pure-Dart `enhanceDocument` → washed-out text |

This explains the 61–77 ms live "detect" (pure-Dart pipeline + per-call
isolate), keyboard lock-on (the Dart detector), destroyed text (Dart
enhancer), and tilted pages (low-confidence → warp skipped, or editor
skipped).

**Fix:** `dartcv4` → **`opencv_core ^1.4.5`** (same API, re-exports dartcv;
bundles natives). Gradle: opencv_core hardcodes compileSdk 33 → forced
library subprojects to compileSdk 36 in `android/build.gradle.kts`
(`checkReleaseAarMetadata` fix). **Verified: `libdartcv.so` (21.4 MB
arm64) now present in the APK** (155.4 MB vs 91.9 — expected: split ABIs or
app-bundle for store delivery).

## Root cause #1: candidate ranking rewarded ANY rectangle

Old rule: *largest 4-point contour wins*; confidence = `0.35 floor +
0.5·rectangularity + 0.15·area`. A keyboard is a large, perfectly
rectangular contour → 75–88% "confidence". No border-touch rejection, no
angle checks, no evidence the quad actually looks like a *document*.

**Fix (implemented, Step 2):** scored candidate system in
`_detectQuadOnGrayMat`:
- Two candidate sources: median-based auto-Canny + morph-close contours, AND
  Otsu bright-region contours (catches low-contrast paper whose outline
  breaks).
- Hard rejections: corner within 2% of border · area outside 15–95% · not
  convex (ε sweep 1.5→5% of perimeter) · interior angle outside 55–125° ·
  opposite-side ratio > 3.
- Score = 0.30·edge-support (perimeter samples on the closed edge map)
  + 0.15·rectangularity (area/minAreaRect) + 0.20·brightness (inside mean −
  ring-outside mean) + 0.20·interior uniformity (low raw-Canny density
  inside) + 0.15·log-scaled area. **Confidence IS this score.**
- Keyboard loses on brightness (not brighter than surroundings), uniformity
  (interior is wall-to-wall edges) and edge support at the paper boundary.
- Thresholds recalibrated: high 0.65, medium 0.50 (`document_detector.dart`).
- Stability: auto-capture now additionally requires **5 consecutive frames**
  with total corner drift ≤ 0.08 normalised (`_consistentFrames` gate) on
  top of the 700 ms timer.
- JSON trace: `detectionTraceSink` records every candidate's factor
  breakdown + winner (used by `test/detection_harness_test.dart`, which dumps
  per-image `.trace.json` + `summary.json` into `docs/detection_results/`).

## Root cause #2: live-loop latency

The 61–77 ms measured on device was the LEGACY path (per-frame PNG encode on
the UI thread + fresh isolate + PNG decode) *plus* pure-Dart detection due to
cause #0. The V3 path (already shipped): Y-plane → raw bytes →
`TransferableTypedData` → long-lived worker → `Mat.fromList` — zero codecs,
zero spawns. With real OpenCV natives this is expected within the 30 ms
budget; measure via the `[ScanPerf] live.*` prints / debug HUD.

## Root cause #3: destructive enhancement

Even the OpenCV path (had it run) pushed `convertScaleAbs(alpha≈1.1, beta=4)`
— clipping bright paper to white — and used fixed 15/21 px adaptive-threshold
blocks (far too small at 2600 px working size → faint strokes eaten).

**Fix (implemented, Step 4):** default modes are now non-destructive:
gray-world **white balance** → **illumination normalisation** (divide by
heavy Gaussian background, scale 235) → **CLAHE on luma only** (YCrCb) →
**mild unsharp**. NO brightness push, NO thresholding outside explicit
B&W/Receipt — and those now do shadow-removal first, block size ≈ width/20
(odd), C 9–12, median despeckle.

## Capture→warp path (verified OK, now armed correctly)

`autoDetectAndCrop` already re-detects on the FULL-RES still and only warps
when confidence ≥ medium; below that the manual crop editor opens seeded
with the best guess. With the old dishonest confidence, garbage quads passed
the gate; with the honest score they can't. PDF embeds rendered JPEGs
without re-encoding (dims carried through `RenderedPage`).

## Harness results on real fixtures (2026-07-06, host with natives)

6 user-supplied images (scanner-UI screenshots of the keyboard/notebook desk
scene) in `test/fixtures/detection/`. To run the harness on Windows, put the
prebuilt natives on PATH first (download `libdartcv-windows-x64-vs2022.tar.gz`
from github.com/rainyl/dartcv releases, tag = `dartcv_version` in
opencv_core's pubspec):
`$env:PATH = "<extracted>\lib;$env:PATH"; flutter test test/detection_harness_test.dart`

Iterations driven by the JSON traces:
1. 0 candidates everywhere → min-area 15% too strict (overlapping notebook
   fragments the page contour) → lowered to 8%.
2. Otsu source: morph-CLOSE fused page+notebook+papers into one
   border-touching mega-blob → switched to morph-OPEN.
3. Every surviving candidate died on the border filter (the blob physically
   extends off-frame; also a page legitimately filling the frame would die
   too) → border touch is now a SOFT ×0.65 penalty: can seed the manual
   editor, can never reach auto-capture.

Outcome: 3/6 detect at 0.43–0.47 (honestly LOW — below medium 0.50 → manual
editor, no green, no auto-warp); 3/6 no quad (→ editor with no seed). The
page never forms its own contour in these scenes: a notebook lies ON it and
white papers run to the frame edge — the physically-merged-region case that
classical CV cannot separate. Synthetic clean-page tests score >0.7 green.
Detect time 17–23 ms/image. **This is the concrete case for Step 3 (ML
segmentation hybrid).** Note the fixtures are phone-UI screenshots, which
worsen merging (white buttons); raw camera photos wanted for a fair set.

## Round 2 — 19 RAW camera fixtures (docs, ID card, license, attendance sheet)

Trace-driven iterations:
4. Real page won with perfect interior (brightness 1.0, uniformity 0.88) but
   edge support 0.34 — paper edges are wavy/bent, single-pixel sampling
   missed them → **±2px neighbourhood sampling** at each perimeter sample.
5. Attendance sheet's contour merged with an adjacent paper → never 4-point
   → **convex-hull retry** before giving up on a contour.
6. ID card contour = 6.7% of frame, under the 8% floor → **floor lowered to
   5%**.
7. Real documents grazing the frame edge (1–2 corners) were crushed by the
   flat ×0.65 border penalty → **graduated penalty** (1 corner ×0.9,
   2 ×0.8, ≥3 ×0.6). A verified wrong quad (keyboard/monitor region) scores
   0.32–0.40 on interior factors alone — the honesty holds without the
   sledgehammer.

**Result: 19/19 detected, 20–50 ms each.** Clean shots 0.84–0.87 (green,
auto-capture); partially-merged scenes 0.49–0.63 (auto-crop + editor);
heavily cluttered/merged 0.33–0.46 (editor, correctly never green). The
remaining low scorers are the physically-merged cases — Step 3 ML
segmentation is the lever for those.

## Round 3 — on-device screenshots of the V3 scanner (2026-07-06 11:43)

Device screenshots confirmed the honest pipeline live (red border, conf 38%,
no false green) but the quad still missed the page. Trace-driven fixes:
8. Pale wooden desk ≈ paper brightness → global Otsu can't separate them →
   added **candidate source 3: centre-seeded flood fill** (5 seeds around
   frame centre — the document is where the user aims). FIXED_RANGE ±25
   (neighbour-diff leaked across the blurred page→desk boundary).
9. floodFill marks the mask's 1-px rim internally → contouring the raw mask
   returned ONE whole-mask component (area 1.005) and every flood candidate
   was silently area-rejected → cut the rim ROI + threshold >127 before
   contouring (also re-aligns the +1 mask offset).
10. Deep-copy the winning contour out of the GC-eligible VecVecPoint.

**Result:** document-fills-frame screenshots score **0.84–0.87 (green,
auto-capture)** via the flood source — edge support 0.83–0.88,
rectangularity 0.94. Page-runs-off-frame scores 0.47 (honest → editor).

## Status / remaining

- [x] Natives bundled (verified in APK) — **retest on device first**, it
  changes everything.
- [x] Scored candidate selection + hard filters + honest confidence.
- [x] 5-consecutive-frame stability gate.
- [x] Non-destructive enhancement defaults; B&W param fixes.
- [x] Harness + JSON traces (`test/detection_harness_test.dart`; put device
  photos in `test/fixtures/detection/`).
- [ ] ML segmentation hybrid (tflite_flutter + bundled doc-seg model) —
  next phase if the rebuilt classical detector still struggles on cluttered
  scenes after on-device validation.
- [ ] On-device numbers for the targets table (no device on this
  workstation).
