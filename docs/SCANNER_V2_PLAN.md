# DokoDocs Scanner V2 — World-Class, Self-Owned Pipeline

**Status:** plan / design. **Date:** 2026-07-05.
**Companion:** `docs/SCANNER_AUDIT.md` (V1 audit + root causes).

---

## Why V2 exists

V1 delegates capture + detection + crop to **ML Kit (Android) / VisionKit
(iOS)** via `cunning_document_scanner`. That is excellent *where it runs* — but
on the user's device the native scanner **never loads** ("device scanner
unavailable → built-in camera"), even after adding the
`com.google.mlkit.vision.DEPENDENCIES=docscanner` manifest declaration. Root
cause is environmental: **no working Google Play Services** (emulator without
Play Store, or a de-Googled/China ROM device). No app-side change can make ML
Kit run there.

The V1 pure-Dart fallback detector is intentionally conservative and CPU-bound
(the `image` package has no SIMD/GPU), so it can't match CamScanner.

**V2 owns the whole vision pipeline** so the experience is identical on every
Android and iOS device, online or offline, Play Services or not.

### Guiding principles
1. **Own the pipeline** — camera, detection, crop, enhancement are ours.
2. **Uniform everywhere** — no dependence on ML Kit/VisionKit availability.
3. **Zero regressions** — every current feature keeps working (matrix below).
4. **Off the UI thread** — all CV/heavy work in isolates; 30–60 fps preview.
5. **Incremental** — ship behind a flag; keep V1 native as an optional turbo.

---

## Technology decision

| Concern | V1 (now) | **V2 (proposed)** | Why |
| --- | --- | --- | --- |
| Camera | `cunning_document_scanner` native UI + `camera` fallback | **`camera`** (single path, full control) | lens/res/focus/exposure/torch + frame stream, both OSes |
| Edge detection | ML Kit/VisionKit (closed, unavailable here) + weak Dart fallback | **`opencv_dart`** (OpenCV via FFI, C++) | fast, offline, no Play Services, both OSes; Canny+contours+quad |
| Perspective / warp | native + `image.copyRectify` (slow) | **OpenCV** `getPerspectiveTransform` + `warpPerspective` | accurate, fast, sub-pixel |
| Enhancement | pure-Dart `image` (CPU-bound) | **OpenCV** (adaptive threshold, CLAHE, denoise, sharpen) + keep `image` for simple ops | orders of magnitude faster, better quality |
| OCR (future) | none | Tesseract (`flutter_tesseract_ocr`) or ML Kit text when present | optional later phase |
| Native "turbo" | primary | **optional**: use ML Kit/VisionKit when available for capture, else OpenCV | best of both, but never *required* |

**Primary new dependency:** `opencv_dart` (a.k.a. `opencv_core`) — prebuilt
OpenCV binaries + Dart FFI bindings, cross-platform, actively maintained.

**Rejected alternatives:** commercial SDKs (Dynamsoft, Scanbot) — excellent but
paid/licensed, against the app's free/open-source core. A hand-written Dart CV
stack — too slow. Staying on ML Kit-only — the exact failure we're fixing.

---

## V2 pipeline (data flow)

```
camera (rear, max res, continuous AF/AE)     [camera pkg]
      │  image stream (throttled ~15–20 fps for detection)
      ▼
frame → grayscale → blur → Canny → dilate     [opencv_dart, isolate]
      ▼
find contours → largest 4-point convex quad → order corners
      ▼
temporal smoothing (Kalman/rolling avg) + confidence score
      ▼
live overlay: green(≥high)/orange(med)/red(low) + "hold steady"   [Flutter CustomPaint]
      ▼
AUTO-CAPTURE when quad stable ~600–800 ms   (toggle)
      │  full-resolution still
      ▼
FULL-RES re-detect corners (OpenCV)  →  refine  →  safety margin
      ▼
warpPerspective (deskew, flatten, correct rotation)   [OpenCV]
      ▼
enhancement (per scan mode):                          [OpenCV, isolate]
   illumination/shadow removal (divide by blurred bg / CLAHE)
   → adaptive threshold (B&W/receipt) OR white-balance+saturation (color/magic)
   → denoise (fastNlMeans / bilateral) → unsharp mask → gamma
      ▼
MULTI-PAGE TRAY (continuous): thumbnail added, camera stays open   ← fixes "bounce"
      ▼
review: reorder / retake / delete / per-page mode / manual crop (draggable corners)
      ▼
export: parallel render → PDF (dims-based, no re-decode) / JPEG / PNG   [already done, V1 Phase 2]
      ▼
(optional) OCR text layer → drift DB `ocr_text`
      ▼
storage + DB rows (Documents/Pages/Folders)   [unchanged]
```

Key UX change vs V1: **the camera stays open across pages** (multi-shot), so a
multi-page scan is one continuous journey — no returning to the dashboard
between pages (the current fallback bounce).

