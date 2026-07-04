# DokoDocs — Master TODO

Single checkbox-level source of truth. `docs/ROADMAP.md` explains *why* the steps are ordered this way; this file is the granular, checkable version of the same plan, now also folding in the Google Play / App Store launch gate from `prompt/launch_app.md`. Check items off as they're actually done and verified — not when merely started.

**Sources merged into this file:** `prompt/dokodocs-master-prompt.md` (spec), `prompt/DokoDocs_Claude_Code_Prompt.md` (Nepal overrides + working rules), `prompt/DokoDocs_Nepal_Launch_Plan.md` (rationale), `prompt/launch_app.md` (store launch gate), `docs/ROADMAP.md` (our derived step plan).

---

## 0. Documentation deliverables

Every markdown file the project is expected to have, and its status.

### Source docs (read-only inputs, not edited by us)
- [x] `prompt/dokodocs-master-prompt.md`
- [x] `prompt/DokoDocs_Claude_Code_Prompt.md`
- [x] `prompt/DokoDocs_Nepal_Launch_Plan.md`
- [x] `prompt/launch_app.md`

### Root
- [x] `README.md` — project overview, self-hosting quickstart, license summary
- [x] `TODO.md` — this file

### `docs/`
- [x] `docs/ROADMAP.md` — step-wise build plan, test gates
- [x] `docs/ARCHITECTURE.md` — module boundaries, data flow, sync engine design
- [x] `docs/DATABASE.md` — full schema (local + backend) with migration notes
- [x] `docs/DEPENDENCIES.md` — every package decision/substitution with rationale
- [x] `docs/PHASE_0_SUMMARY.md`
- [ ] `docs/PHASE_1_SUMMARY.md`
- [ ] `docs/STORE_COMPLIANCE.md` — App Store / Google Play requirements checklist for what was actually built (spec §7; feeds Part B/C/D of `prompt/launch_app.md`)
- [ ] `docs/API.md` — backend REST endpoints, request/response shapes, auth flow (Phase 2)
- [ ] `docs/DEPLOYMENT.md` — Docker self-hosting guide, env vars, LAN pairing (Phase 2)
- [ ] `docs/OCR_EVAL.md` — ML Kit vs Tesseract Devanagari accuracy tradeoff (Phase 2.5)
- [ ] `docs/PHASE_2_SUMMARY.md`
- [ ] `docs/PHASE_2.5_SUMMARY.md`
- [ ] `docs/PHASE_3_SUMMARY.md`
- [ ] `docs/PHASE_4_SUMMARY.md`
- [ ] `docs/PHASE_5_SUMMARY.md`

### `lib/` module READMEs (spec §4 screens)
- [x] `lib/core/README.md`
- [x] `lib/features/home/README.md`
- [x] `lib/features/onboarding/README.md`
- [x] `lib/features/auth/README.md`
- [x] `lib/features/scan/README.md`
- [x] `lib/features/editor/README.md`
- [x] `lib/features/pdf_viewer/README.md`
- [x] `lib/features/settings/README.md`
- [x] `lib/features/storage_connectors/README.md`
- [x] `lib/features/secure_folder/README.md`
- [x] `lib/features/qr/README.md`
- [x] `lib/features/trash/README.md`
- [ ] Each README above rewritten from "planned" to "implemented" once its module actually ships — do this in the same commit as the feature, not after

---

## 1. Step 0 — Local tooling

