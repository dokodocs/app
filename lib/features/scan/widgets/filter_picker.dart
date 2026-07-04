import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';

/// Horizontal filter chip row — Original/Grayscale/B&W/Lighten/Enhance/High
/// contrast, matching the allowed values on the `Pages.filter` drift column.
class FilterPicker extends StatelessWidget {
  const FilterPicker({
    super.key,
    required this.selectedFilter,
    required this.onSelected,
  });

  final String selectedFilter;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <String, String>{
      'original': l10n.scanFilterOriginal,
      'grayscale': l10n.scanFilterGrayscale,
      'bw': l10n.scanFilterBw,
      'lighten': l10n.scanFilterLighten,
      'enhance': l10n.scanFilterEnhance,
      'high_contrast': l10n.scanFilterHighContrast,
    };

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final entry in options.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(entry.value),
                selected: selectedFilter == entry.key,
                onSelected: (_) => onSelected(entry.key),
              ),
            ),
        ],
      ),
    );
  }
}
