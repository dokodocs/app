import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import 'onboarding_screen.dart';

/// 3 swipeable value pages, page dots, Skip — jumps straight to [onDone]
/// (the permission priming step) either via Skip or after the last page.
class ValuePagesScreen extends StatefulWidget {
  const ValuePagesScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<ValuePagesScreen> createState() => _ValuePagesScreenState();
}

class _ValuePagesScreenState extends State<ValuePagesScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = [
      ValuePage(
        icon: Icons.document_scanner_outlined,
        imageAsset: 'assets/illustrations/onboard_scan.png',
        title: l10n.onboardingPage1Title,
        body: l10n.onboardingPage1Body,
      ),
      ValuePage(
        icon: Icons.smartphone_outlined,
        imageAsset: 'assets/illustrations/onboard_organize.png',
        title: l10n.onboardingLocalFirstTitle,
        body: l10n.onboardingLocalFirstBody,
      ),
      ValuePage(
        icon: Icons.sync_outlined,
        imageAsset: 'assets/illustrations/onboard_own.png',
        title: l10n.onboardingPage3Title,
        body: l10n.onboardingPage3Body,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: widget.onDone,
                child: Text(l10n.onboardingSkip),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (index) => setState(() => _index = index),
                children: pages,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton(
                onPressed: () {
                  if (_index == pages.length - 1) {
                    widget.onDone();
                  } else {
                    _controller.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                },
                child: Text(l10n.onboardingContinue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
