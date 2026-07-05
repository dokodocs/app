# DokoDocs — App Store & Play Store Launch Criteria and Checklist

**Scope:** This document defines the step-by-step, non-skippable process and gating rules for taking DokoDocs Phase 1 (the MVP release milestone defined in the master prompt — scan → crop → filter → save → combine to PDF → share) live on the **Google Play Store** and the **Apple App Store**, Nepal-first, global-ready.

**How to use this file:** Treat every unchecked box as a release blocker. Nothing ships to a production track until Part A (Build Readiness Gate) is fully checked. Nothing goes to public production until the platform-specific checklist in Part C (Play) and Part D (App Store) is fully checked.

> **Last policy review: 2026-07-05.** Store policies change often. Re-verify Part A0, the target-API dates in Part C, and the privacy-manifest rule in Part D against the official console help before every release cycle. Sources for the 2026 rules are listed at the bottom of this file.

---

## Part A0 — Pre-Build Checklist (RUN EVERY TIME before generating any APK / AAB / IPA)

This is the fast gate the team asked for: **do not run `flutter build ...` until every box here is green.** It is deliberately short so it can be run on every build, not just release day. Part A (below) is the deeper, once-per-release gate.

**Automated helper:** run `bash tool/prebuild_check.sh` (or `pwsh tool/prebuild_check.ps1` on Windows) — it checks the mechanical items marked ⚙ below and exits non-zero if any fail.

- [ ] ⚙ `flutter analyze` is clean (0 issues)
- [ ] ⚙ `flutter test` passes
- [ ] ⚙ No debug/staging leftovers in `lib/`: no `localhost`, `10.0.2.2`, `ngrok`, hardcoded API keys/tokens, or `TODO: remove` shims in code that ships
- [ ] ⚙ No stray `print(` in `lib/` (use gated logging only)
- [ ] ⚙ `version:` in `pubspec.yaml` was bumped since the last store upload (both name and +build number) — you cannot re-upload the same build number
- [ ] ⚙ **Android** `targetSdk`/`compileSdk` resolve to **36 (Android 16)** or higher — required for new Play submissions from 2026-08-31 (see Part C Step 2)
- [ ] ⚙ **iOS** `ios/Runner/PrivacyInfo.xcprivacy` exists and is in the Runner target (see Part D Step 2)
- [ ] ⚙ Secrets are NOT staged for commit: `android/key.properties`, `*.jks`, `*.keystore`, App Store API keys are all git-ignored
- [ ] Manual: launch the built artifact once and confirm the full flow (scan → crop → filter → save → PDF → share) does not crash
- [ ] Manual: confirm the build channel/flavor is **release**, not debug, for anything leaving your machine

**If any ⚙ box fails, the build is not allowed to proceed.** Fix, then re-run the helper.

---

## Part A — Build Readiness Gate (before touching either console)

This gate must pass before any store work begins. It is the same bar as the master prompt's Phase 1 "Target State."

