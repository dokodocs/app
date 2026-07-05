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
    case 'warm':
      // Lift red, ease off blue (matches the 'warm' export offsets).
      return const ColorFilter.matrix(<double>[
        1.05, 0, 0, 0, 18, //
        0, 1.0, 0, 0, 4, //
        0, 0, 0.92, 0, -18, //
        0, 0, 0, 1, 0, //
      ]);
    // Professional scan modes. The real shadow-removal/whitening is a spatial
    // operation that can't be a colour matrix, so these are cheap live
    // approximations (brighten + contrast) — the full effect applies on save.
    case 'auto':
      const f = 1.18;
      const t = 128 - 128 * f + 14;
      return const ColorFilter.matrix(<double>[
        f, 0, 0, 0, t, //
        0, f, 0, 0, t, //
        0, 0, f, 0, t, //
        0, 0, 0, 1, 0, //
      ]);
    case 'magic':
      const f = 1.3;
      const t = 128 - 128 * f + 18;
      return const ColorFilter.matrix(<double>[
        f, 0, 0, 0, t, //
        0, f, 0, 0, t, //
        0, 0, f, 0, t, //
        0, 0, 0, 1, 0, //
      ]);
    case 'bw_text':
    case 'receipt':
      // Greyscale + strong contrast (real de-shadow applies on save).
      const f = 2.8;
      const t = 128 - 128 * f + 20;
      return const ColorFilter.matrix(<double>[
        lr * f, lg * f, lb * f, 0, t, //
        lr * f, lg * f, lb * f, 0, t, //
        lr * f, lg * f, lb * f, 0, t, //
        0, 0, 0, 1, 0, //
      ]);
    case 'color':
    case 'book':
      // Gentle colour clean-up.
      const f = 1.08;
      const t = 128 - 128 * f + 8;
      return const ColorFilter.matrix(<double>[
        f, 0, 0, 0, t, //
        0, f, 0, 0, t, //
        0, 0, f, 0, t, //
        0, 0, 0, 1, 0, //
      ]);
    case 'professional':
    case 'hd':
    case 'extreme_clarity':
      // Whitened + contrasty colour (sharpening not previewable via a matrix).
      const f = 1.24;
      const t = 128 - 128 * f + 16;
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
