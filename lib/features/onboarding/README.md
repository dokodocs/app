# onboarding

**Status:** implemented (Stage B of the combined Phase 1 + First-Launch Journey build). Gated by `UserSettings.onboardingComplete`.

## Responsibility
First-launch journey: splash → language picker → 3 swipeable value pages → camera permission priming → Home. Spec §4 screen 1, expanded per the "First-Launch Journey" prompt. Also reachable anytime via Settings > About > "Replay intro".

## Key packages
- `flutter_riverpod` — `UserSettings.onboardingComplete` read/write via `userSettingsRepositoryProvider`
- `permission_handler` — camera permission request on the priming screen
- `core/l10n` — every string localized (en/ne), including language-picker labels that intentionally always show each language's own name regardless of active locale

## Contents
- `onboarding_flow.dart` — orchestrates the 4 steps via a simple internal `switch`, no external router needed
- `splash_screen.dart` — icon/name/tagline, ~1.2s auto-advance
- `language_picker_screen.dart` — two large cards, switches `UserSettings.language` immediately
- `value_pages_screen.dart` — `PageView` of 3 pages, dots, Skip
- `onboarding_screen.dart` — `ValuePage`, the reusable icon/title/body widget used by the 3 value pages (this file is Phase 0's original single explainer screen, generalized rather than replaced/deleted)
- `permission_priming_screen.dart` — proactive camera-access explainer; denied/permanently-denied paths offer retry / "Open settings" but never dead-end onboarding

`main.dart` shows `OnboardingFlow` or `HomeScreen` reactively based on `UserSettings.onboardingComplete` (watched via `userSettingsProvider`) — no navigation call needed on completion, the DB flag flip alone swaps the screen.
