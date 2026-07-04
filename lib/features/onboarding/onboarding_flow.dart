import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database_provider.dart';
import 'language_picker_screen.dart';
import 'permission_priming_screen.dart';
import 'splash_screen.dart';
import 'value_pages_screen.dart';

/// Orchestrates the first-launch journey: splash -> language -> 3 value
/// pages -> permission priming -> marks `UserSettings.onboardingComplete`
/// and hands off to [onFinished] (Home). Gated by that same flag in
/// `main.dart` — this widget itself doesn't check it, so it doubles as
/// the "Replay intro" flow from Settings > About.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

enum _Step { splash, language, valuePages, permission }

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  _Step _step = _Step.splash;

  void _advance(_Step next) => setState(() => _step = next);

  Future<void> _finish() async {
    await ref
        .read(userSettingsRepositoryProvider)
        .setOnboardingComplete(true);
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      _Step.splash => SplashScreen(
        onDone: () => _advance(_Step.language),
      ),
      _Step.language => LanguagePickerScreen(
        onDone: () => _advance(_Step.valuePages),
      ),
      _Step.valuePages => ValuePagesScreen(
        onDone: () => _advance(_Step.permission),
      ),
      _Step.permission => PermissionPrimingScreen(onDone: _finish),
    };
  }
}
