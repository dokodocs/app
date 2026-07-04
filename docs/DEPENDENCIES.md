# Dependency decisions

Per the master spec (§8.2: "Confirm/replace any package listed in Section 2 that is outdated or deprecated at build time; explain substitutions") and the Claude Code prompt's Stop Conditions ("Adding any dependency not listed in spec Section 2" requires stopping and asking first). This file is the running log — append an entry whenever a package is added, substituted, or deliberately deferred.

**Caveat:** Flutter/Dart are not installed on this machine (see `docs/ROADMAP.md` Step 0), so none of the versions below have been verified by an actual `flutter pub get`. Versions were checked against pub.dev directly where noted; everything else is a reasonable current caret range that `flutter pub get` will resolve once the SDK is available. Run `flutter pub outdated` after the first `pub get` and correct this file if anything resolved differently than expected.

## Phase 0 — added

| Package | Version | Why |
|---|---|---|
| `flutter_riverpod` | `^3.3.2` | Spec §2.1 state management. Verified current on pub.dev. Using the **classic (non-codegen) API** for Phase 0 — `riverpod_annotation`/`riverpod_generator` are not in spec §2 by name and are deferred to a Phase 1 decision rather than added silently. |
| `drift` | `^2.34.0` | Spec §2.1 local DB. Verified current on pub.dev. |
| `drift_flutter` | `^0.3.0` | Not named in spec §2, but mechanically required: `drift` core is Dart-only and cannot open a platform database connection by itself — `drift_flutter`'s `driftDatabase()` is the standard Flutter bridge. Treated as part of implementing "drift" rather than a new architectural choice. |
| `path_provider` | `^2.1.5` | Spec §2.1, explicitly named (file storage). |
| `path` | `^1.9.1` | Standard path-joining utility, used by drift setup. |
| `intl` | `^0.20.2` | Mechanical companion to `flutter_localizations`/`flutter gen-l10n`, required to satisfy the Nepal override (en+ne i18n scaffold from Phase 0). |
| `flutter_lints` | `^6.0.0` | CI lint skeleton (spec §5 Phase 0 deliverable). |
| `build_runner`, `drift_dev` | `^2.7.1`, `^2.34.0` | Required to generate `database.g.dart` — drift is unusable without them. |

## Phase 1 — added

| Package | Version | Why |
|---|---|---|
| `cunning_document_scanner` | `^2.5.0` | Scanner package decision — your pick over `flutter_doc_scanner` (less mature, unverified publisher, still 0.0.x) and custom `camera`+`opencv_dart` (far more build/maintenance effort, higher crash risk on 3GB RAM devices). v2.5.0, verified publisher, wraps Android ML Kit Document Scanner + iOS VisionKit. Verified current on pub.dev. |
| `image` | `^4.9.1` | Spec §2.1, explicitly named — filters (Grayscale/B&W/brightness-contrast) applied post-capture regardless of scanner package. |
| `pdf` | `^3.13.0` | Spec §2.1, explicitly named — PDF creation. |
| `pdfrx` | `^2.4.4` | PDF **viewing**. Spec §2.1 named `pdfrx` *or* `syncfusion_flutter_pdfviewer` — picked `pdfrx` (fully open-source, MIT) per the Nepal override's "prefer fully open-source; propose an alternative before using Syncfusion" (§7), avoiding the Syncfusion community-license eligibility question entirely rather than checking it. |
| `share_plus` | `^13.2.0` | Spec §2.1, explicitly named — native share sheet. |
| `printing` | `^5.15.0` | Spec §2.1, explicitly named — system print dialog. |
| `permission_handler` | `^12.0.3` | Spec §2.1, explicitly named — camera/photo permission requests with rationale (spec §6, applies from Phase 1). |
| `google_sign_in` | `^7.2.0` | Spec §2.1, explicitly named. **Not functionally testable in this environment** — I don't create Firebase/OAuth client IDs (Claude Code prompt Scope rule). Code is wired to the real SDK; needs your Google Cloud OAuth client setup + SHA-1 fingerprint before it will actually sign a user in. Guest mode is the fully working path in the meantime. |
| `sign_in_with_apple` | `^8.1.0` | Spec §2.1, explicitly named. Same caveat as `google_sign_in` — needs your Apple Developer "Sign in with Apple" capability + entitlement, and iOS itself isn't buildable on this Windows machine yet regardless. |
| `flutter_launcher_icons` (dev) | `^0.14.4` | App launcher icon generation, per the onboarding/nav/icon prompt's own ask. |

