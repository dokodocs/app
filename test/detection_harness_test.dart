import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:opencv_core/opencv.dart' as cv;
import 'package:dokodocs/features/scan/document_detector_cv.dart';
import 'package:flutter_test/flutter_test.dart';

/// Offline detection harness (V3 Step 1): drop real photos into
/// `test/fixtures/detection/` (white paper on light wood, keyboard clutter,
/// low light, shadow, page filling frame, angled page…) and run
///   flutter test test/detection_harness_test.dart
/// on a host with the OpenCV natives. For every image it writes to
/// `docs/detection_results/`:
///   `name.trace.json` — every candidate with its full score breakdown
///     (edgeSupport / rectangularity / brightness / uniformity / areaScore)
///     plus the winner index, and the final quad + confidence.
/// plus a summary.json table across all fixtures.
///
/// Skips (does not fail) when natives or fixtures are absent, so the normal
/// suite stays green everywhere.
void main() {
  final cvAvailable = () {
    try {
      cv.Mat.fromList(2, 2, cv.MatType.CV_8UC1, Uint8List(4)).dispose();
      return true;
    } catch (_) {
      return false;
    }
  }();

  test('detection harness over fixture images', () async {
    if (!cvAvailable) {
      markTestSkipped('OpenCV natives not available on this host');
      return;
    }
    final fixturesDir = Directory('test/fixtures/detection');
    if (!fixturesDir.existsSync()) {
      markTestSkipped('no fixtures in test/fixtures/detection');
      return;
    }
    final images = fixturesDir
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.jpg') ||
            f.path.endsWith('.jpeg') ||
            f.path.endsWith('.png'))
        .toList();
    if (images.isEmpty) {
      markTestSkipped('no fixture images found');
      return;
    }

    final outDir = Directory('docs/detection_results')
      ..createSync(recursive: true);
    final summary = <Map<String, dynamic>>[];

    for (final f in images) {
      final name = f.uri.pathSegments.last;
      final sink = <Map<String, dynamic>>[];
      detectionTraceSink = sink;
      final sw = Stopwatch()..start();
      final det = detectDocumentCvBytes(f.readAsBytesSync());
      sw.stop();
      detectionTraceSink = null;

      final result = {
        'image': name,
        'engine': 'classical',
        'timeMs': sw.elapsedMilliseconds,
        'confidence': det?.confidence,
        'quad': det == null
            ? null
            : [
                [det.quad.tl.x, det.quad.tl.y],
                [det.quad.tr.x, det.quad.tr.y],
                [det.quad.br.x, det.quad.br.y],
                [det.quad.bl.x, det.quad.bl.y],
              ],
        'trace': sink,
      };
      File('${outDir.path}/$name.trace.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(result));
      summary.add({
        'image': name,
        'found': det != null,
        'confidence': det?.confidence,
        'timeMs': sw.elapsedMilliseconds,
        'candidates':
            sink.isEmpty ? 0 : (sink.last['candidates'] as List).length,
      });
    }

    File('${outDir.path}/summary.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(summary));
    // The harness is diagnostic — it must complete, not judge.
    expect(summary, isNotEmpty);
  });
}
