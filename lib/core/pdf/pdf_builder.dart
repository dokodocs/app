import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One PDF page source: the image file [path] and its pixel [width]/[height].
/// Dimensions are supplied by the caller (from [renderPage]) so the builder
/// never re-decodes the image just to size the page.
class PdfPageSource {
  const PdfPageSource({
    required this.path,
    required this.width,
    required this.height,
  });
  final String path;
  final int width;
  final int height;
}

/// Combines [pages] (in order) into a single PDF at [outputPath], one image
/// per page sized to its own aspect ratio. Runs off the main isolate. The
/// image bytes are embedded as-is (no re-encode) and the page size comes from
/// the supplied dimensions (**no re-decode** — the fast save path).
Future<String> buildPdfFromSources({
  required List<PdfPageSource> pages,
  required String outputPath,
}) {
  return compute(_buildPdfIsolate, _PdfArgs(pages, outputPath));
}

/// Path-only variant kept for callers that don't already know each image's
/// dimensions (editor rebuild, version restore, merge of arbitrary images).
/// It decodes each image once solely to read its size. Prefer
/// [buildPdfFromSources] on the hot scan-save path.
Future<String> buildPdfFromImages({
  required List<String> imagePaths,
  required String outputPath,
}) async {
  final pages = <PdfPageSource>[];
  for (final path in imagePaths) {
    final decoded = img.decodeImage(await File(path).readAsBytes());
    if (decoded == null) {
      throw StateError('Could not decode image at $path');
    }
    pages.add(
      PdfPageSource(path: path, width: decoded.width, height: decoded.height),
    );
  }
  return buildPdfFromSources(pages: pages, outputPath: outputPath);
}

class _PdfArgs {
  const _PdfArgs(this.pages, this.outputPath);
  final List<PdfPageSource> pages;
  final String outputPath;
}

/// Typical phone-camera document scans read comfortably at this DPI when
/// mapped to PDF points (1 point = 1/72 inch); used to size each PDF page
/// to the source image's own dimensions instead of forcing a fixed A4 page.
const _assumedScanDpi = 200.0;

Future<String> _buildPdfIsolate(_PdfArgs args) async {
  final doc = pw.Document();

  for (final page in args.pages) {
    final bytes = await File(page.path).readAsBytes();

    final pageFormat = PdfPageFormat(
      page.width * 72 / _assumedScanDpi,
      page.height * 72 / _assumedScanDpi,
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
