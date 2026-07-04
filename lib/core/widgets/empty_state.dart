import 'package:flutter/material.dart';

/// One reusable empty-state layout — circular tinted icon container,
/// title, body, optional primary/secondary actions — used everywhere an
/// empty-state appears (Home, Folders, Search-no-results, Trash) so the
/// copy/visual language stays consistent. Copy rule: invitation, not
/// apology — e.g. "Scan your first document", never "No documents found".
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.secondaryLine,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String title;
  final String body;

  /// An optional fixed brand line shown under [body] regardless of the
  /// active locale (e.g. Home's Nepali tagline) — not run through l10n by
  /// design, same rationale as the onboarding language picker's labels.
  final String? secondaryLine;

  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Centers when it fits, scrolls instead of overflowing when it
    // doesn't: this widget renders inside variable, sometimes-tight
    // vertical space (e.g. Home's search bar + folder-chip row above it).
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: _content(context, theme)),
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 32,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (secondaryLine != null) ...[
              const SizedBox(height: 4),
              Text(
                secondaryLine!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (primaryActionLabel != null) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onPrimaryAction,
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                ),
                child: Text(primaryActionLabel!),
              ),
            ],
            if (secondaryActionLabel != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSecondaryAction,
                child: Text(secondaryActionLabel!),
              ),
            ],
          ],
        ),
      );
  }
}