- [ ] `flutter build apk --release` and `flutter build appbundle --release` both succeed with no warnings treated as errors
- [ ] `flutter build ios --release` succeeds and the app runs clean on an iOS simulator
- [ ] Full flow works with no crash: scan → auto edge detect → manual crop → filter → multi-page reorder → save → combine to PDF → share
- [ ] Guest mode works with zero network access (test in airplane mode)
- [ ] UI fully switchable English ↔ नेपाली at runtime, no untranslated strings visible
- [ ] Unit tests pass for image pipeline + PDF utilities; widget test passes for scan-to-save
- [ ] Release Android App Bundle (.aab) size is within budget (target ≤ 40 MB via split ABIs/app bundle — Google no longer hard-caps APK size the way older 100 MB rules implied, but the 40 MB target is DokoDocs' own low-end-device budget, not a store rule)
- [ ] No hardcoded dev/staging endpoints (`localhost`, `10.0.2.2`, ngrok URLs, test API keys) anywhere in the release build
- [ ] All `print()` / `debugPrint()` / verbose logging disabled or gated to debug builds only
- [ ] Crash reporting wired and verified to actually capture a test crash (self-hosted Sentry per the plan, or equivalent)
- [ ] `docs/PHASE_1_SUMMARY.md` and `docs/STORE_COMPLIANCE.md` written and reviewed
- [ ] You (PM) have explicitly signed off on Phase 1 completion per the master prompt's phase-gate rule

**Do not proceed to Part B until every box above is checked.**

---

## Part B — Accounts, Legal & Shared Assets (do once, feeds both stores)

### B1. Developer accounts
- [ ] Apple Developer Program enrollment complete — **$99/year**, individual or organization; organization enrollment requires a D-U-N-S number, so start this early if going the organization route
- [ ] Google Play Console developer account created and the one-time registration fee paid; developer profile and payment/payout setup completed
- [ ] Decide account holder now: personal account vs. a DokoDocs organization/company account. Do not file support requests from a personal Apple ID tied to an employer's account — keep identities clean per platform ToS.

### B2. Legal & compliance documents (required by both stores)
- [ ] Privacy Policy — hosted at a public URL, must accurately state: DokoDocs collects nothing by default in guest mode, describes exactly what Google/Apple Sign-In collects, and states no ads / no data sale, matching the product's core principle
- [ ] Terms of Use (if you want a custom EULA beyond Apple's standard EULA)
- [ ] Open-source license file in the repo (AGPLv3 or chosen license) — reference it from the in-app About/License screen
- [ ] Support/contact email or page (both stores require a way for users and reviewers to reach you)
- [ ] Business tax info on file if you intend to sell the corporate license through either store's IAP later (not required for a fully free-to-download app, but prepare it now if any future paid tier could route through store billing)

### B3. Branding & store assets (prepare once, resize per platform in Part C/D)
- [ ] Final app name — confirmed, matches branding, unique enough not to collide in search
- [ ] Final app icon — vector master, exported to every required resolution (see per-platform checklist)
- [ ] Feature graphic / promotional graphic source file
- [ ] Screenshot source captures from a **real flow**, not placeholder content: onboarding, scan capture, crop, filter, multi-page reorder, save/organize, PDF share — captured in both English and Nepali
- [ ] Short description (≤80 chars) and long description drafted in English and Nepali
- [ ] Demo video (optional but recommended) — the "citizenship-card scan → PDF → share in under 30 seconds" demo referenced in the launch plan doubles as a store preview video candidate

### B4. Package/bundle identity — **do this before any submission, it is permanent**
- [ ] Final reverse-DNS package name chosen (e.g. `com.dokodocs.app`) — **not** `com.example.*` or any placeholder
- [ ] Package name matches exactly across Xcode Bundle Identifier, Android `applicationId`, and both console listings
- [ ] `versionName` and `versionCode`/build number scheme decided and documented (e.g. semantic version + monotonically increasing integer build number)

---

## Part C — Google Play Store: Step-by-Step (do not skip a step)

### Step 1 — Signing
- [ ] Generate the release keystore (`.jks`). Back it up in at least two secure locations (password manager + encrypted offline copy). **Losing this file before enabling Play App Signing means you can never update the app under the same listing.**
- [ ] Enable **Play App Signing** in Play Console so Google manages/rotates the app signing key
- [ ] `key.properties` / keystore credentials excluded from git via `.gitignore` — confirm they were never committed, including in prior commits

### Step 2 — Build format & target API level
- [ ] Build is an **Android App Bundle (.aab)** — required for all new apps since Aug 2021, plain `.apk` uploads are not accepted for new app listings
- [ ] **Target API level 36 (Android 16)** or higher — from **2026-08-31**, all new apps AND updates must target Android 16 (API 36); Wear OS / Android TV must target at least API 35. **Current status: compliant** — this project uses `targetSdk = flutter.targetSdkVersion`, which resolves to **36** on the pinned Flutter 3.44. Re-verify this after any Flutter upgrade/downgrade (an older Flutter could silently lower it); pin an explicit `targetSdk = 36` in `android/app/build.gradle.kts` if you ever want to decouple from the Flutter default. A build targeting an old API is rejected at upload.
- [ ] R8/Proguard (code shrinking) enabled for the release build
- [ ] Release build manually smoke-tested after shrinking (aggressive shrinking occasionally strips code that's only reached via reflection — verify nothing broke)

### Step 3 — Create the app in Play Console
- [ ] Play Console → Create app → set default language, category (Productivity or Tools), Free
- [ ] Store listing: title, short description, full description (EN + NE)
- [ ] Graphics: app icon (512×512), feature graphic (1024×500), phone screenshots (minimum required count per current console requirements), tablet screenshots if the app supports tablets

### Step 4 — Permissions, privacy & policy declarations
- [ ] Data Safety form completed accurately — this is the section most likely to cause a rejection or a bad-faith flag if wrong. State plainly: no data collected by default, Google Sign-In auth data disclosed if used, no data shared with third parties, no data sold
- [ ] Content rating questionnaire completed
- [ ] Ads declaration set to **No ads** (matches the product's no-ads principle)
- [ ] Only request permissions actually used (Camera, Photos/Storage, Biometrics for app lock later) — each with a clear, honest permission-rationale string; Google actively rejects apps requesting sensitive permissions (e.g. location) without a justified in-app use
- [ ] Account deletion: if the app allows account creation (Google Sign-In), an in-app account/data-deletion path is provided — this is a hard Play policy requirement, not optional
- [ ] Guest access confirmed reachable without forcing sign-up first — required both by policy expectation and by DokoDocs' own trust positioning

### Step 5 — Testing tracks (use them in this order, do not jump straight to Production)

> **⚠️ Hard gate for new PERSONAL Play accounts (created after 2023-11-13):** you must run **Closed testing with at least 12 testers who stay opted-in for 14 continuous days** before you can even *apply* for production access (approval then takes up to ~7 days). Organization accounts and personal accounts created before 2023-11-13 are exempt. **If you are on a new personal account, plan ~3 weeks of lead time for this — it is the single most common reason first launches slip.** Consider an **organization account** to skip this entirely (needs a D-U-N-S number).

- [ ] **Internal testing** track — fastest, small trusted group (you + core team), validates the pipeline end-to-end
- [ ] **Closed testing** track — meets the 12-testers-for-14-days rule above (recruit real testers, not throwaway accounts — Google can reject bought/fake tester lists), and doubles as the 100–200 Nepal beta testers (Pulchowk/KU/TU students, law offices, cooperatives, school admin, freelancers per the launch plan); collect feedback via a form + Discord/Telegram
- [ ] Beta exit criteria met: crash-free rate > 99%, top-10 reported issues fixed, scan-to-PDF success rate acceptable
- [ ] (Optional) **Open testing** track if you want a public beta before full production
- [ ] Staged rollout configured for the Production release (e.g. start at 10–20%, watch pre-launch report + vitals, ramp up) rather than 100% on day one

### Step 6 — Submit & publish
- [ ] Countries/territories selected — Nepal at minimum, expand as intended
- [ ] Pricing confirmed Free
- [ ] Release notes written (EN + NE)
- [ ] Upload signed `.aab`, submit to Production
- [ ] Monitor Play Console prelaunch report (device compatibility, automated crash checks) before rollout completes

### Google Play — Final Checklist (all must be ticked before Production release)
- [ ] Signed `.aab`, Play App Signing enabled
- [ ] Package name final and correct, no `com.example.*`
- [ ] Store listing complete in EN + NE with real-flow screenshots
- [ ] Data Safety form accurate; no ads declared; account-deletion path present if accounts exist
- [ ] Only-used permissions requested, each with a rationale string
- [ ] Guest mode reachable without forced sign-up
- [ ] Internal → Closed (Nepal beta) → (optional Open) → staged Production rollout, in that order
- [ ] Privacy Policy URL live and correct
- [ ] Direct-download APK also prepared for the website (sideloading is common in Nepal) — sign it with the same key, host it alongside the Play listing

---

## Part D — Apple App Store: Step-by-Step (do not skip a step)

### Step 1 — Prerequisites
- [ ] Apple Developer Program active ($99/year)
- [ ] **Built with the required Xcode / iOS SDK version** — from **2026-04**, submissions must be built with the **Xcode 26 SDK** (iOS 18/26 SDK) or later. An older SDK is rejected at upload. (This is why the build must run on an up-to-date Mac / cloud-Mac CI; it cannot be built on Windows at all.)
- [ ] Xcode project has a unique Bundle Identifier matching the reverse-DNS name locked in Part B4
- [ ] `CFBundleShortVersionString` (marketing version) and `CFBundleVersion` (build number) set and incremented per build
- [ ] Code signed with a valid Apple Distribution certificate; provisioning profile in place (automatic signing via Xcode is fine for a small team)
- [ ] Only request entitlements actually used at this phase — Phase 1 needs none beyond standard camera/photo library usage; do **not** pre-add HealthKit, Push, Apple Pay, etc. "just in case," since unused entitlements are a common rejection cause

### Step 2 — Required platform-specific items unique to iOS
- [ ] **Sign in with Apple implemented if Google Sign-In is offered** — Apple requires apps that offer a third-party login (Google Sign-In) to also offer Sign in with Apple as an equivalent option. This is already reflected as an explicit auth screen requirement in the product spec (Section 4) — confirm it before submission, since this is one of Apple's most common rejection reasons for apps that only wire up Google Sign-In first
- [ ] `Info.plist` usage strings written for every requested permission (`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `NSFaceIDUsageDescription` if/when app lock ships) — each string must clearly explain *why*, not just restate the permission name
- [ ] **Privacy manifest present and correct** — `ios/Runner/PrivacyInfo.xcprivacy` exists, is added to the Runner target (Target Membership ticked), declares `NSPrivacyTracking`, collected data types, and a valid reason code for every required-reason API used. **Missing/incorrect manifest = automatic rejection since 2024-05-01.** Every third-party SDK bundled must also ship its own manifest (the Flutter engine and current plugins do; verify after `pod install`).
- [ ] **Privacy Report validated** — in Xcode run *Product → Generate Privacy Report* and confirm the merged report (app + all SDK manifests) has no missing declarations before archiving

### Step 3 — Build & internal test via TestFlight
- [ ] Archive built in Xcode, uploaded via Organizer (or CI with `xcrun altool`/Transporter)
- [ ] TestFlight internal testing group validates the build on real devices
- [ ] TestFlight external testing group (can overlap with the Nepal closed-beta cohort used for Play) collects crash logs and feedback before submission

### Step 4 — App Store Connect: create the app record
- [ ] App Store Connect → My Apps → New App: app name, primary language, Bundle ID (must match Xcode exactly), SKU, platform (iOS)
- [ ] Pricing & availability: Free, territories selected (Nepal at minimum)

### Step 5 — Metadata & assets
- [ ] App name, subtitle, keywords field, short value-prop description
- [ ] Long description (EN + NE if you localize the listing)
- [ ] Screenshots for every required device class you support (6.7" and 5.5" iPhone sizes at minimum, iPad sizes if the app supports iPad) — real UI, not mocked paywall content
- [ ] App icon provided via the Xcode asset catalog at all required retina sizes
- [ ] App Privacy (Data Collection) section completed in App Store Connect — same honesty standard as Play's Data Safety form: state what Sign-In collects, confirm no tracking, no ads, no data sale

### Step 6 — Submit for review
- [ ] Build attached to the new version, release notes written
- [ ] **Review notes filled in** — since guest mode exists, note clearly for the reviewer that no login is required to test core scanning; if you also want the reviewer to see the signed-in path, provide an active demo account (Apple reviewers will not guess credentials and will reject if login is required but no demo account is given)
- [ ] App Review questionnaire answered accurately (permissions used, encryption/export compliance — a document scanner typically qualifies for the standard encryption exemption, but confirm and answer honestly)
- [ ] Submitted; status monitored in App Store Connect

### Step 7 — After approval
- [ ] Choose manual release (recommended for the first release, so you control the exact go-live moment alongside the Play rollout) vs. automatic
- [ ] Crash reporting + analytics confirmed live in production build

### Apple App Store — Final Checklist (all must be ticked before submission)
- [ ] Bundle ID final and matches Play package-name decision pattern (naming can differ, but both are locked and documented)
- [ ] Sign in with Apple present alongside Google Sign-In
- [ ] Every requested permission has a clear `Info.plist` usage string
- [ ] Guest/no-login path clearly explained in review notes; demo account provided if a signed-in path should also be reviewed
- [ ] App Privacy form accurate; no ads/tracking declared
- [ ] TestFlight internal + external testing completed with real-device feedback before submission
- [ ] Screenshots are real UI for every required device size
- [ ] Privacy Policy URL live and correct

---

## Part E — Common Rejection Causes to Pre-empt on Both Stores

- [ ] No placeholder content, Lorem Ipsum, or "Coming soon" screens anywhere in the shipped Phase 1 build
- [ ] No feature advertised in the store listing that isn't actually present in Phase 1 (do not market Phase 2+ features like sync/OCR/security yet — that is scope the master prompt explicitly defers)
- [ ] No misleading screenshots (e.g. showing a paywall or feature not yet built)
- [ ] Crash-on-launch tested explicitly on a low-RAM device/emulator (2–3 GB RAM Android per the Nepal performance budget) — this is both a store-rejection risk and the product's own quality bar
- [ ] Permission requests match the permission-rationale requirements called out in the master prompt's Section 6, applied from Phase 1
- [ ] Data-safety/privacy answers on both platforms are internally consistent with each other and with the Privacy Policy text — mismatches between the two forms and the actual policy page are a known trigger for manual review flags

---

## Part H — DO / DON'T (the fast rules to avoid rejection or a ban)

These are the behaviors that get apps **removed or accounts banned** — not just a single build rejected. Internalize them.

### ✅ DO
- **DO** keep the Play Data Safety form, the Apple App Privacy form, and the hosted Privacy Policy **saying the exact same thing.** Mismatches between the three are a top trigger for manual review and enforcement flags.
- **DO** request only permissions you use *right now*, each with an honest rationale string. Add a permission in the release that first uses it — never pre-request.
- **DO** offer **Sign in with Apple** whenever Google Sign-In is offered (Apple hard rule), and provide an **in-app account+data deletion** path whenever accounts exist (Play hard rule).
- **DO** make guest mode reachable without a forced sign-up, and **tell the reviewer** (in Apple review notes) that no login is needed to test core scanning.
- **DO** back up the Android release keystore in ≥2 places before first upload — losing it means you can never update the listing.
- **DO** bump the version/build number on every upload, and test the *shrunk* release build (R8 can strip reflection-reached code).
- **DO** use the testing tracks in order (Internal → Closed → Production, staged rollout), and satisfy the 12-testers/14-day rule if on a new personal Play account.
- **DO** re-check store policies before each release — the dated rules in this file (target API, privacy manifest, testers) move.

### ❌ DON'T
- **DON'T** ship placeholder/"Coming soon"/Lorem Ipsum screens, or screenshots showing features (sync, OCR, paywalls) that aren't in the shipped build. Advertising unbuilt features = rejection.
- **DON'T** declare "no data collected" while an SDK quietly collects — false privacy declarations are treated as bad-faith and risk account-level action.
- **DON'T** request sensitive permissions (location, contacts, all-files access, background mic/camera) without a justified, visible in-app use. Play actively rejects these.
- **DON'T** include ads or third-party tracking SDKs in a build declared "no ads / no tracking."
- **DON'T** use `com.example.*` or any placeholder bundle/package id, or change it after first submission (it's permanent per listing).
- **DON'T** submit an iOS build without a `PrivacyInfo.xcprivacy`, or an Android build targeting an old API level — both are auto-rejected before human review.
- **DON'T** buy/fake testers to pass the 12-tester rule, submit misleading metadata, or operate multiple accounts to evade a rejection — these escalate from rejection to **account termination**.
- **DON'T** ship debug builds, verbose logging, or dev endpoints to production (see Part A0).
- **DON'T** collect data from children or a general audience beyond what your content rating / target-audience declaration allows.

---

## Part F — Platform Economics Reference (for monetization planning, not required for the free Phase 1 launch)

These figures apply if/when a store-billed purchase path is ever added (the corporate license itself is planned to route through eSewa/Khalti/FonePay outside the stores, per the Nepal launch plan, so this section is informational, not a blocker):

- Apple: standard commission is 30% on digital goods sold through the App Store; **15% under the App Store Small Business Program** for developers with ≤ $1M in annual proceeds — apply for this if any future in-app purchase is added.
- Google Play: **15% service fee on the first $1M USD** of a developer's annual revenue, 30% above that; renewing subscriptions are charged at 15%.
- Both figures are for store-billed transactions only. Since DokoDocs' corporate license is designed to be sold via direct payment gateways (eSewa/Khalti/FonePay) rather than store billing, neither commission applies to the primary monetization path — confirm this routing stays compliant with each store's policy on external payment links for the specific transaction type before relying on it (policy in this area, especially for Apple, has been evolving and differs by region).

---

## Part G — Go/No-Go Summary

Ship to **public Production / public App Store release** only when:

1. Part A (Build Readiness Gate) — fully checked
2. Part B (Accounts, Legal, Assets) — fully checked
3. Part C (Google Play) — fully checked, staged rollout has run without a spike in crashes/ANRs
4. Part D (Apple App Store) — fully checked, build approved by Apple Review
5. Part E (Rejection pre-empt list) — fully checked
6. Nepal closed-beta exit criteria met: crash-free rate > 99%, top reported issues resolved

If any item is unchecked, the release is **not** ready — return to the relevant phase of the master prompt or the relevant step above rather than skipping ahead.

---

## Sources (2026 policy rules cited above — re-verify each release)

- Google Play target API level (Android 16 / API 36 from 2026-08-31): https://support.google.com/googleplay/android-developer/answer/11926878 and https://developer.android.com/google/play/requirements/target-sdk
- Google Play closed-testing 12-testers/14-days for new personal accounts: https://support.google.com/googleplay/android-developer/answer/14151465
- Apple privacy manifest (`PrivacyInfo.xcprivacy`) requirement, enforced 2024-05-01: https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk and https://developer.apple.com/news/?id=3d8a9yyh
- Apple required-reason API reason codes: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- Apple Xcode/SDK minimum for submissions: https://developer.apple.com/news/
