# Phase 1 Summary — Lightweight MVP (Stage A: core scan pipeline)

This covers **Stage A** of the combined build (`docs/ROADMAP.md` Step 2 + the "First-Launch Journey" prompt) — the actual scan → crop → filter → save → PDF → share pipeline, real Home, and Settings. Stages B (onboarding/empty-state/bottom-nav/icon) and C (auth) are tracked separately in `TODO.md`.

## What was built

- **Database**: `Documents`/`Pages`/`Folders`/`UserSettings` repositories with real query/insert/update methods (`lib/core/database/repositories/`); `UserSettings.onboardingComplete` added (schema v1→v2, migration in `AppDatabase.migration`). The `Pages` table's generated data class was renamed `DocPage` via `@DataClassName` — the natural name `Page` collides with Flutter's own `Page` (routing).
- **`lib/features/scan/`**: `scan_capture.dart` (permission request + native scanner invocation via `cunning_document_scanner`, camera and gallery sources), `scan_review_screen.dart` (multi-page tray: reorder, retake, delete, add page, per-page filter picker, save), `image_filters.dart` (grayscale/B&W/brightness-contrast via the `image` package, off the main isolate via `compute()`), `document_builder.dart` (orchestrates filter → combine-to-PDF → `Documents`/`Pages` row insert).
- **`lib/core/pdf/pdf_builder.dart`**: combines images into a PDF sized to each image's own aspect ratio (not forced A4), off the main isolate.
- **`lib/features/editor/`**: reorder/delete pages on an already-saved document, regenerates the PDF, share, opens the PDF viewer.
- **`lib/features/pdf_viewer/`**: `pdfrx`-based viewer.
- **`lib/features/home/`**: real grid of saved documents, folder chips (create/filter), filename search, favorite/trash actions per document, scan FAB.
- **`lib/features/settings/`**: theme (system/light/dark), language (EN/NE, live-applied via `main.dart` watching `UserSettingsProvider`), scan defaults (quality, default color mode), storage mode (read-only, "Local" until Phase 2).
- New dependencies and the reasoning for each: `docs/DEPENDENCIES.md` Phase 1 section.

## What was tested — and how

### Automated
- `flutter analyze` — clean, zero issues.
- `test/widget_test.dart` — app boots to the empty, localized Home screen. **Had to switch to `LiveTestWidgetsFlutterBinding`** (real-time, not the default fake-async binding) — drift's real `NativeDatabase` streams schedule real `Timer`s that the default fake-async test binding flags as "still pending" at teardown even though nothing is actually leaking. This is required knowledge for any future DB-backed widget test in this repo.
- `test/scan_pipeline_test.dart` (new) — a plain Dart test (no widget binding) that exercises the actual money path — filter → combine-to-PDF → `Documents`/`Pages` row insert — against two synthetic in-memory images, using an in-memory drift database and a faked `path_provider`. This is what actually proves the save/PDF/DB logic works, since the native scanner UI (see below) couldn't be driven end-to-end in this environment.

