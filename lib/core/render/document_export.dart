import 'dart:io';

import '../database/database.dart';
import 'page_renderer.dart';
import 'watermark_asset.dart';

/// The DokoDocs watermark is ALWAYS applied at export time and cannot be
/// turned off — it's rendered onto the processed copy only, never the
/// immutable original (non-destructive rule intact). Kept as a function
/// (rather than inlining `true`) so every render path routes through one
/// place and only the position remains user-configurable.
bool resolveWatermark(UserSetting settings, {required int pageCount}) {
  return true;
}

/// Re-renders every page of a document from its IMMUTABLE original, applying
/// each page's filter/rotation and the resolved watermark, refreshing the
/// cached processed preview (`localImagePath`) in place, and returns the
/// processed paths in page order. Nothing touches `originalImagePath`.
Future<List<String>> renderProcessedPages({
  required List<DocPage> pages,
  required bool watermark,
  required String watermarkPosition,
}) async {
  final logo = watermark ? await loadWatermarkLogo() : null;
  final out = <String>[];
  for (final page in pages) {
    // If the original is missing (e.g. legacy row pre-backfill), fall back to
    // the cached preview so export still succeeds.
    final source = await File(page.originalImagePath).exists()
        ? page.originalImagePath
        : page.localImagePath;
    final rendered = await renderPage(
      originalPath: source,
      destPath: page.localImagePath,
      filter: page.filter,
      rotationDegrees: page.rotation,
      watermark: watermark,
      watermarkPosition: watermarkPosition,
      watermarkLogo: logo,
    );
    out.add(rendered.path);
  }
  return out;
}
