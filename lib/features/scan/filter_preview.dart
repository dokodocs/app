import 'package:flutter/widgets.dart';

/// Live, on-screen approximation of each scan filter, used so the review and
/// per-page edit previews actually *change* when the user taps a filter chip.
///
/// The real pixel processing happens at export time in [applyFilter]
/// (image package, off the main isolate). Re-encoding on every chip tap would
/// be far too slow for a preview, so here we approximate the same visual
/// result cheaply with a GPU [ColorFilter] colour matrix. The filter keys
/// match the allowed values on the `Pages.filter` drift column.
///
/// Returns null for 'original' (and unknown keys) — the caller should then
/// render the image with no filter.
ColorFilter? previewColorFilter(String filter) {
  // Rec. 709 luminance weights (same desaturation the image package uses).
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;

  switch (filter) {
    case 'grayscale':
      return const ColorFilter.matrix(<double>[
        lr, lg, lb, 0, 0, //
        lr, lg, lb, 0, 0, //
        lr, lg, lb, 0, 0, //
        0, 0, 0, 1, 0, //
      ]);
    case 'bw':
      // Grayscale + hard contrast so text goes near black-on-white.
      const f = 2.4;
      const t = 128 - 128 * f;
      return const ColorFilter.matrix(<double>[
        lr * f, lg * f, lb * f, 0, t, //
        lr * f, lg * f, lb * f, 0, t, //
        lr * f, lg * f, lb * f, 0, t, //
        0, 0, 0, 1, 0, //
      ]);
    case 'lighten':
      return const ColorFilter.matrix(<double>[
        1, 0, 0, 0, 40, //
        0, 1, 0, 0, 40, //
        0, 0, 1, 0, 40, //
        0, 0, 0, 1, 0, //
      ]);
    case 'enhance':
      const f = 1.2;
      const t = 128 - 128 * f;
      return const ColorFilter.matrix(<double>[
        f, 0, 0, 0, t, //
        0, f, 0, 0, t, //
        0, 0, f, 0, t, //
        0, 0, 0, 1, 0, //
      ]);
    case 'high_contrast':
      const f = 1.6;
      const t = 128 - 128 * f;
      return const ColorFilter.matrix(<double>[
        f, 0, 0, 0, t, //
        0, f, 0, 0, t, //
        0, 0, f, 0, t, //
        0, 0, 0, 1, 0, //
      ]);
    case 'original':
    default:
      return null;
  }
}

/// Wraps [child] in the preview colour filter for [filter], or returns it
/// unchanged for 'original'.
Widget filteredPreview({required String filter, required Widget child}) {
  final cf = previewColorFilter(filter);
  if (cf == null) return child;
  return ColorFiltered(colorFilter: cf, child: child);
}
