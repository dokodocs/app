# Phase 0 Summary — Foundation

## What was built

- Flutter project scaffold (`pubspec.yaml`, `analysis_options.yaml`, `.gitignore`) and a feature-based folder structure: `lib/core/` (database, theme, l10n) + `lib/features/<module>/` — one folder per screen named in spec §4, each carrying its own `README.md`.
- `core/database`: drift schema for all 8 tables in spec §3 (`Documents`, `Pages`, `Folders`, `Tags`, `DocumentTags` join table, `Signatures`, `Stamps`, `UserSettings`), local-only, wired to the app via `databaseProvider` (plain Riverpod `Provider`). Details: `docs/DATABASE.md`.
- `core/theme`: shared Material 3 light/dark theme.
- `core/l10n`: `app_en.arb` + `app_ne.arb` (Nepali) source strings, `l10n.yaml` config for `flutter gen-l10n` — i18n from day one per the Nepal override, not deferred to Phase 4.
- `lib/main.dart`: `ProviderScope` → `MaterialApp` → `HomeScreen`, with localization delegates wired up.
- `lib/features/home/home_screen.dart`: Phase 0 empty-state screen (title + "no documents yet", localized).
- `lib/features/onboarding/onboarding_screen.dart`: local-first explainer screen, built but not yet wired into navigation (nothing to hand off to until Phase 1's auth/router flow exists).
- `lib/features/{auth,scan,editor,pdf_viewer,qr,settings,storage_connectors,secure_folder,trash}/README.md`: documentation-only stubs (no code) stating each module's responsibility, target phase, and planned packages — per the spec's own rule against scaffolding future-phase features early.
- `.github/workflows/ci.yml`: lint + test on push.
- `test/widget_test.dart`: smoke test asserting the app boots and shows the localized empty-home-screen text.
- Docs: `docs/ROADMAP.md` (full step-wise plan), `docs/ARCHITECTURE.md`, `docs/DATABASE.md`, `docs/DEPENDENCIES.md`, root `README.md`.

## What was tested (updated — tooling is now installed, gate actually ran)

Flutter (3.44.4 stable) and a full Android toolchain were installed on this machine in this session (see `docs/ROADMAP.md` Step 0 and `TODO.md` §1 for exactly what). The Phase 0 test gate was then run for real, not just scaffolded:

1. `flutter create --platforms=android,ios .` — generated `android/` and `ios/` around the existing scaffold; did not touch `lib/` or `pubspec.yaml`.
2. `flutter pub get` — resolved clean.
3. `dart run build_runner build --delete-conflicting-outputs` — generated `lib/core/database/database.g.dart` from the drift schema with no errors.
4. `flutter gen-l10n` — generated `app_localizations*.dart` from the `en`/`ne` ARB files.
5. `flutter analyze` — found 2 issues (`unnecessary_non_null_assertion` in `home_screen.dart` and `onboarding_screen.dart`, since `l10n.yaml` sets `nullable-getter: false` so `AppLocalizations.of(context)` is already non-null). Fixed both; re-ran clean.
6. `flutter test` — 1/1 passed.
7. Built a debug APK, installed and launched it on a real Android emulator (`dokodocs_test`, Pixel 6, Android 16/API 36) via `adb`. Verified three ways: `adb dumpsys activity` shows `MainActivity` as the resumed (foreground) activity, `adb logcat` shows no crash/`FATAL` entries, and a screenshot confirms the app renders the localized empty state ("DokoDocs" / "No documents yet") exactly as designed.

**Phase 0 test gate: passed for real, on a real emulator.**

**iOS build step was not run** — Xcode is macOS-only and this is a Windows machine; this is a hard OS constraint, not a missing package. Deferred until a Mac or a macOS CI runner (Codemagic / GitHub Actions macOS) is available, consistent with the Nepal overrides' "iOS trails Android by one phase."

No native platform configuration (Info.plist usage strings, Android manifest permissions, signing, entitlements) was needed yet — Phase 0 has no camera/biometric/network permissions to declare. The first real checklist of that kind lands with Phase 1 (camera permission strings) and will be written into `docs/PHASE_1_SUMMARY.md` when we get there.

## Open decisions still ahead (not blocking Phase 0)

- Scanner package for Phase 1 (`docs/ROADMAP.md` Step 2)
- Backend language for Phase 2 (`docs/ROADMAP.md` Step 3)
- Router package for Phase 1 (`docs/DEPENDENCIES.md`)

## Next step

Once you've installed Flutter and the test gate above passes, say so and we start **Phase 1 — Lightweight MVP** (`docs/ROADMAP.md` Step 2), starting with the scanner-package decision.
