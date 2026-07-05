# DokoDocs

**तपाईंको कागजात, तपाईंकै फोनमा — your documents, on your own phone.**
Scan. Organize. Sync. Own Your Data.

DokoDocs is an open-source, self-hostable document scanner and PDF toolkit for iOS and Android — comparable to CamScanner / Adobe Scan / Microsoft Lens, but built around **data ownership**: your files live on your device by default, and any sync destination (your own server, your own LAN PC, or your own cloud account) is something *you* configure. DokoDocs never routes files through a proprietary company server you didn't choose.

## Status

**Phase 1 + batch/versioning/calendar/home upgrade — built and verified.** The core money path (scan → filter → multi-page reorder → save → combine-to-PDF → share) plus five user-facing upgrades are in: high-quality batch scanning with a non-destructive pipeline and per-page revert-to-original, an always-on DokoDocs corner watermark applied at export time, document version history, dual-calendar dates (AD + Bikram Sambat), and a redesigned Home (styled tagline, favorite/pinned folders, Recent-10). Verified with unit + widget tests and a live run on an Android 16 emulator (Home, folders, tagline, and localized Nepali UI confirmed). Onboarding illustrations and the SVG logo are wired in.

**Recent polish pass.** An animated brand splash screen; a **basic-camera fallback** so capture still works when Google Play services is unavailable (see below); a **Device status** checklist in Settings (camera / document scanner / local storage, with a scanner self-test); live in-preview color filters so Grayscale/B&W are visible before saving; a dimmed black-and-white export watermark; tappable info (ⓘ) details for watermark & local storage; DokoDocs → website links; a softer Home background; multi-document share straight from Home; and a clearer page-reorder handle.

## Supported devices & OS versions

DokoDocs targets the newest Android/iOS **and** old, low-end hardware (the Nepal reality: budget phones on old OS builds).

| Platform | Minimum | Target / tested |
|---|---|---|
| **Android** | 7.0 Nougat (API 24) | Compiles against and is compliant with the latest Android, incl. **Android 15 & 16** (edge-to-edge, current `targetSdk`). `minSdk` follows Flutter's floor (API 21) in `android/app/build.gradle.kts`, but the **effective** merged minimum is **API 24** because the auth plugins (`google_sign_in`/`sign_in_with_apple`) require it. Covers **Android 8 → 15** and beyond with room to spare. |
| **iOS** | iOS 13.0 | Deployment target 13.0 in the Xcode project — covers **iPhone 7 (on iOS 13–15) through the latest iPhone**. The VisionKit document scanner requires iOS 13+, which every supported device meets. |

**Camera scanning** uses the on-device ML Kit Document Scanner (Android, `SCANNER_MODE_FULL`) / VisionKit (iOS) via `cunning_document_scanner` — the same on-device engines CamScanner / Adobe Scan / Microsoft Lens use. Out of the box this gives the full professional experience on both platforms: **rear camera by default, full-screen live preview, real-time edge detection with a live border, automatic capture, auto-crop with perspective correction, manual draggable corner handles, rotate, flash, retake, and high-quality output** — so the app deliberately does not reimplement a custom camera/edge-detection stack. On Android this requires **Google Play services** to be present and up to date — the scanner module is delivered through it. On a device/emulator without current Play services the ML Kit scanner can't open; the app then **falls back to a custom rear-camera scanner** (`camera` package) — it **strictly** opens the back (primary-wide) lens (never the front), shows a full-screen preview with a **live green document border**, flash toggle, and capture button, then opens the crop editor (auto-detected corners + perspective correction) right after the shot. **Gallery import** remains available too (neither needs Play services). Settings → **Device status** shows the live availability of the camera, the document scanner (with a one-tap self-test), and local storage.

