# DokoDocs — Step-Wise Roadmap

This is the single source of truth for build order. It merges:
- `prompt/dokodocs-master-prompt.md` — the authoritative spec (tech stack, data model, screens, phase plan)
- `prompt/DokoDocs_Claude_Code_Prompt.md` — Nepal-first overrides + agent working rules
- `prompt/DokoDocs_Nepal_Launch_Plan.md` — the business rationale behind the phase order
- `prompt/launch_app.md` — the Google Play / Apple App Store launch gate (Parts A–G), which sits between Phase 1 dev finishing and Phase 1 actually going public — see Step 2.5 below

**Rule:** work strictly top to bottom. Each step ends in something you can run and test yourself. A step is not "done" until its test gate passes, its phase summary doc is written, and you've explicitly approved moving on — see master spec §8 and the Claude Code prompt's Stop Conditions.

**Checkbox-level tracking lives in [`TODO.md`](../TODO.md)** at the repo root — this file explains the *why* and the test gates; `TODO.md` is what gets checked off item by item as work happens.

---

## Step 0 — Local tooling (you do this; blocking)

Nothing below is runnable until this is installed. Checked on this machine: **Flutter/Dart are not currently on PATH.**

- [ ] Flutter SDK (stable channel) — https://docs.flutter.dev/get-started/install
- [ ] Android Studio + Android SDK + at least one emulator image (primary target platform per Nepal overrides)
- [ ] A JDK compatible with your Android Gradle Plugin version (Android Studio usually bundles one)
- [ ] (Optional, iOS trails Android by one phase) Xcode, if/when you build on macOS
- [ ] Verify with: `flutter doctor`

Tell me once `flutter --version` works and I'll run the test gates myself instead of just handing you commands.

---

## Step 1 — Phase 0: Foundation *(scaffolded this session)*

- Flutter project scaffold, feature-based folders (`lib/core/`, `lib/features/<module>/`)
- Riverpod + drift wired up with the local schema (spec §3) — local tables only, no backend yet
- i18n scaffold with `en` **and** `ne` ARB files from the first commit (Nepal override — not deferred to Phase 4)
- CI skeleton (lint + test on push)
- `docs/ARCHITECTURE.md` describing module boundaries

**Test gate:**
```
flutter create --platforms=android,ios .   # generates android/ ios/ runner
                                             # projects around the existing
                                             # pubspec.yaml/lib — one-time,
                                             # only needed the first time
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run   # boots to an empty home screen
```
The `flutter create` step only exists because this scaffold was written without a Flutter SDK on this machine (see Step 0) — it adds the platform runner folders (`android/`, `ios/`) that the CLI normally generates on day one and does not touch `lib/`, `pubspec.yaml`, or anything else already committed.

---

## Step 2 — Phase 1: Lightweight MVP (the "go live" milestone)

- Camera capture, auto edge detection, manual crop/perspective correction
- Multi-page scan session (reorder, retake, delete)
- Filters: Original, Grayscale, B&W, brightness/contrast
- Local save + thumbnails; Home grid/list, folders, filename search
- Combine pages → PDF; export PDF/images; native share; system print
- Guest mode (no account, fully offline)
- Google Sign-In + Apple Sign-In (email/password + phone OTP may land in 1b)
- Settings: defaults, theme, language toggle (English/नेपाली), storage = Local only
- Release APK ≤ 40 MB (Nepal override — split ABIs / app bundle)

**Open decision — needs your pick before this step starts:** scanner package —
`cunning_document_scanner` vs `flutter_doc_scanner` vs custom `camera` + `opencv_dart`. I'll present tradeoffs and a recommendation when we get here.

**Test gate:** full scan → crop → filter → save → combine-to-PDF → share flow completes with no crash on an Android emulator (or a real budget device); unit tests on image/PDF utilities pass; one widget test covers scan-to-save; guest mode works in airplane mode; UI switches English ↔ नेपाली at runtime.

---

## Step 2.5 — Store Launch Readiness (Google Play + Apple App Store)

Once Phase 1 development itself is done and its test gate above passes, going *public* on either store is its own gated process — full detail in `prompt/launch_app.md`, checkbox tracking in `TODO.md` §4:

