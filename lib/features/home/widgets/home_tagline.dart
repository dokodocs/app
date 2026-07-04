import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';

/// The Home tagline band directly under the app bar: "Scan. Organize. Sync."
/// in muted text with "Own Your Data." in brand green, and the Nepali line
/// beneath in muted text. Compact (≤72px) and part of the scroll view, so it
/// scrolls away as the user browses.
class HomeTagline extends StatelessWidget {
  const HomeTagline({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // The secondary line is Nepali script — only show it when the app is
    // actually in Nepali, so English users don't see a stray Devanagari line.
    final isNepali = Localizations.localeOf(context).languageCode == 'ne';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 72),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${l10n.homeTaglineLead} ',
                    style: theme.textTheme.titleMedium?.copyWith(color: muted),
                  ),
                  TextSpan(
                    text: l10n.homeTaglineEmphasis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            if (isNepali) ...[
              const SizedBox(height: 2),
              Text(
                l10n.homeTaglineSecondary,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
