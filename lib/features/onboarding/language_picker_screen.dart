import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database_provider.dart';
import '../../core/l10n/app_localizations.dart';

/// Two large tappable cards — English / नेपाली. Switches the app locale
/// immediately (via `UserSettings.language`, watched reactively by
/// `main.dart`) so the rest of onboarding renders in the chosen language.
class LanguagePickerScreen extends ConsumerWidget {
  const LanguagePickerScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                l10n.onboardingChooseLanguage,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _LanguageCard(
                label: l10n.languageNameEnglish,
                onTap: () => _select(ref, 'en'),
              ),
              const SizedBox(height: 16),
              _LanguageCard(
                label: l10n.languageNameNepali,
                onTap: () => _select(ref, 'ne'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _select(WidgetRef ref, String languageCode) async {
    await ref.read(userSettingsRepositoryProvider).setLanguage(languageCode);
    onDone();
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Text(label, style: Theme.of(context).textTheme.headlineSmall),
          ),
        ),
      ),
    );
  }
}
