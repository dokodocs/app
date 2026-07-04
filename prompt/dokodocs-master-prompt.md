# DokoDocs — Master Development Prompt

**Tagline:** Scan. Organize. Sync. Own Your Data.

Copy this entire document into your AI coding agent (Claude Code, Cursor, etc.) as the project brief. It is organized phase-by-phase. **Do not skip a phase. Do not start a phase until the previous phase is built, tested, and explicitly approved.**

---

## 1. Product Summary

DokoDocs is an **open-source, self-hostable** document scanner and PDF toolkit for iOS and Android, comparable to CamScanner / Adobe Scan / Microsoft Lens — but built around **data ownership**: the user's files live on their device by default, and any sync destination (their own server, their own LAN PC, or their own cloud account) is something *they* configure. DokoDocs never routes files through a proprietary company server the user didn't choose.

### 1.1 Licensing & business model
- **Core app: free and open source** (choose a permissive-but-protective license, e.g. AGPLv3 or a source-available license — flag this as a decision for the user to confirm with a lawyer if this becomes a real commercial product; do not treat this as legal advice).
- **Individuals:** always free, full local-first feature set.
- **Corporate/business tier:** **one-time license fee** (not subscription) that unlocks organization features — e.g. admin panel, multi-user server deployment, priority support artifacts. Implement this as a license-key gate on the *self-hosted backend/admin panel*, not on the mobile app's core scanning features, since those must remain free per the open-source promise.
- No forced subscription. No ads. No selling of user data — this is a core product principle, state it in the app's About/Privacy screen.

### 1.2 Guiding principles for every phase
1. **Local-first, cloud-optional.** The app must be 100% usable with zero network connection except for the sync step itself.
2. **User owns the destination.** Every cloud/server connector is something the user configures; nothing is mandatory.
3. **Ship a lightweight, working core before adding advanced features.** Phase 1 must be a real, usable, installable app — scan, save, organize, PDF, share — before OCR/AI/advanced security/admin panel are touched.
4. **Test and document before moving on.** Each phase ends with a working build, a passing test suite for that phase's features, and a written summary in `/docs`.

---

## 2. Tech Stack

### 2.1 Mobile app
- **Framework:** Flutter (latest stable), Dart null-safety
- **State management:** Riverpod
- **Local DB:** `drift` (type-safe SQL, better migration story than raw `sqflite` for a growing schema)
- **File storage:** device filesystem via `path_provider`, thumbnails cached separately
- **Camera/edge detection:** `cunning_document_scanner` or `flutter_doc_scanner`; fallback to `camera` + `opencv_dart` for custom perspective correction and contrast/color filters
- **Image processing:** `image` (Dart) for basic filters; `opencv_dart` for perspective transform, adaptive contrast, grayscale/B&W thresholding
- **PDF create/edit:** `pdf` (create), `syncfusion_flutter_pdf` (edit/annotate/merge/split/watermark/forms — verify free community license eligibility for the intended org size) with `pdfrx` or `syncfusion_flutter_pdfviewer` for viewing
- **QR:** `mobile_scanner` (scan), `qr_flutter` (generate) — Phase 3+
- **E-signature:** `signature` package
- **Auth clients:** `firebase_auth` or a self-hosted auth service (see 2.2) + `google_sign_in`, `sign_in_with_apple`; email/password and phone OTP handled by the chosen backend
- **Storage connectors:** `dio` (generic REST), a WebDAV client package, `googleapis` (Google Drive), Microsoft Graph SDK/REST (OneDrive), Dropbox REST API, an FTP/SFTP client package, plus a custom LAN-discovery module (see Phase 2)
- **Printing:** `printing`
- **Sharing:** `share_plus`
- **Biometrics/security:** `local_auth` (Face ID/fingerprint), `flutter_secure_storage` (keys/tokens)
- **Permissions:** `permission_handler`

