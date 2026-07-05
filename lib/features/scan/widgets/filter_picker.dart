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
      // Professional scan modes first (shadow-removed, whitened, sharpened).
      'auto': l10n.scanFilterAuto,
      'magic': l10n.scanFilterMagic,
      'color': l10n.scanFilterColor,
      'professional': l10n.scanFilterProfessional,
      'hd': l10n.scanFilterHd,
      'extreme_clarity': l10n.scanFilterExtremeClarity,
      'receipt': l10n.scanFilterReceipt,
      'book': l10n.scanFilterBook,
      'bw_text': l10n.scanFilterBwText,
      'original': l10n.scanFilterOriginal,
      'grayscale': l10n.scanFilterGrayscale,
      'bw': l10n.scanFilterBw,
      'lighten': l10n.scanFilterLighten,
      'enhance': l10n.scanFilterEnhance,
      'high_contrast': l10n.scanFilterHighContrast,
      'warm': l10n.scanFilterWarm,
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
