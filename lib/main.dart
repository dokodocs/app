import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/app_localizations.dart';
import 'core/navigation/app_shell.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/onboarding_flow.dart';
import 'features/settings/providers/settings_provider.dart';

void main() {
  runApp(const ProviderScope(child: DokoDocsApp()));
}

class DokoDocsApp extends ConsumerWidget {
  const DokoDocsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(userSettingsProvider);
    final settings = settingsAsync.value;

    return MaterialApp(
      title: 'DokoDocs',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (settings?.theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      locale: settings == null ? null : Locale(settings.language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: settings == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : settings.onboardingComplete
          ? const AppShell()
          : OnboardingFlow(
              onFinished: () {
                // onboardingComplete flips in the DB; this widget tree
                // rebuilds via userSettingsProvider and swaps to HomeScreen
                // on its own — nothing else to do here.
              },
            ),
    );
  }
}
