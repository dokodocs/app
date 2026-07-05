#!/usr/bin/env bash
# DokoDocs pre-build gate (Part A0 of prompt/launch_app.md).
# Run BEFORE every `flutter build apk|appbundle|ios`. Exits non-zero on any
# mechanical failure so a bad build never leaves the machine / CI.
#
#   bash tool/prebuild_check.sh
#
# Checks the ⚙ items only; manual boxes (launch & smoke-test the artifact)
# are still yours to tick.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
fail=0
red()  { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }
ok()   { printf '  ok    %s\n' "$1"; }
warn() { printf '  warn  %s\n' "$1"; }

echo "DokoDocs pre-build check"

# 1. flutter analyze
if flutter analyze 2>&1 | grep -q 'No issues found'; then ok 'flutter analyze clean'
else red 'flutter analyze reported issues (run: flutter analyze)'; fi

# 2. flutter test
if flutter test >/dev/null 2>&1; then ok 'flutter test passed'; else red 'flutter test failed'; fi

# 3. no debug/staging endpoints in lib/
if grep -rnE 'localhost|10\.0\.2\.2|ngrok' lib/ >/dev/null 2>&1; then
  red 'debug/staging endpoint(s) found in lib/'
else ok 'no localhost/10.0.2.2/ngrok in lib/'; fi

# 3b. stray print()
if grep -rnE '(^|[^A-Za-z_])print\(' lib/ >/dev/null 2>&1; then
  warn 'stray print() in lib/ — confirm each is debug-gated'
else ok 'no stray print() in lib/'; fi

# 4. version reminder
ver=$(grep -E '^version:' pubspec.yaml | head -1 | sed 's/version:[[:space:]]*//')
warn "pubspec version is '$ver' — confirm it is HIGHER than the last store upload"

# 5. Android target SDK >= 36 (Play requires Android 16 for new apps from 2026-08-31).
#    Accept explicit >=36 OR flutter.targetSdkVersion (36 on Flutter 3.44+).
if grep -qE 'targetSdk\s*=\s*flutter\.targetSdkVersion' android/app/build.gradle.kts; then
  ok 'android targetSdk = flutter.targetSdkVersion (36 on Flutter 3.44+) — re-verify after Flutter upgrades'
elif grep -qE 'targetSdk\s*=\s*(3[6-9]|[4-9][0-9])' android/app/build.gradle.kts; then
  ok 'android targetSdk explicitly >= 36'
else
  red 'android targetSdk not >=36 — required for Play from 2026-08-31'
fi

# 6. iOS privacy manifest
if [ -f ios/Runner/PrivacyInfo.xcprivacy ]; then ok 'ios/Runner/PrivacyInfo.xcprivacy present'
else red 'ios/Runner/PrivacyInfo.xcprivacy missing — Apple auto-rejects without it'; fi

# 7. secrets not tracked
if git ls-files | grep -qE 'key\.properties$|\.jks$|\.keystore$'; then
  red 'secret file(s) tracked by git'
else ok 'no keystore/key.properties tracked by git'; fi

echo
if [ "$fail" -gt 0 ]; then
  echo "PRE-BUILD CHECK FAILED ($fail blocking issue(s)). Do not build."
  exit 1
else
  echo "Pre-build check passed. Manual step: launch the build and smoke-test scan->crop->filter->save->PDF->share."
  exit 0
fi