**Manual crop & perspective editor.** Pages that arrive **without** native edge-detection — gallery imports and the basic-camera fallback — can be corrected with a built-in **Crop** editor (review screen → Crop): full-bleed image, four **draggable corner handles** with a live green outline of exactly what's kept, a **Reset** to the full frame, and Confirm/Cancel. Confirming warps the selected quad flat (perspective-corrected, true aspect ratio, nothing clipped) on a background isolate. Rotate sits beside it on the same screen. It's pure Flutter, so it behaves identically on Android and iOS.

Required permissions are declared for every supported OS level: Android `CAMERA`, `READ_MEDIA_IMAGES` + `READ_MEDIA_VISUAL_USER_SELECTED` (Android 13/14+ photo access) with a `READ_EXTERNAL_STORAGE` fallback (≤ API 32); iOS `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription` (without these iOS crashes on camera/photo access — now fixed).

### Capture entry points

Scan is one unified chooser — **single page (camera)**, **multiple pages / batch (camera)**, and **import from gallery** — reachable from the center Scan button, Home's empty state, and inside a folder. Each launch starts a **fresh** session (a backed-out, unsaved session no longer bleeds into the next scan or blocks gallery import from being used again).

## Why

Primary market is Nepal: ~95% Android on budget (2–3GB RAM) devices, unstable/expensive connectivity, Devanagari as the primary local language, and real institutional distrust of foreign cloud services. The build order and every default in this repo (Android-first, Nepali OCR pulled forward, ≤40MB APK target, local payment gateways for the corporate tier) is driven by that. Full rationale: `prompt/DokoDocs_Nepal_Launch_Plan.md`.

## Principles

1. **Local-first, cloud-optional.** 100% usable with zero network connection except the sync step itself.
2. **You own the destination.** Every cloud/server connector is something you configure; nothing is mandatory.
3. **Ship a lightweight, working core before advanced features.** Phase 1 (scan → save → organize → PDF → share) ships before OCR/AI/admin panel are touched.
4. **No forced subscription, no ads, no selling user data.**

## Licensing & business model

- Core app: free and open source under **Apache License 2.0** (see [`LICENSE`](LICENSE)), full local-first feature set, for individuals, forever.
- Corporate/organization tier: a **one-time** license fee (not a subscription) unlocking admin panel + multi-user server deployment on the self-hosted backend only — mobile core scanning features are never gated. The corporate tier's licensing/entitlement mechanism is separate from the app's own open-source license and lands with Phase 5.

## Repository layout

```
prompt/          Source planning documents (master spec, Nepal overrides, launch plan)
docs/            ROADMAP, ARCHITECTURE, DATABASE, DEPENDENCIES, phase summaries
lib/
  core/          Shared: database (drift), theme, l10n — see lib/core/README.md
  features/      One folder per screen/module, each with its own README.md
test/
```

Every module under `lib/features/` and `lib/core/` has its own `README.md` — start there for module-level detail; start at `docs/ARCHITECTURE.md` for the overall picture.

## Getting started (once Flutter is installed — see `docs/ROADMAP.md` Step 0)

```
flutter create --platforms=android,ios .
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

## Self-hosting

Not yet available — the reference backend is a Phase 2 deliverable. `docs/DEPLOYMENT.md` will be written when that lands.

## Documentation

- [`TODO.md`](TODO.md) — the master, checkbox-level task list: every doc deliverable, every build step, and the full Google Play / Apple App Store launch gate, all in one place
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — the step-wise build plan and *why*, with a test gate per step
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — module boundaries, data flow
- [`docs/DATABASE.md`](docs/DATABASE.md) — schema + migration notes
- [`docs/DEPENDENCIES.md`](docs/DEPENDENCIES.md) — every package choice/substitution, with rationale
- [`prompt/launch_app.md`](prompt/launch_app.md) — the authoritative Google Play / Apple App Store launch checklist (Phase 1 exit gate)
- `docs/PHASE_N_SUMMARY.md` — one per completed phase (what shipped, what was tested, manual setup required)

## License

[Apache License 2.0](LICENSE).
