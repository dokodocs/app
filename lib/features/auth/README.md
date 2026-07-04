# auth

**Status:** not yet implemented. Lands in **Phase 1** (Guest, Google, Apple) and **Phase 2** (email/password, phone OTP — only if the backend isn't ready in time for 1b, per master spec §5 Phase 1).

## Responsibility
Sign-in screen: Google / Apple / Microsoft / Email+Password / Phone OTP / Guest (skip). Spec §4 screen 2. Guest mode must work fully offline with zero account — this is a core "own your data" trust signal, not a lesser mode.

## Key packages (planned, not yet added to pubspec.yaml)
- `google_sign_in`, `sign_in_with_apple` (Phase 1)
- Backend-issued JWT auth + email/password + phone OTP (Phase 2, depends on the backend-language decision in `docs/ROADMAP.md` Step 3)
- `flutter_secure_storage` for token storage

## Contents (planned)
- `auth_screen.dart`, `providers/auth_provider.dart`, one widget per provider button.

Do not add auth packages to `pubspec.yaml` before Phase 1 starts — see the Stop Conditions in `prompt/DokoDocs_Claude_Code_Prompt.md`.
