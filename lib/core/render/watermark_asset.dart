import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// Loads (and caches) the DokoDocs logo mark used in the export watermark.
///
/// The page renderer runs inside a background isolate (via `compute`) where
/// `rootBundle` is unavailable, so the bytes must be read on the main isolate
/// and passed in. Cached after first read since the asset never changes.
Uint8List? _cachedLogo;

Future<Uint8List> loadWatermarkLogo() async {
  final cached = _cachedLogo;
  if (cached != null) return cached;
  final data = await rootBundle.load('assets/logo/logo_mark.png');
  final bytes = data.buffer.asUint8List();
  _cachedLogo = bytes;
  return bytes;
}
