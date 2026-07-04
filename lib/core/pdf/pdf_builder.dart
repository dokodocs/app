import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Combines [imagePaths] (in order) into a single PDF at [outputPath], one
/// image per page sized to that image's own aspect ratio (rather than
/// forcing every scan onto a fixed A4 page). Runs off the main isolate —
/// Nepal 3GB-RAM performance budget.
Future<String> buildPdfFromImages({
  required List<String> imagePaths,
  required String outputPath,
}) {
  return compute(_buildPdfIsolate, _PdfArgs(imagePaths, outputPath));
}

class _PdfArgs {
  const _PdfArgs(this.imagePaths, this.outputPath);
  final List<String> imagePaths;
  final String outputPath;
}

/// Typical phone-camera document scans read comfortably at this DPI when
/// mapped to PDF points (1 point = 1/72 inch); used to size each PDF page
/// to the source image's own dimensions instead of forcing a fixed A4 page.
const _assumedScanDpi = 200.0;

Future<String> _buildPdfIsolate(_PdfArgs args) async {
  final doc = pw.Document();

  for (final path in args.imagePaths) {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Could not decode image at $path');
    }

    final pageFormat = PdfPageFormat(
      decoded.width * 72 / _assumedScanDpi,
      decoded.height * 72 / _assumedScanDpi,
    );
    final memoryImage = pw.MemoryImage(bytes);

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Image(memoryImage, fit: pw.BoxFit.fill),
      ),
    );
  }

  final bytes = await doc.save();
  final file = File(args.outputPath);
  await file.writeAsBytes(bytes);
  return args.outputPath;
}
