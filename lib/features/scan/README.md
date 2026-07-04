# scan

**Status:** implemented (Phase 1 Stage A). Native capture/crop UI verified reaching the OS scanner correctly on-device; full capture flow needs a real device or a Play-Store-signed-in emulator to see through to completion (see `docs/PHASE_1_SUMMARY.md`).

## Responsibility
Covers spec §4 screens 4–5: Camera/Scan and Crop/Adjust — combined into one flow since the native scanner (`cunning_document_scanner`, wrapping Android ML Kit Document Scanner / iOS VisionKit) already handles capture, edge detection, and crop itself.

## Key decision — resolved
Scanner package: **`cunning_document_scanner`** — verified publisher, actively maintained, native OS-level scanner. See `docs/DEPENDENCIES.md`.

## Key packages
- `cunning_document_scanner` — capture/edge-detect/crop
- `image` — filters (grayscale/B&W/brightness-contrast), applied off the main isolate via `compute()`
- `permission_handler` — camera permission with rationale (requires `CAMERA`/`READ_MEDIA_IMAGES` in `AndroidManifest.xml` — already added)

## Contents
- `scan_capture.dart` — permission request + native scanner invocation (camera and gallery sources), permission-denied rationale dialog
- `scan_review_screen.dart` — multi-page tray: reorder, retake, delete, add page, per-page filter, save
- `document_builder.dart` — orchestrates filter → combine-to-PDF (`core/pdf`) → `Documents`/`Pages` DB rows
- `image_filters.dart` — grayscale/B&W/brightness-contrast, isolate-safe
- `models/scan_page.dart` — in-progress session page model
- `providers/scan_session_provider.dart` — Riverpod `Notifier` holding the active session
- `widgets/filter_picker.dart` — filter chip row

Tested via `test/scan_pipeline_test.dart` (plain Dart test, synthetic images — the native scanner UI itself isn't drivable in this dev environment).