### 2.2 Backend (self-hostable, optional)
Since the questionnaire calls for "multiple options" with self-hosting as the priority, build one lightweight **reference backend** the user can self-host, rather than depending on a specific vendor:
- **Language/framework:** Node.js (NestJS or Fastify) or Go — pick whichever the coding agent is strongest in; justify the choice
- **Database:** PostgreSQL
- **Auth:** the backend issues its own JWT-based auth (email/password, phone OTP via a pluggable SMS provider interface) and also acts as an OAuth relay so the mobile app can complete Google/Apple/Microsoft sign-in without embedding secrets client-side
- **File storage abstraction:** the backend exposes a single storage interface with pluggable drivers: Local disk, S3-compatible (covers Wasabi/Backblaze B2/AWS S3), WebDAV passthrough, FTP/SFTP passthrough — this lets self-hosters point at whatever they already run
- **Deployment:** Docker + `docker-compose.yml` for one-command self-hosting; document environment variables in `docs/DEPLOYMENT.md`
- **This backend is entirely optional** — the mobile app must work fully without it, connecting directly to Google Drive/OneDrive/Dropbox/WebDAV/FTP/a LAN PC if the user prefers not to run it.

### 2.3 Local PC / LAN sync
Per the answers, implement this as: **a local server over WiFi**, i.e. a small companion mode where:
- Phase 2: the user runs the same lightweight backend (Docker or a simple binary) on their PC, and the mobile app discovers it on the LAN (mDNS/Bonjour-style service discovery, or manual IP entry as a fallback) and syncs over local HTTP.
- This avoids needing a separate "desktop app" build in Phase 1; revisit a dedicated desktop companion app only if the user wants it after v1.

---

## 3. Data Model

```
Document
  id, title, createdAt, updatedAt, folderId, tags[], pageCount,
  localPath, fileType (pdf|image), sizeBytes,
  syncStatus (none|pending|synced|failed|conflict), remoteUrl?,
  isFavorite, isArchived, isTrashed, trashedAt?, colorLabel?,
  passwordProtected (bool), ocrText? (nullable, Phase 4)

Page
  id, documentId, order, localImagePath, filter, cropCoordinates,
  width, height, rotation

Folder
  id, name, parentId?, createdAt, isSmartFolder (bool), smartRule? (json)

Tag
  id, name, colorLabel?

Signature
  id, userId, imagePath, createdAt

Stamp
  id, userId, imagePath, label, createdAt

UserSettings
  authProvider, storageMode (local|gdrive|onedrive|dropbox|webdav|ftp|customApi|lanServer),
  serverConfig { type, url, protocol, authToken, port? },
  defaultFileNaming, defaultQuality, defaultColorMode,
  theme, language (en|hi|ne),
  appLockEnabled, biometricEnabled, secureFolderEnabled

DocumentVersion   -- Phase 3+, version history
  id, documentId, versionNumber, snapshotPath, createdAt
```

Backend (Postgres) mirrors `Document`, `Folder`, `Tag`, `UserSettings` for multi-device sync, plus a `Users` and `Organizations`/`LicenseKeys` table for the corporate one-time-license tier.

---

## 4. Screens

1. Splash / Onboarding — explain local-first + own-your-data model
2. Auth — Google / Apple / Microsoft / Email+Password / Phone OTP / Guest (skip)
3. Home — grid/list toggle, folders, tags, favorites, recent, archive, trash, search (filename/tag/date; OCR search from Phase 4)
4. Camera/Scan — live edge detection, flash toggle, auto-capture toggle, multi-page tray
5. Crop/Adjust — corner drag, perspective correction, filters (Original/Magic Color/Grayscale/B&W/High Contrast), brightness/contrast sliders
6. Document Editor — reorder pages, add/remove pages, merge/split, watermark, annotate (draw/highlight/underline/strikethrough/sticky note/text/erase/shapes/images), signature/stamp placement, export
7. PDF Viewer — view, annotate, sign, page thumbnails sidebar
8. QR Scanner / QR Generator (Phase 3)
9. Settings — Account, Storage & Sync, Security (app lock/biometric/secure folder), Scan defaults, Printer, App preferences (theme/language), About/License
10. Storage Connection setup — one screen per connector type (Google Drive OAuth, OneDrive OAuth, Dropbox OAuth, WebDAV/FTP form, LAN server discovery/pairing, custom API endpoint form) each with a "Test Connection" action
11. Secure Folder (Phase 3) — biometric-gated hidden documents
12. Trash — restore/permanently delete