- [x] Flutter SDK installed, on PATH — Flutter 3.44.4 stable, cloned to `C:\Users\user\dev\flutter`
- [x] Android SDK cmdline-tools installed (`ANDROID_HOME` set) — `C:\Users\user\AppData\Local\Android\Sdk`
- [x] Android platform-tools, build-tools, at least one platform + one emulator system image installed — platform 36, build-tools 36.1.0, `system-images;android-36;google_apis;x86_64`
- [x] Android licenses accepted (`flutter doctor --android-licenses`)
- [x] At least one AVD (emulator) created and bootable — `dokodocs_test` (Pixel 6, Android 16/API 36)
- [x] JDK compatible with the Android Gradle Plugin confirmed via `flutter doctor` — JDK 17.0.10 (bundled with an existing Android Studio install found on this machine)
- [x] `flutter doctor` run clean for mobile — only remaining warning is the unrelated Windows-desktop C++ toolchain (not needed; DokoDocs doesn't ship a Windows desktop build)
- [x] iOS toolchain — **confirmed not possible on this Windows machine** (Xcode is macOS-only, verified this is an OS restriction, not a missing package). Revisit when a Mac or macOS CI runner (Codemagic / GitHub Actions macOS) is available; does not block Android-first development per the Nepal overrides.

## 2. Step 1 — Phase 0: Foundation

- [x] Flutter project scaffold, feature-based folders (`lib/core/`, `lib/features/<module>/`)
- [x] `pubspec.yaml` with Phase-0-only dependencies (rest deferred, logged in `docs/DEPENDENCIES.md`)
- [x] drift schema for all 8 tables from spec §3 (local only)
- [x] Riverpod wired (`databaseProvider`)
- [x] i18n scaffold: `app_en.arb` + `app_ne.arb`, `l10n.yaml`
- [x] Material theme (light/dark)
- [x] `main.dart` boots to `HomeScreen`
- [x] `onboarding_screen.dart` built (not yet wired into navigation)
- [x] CI skeleton (`.github/workflows/ci.yml`) — lint + test on push
- [x] `docs/ARCHITECTURE.md` written
- [x] Placeholder widget test
- [x] `docs/PHASE_0_SUMMARY.md` written
- [x] **Test gate actually run and passing:**
  - [x] `flutter create --platforms=android,ios .` — added `android/`, `ios/` around the existing scaffold without touching `lib/`/`pubspec.yaml`
  - [x] `flutter pub get`
  - [x] `dart run build_runner build --delete-conflicting-outputs` — generated `database.g.dart`
  - [x] `flutter gen-l10n` — generated `app_localizations*.dart`
  - [x] `flutter analyze` — 2 lint issues found and fixed (`unnecessary_non_null_assertion` in `home_screen.dart`/`onboarding_screen.dart`, since `l10n.yaml` has `nullable-getter: false`), now zero issues
  - [x] `flutter test` — 1/1 passed
  - [x] Built a debug APK, installed + launched on the `dokodocs_test` emulator (Android 16/API 36), confirmed via `adb dumpsys` (activity resumed, not crashed), empty logcat error stream, and a real screenshot — boots to the empty, localized ("DokoDocs" / "No documents yet") home screen exactly as designed
- [ ] You approve Phase 0 → Phase 1 starts

## 3. Step 2 — Phase 1: Lightweight MVP (the "go live" milestone)

**Scanner package decision — resolved:** `cunning_document_scanner` (your pick), logged in `docs/DEPENDENCIES.md`.

**Stage A (core pipeline) — built and verified this session:**
- [x] Camera capture with auto edge detection + crop — delegated to the native scanner (ML Kit/VisionKit); invocation confirmed reaching Google Play Services correctly on-device (see `docs/PHASE_1_SUMMARY.md` for the module-download blocker on this bare emulator — needs a real device or Play-Store-signed-in emulator to see the actual capture UI)
- [x] Multi-page scan session: reorder, retake, delete page (`scan_review_screen.dart`)
- [x] Filters: Original, Grayscale, B&W, brightness/contrast (`image_filters.dart`, verified via `scan_pipeline_test.dart`)
- [x] Local save with metadata (`document_builder.dart`, verified via `scan_pipeline_test.dart`)
- [x] Home screen: grid, folders, filename search — verified on emulator screenshot
- [x] Combine pages into PDF (`pdf_builder.dart`, verified via `scan_pipeline_test.dart`); export via editor
- [x] Share via native share sheet (`share_plus`, wired in scan-review and editor)
- [ ] Basic print via system dialog — `printing` added as a dependency, not yet wired to a UI action
- [x] Guest mode fully functional (no account) — the whole app is usable with zero auth, by construction (no auth screen exists yet)
- [ ] Google Sign-In — deferred to Stage C; can't be functionally tested without your OAuth console setup regardless
- [ ] Apple Sign-In — deferred to Stage C; also needs a Mac
- [x] Settings: defaults (quality, color mode), theme, language toggle EN/NE, storage mode = Local only — built and wired to `UserSettings`
- [ ] Release APK/AAB ≤ 40 MB — still building debug APKs for iteration; do the release-size check once Stage B/C land
- [x] Unit tests: image pipeline + PDF utilities (`test/scan_pipeline_test.dart`)
- [x] Widget test: app boot / empty state (`test/widget_test.dart` — required switching to `LiveTestWidgetsFlutterBinding`, see summary doc)
- [x] Full flow tested as far as this environment allows: scan → crop → filter → save → combine-to-PDF → share verified end-to-end via `scan_pipeline_test.dart` (synthetic images) + Home/permission flow verified live on the `dokodocs_test` emulator; the native capture UI itself is blocked by Play Services module download on this bare AVD
- [ ] Guest mode tested in airplane mode — not yet explicitly tested (no auth screen exists yet to contrast against)
- [x] UI switches English ↔ नेपाली at runtime, no untranslated strings — `main.dart` reactively applies `UserSettings.language`; Settings screen has a working toggle
- [x] `docs/PHASE_1_SUMMARY.md` written

**Stage B — built AND verified live on the `dokodocs_test` emulator (fresh install, uninstall-then-reinstall to force true first-launch):**
- [x] Onboarding: splash → language picker (English/नेपाली) → 3 value pages (Skip/dots/Continue) → permission priming (camera dialog granted correctly) → lands on Home, `onboardingComplete` persists across relaunch
- [x] Reusable `EmptyState`: Home (Scan now / Import from gallery + Nepali sub-line), Folders ("Create your first folder"), Search-no-results — all screenshotted and correct
- [x] Bottom nav shell: all 4 tabs (Home/Folders/Tools/Settings) function, no crashes, per-tab state preserved; center scan FAB present exactly once (see bug below)
- [x] App launcher icon: confirmed rendering correctly in the emulator's recent-apps card
- [x] Settings "Replay intro" row present and wired
- **Bug found + fixed during this verification**: `HomeScreen` still had its own Stage-A `FloatingActionButton`, which duplicated `AppShell`'s new shared notched center FAB (two scan buttons visible) — removed Home's own FAB since the shell now owns it exclusively.
- [ ] Full onboarding walkthrough was verified manually via `adb input tap` (screenshots each step) — an automated `testWidgets` "onboarding-completes-once" test per the original prompt's acceptance criteria is still owed (Stage D)

**Post-Stage-B UX feedback round — built and verified live on the emulator:**
- [x] Export format choice (PDF/JPEG/PNG) before saving a scan
- [x] Single vs. batch page choice before invoking the scanner
- [x] "Add page" action on the editor for existing PDF documents
- [x] Folder-assignment bug fixed — scans now save into the folder they were started from
- [x] New Lighten / High Contrast filters (alongside Grayscale/B&W/Enhance)
- [x] App icon redesigned smaller/softer with rounded bracket caps
- [x] App-wide text/icon scale reduced (Material 3 defaults felt too big/bold)
- Full writeup + the "false alarm" test-contamination finding: `docs/PHASE_1_SUMMARY.md`

**Still ahead:**
- [ ] Auth screen: Guest + Google/Apple Sign-In buttons wired (Stage C)
- [ ] Stage D: automated widget tests (onboarding-completes-once, nav-bar-tab-switching), remaining doc updates
- [ ] You approve Phase 1 dev complete → move to Step 2.5 (Store Launch)

## 4. Step 2.5 — Store Launch Readiness (Google Play + Apple App Store)

Full detail and rationale: `prompt/launch_app.md`. Mirrored here as checkboxes so nothing gets silently skipped; update both files if scope changes.

### Part A — Build Readiness Gate (blocks everything below)
- [ ] `flutter build apk --release` succeeds, no warnings-as-errors
- [ ] `flutter build appbundle --release` succeeds
- [ ] `flutter build ios --release` succeeds on simulator (needs a Mac — see Step 0)
- [ ] Full flow crash-free: scan → edge detect → crop → filter → reorder → save → PDF → share
- [ ] Guest mode works in airplane mode
- [ ] EN ↔ NE fully switchable, no untranslated strings
- [ ] Unit + widget tests pass
- [ ] Release `.aab` size ≤ 40 MB
- [ ] No hardcoded dev/staging endpoints or test API keys in the release build
- [ ] All `print()`/`debugPrint()`/verbose logging gated to debug only
- [ ] Crash reporting wired + verified with a real test crash
- [ ] `docs/PHASE_1_SUMMARY.md` and `docs/STORE_COMPLIANCE.md` written and reviewed
- [ ] You sign off on Phase 1 completion

### Part B — Accounts, Legal & Shared Assets (do once, feeds both stores)
- [ ] Apple Developer Program enrollment ($99/yr) — needs a Mac/Apple ID decision first
- [ ] Google Play Console developer account + registration fee paid
- [ ] Account holder decided: personal vs. org account (kept separate from any employer account)
- [ ] Privacy Policy hosted at a public URL (states: nothing collected by default in guest mode, what Google/Apple Sign-In collects, no ads, no data sale)
- [ ] Terms of Use (if a custom EULA is wanted)
- [x] Open-source license file committed (`LICENSE`, Apache 2.0) — [ ] still needs referencing from an in-app About/License screen (lands with Stage B/C Settings polish)
- [ ] Support/contact email or page
- [ ] Business tax info on file (only if routing the corporate license through store IAP later)
- [ ] Final app name confirmed
- [ ] Final app icon (vector master + all required resolutions)
- [ ] Feature/promo graphic source file
- [ ] Real-flow screenshots captured in EN + NE (onboarding, capture, crop, filter, reorder, save, share)
- [ ] Short (≤80 char) + long descriptions drafted in EN + NE
- [ ] Demo video (optional): "citizenship-card scan → PDF → share in <30s"
- [ ] Final reverse-DNS package name chosen (e.g. `com.dokodocs.app`, **not** `com.example.*`) — **your call, needed before any submission, permanent**
- [ ] Package name matches exactly across Xcode Bundle ID, Android `applicationId`, both console listings
- [ ] `versionName`/`versionCode` scheme decided and documented

### Part C — Google Play
- [ ] Release keystore generated, backed up in 2+ secure locations
- [ ] Play App Signing enabled
- [ ] Keystore/`key.properties` confirmed never committed (`.gitignore` already covers this — verify no prior commit leaked it)
- [ ] Build is `.aab`, R8/Proguard enabled, smoke-tested after shrinking
- [ ] App created in Play Console (language, category, Free)
- [ ] Store listing complete EN + NE, all required graphics uploaded
- [ ] Data Safety form accurate
- [ ] Content rating questionnaire completed
- [ ] Ads declaration: No ads
- [ ] Only actually-used permissions requested, each with a rationale string
- [ ] Account-deletion path present (if Google Sign-In offered)
- [ ] Guest access reachable without forced sign-up
- [ ] Internal testing track validated
- [ ] Closed testing (Nepal beta cohort) run, exit criteria met (crash-free >99%, top-10 issues fixed)
- [ ] (Optional) Open testing track
- [ ] Staged Production rollout configured
- [ ] Countries/territories selected (Nepal minimum)
- [ ] Release notes written EN + NE
- [ ] Direct-download APK prepared for the website, signed with the same key

### Part D — Apple App Store (needs a Mac)
- [ ] Xcode project Bundle ID matches Part B's package-name decision
- [ ] Version/build numbers set and incremented per build
- [ ] Code signed (Distribution cert + provisioning profile)
- [ ] Only entitlements actually used at Phase 1 requested
- [ ] Sign in with Apple implemented alongside Google Sign-In (Apple requirement)
- [ ] `Info.plist` usage strings written for every requested permission
- [ ] TestFlight internal testing done
- [ ] TestFlight external testing (can reuse the Nepal closed-beta cohort)
- [ ] App record created in App Store Connect
- [ ] Pricing/territories set
- [ ] Metadata + real-UI screenshots for every required device size
- [ ] App Privacy (Data Collection) section completed, consistent with Play's Data Safety form and the Privacy Policy page
- [ ] Review notes explain guest mode / provide a demo account for the signed-in path
- [ ] App Review questionnaire answered honestly (encryption/export compliance)
- [ ] Submitted, status monitored
- [ ] Manual release chosen for the first release, crash reporting confirmed live

### Part E — Pre-empt common rejections (both stores)
- [ ] No placeholder/Lorem Ipsum/"coming soon" screens in the shipped build
- [ ] No Phase 2+ feature advertised that isn't actually in Phase 1
- [ ] No misleading screenshots
- [ ] Crash-on-launch tested explicitly on a 2–3GB RAM Android device/emulator
- [ ] Permission requests match spec §6 rationale requirements
- [ ] Data-safety/App Privacy answers internally consistent with each other and the Privacy Policy text

### Part F — Platform economics (reference only, not a blocker for the free launch)
- [ ] Apple Small Business Program applied for, if/when any IAP is ever added
- [ ] Confirmed corporate-license routing via eSewa/Khalti/FonePay (outside store billing) stays policy-compliant

### Part G — Go/No-Go
- [ ] Parts A–E fully checked
- [ ] Nepal closed-beta exit criteria met (crash-free >99%, top issues resolved)
- [ ] You give explicit go for public Production / public App Store release

## 5. Step 3 — Phase 2: Self-hosted sync & storage connectors

**Open decision, blocking this step's start:** backend language — Node.js/NestJS vs Go.

- [ ] Reference backend scaffolded (chosen language), PostgreSQL
- [ ] Backend JWT auth + OAuth relay for Google/Apple/Microsoft
- [ ] Storage driver interface: Local disk, S3-compatible, WebDAV passthrough, FTP/SFTP passthrough
- [ ] `docker-compose.yml` one-command self-hosting + `docs/DEPLOYMENT.md`
- [ ] Mobile connectors: Custom API, WebDAV, FTP/SFTP, Google Drive, OneDrive, Dropbox
- [ ] LAN server discovery/pairing (mDNS + manual-IP fallback)
- [ ] Sync engine: manual "Sync now" + background sync, per-document status, last-write-wins conflict flagging
- [ ] Email/password + phone-OTP auth (pluggable SMS gateway incl. Nepali gateway stub)
- [ ] iOS release prepared (needs Mac/CI)
- [ ] `docs/API.md` written
- [ ] Test gate: offline scan syncs to each connector type in a self-hosted test env; airplane-mode-to-online tested
- [ ] `docs/PHASE_2_SUMMARY.md` written; you approve

## 6. Step 4 — Phase 2.5: Nepali/English OCR

- [ ] OCR engine eval (ML Kit vs Tesseract for Devanagari) documented in `docs/OCR_EVAL.md` **before** implementation
- [ ] On-device OCR implemented (English + Nepali)
- [ ] Searchable PDF output
- [ ] OCR-based document search in Home
- [ ] Test gate: OCR accuracy spot-checked against a sample set
- [ ] `docs/PHASE_2.5_SUMMARY.md` written; you approve

## 7. Step 5 — Phase 3: Full PDF editing, security, folders, QR, printer

- [ ] Annotation suite: draw, highlight, underline, strikethrough, sticky note, text, erase, shapes, image insert
- [ ] Reusable signatures/stamps placement
- [ ] Watermark (text/image), merge/split, page rotate/delete/insert
- [ ] PDF → image export, multi-image → long scroll image
- [ ] PIN/app lock, Face ID/fingerprint
- [ ] Secure/hidden folder + local encryption
- [ ] Password-protected PDFs
- [ ] Tags, favorites, smart folders, archive, trash w/ restore, color labels
- [ ] Secure/expiring/password-protected/LAN/QR share links
- [ ] QR scanner (URL/text/wifi/contact) + generator (text/URL/wifi)
- [ ] Printer settings: AirPrint, Android Print Service, network/Bluetooth/USB, presets
- [ ] Extra format import/export where feasible (DOCX/XLSX/PPTX/TXT/RTF/HEIC/TIFF/WEBP/SVG)
- [ ] Test gate: Face ID (iOS)/fingerprint (Android) tested per platform; smart folder rules verified against a seeded set
- [ ] `docs/PHASE_3_SUMMARY.md` written; you approve

## 8. Step 6 — Phase 4: AI & OCR (advanced)

- [ ] OCR accuracy/handwriting improvements (expectations set explicitly for handwriting)
- [ ] Background/shadow removal
- [ ] Auto-crop/rotation via vision pipeline
- [ ] Translation of scanned text (ne↔en)
- [ ] AI summary / chat-with-PDF — self-hosted or user-provided LLM key only, explicit per-action consent
- [ ] Test gate: OCR accuracy spot-checked across EN/HI/NE; consent flow verified before any document leaves device
- [ ] `docs/PHASE_4_SUMMARY.md` written; you approve

## 9. Step 7 — Phase 5: Admin panel & corporate tier

- [ ] Web dashboard: user/storage/sync/server monitoring, analytics
- [ ] License-key activation flow, one-time fee
- [ ] Payment providers pluggable: eSewa/Khalti/FonePay/ConnectIPS first, **not** Stripe by default; bank transfer + VAT invoice support
- [ ] Multi-user org accounts on the self-hosted backend
- [ ] Office format conversion backend job (headless LibreOffice, PDF↔Word/Excel/PPT)
- [ ] Test gate: end-to-end org onboarding — admin creates org, applies license key, invites users, users sync, admin views on dashboard
- [ ] `docs/PHASE_5_SUMMARY.md` written; you approve

---

## Post-mortem log

After each step is checked off above, add a one-entry note here: what was built, what broke, what was learned, so the next phase starts with the previous one's lessons instead of repeating them.

- **Step 0/1, part 1:** Scaffolded Phase 0 entirely without Flutter installed on the dev machine — real risk was writing drift/riverpod/l10n code that looks right but hasn't compiled once. Lesson carried forward: install tooling *before* writing the next phase's code, not after, so errors surface immediately instead of accumulating across an entire phase.
- **Step 0/1, part 2:** Installed Flutter 3.44.4 + a full Android SDK/emulator toolchain from scratch (winget wasn't available for Flutter itself, used a shallow `git clone` of the stable branch instead; Android SDK via headless `sdkmanager`, no Android Studio GUI needed). Ran the real Phase 0 gate end-to-end on an actual emulator. Only defect found was 2 trivial `unnecessary_non_null_assertion` lints, caused by `l10n.yaml`'s `nullable-getter: false` making `AppLocalizations.of(context)!` redundant — fixed immediately. Everything else (drift schema, riverpod wiring, l10n ARB setup, theme) compiled and ran correctly on the first real build. Confirmed iOS is a hard no-go on this Windows machine (Xcode is macOS-only) — not attempted, correctly deferred rather than guessed at.
