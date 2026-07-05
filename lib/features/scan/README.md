# scan

**Status:** implemented (Phase 1 Stage A). Native capture/crop UI verified reaching the OS scanner correctly on-device; full capture flow needs a real device or a Play-Store-signed-in emulator to see through to completion (see `docs/PHASE_1_SUMMARY.md`).

## Responsibility
Covers spec §4 screens 4–5: Camera/Scan and Crop/Adjust — combined into one flow since the native scanner (`cunning_document_scanner`, wrapping Android ML Kit Document Scanner / iOS VisionKit) already handles capture, edge detection, and crop itself.

## Scanner behaviour — how the "CamScanner-class" requirements are met
The **camera** path delegates to the OS document scanner, so it already provides the professional experience end-to-end, on **both platforms**:

- **Android** — Google ML Kit Document Scanner in `SCANNER_MODE_FULL` (the plugin's default; we don't override it): rear camera, full-screen live preview, real-time edge detection with a live border, auto-capture, automatic crop + perspective correction, **manual draggable corner handles**, rotate, retake, flash, and high-quality JPEG output.
- **iOS** — VisionKit `VNDocumentCameraViewController`: the same automatic edge detection, live border, perspective correction, and manual corner adjustment, Apple-controlled.

These are the same on-device ML engines CamScanner / Adobe Scan / Microsoft Lens rely on, so we intentionally do **not** reimplement a custom camera + edge-detection pipeline.

### The gap we fill ourselves — `crop_editor_screen.dart`
Two page sources arrive **without** native edge-detection and previously got no crop at all:
1. **Gallery import** (`image_picker.pickMultiImage`).
2. The **basic-camera fallback** (`_captureWithBasicCamera`) used when Google Play services / ML Kit is unavailable.

For these, the review screen exposes a **Crop** action opening `CropEditorScreen`: a full-bleed image with four **draggable corner handles** and a live green outline of exactly what will be kept (no false border where nothing was detected — the handles default to just inside the frame). Confirm warps the selected quad flat via `crop_processor.rectifyDocument` (`image` package `copyRectify`, run on a `compute()` isolate), preserving the document's true aspect ratio and every corner/margin/stamp inside the quad. Rotate and Reset live one tap away on the same review screen. Pure Flutter → identical on Android and iOS.

## Key decision — resolved
Scanner package: **`cunning_document_scanner`** — verified publisher, actively maintained, native OS-level scanner. See `docs/DEPENDENCIES.md`.

## Key packages
- `cunning_document_scanner` — capture/edge-detect/crop
- `image` — filters (grayscale/B&W/brightness-contrast), applied off the main isolate via `compute()`
- `permission_handler` — camera permission with rationale (requires `CAMERA`/`READ_MEDIA_IMAGES` in `AndroidManifest.xml` — already added)

## Contents
- `scan_capture.dart` — permission request + native scanner invocation (camera and gallery sources), basic-camera fallback (rear camera forced), permission-denied rationale dialog
- `scan_review_screen.dart` — multi-page tray: reorder, retake, delete, add page, per-page filter, **crop**, rotate, save
- `crop_editor_screen.dart` — manual crop + perspective editor (draggable corners, live outline, reset) for pages without native detection
- `crop_processor.dart` — isolate-safe perspective warp (`copyRectify`) that flattens the selected quad to a proportional JPEG
- `crop_geometry.dart` — pure crop-policy math (safety margin, min-area) shared by the editor's defaults
- `document_builder.dart` — orchestrates filter → combine-to-PDF (`core/pdf`) → `Documents`/`Pages` DB rows
- `image_filters.dart` — grayscale/B&W/brightness-contrast, isolate-safe
- `models/scan_page.dart` — in-progress session page model
- `providers/scan_session_provider.dart` — Riverpod `Notifier` holding the active session
- `widgets/filter_picker.dart` — filter chip row

Tested via `test/scan_pipeline_test.dart` (plain Dart test, synthetic images — the native scanner UI itself isn't drivable in this dev environment).
