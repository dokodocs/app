# settings

**Status:** implemented (Phase 1 Stage A) — theme, language, scan defaults, storage mode (read-only). Not yet reachable from navigation (lands with Stage B's bottom nav shell). Account section and Security land later.

## Responsibility
Spec §4 screen 9: Account (Stage C), Storage & Sync (read-only until Phase 2), Security (Phase 3), Scan defaults, Printer (Phase 3), App preferences (theme/language), About/License.

Backed entirely by the `UserSettings` table in `core/database` (spec §3) — theme, language, `defaultQuality`, `defaultColorMode` are live; `storageMode` is fixed to `'local'` and shown read-only until Phase 2 connectors exist.

## Key packages
- `flutter_riverpod`
- `local_auth`, `flutter_secure_storage` (Phase 3, security section)

## Contents
- `settings_screen.dart` — Appearance (theme/language), Scan defaults (quality/color mode), Storage & sync (read-only), About
- `providers/settings_provider.dart` — `userSettingsProvider`, also watched by `main.dart` to apply locale/theme live
