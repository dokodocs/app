# DokoDocs pre-build gate (Part A0 of prompt/launch_app.md).
# Run BEFORE every `flutter build apk|appbundle|ios`. Exits non-zero on any
# mechanical failure so a bad build never leaves the machine.
#
#   pwsh tool/prebuild_check.ps1
#
# Checks the ⚙ items only; the manual boxes (launch & smoke-test the artifact)
# are still yours to tick.

$ErrorActionPreference = 'Continue'
$fail = 0
function Fail($m) { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:fail++ }
function Pass($m) { Write-Host "  ok    $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  warn  $m" -ForegroundColor Yellow }

$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
Write-Host "DokoDocs pre-build check" -ForegroundColor Cyan

# 1. flutter analyze
$analyze = & flutter analyze 2>&1 | Out-String
if ($analyze -match 'No issues found') { Pass 'flutter analyze clean' }
else { Fail 'flutter analyze reported issues (run: flutter analyze)' }

# 2. flutter test
& flutter test *> $null
if ($?) { Pass 'flutter test passed' } else { Fail 'flutter test failed' }

# 3. no debug/staging endpoints or stray print in lib/
$badPatterns = 'localhost','10\.0\.2\.2','ngrok'
$hits = Select-String -Path (Join-Path $root 'lib\*') -Pattern $badPatterns -Recurse -ErrorAction SilentlyContinue
if ($hits) { Fail "debug/staging endpoint(s) found in lib/: $($hits.Count) match(es)" }
else { Pass 'no localhost/10.0.2.2/ngrok in lib/' }

$prints = Select-String -Path (Join-Path $root 'lib\*') -Pattern '(?<![A-Za-z_])print\(' -Recurse -ErrorAction SilentlyContinue
if ($prints) { Warn "stray print() in lib/: $($prints.Count) — confirm each is debug-gated" }
else { Pass 'no stray print() in lib/' }

# 4. version bumped since last git tag/commit (best-effort reminder)
$ver = (Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(.+)$').Matches.Groups[1].Value
if ($ver) { Warn "pubspec version is '$ver' — confirm it is HIGHER than the last store upload" }

# 5. Android target SDK >= 36 (Play requires Android 16 for new apps from 2026-08-31).
#    Accept an explicit literal >=36, OR `flutter.targetSdkVersion` which tracks
#    Flutter's latest (36 on Flutter 3.44+). Fail only on an explicit low literal.
$gradle = Get-Content (Join-Path $root 'android\app\build.gradle.kts') -Raw
if ($gradle -match 'targetSdk\s*=\s*flutter\.targetSdkVersion') {
  Pass 'android targetSdk = flutter.targetSdkVersion (36 on Flutter 3.44+) — re-verify after Flutter upgrades'
} elseif ($gradle -match 'targetSdk\s*=\s*(3[6-9]|[4-9]\d)') {
  Pass 'android targetSdk explicitly >= 36'
} else {
  Fail 'android targetSdk not >=36 — required for Play from 2026-08-31 (edit android/app/build.gradle.kts)'
}

# 6. iOS privacy manifest present
if (Test-Path (Join-Path $root 'ios\Runner\PrivacyInfo.xcprivacy')) {
  Pass 'ios/Runner/PrivacyInfo.xcprivacy present'
} else {
  Fail 'ios/Runner/PrivacyInfo.xcprivacy missing — Apple auto-rejects without it'
}

# 7. secrets not tracked by git
$tracked = & git ls-files 2>$null | Select-String -Pattern 'key\.properties$|\.jks$|\.keystore$'
if ($tracked) { Fail "secret file(s) tracked by git: $tracked" }
else { Pass 'no keystore/key.properties tracked by git' }

Write-Host ""
if ($fail -gt 0) {
  Write-Host "PRE-BUILD CHECK FAILED ($fail blocking issue(s)). Do not build." -ForegroundColor Red
  exit 1
} else {
  Write-Host "Pre-build check passed. Manual step: launch the build and smoke-test scan->crop->filter->save->PDF->share." -ForegroundColor Green
  exit 0
}
