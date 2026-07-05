# scan

**Status:** implemented (Phase 1 Stage A). Native capture/crop UI verified reaching the OS scanner correctly on-device; full capture flow needs a real device or a Play-Store-signed-in emulator to see through to completion (see `docs/PHASE_1_SUMMARY.md`).

## Responsibility
Covers spec §4 screens 4–5: Camera/Scan and Crop/Adjust — combined into one flow since the native scanner (`cunning_document_scanner`, wrapping Android ML Kit Document Scanner / iOS VisionKit) already handles capture, edge detection, and crop itself.

## Scanner behaviour — how the "CamScanner-class" requirements are met
The **camera** path delegates to the OS document scanner, so it already provides the professional experience end-to-end, on **both platforms**:

- **Android** — Google ML Kit Document Scanner in `SCANNER_MODE_FULL` (the plugin's default; we don't override it): rear camera, full-screen live preview, real-time edge detection with a live border, auto-capture, automatic crop + perspective correction, **manual draggable corner handles**, rotate, retake, flash, and high-quality JPEG output.
- **iOS** — VisionKit `VNDocumentCameraViewController`: the same automatic edge detection, live border, perspective correction, and manual corner adjustment, Apple-controlled.

These are the same on-device ML engines CamScanner / Adobe Scan / Microsoft Lens rely on, so we intentionally do **not** reimplement a custom camera + edge-detection pipeline.

### The gap we fill ourselves — custom camera + crop editor
The native scanner isn't available on every device (missing Google Play
services), and gallery imports never go through it. Those paths used to fall
back to `image_picker`, which **opened the front camera** (its rear hint is
ignored on most Android devices) and had no edge detection. Replaced with:

**`camera_scanner_screen.dart`** — a custom camera on the `camera` package:
STRICTLY selects the rear (back/primary-wide) lens, full-screen preview,
capture button, flash On/Auto/Torch, back button, optional camera switch, and
a **live green document outline** from throttled per-frame detection
(`camera_frame_utils.dart` → grayscale → `document_detector.dart`). High-res
capture with autofocus/exposure (camera plugin defaults).

**`document_detector.dart`** — dependency-free quad detector (downscale →
bright/low-saturation mask → extreme-point corners), with a min-area guard so
no false border is drawn. Runs both on live frames and (via `compute`) on the
captured still to seed the crop corners.

**`crop_editor_screen.dart`** — opened automatically right after a fallback
capture, and on demand from the review screen's **Crop** action for gallery
imports. Full-bleed image, four **draggable corner handles** pre-seeded with
the detected quad, live green outline + dim scrim, **Reset** (back to full
frame), Confirm/Cancel. Confirm warps the quad flat via
`crop_processor.rectifyDocument` (`image` `copyRectify` on a `compute()`
isolate), preserving the document's true aspect ratio and every
corner/margin/stamp. Pure Flutter → identical on Android and iOS.

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
