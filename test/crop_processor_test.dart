import 'dart:io';

import 'package:dokodocs/features/scan/crop_processor.dart';
import 'package:dokodocs/features/scan/image_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Guards the manual-crop perspective warp used for gallery imports and the
/// basic-camera fallback (pages the native scanner never edge-detected).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dokodocs_crop_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('rectifyDocument warps a quad to a proportional flattened JPEG', () async {
    // A 400x400 canvas with a smaller off-square region we "detect" as the doc.
    final src = img.Image(width: 400, height: 400);
    img.fill(src, color: img.ColorRgb8(255, 255, 255));
    final srcPath = p.join(tempDir.path, 'src.jpg');
    File(srcPath).writeAsBytesSync(img.encodeJpg(src));

    final outPath = p.join(tempDir.path, 'out.jpg');
    // Quad ~ 200 wide x 300 tall → output should keep that ~2:3 proportion.
    final req = CropRequest(
      srcPath: srcPath,
      corners: Quad(
        (x: 50, y: 50),
        (x: 250, y: 50),
        (x: 250, y: 350),
        (x: 50, y: 350),
      ).toList(),
      outPath: outPath,
    );

    final result = rectifyDocument(req.toMap());

    expect(result, outPath);
    expect(File(outPath).existsSync(), isTrue);
    final out = img.decodeImage(File(outPath).readAsBytesSync())!;
    // ~200x300 (allow small rounding), NOT the source's 400x400.
    expect(out.width, inInclusiveRange(195, 205));
    expect(out.height, inInclusiveRange(295, 305));
  });

  test('Quad round-trips through its flat list encoding', () {
    final q = Quad((x: 1, y: 2), (x: 3, y: 4), (x: 5, y: 6), (x: 7, y: 8));
    final back = Quad.fromList(q.toList());
    expect(back.tl, q.tl);
    expect(back.tr, q.tr);
    expect(back.br, q.br);
    expect(back.bl, q.bl);
  });

  test('normalizeImageForPipeline passes a decodable JPEG through unchanged',
      () async {
    final im = img.Image(width: 20, height: 20);
    img.fill(im, color: img.ColorRgb8(120, 120, 120));
    final path = p.join(tempDir.path, 'ok.jpg');
    File(path).writeAsBytesSync(img.encodeJpg(im));

    final result = await normalizeImageForPipeline(path);
    expect(result, path); // fast path: already decodable
  });

  test('normalizeImageForPipeline returns null for an undecodable file',
      () async {
    final path = p.join(tempDir.path, 'bad.jpg'); // arbitrary name, not real image bytes
    File(path).writeAsBytesSync([0, 1, 2, 3, 4, 5, 6, 7]);

    final result = await normalizeImageForPipeline(path);
    expect(result, isNull); // skipped, not a crash
  });
}