### Manual, on the `dokodocs_test` Android emulator (API 36)
- Built a debug APK, installed, launched — confirmed via `adb dumpsys` (activity resumed, no crash) and a screenshot that the real Home screen (search bar, folder chips, empty state, scan FAB) renders correctly.
- Tapped the scan FAB — confirmed the camera permission rationale/OS dialog appears correctly. **This required a fix**: `AndroidManifest.xml` had no `<uses-permission>` entries at all (Phase 0's template never needed any) — added `CAMERA`, `READ_MEDIA_IMAGES`, `READ_EXTERNAL_STORAGE` (maxSdkVersion 32), and a non-required camera `<uses-feature>`.
- Granted the permission — confirmed `cunning_document_scanner` correctly invokes Google Play Services' ML Kit Document Scanner (`com.google.android.gms/.chimera.container.ui.ModuleDownloadActivity` becomes the foreground activity, no crash in our app).
- **Blocked here**: the ML Kit Document Scanner is a Play Services *dynamic feature module* that must download on first use — this bare AVD emulator has no Google account signed in / no real Play Store access, so the download fails ("Something went wrong / Try again later"). **This is an environment limitation, not a code bug** — our code correctly reaches and invokes the real native scanner. Verifying the actual capture/crop UI needs either a real device or an emulator with a signed-in Google account and Play Store access.

### Also fixed along the way (Windows-specific, not app bugs)
- `android/gradle.properties`: added `kotlin.incremental=false` — several plugins compiling Kotlin in the same build hit a Windows-only Gradle/Kotlin bug ("Could not close incremental caches") that failed the build outright.

## Manual setup checklist for you

- [ ] **Verify the actual camera/scan capture UI** on a real Android device, or an emulator with a Google account signed in and Play Store access (the ML Kit module needs to download once).
- [ ] Google Sign-In: create an OAuth client in Google Cloud Console + register the debug/release SHA-1 fingerprint — not done here (Claude Code prompt's Scope rule: no Firebase/OAuth console access). Auth screen isn't built yet (Stage C).
- [ ] Apple Sign-In / iOS build: needs a Mac — not attempted here, unchanged from Phase 0.
- [ ] `flutter build apk --release` and release-size (≤40MB) checks not yet run — still on a debug build for iteration speed; do this once Stage B/C land.

## Open decisions still ahead

- Backend language for Phase 2 (`docs/ROADMAP.md` Step 3).
- Router package, if bottom-nav (Stage B) turns out to need real cross-tab deep-linking beyond `IndexedStack` — currently deferred, see `docs/DEPENDENCIES.md`.

## Stage B addendum — onboarding, EmptyState, bottom nav, app icon

Built and verified live on the `dokodocs_test` emulator with a true fresh install (`adb uninstall` then reinstall): splash → language picker → 3 value pages → permission priming → Home, all screenshotted and working; all 4 bottom-nav tabs (Home/Folders/Tools/Settings) function with no crashes; the custom launcher icon renders correctly in the recent-apps view.

**Bug found and fixed during this verification**: `HomeScreen` still carried its own Stage-A `FloatingActionButton`, which duplicated `AppShell`'s new shared, notched center FAB — two scan buttons were visible on Home. Fixed by removing Home's own FAB; `AppShell` is now the single owner of that button across all tabs.

Also fixed: `EmptyState` initially used a bare `Center`+`Column`, which overflowed (`RenderFlex` error) in constrained vertical space — reproduced by the widget test, not just theoretical. Fixed with a `LayoutBuilder` + `SingleChildScrollView` pattern that centers when there's room and scrolls instead of overflowing when there isn't.

## Post-Stage-B fixes — real-device UX feedback round

After Stage B, testing surfaced several real gaps, all fixed and verified:

- **Export format choice**: saving a scan now asks PDF / JPEG / PNG (`ExportFormat` in `document_builder.dart`) — JPEG/PNG creates one image `Document` per page, since there's no single-file container for "N images" the way a PDF provides one. Covered by `scan_pipeline_test.dart`'s new JPEG-export test.
- **Single vs. batch page choice**: a bottom sheet before invoking the scanner now lets the user pick "Single page" (`noOfPages: 1`) vs. "Multiple pages" (`noOfPages: 100`) — this wasn't discoverable via the native scanner's own in-flow control alone.
- **Add page to an existing document**: the editor now has an "Add page" action (PDF documents only) that scans more pages, appends them in the same on-disk folder, and regenerates the combined PDF.
- **Folder-assignment bug**: scans saved while a folder is selected (Home's chip row, or from within a Folder's own screen) previously always landed at the root — `folderId` is now threaded through `startScanFlow`/`startImportFromGalleryFlow` → `ScanReviewScreen` → `saveScanSessionAsDocument`.
- **New filters**: added Lighten (brightness-only) and High Contrast (contrast boost, keeps color — useful on colored backgrounds) alongside the existing Grayscale/B&W/Enhance.
- **App icon redesign**: shrunk the glyph, thinned the scan-corner brackets, added rounded end-caps and more negative space for a softer, more professional look (kept the brand green background per your call).
- **Text/icon scale reduced app-wide**: Material 3's default type scale felt too big/bold — `AppTheme`'s `TextTheme` now caps everything at medium weight (w500) with smaller sizes; `EmptyState`'s icon container and a few onboarding icons shrunk too.
- **False alarm, documented for the record**: a Home document tile briefly appeared to show "Create your first folder" as its thumbnail. Root cause was **test-environment contamination, not an app bug** — my own `adb screencap` debug screenshots had been dumped to the emulator's `/sdcard/`, got indexed by its Gallery app, and a "Import from gallery" test scan picked one up as the source photo. Cleaned up; confirmed the tile renders correctly once a real image is behind it.

## Next step

Stage C: Auth screen (Guest + Google/Apple Sign-In). Then Stage D: automated widget tests for onboarding/nav, and final doc pass.