---

## Feature-preservation matrix (nothing regresses)

| Current feature | V2 status |
| --- | --- |
| Single / batch camera capture | ✅ own camera, continuous multi-shot |
| Gallery import (multi, HEIC-safe) | ✅ unchanged (`image_normalizer`) |
| Auto edge detection + crop | ✅ OpenCV (works without Play Services) |
| Manual crop editor (draggable corners) | ✅ kept; seeded by OpenCV corners |
| Perspective correction | ✅ OpenCV warp |
| Scan modes / filters (Auto/Magic/…) | ✅ re-implemented on OpenCV, same chip UI |
| Rotate / revert / reorder / retake / delete | ✅ unchanged (session provider) |
| Watermark | ✅ unchanged (render pipeline) |
| PDF / JPEG / PNG export | ✅ unchanged (V1 Phase-2 parallel path) |
| Signatures, versions, merge, share, search, history | ✅ unchanged |
| Localization (en/ne), dual calendar | ✅ unchanged |
| Native ML Kit/VisionKit | ✅ optional turbo when available, no longer required |
| OCR | ➕ new optional phase (was never implemented) |

---

## Phased implementation

Each phase is independently shippable behind a `useScannerV2` flag; V1 remains
the default until V2 is verified on-device.

| Phase | Deliverable | Complexity | Risk | Gain |
| --- | --- | --- | --- | --- |
| **V2.0 Foundation** | add `opencv_dart`; wire Android (CMake/NDK) + iOS (pod) FFI build; isolate wrapper; smoke test a Canny call | Med | **Med** (native build/size) | CV available offline both OSes |
| **V2.1 Detection engine** | pure-function `detectQuad(bytes)`: gray→blur→Canny→contours→quad→order; unit-tested on sample images; confidence score | Med | Low | accurate corners, no Play Services |
| **V2.2 Live camera** | integrate into `camera_scanner_screen`: stream→isolate detect→smoothed overlay→auto-capture; orientation-correct mapping | High | Med | CamScanner-style live border |
| **V2.3 Full-res + warp** | full-res re-detect + OpenCV `warpPerspective`; safety margin; confidence-gated auto vs manual | Med | Low | precise deskewed crop |
| **V2.4 Enhancement** | OpenCV scan modes (CLAHE, adaptive threshold, denoise, sharpen); map existing filter keys | Med | Low | pro image quality, faster than Dart |
| **V2.5 Continuous multi-shot** | camera stays open; thumbnail strip; Done button; per-page background processing | Med | Med | one continuous scanning journey |
| **V2.6 Native turbo (opt)** | use ML Kit/VisionKit when present for capture, else V2 engine | Low | Low | best quality where available |
| **V2.7 OCR (opt)** | Tesseract/ML-Kit-text → `ocr_text`; search integration | Med | Med | searchable scans |

---

## Risks & mitigations

- **Binary size.** OpenCV adds ~15–40 MB per ABI. The APK is already ~100 MB
  (universal). Mitigate: ship **per-ABI split APKs / an app bundle** (Play does
  this automatically); the user downloads one ABI (~40–50 MB).
- **Native build complexity.** `opencv_dart` needs NDK/CMake (Android) and a pod
  (iOS). Mitigate: pin versions; document the build; keep the CI macOS job.
- **iOS parity.** Verify OpenCV FFI + camera stream formats (BGRA) on iOS
  early (V2.0/V2.2). The macOS CI + a real iPhone are required to validate.
- **Frame throughput.** Convert camera `CameraImage` (YUV/BGRA) → Mat
  efficiently; downscale for detection; run in an isolate. Cap detection to
  ~15–20 fps; keep preview at full fps.
- **Regression.** Ship behind `useScannerV2`; keep V1 path until parity is
  proven; the existing test suites stay green throughout.

---

## Success criteria (parity with CamScanner / Adobe Scan / Lens)

- Accurate live edge border, stable (no flicker), on any device — **no Play
  Services required**.
- Auto-capture on stability; auto-crop + perspective with no clipped content.
- Manual crop only when confidence is low.
- Clean, uniform, shadow-free, sharp output; multiple pro scan modes.
- Continuous multi-page journey (camera stays open).
- All current features intact; works on Android **and** iOS.

---

## Immediate next step (if approved)

Start **V2.0**: add `opencv_dart`, get a trivial OpenCV call (e.g. `cvtColor`)
running in an isolate on both a real Android device and iOS, and confirm
APK/IPA build + size impact. That single spike de-risks the whole plan before
we touch the camera UI. Everything after builds on a proven native-CV
foundation.

Sources: opencv_dart real-time edge detection guide
(medium.com/@kishansakariya0000), Dynamsoft/Scanbot offline Flutter scanner
techblogs, Flutter Gems document-scanner list.
