import 'dart:io';

import 'package:dokodocs/core/pdf/pdf_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Guards the PDF builder's dimensions-driven path (the perf change that lets
/// the scan-save pipeline size PDF pages WITHOUT a second full-image decode).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dokodocs_pdf_test_');
  });
  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('buildPdfFromSources writes a PDF using the supplied dimensions', () async {
    final imgPath = p.join(tempDir.path, 'p0.jpg');
    File(imgPath)
        .writeAsBytesSync(img.encodeJpg(img.Image(width: 300, height: 400)));
    final out = p.join(tempDir.path, 'out.pdf');

    final result = await buildPdfFromSources(
      pages: [PdfPageSource(path: imgPath, width: 300, height: 400)],
      outputPath: out,
    );

    expect(result, out);
    expect(File(out).existsSync(), isTrue);
    final bytes = File(out).readAsBytesSync();
    expect(bytes.length, greaterThan(0));
    // PDFs start with the "%PDF" magic bytes.
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('buildPdfFromImages (path-only) still works for arbitrary images', () async {
    final imgPath = p.join(tempDir.path, 'a.jpg');
    File(imgPath)
        .writeAsBytesSync(img.encodeJpg(img.Image(width: 200, height: 200)));
    final out = p.join(tempDir.path, 'a.pdf');

    final result = await buildPdfFromImages(imagePaths: [imgPath], outputPath: out);
    expect(File(result).existsSync(), isTrue);
  });
}
