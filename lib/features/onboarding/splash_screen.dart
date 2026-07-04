import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/l10n/app_localizations.dart';

/// Splash: icon + name + tagline, shown for a short fixed delay (or until
/// [onDone] fires sooner from external init work — none needed yet, so
/// this is purely time-based).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1200), widget.onDone);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/logo/logo_dokodocs.svg',
              width: 128,
              height: 128,
              placeholderBuilder: (context) => Image.asset(
                'assets/icon/logo_header.png',
                width: 96,
                height: 96,
              ),
            ),
            const SizedBox(height: 16),
            Text(l10n.appTitle, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              l10n.onboardingTagline,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