---

## 5. Phased Build Plan

Build strictly in this order. **After each phase: build must run on both Android and iOS simulators, the phase's test checklist must pass, and a `docs/PHASE_N_SUMMARY.md` must be written before starting the next phase.**

### Phase 0 — Foundation (no user-facing features yet)
- Flutter project scaffold, feature-based folder structure (`lib/features/...`, `lib/core/...`)
- Riverpod + drift wired up with the schema in Section 3 (local tables only)
- CI pipeline skeleton (lint + test on push)
- `docs/ARCHITECTURE.md` describing module boundaries
- **Test gate:** app builds and runs to an empty home screen on both platforms.

### Phase 1 — Lightweight MVP (this is the "go live" milestone)
Scope deliberately kept light per the requirement to "get the product live" before layering on extras:
- Camera capture with auto edge detection + manual crop/perspective correction
- Multi-page scan session, reorder, retake/delete page
- Filters: Original, Grayscale, B&W, basic brightness/contrast
- Local save with thumbnail + metadata; Home screen grid/list, folders, basic search
- Combine pages into PDF; export PDF or images
- Share via native share sheet; basic print via system dialog
- Guest mode (no account) fully functional
- Google Sign-In + Apple Sign-In (Email/password and phone OTP can land in Phase 1b if the backend isn't ready yet — flag this explicitly rather than blocking the release)
- Settings: defaults (naming, quality, color mode), theme, storage mode = Local only
- **Test gate:** full flow scan → crop → filter → save → combine to PDF → share, on a real or simulated device, with unit tests on image/PDF utilities and a widget test for the scan-to-save flow. This is the version that can be released to app stores as v1.0.

### Phase 2 — Self-hosted sync & storage connectors
- Backend reference implementation (Section 2.2) + Docker deployment docs
- Storage connectors: Custom API endpoint, WebDAV, FTP/SFTP, Google Drive, OneDrive, Dropbox
- LAN server discovery/pairing (local PC over WiFi) with manual-IP fallback
- Sync engine: manual "Sync now" + background sync, per-document sync status, basic conflict flagging (last-write-wins with a visible conflict marker — full merge UI can wait)
- Email/password + phone OTP auth if not done in Phase 1
- **Test gate:** a document scanned offline syncs correctly to at least one of each connector type in a self-hosted test environment; airplane-mode-to-online transition tested.

### Phase 3 — Full PDF editing, security, folders, QR, printer
- Annotation suite: draw, highlight, underline, strikethrough, sticky notes, text boxes, erase, shapes, image insert, stamps, reusable signatures
- Watermark (text/image), merge/split, page-level rotate/delete/insert
- PDF → image export, multi-image → long scroll image
- Security: PIN/app lock, Face ID/fingerprint, secure/hidden folder, password-protected PDFs, device encryption for local secure-folder contents
- Folder management: tags, favorites, smart folders (rule-based, e.g. "all PDFs tagged Invoice from this month"), archive, trash with restore, color labels
- Sharing: secure link, expiring link, password-protected share, LAN share, QR share
- QR scanner (URL/text/wifi/contact) + QR generator (text/URL/wifi)
- Printer settings: AirPrint, Android Print Service, network/Bluetooth/USB printer selection, print presets (paper size, duplex, quality)
- Additional file format support: DOCX/XLSX/PPTX/TXT/RTF/HEIC/TIFF/WEBP/SVG import/export where format allows
- **Test gate:** annotation and security features tested per-platform (Face ID on iOS, fingerprint on Android); smart folder rules verified against a seeded document set.

### Phase 4 — AI & OCR (explicitly deferred per requirements)
- OCR: English, Hindi, Nepali initially (evaluate on-device OCR — e.g. ML Kit / Tesseract-based Flutter plugins — vs. a backend OCR service for accuracy on Devanagari script; document the tradeoff before implementing)
- Searchable PDF output, OCR-based document search
- Auto document detection/auto crop/auto rotation improvements using the OCR/vision pipeline
- Background/shadow removal
- Handwriting recognition (evaluate feasibility separately — may be lower accuracy, set expectations)
- Translation of scanned document text
- AI summary of a document, AI chat with a PDF (requires an LLM API integration — self-hosted or user-provided API key, consistent with the "own your data" principle: never send documents to a third-party AI service without explicit per-action user consent)
- **Test gate:** OCR accuracy spot-checked against a sample set in each of the 3 languages before shipping search-by-OCR.

### Phase 5 — Admin panel & organization features (corporate tier)
- Web dashboard: user management, storage management, server monitoring, sync monitoring, basic analytics
- License-key activation flow for the one-time corporate fee
- Multi-user org accounts on the self-hosted backend
- Office format conversion service (PDF↔Word/Excel/PPT) as a backend job, since reliable conversion needs a server-side engine (e.g. headless LibreOffice) rather than on-device processing
- **Test gate:** end-to-end org onboarding — admin creates org, applies license key, invites users, users sync documents, admin views them on the dashboard.

---

## 6. Non-functional requirements
- Fully offline-capable except the sync action itself; clear UI state for offline/pending/synced/failed/conflict
- Compress images at a configurable quality to control local storage growth
- Material 3 on Android, Cupertino-appropriate navigation feel on iOS, shared design language between them (per "blend of both")
- Support phones, tablets, iPad, and foldables — test adaptive layouts at common breakpoints
- Proper permission rationale dialogs (camera, photos, storage, biometrics) on both platforms
- Accessibility: minimum tappable target sizes, screen-reader labels on primary actions
- i18n scaffold from Phase 0 even though only English ships UI text initially; Hindi/Nepali UI strings can follow OCR language support in Phase 4

---

## 7. Documentation deliverables (write these as the project progresses, not at the end)
- `docs/ARCHITECTURE.md` — module boundaries, data flow, sync engine design
- `docs/DATABASE.md` — full schema (local + backend) with migration notes
- `docs/API.md` — backend REST endpoints, request/response shapes, auth flow
- `docs/DEPLOYMENT.md` — Docker self-hosting guide, environment variables, LAN server pairing instructions
- `docs/PHASE_N_SUMMARY.md` — one per completed phase: what was built, what was tested, what manual setup (Firebase/OAuth console steps, signing certificates, entitlements) the user must do outside the code
- `docs/STORE_COMPLIANCE.md` — App Store and Google Play requirements checklist (privacy nutrition labels, permission usage strings, sign-in with Apple requirement, data-safety form) relevant to what was actually built
- `README.md` — project overview, self-hosting quickstart, license summary

---

## 8. Instructions to the coding agent
1. Read this entire document before writing any code.
2. Confirm/replace any package listed in Section 2 that is outdated or deprecated at build time; explain substitutions.
3. Build **Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5** strictly in order. Do not begin a phase until the previous phase's test gate passes and its summary doc is written.
4. Phase 1 is the release milestone — treat it as "ship a real, working, lightweight app" and resist scope creep into later phases' features.
5. After each phase, pause and report: what was built, what was tested, what manual console/dashboard setup the user needs to do (Firebase/Google Cloud OAuth client IDs, Apple Developer signing + Sign in with Apple capability, Google Sign-In SHA-1 fingerprint, Docker/self-host env setup), and ask for confirmation before continuing.
6. Flag every native platform configuration requirement explicitly as a checklist (Info.plist usage strings, Android manifest permissions, entitlements, etc.).
7. Do not silently drop or reinterpret any feature listed above; if something is technically infeasible or ill-advised as scoped, say so explicitly and propose an alternative rather than quietly omitting it.

---

*End of master prompt.*
