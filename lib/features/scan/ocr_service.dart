import 'package:flutter/foundation.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

/// Offline OCR (V2.7) via Tesseract — no Google Play services / ML Kit.
///
/// Runs on the native side (the plugin manages its own threads), so it is
/// safe to call without blocking the UI. Callers should fire-and-forget it
/// AFTER a document is saved and update the `ocr_text` column when it
/// completes, so scanning/saving stays instant and search gets full text once
/// recognition finishes.
class OcrService {
  const OcrService();

  /// Recognises text in the images at [imagePaths] (a document's pages, in
  /// order) and returns the concatenated text. Never throws — returns what it
  /// could read (empty string if none), so a bad page can't break the flow.
  Future<String> recognizePages(List<String> imagePaths) async {
    final buffer = StringBuffer();
    for (final path in imagePaths) {
      try {
        final text = await FlutterTesseractOcr.extractText(
          path,
          language: 'eng',
          args: {
            'preserve_interword_spaces': '1',
          },
        );
        final trimmed = text.trim();
        if (trimmed.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.write('\n\n');
          buffer.write(trimmed);
        }
      } catch (e) {
        debugPrint('OCR failed for $path: $e');
      }
    }
    return buffer.toString();
  }
}
