# secure_folder

**Status:** not yet implemented. Lands in **Phase 3**.

## Responsibility
Spec §4 screen 11: biometric-gated hidden documents. Backed by `UserSettings.secureFolderEnabled`/`biometricEnabled` (already in the Phase 0 schema) plus device-level encryption for secure-folder contents.

## Key packages (planned)
- `local_auth` (Face ID/fingerprint gate), `flutter_secure_storage` (keys)

## Contents (planned)
- `secure_folder_screen.dart`, `providers/secure_folder_provider.dart`.