- **Part A — Build Readiness Gate:** release builds (`apk`/`appbundle`/iOS), full flow crash-free, no dev endpoints/logging left in, crash reporting verified, ≤40MB budget met. Nothing below starts until this passes.
- **Part B — Accounts, legal & shared assets:** Apple/Google developer accounts, Privacy Policy, license file, package identity (final reverse-DNS name — permanent, your call) — done once, feeds both stores.
- **Part C — Google Play:** signing → build format → console listing → Data Safety/permissions/policy → Internal → Closed (Nepal beta) → staged Production.
- **Part D — Apple App Store** (requires a Mac — see Step 0): signing/entitlements → Sign in with Apple (required alongside Google Sign-In) → TestFlight → App Store Connect listing → submit → review.
- **Part E — Common rejection causes to pre-empt** on both stores.
- **Part F — Platform economics** (reference only — the corporate license routes through eSewa/Khalti/FonePay outside store billing, so this isn't a blocker for the free Phase 1 launch).
- **Part G — Go/No-Go:** public release only when Parts A–E are fully checked and the Nepal closed-beta exit criteria are met.

This step does not block starting Phase 2 development in parallel once Phase 1 itself is stable — but public store release should not jump ahead of it.

---

## Step 3 — Phase 2: Self-hosted sync & storage connectors

- Reference backend + `docker-compose.yml` for one-command self-hosting
- Storage connectors: Custom API, WebDAV, FTP/SFTP, Google Drive, OneDrive, Dropbox
- LAN server discovery/pairing (mDNS + manual-IP fallback)
- Sync engine: manual "Sync now" + background sync, per-document sync status, last-write-wins conflict flagging
- Email/password + phone-OTP auth (pluggable SMS gateway, incl. a Nepali gateway stub e.g. Sparrow-SMS-style)
- iOS release lands here (Nepal override: iOS trails Android)

**Open decision — needs your pick before this step starts:** backend language — Node.js/NestJS vs Go.

**Test gate:** a document scanned offline syncs correctly to at least one of each connector type in a self-hosted test environment; airplane-mode-to-online transition tested.

---

## Step 4 — Phase 2.5: Nepali/English OCR *(pulled forward per Nepal override — normally Phase 4)*

- On-device OCR eval: ML Kit vs Tesseract for Devanagari accuracy — documented in `docs/OCR_EVAL.md` before implementation
- Searchable PDF output, OCR-based document search

**Test gate:** OCR accuracy spot-checked against a sample set before shipping search-by-OCR.

---

## Step 5 — Phase 3: Full PDF editing, security, folders, QR, printer

- Annotation suite (draw/highlight/underline/strikethrough/sticky note/text/erase/shapes/images), reusable signatures/stamps
- Watermark, merge/split, page-level rotate/delete/insert
- Security: PIN/app lock, Face ID/fingerprint, secure/hidden folder, password-protected PDFs
- Folder management: tags, favorites, smart folders, archive, trash with restore, color labels
- Secure/expiring/password-protected/LAN/QR share links
- QR scanner + generator
- Printer settings (AirPrint, Android Print Service, network/Bluetooth/USB)
- Extra format import/export (DOCX/XLSX/PPTX/TXT/RTF/HEIC/TIFF/WEBP/SVG where feasible)

**Test gate:** annotation and security features tested per-platform (Face ID on iOS, fingerprint on Android); smart folder rules verified against a seeded document set.

---

## Step 6 — Phase 4: AI & OCR (advanced)

- OCR accuracy/handwriting improvements, background/shadow removal, auto-crop/rotation via vision pipeline
- Translation of scanned text
- AI summary / chat-with-PDF — self-hosted or user-provided LLM key only, explicit per-action consent, never silent third-party upload

**Test gate:** OCR accuracy spot-checked across all 3 languages; consent flow verified before any document leaves the device.

---

## Step 7 — Phase 5: Admin panel & corporate tier

- Web dashboard: user/storage/sync/server monitoring, analytics
- License-key activation for the one-time corporate fee — pluggable payment providers (eSewa/Khalti/FonePay/ConnectIPS first, **not** Stripe by default)
- Multi-user org accounts on the self-hosted backend
- Office format conversion (PDF↔Word/Excel/PPT) as a backend job (headless LibreOffice)

**Test gate:** end-to-end org onboarding — admin creates org, applies license key, invites users, users sync documents, admin views them on the dashboard.

---

## Per-step exit checklist (applies to every step above)

1. Test gate passes.
2. `docs/PHASE_N_SUMMARY.md` written: what was built, what was tested, what manual console/dashboard setup you need to do outside the code (Firebase/OAuth client IDs, Apple signing + Sign in with Apple capability, SHA-1 fingerprints, Docker/env setup).
3. Any native platform config requirement flagged as an explicit checklist (Info.plist strings, Android manifest permissions, entitlements).
4. You approve → next step starts. I will not silently start the next phase or silently drop/reinterpret a feature — infeasible-as-scoped items get flagged explicitly with an alternative proposed.