## Deliberately NOT added (flagged, not silently included)

| Package | Status | Why not |
|---|---|---|
| `go_router` (or any router) | Not adding | The bottom-nav-shell prompt itself offers a fallback ("else an IndexedStack") for when go_router isn't present. Adding go_router now would be an unreviewed new dependency beyond what either the original spec or the onboarding prompt (which caps new deps at 2) actually requires — an `IndexedStack` + one `Navigator` per tab satisfies "each destination preserves its own navigation stack" without it. |
| `shared_preferences` | Not adding | The onboarding prompt allows either `shared_preferences` or a `UserSettings` DB row for the first-launch flag. Chose the DB row (`UserSettings.onboardingComplete`, drift migration) since `UserSettings` is already the single-row local-first settings source of truth — adding a second, parallel persistence mechanism for one boolean would be redundant. |
| `riverpod_annotation`, `riverpod_generator`, `riverpod_lint`, `custom_lint` | Still deferred | No architectural need has come up yet; classic Riverpod API continues to be sufficient through Phase 1. |
| `camera`, `opencv_dart`, `flutter_doc_scanner` | Not chosen | Scanner package alternatives not picked — see `cunning_document_scanner` above. |
| `syncfusion_flutter_pdf`, `syncfusion_flutter_pdfviewer` | Not chosen | Open-source `pdf`/`pdfrx` picked instead — see above. |
| `firebase_auth` | Not adding | `google_sign_in`/`sign_in_with_apple` cover Phase 1's named auth providers without pulling in the full Firebase SDK; revisit only if Phase 2's backend JWT/OAuth-relay design calls for it. |
| `mobile_scanner`, `qr_flutter` | Phase 3 | QR module unimplemented until Phase 3. |
| `local_auth`, `flutter_secure_storage` | Phase 3 | Security features (app lock/biometric/secure folder) unimplemented until Phase 3. |
| `dio`, WebDAV/FTP/SFTP clients, `googleapis`, Microsoft Graph SDK, Dropbox REST | Phase 2 | Storage connectors unimplemented until Phase 2; also gated on the backend-language decision. |
| `signature` | Phase 3 | Signature capture lands with the full annotation suite. |

## Batch/versioning/calendar/home pass

- `nepali_utils` (`^3.0.8`) — pure-Dart Bikram Sambat ↔ AD conversion, Nepali month names, and Devanagari digit formatting, backing the dual-calendar `DateFormatter` (`lib/core/date/`). No native code, so it adds nothing to the APK's native footprint. Chosen over `nepali_date_picker` because only display formatting is needed now (no date picker exists yet — a picker would pull that in later per spec §4).
- `flutter_svg` (`^2.3.0`) — renders the vector logo (`assets/logo/logo_dokodocs.svg`) crisply in the app bar and splash, instead of shipping large multi-density PNGs.
- `image_picker` (`^1.2.3`) — multi-image gallery import. The native document scanner's gallery mode only picks one image at a time; `pickMultiImage()` lets the user select many photos at once to build a multi-page document. Uses the system photo picker, so it needs no extra runtime permission on Android 13+/iOS (the iOS `NSPhotoLibraryUsageDescription` is already declared).

## Substitutions vs. the master spec

- `pdfrx` instead of `syncfusion_flutter_pdfviewer` for PDF viewing — see Phase 1 table above. This is a same-tier substitution the spec explicitly offered as a choice, not a deprecation-driven swap.
