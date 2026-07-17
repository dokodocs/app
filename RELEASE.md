# DokoDocs Release Checklist

Status as of 2026-07-13. App version: `0.1.0+1` (pubspec.yaml).

## Current blocker: Play Store internal testing shows "item not found"

Play Console → Testing → Internal testing shows:

> Temporary app name: `com.bhrikuty.dokodocs (unreviewed)` — **Not reviewed**

New apps must pass Google's **initial review** before the internal testing
link works for testers who aren't the account owner. Until that first
review completes, testers opening the internal test link get "item not
found". This is normal for a brand-new app — not a bug in the app itself.

### To unblock: finish the store listing (Play Console → Store presence → Store listing)

Missing/incomplete fields observed in Play Console:

- [ ] **App name** (public listing name field — separate from the package
      "DokoDocs" title shown in the sidebar)
- [ ] **Short description** (0/80 chars — currently empty)
- [ ] **Full description** (0/4000 chars — currently empty)
- [ ] **App icon** (512x512 PNG/JPEG, ≤1MB)
- [ ] **Feature graphic** (1024x500 PNG/JPEG, ≤15MB)
- [ ] **Phone screenshots** (2-8 images, 16:9 or 9:16, 320-3840px per side)
- [ ] Tablet screenshots (7" and 10") — required per the listing page
- [ ] Content rating questionnaire
- [ ] Target audience declaration
- [ ] Data safety form
- [ ] Ads declaration

Once the store listing is complete, submit the app for review from
**Publishing overview**. First review is typically a few hours to ~2 days.
After it passes, the internal testing link will resolve correctly.

## Android — build artifacts (built locally, 2026-07-13)

Located in `release_apk/` (gitignored, not committed):

| File | Purpose |
|---|---|
| `DokoDocs.aab` | Upload this to Play Console (Internal testing / Production) — Play requires AAB, not APK, for Play App Signing |
| `DokoDocs-arm64-v8a.apk` | Direct-install APK, modern 64-bit ARM devices (most phones) |
| `DokoDocs-armeabi-v7a.apk` | Direct-install APK, older 32-bit ARM devices |
| `DokoDocs-x86_64.apk` | Direct-install APK, emulators/x86 devices |

To rebuild after code changes:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release --split-per-abi   # sideload APKs
flutter build appbundle --release             # Play Store AAB
```

Output paths: `build/app/outputs/flutter-apk/*.apk`,
`build/app/outputs/bundle/release/app-release.aab`.

### To release on Play Store

1. Finish the store listing blockers above and pass initial review.
2. Play Console → Internal testing (or Production) → **Create new release**.
3. Upload `release_apk/DokoDocs.aab`.
4. Fill release notes, save, review, and roll out.

## iOS — requires Codemagic (this machine is Windows, no Xcode)

`codemagic.yaml` already has two workflows configured in this repo:

- **`ios-unsigned`** — sanity build only (`.app`, no code signing). Zero
  setup, confirms the iOS build compiles.
- **`ios-testflight`** — signed `.ipa`, uploaded straight to TestFlight.

### One-time setup needed before `ios-testflight` will work

1. **Apple Developer Program account** ($99/yr) — needed for App Store
   distribution (the free-Mac/USB route in the codemagic.yaml comments is
   TestFlight/App-Store-incompatible, local-device-only).
2. Connect this GitHub repo to [codemagic.io](https://codemagic.io).
3. In Codemagic → your app → **Settings → Code signing identities**:
   upload/generate an Apple Distribution certificate + App Store
   provisioning profile for bundle id `com.dokodocs.dokodocs`.
4. In Codemagic → Teams → **Integrations → App Store Connect**: add an API
   key, then set its integration name in `codemagic.yaml` in place of
   `APP_STORE_CONNECT_KEY_ID`.
5. In App Store Connect: create the app record for `com.dokodocs.dokodocs`,
   enable the "Sign in with Apple" capability on the App ID (the app ships
   the `com.apple.developer.applesignin` entitlement).
6. Push to the branch Codemagic watches, or trigger `ios-testflight`
   manually from the Codemagic dashboard.

Once that's done, every run of `ios-testflight` builds a signed `.ipa` and
uploads it to TestFlight automatically (`submit_to_testflight: true` in
`codemagic.yaml`).

### To release on the App Store

1. Get a build into TestFlight via the above.
2. App Store Connect → your app → fill out the App Store listing
   (screenshots, description, privacy details, age rating, etc. — same
   category of missing info as the Play Store listing above).
3. Submit the TestFlight build for App Store review from App Store Connect.

## Not done by this checklist

Actually clicking "submit for review" / "roll out to production" on either
store is a live-publish action — do that yourself (or ask in-session to
confirm each step) once the listing content above is filled in.
