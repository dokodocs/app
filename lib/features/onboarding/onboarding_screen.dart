import 'package:flutter/material.dart';

/// Reusable "value page" content — icon, title, one-line body — used for
/// each of the 3 swipeable pages in the onboarding flow (see
/// `value_pages_screen.dart`). Kept in this file (rather than moved/
/// renamed) since this project's working rules treat deleting files as a
/// stop-and-ask action; this widget is the evolution of Phase 0's single
/// local-first explainer screen, now generalized to take any icon/title/
/// body rather than hardcoding the local-first copy.
class ValuePage extends StatelessWidget {
  const ValuePage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.imageAsset,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Optional illustration shown instead of [icon]. [icon] stays as the
  /// fallback if the asset is missing or not provided.
  final String? imageAsset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imageAsset != null)
            Image.asset(
              imageAsset!,
              height: 240,
              fit: BoxFit.contain,
              errorBuilder: (context, _, __) =>
                  Icon(icon, size: 72, color: theme.colorScheme.primary),
            )
          else
            Icon(icon, size: 72, color: theme.colorScheme.primary),
          const SizedBox(height: 28),
          Text(
            title,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            body,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
