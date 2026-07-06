import 'dart:typed_data';

import 'package:opencv_core/opencv.dart' as cv;
import 'package:dokodocs/core/cv/cv_worker.dart';
import 'package:dokodocs/features/scan/document_detector_cv.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the V3 live-detection hot path: the zero-codec gray detector and
/// the long-lived cv_worker isolate protocol (latest-only mailbox, rotation
/// handling, dispose safety).
///
/// The OpenCV-dependent tests SKIP when the dartcv native library is not
/// loadable on the test host (e.g. a dev machine without dartcv.dll) — they
/// run for real on hosts/CI with the natives present and on-device. The
/// worker-protocol tests that don't need a successful detection always run.
void main() {
  final cvAvailable = () {
    try {
      cv.Mat.fromList(2, 2, cv.MatType.CV_8UC1, Uint8List(4)).dispose();
      return true;
    } catch (_) {
      return false;
    }
  }();
  final skipCv = cvAvailable
      ? null
      : 'dartcv native library not available on this test host';
  /// A synthetic raw grayscale frame: bright page on a dark desk.
  /// Page occupies x in [40,160), y in [40,220) of a 200×260 frame.
  Uint8List page({int w = 200, int h = 260}) {
    final bytes = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final onPage = x >= 40 && x < 160 && y >= 40 && y < 220;
        bytes[y * w + x] = onPage ? 245 : 20;
      }
    }
    return bytes;
  }

  group('detectDocumentCvGray (zero-codec)', skip: skipCv, () {
    test('finds a bright page on a dark background', () {
      final det = detectDocumentCvGray(page(), 200, 260);
      expect(det, isNotNull);
      expect(det!.confidence, greaterThan(0.7));
      final q = det.quad;
      expect(q.tl.x, closeTo(40, 12));
      expect(q.tl.y, closeTo(40, 12));
      expect(q.br.x, closeTo(160, 12));
      expect(q.br.y, closeTo(220, 12));
    });

    test('returns null on a uniform frame', () {
      final det =
          detectDocumentCvGray(Uint8List.fromList(List.filled(200 * 200, 240)),
              200, 200);
      expect(det, isNull);
    });

    test('90° rotation lands corners in rotated space', () {
      // Landscape sensor frame 260×200; after 90° CW it is 200×260 upright.
      final w = 260, h = 200;
      final bytes = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final onPage = x >= 40 && x < 220 && y >= 40 && y < 160;
          bytes[y * w + x] = onPage ? 245 : 20;
        }
      }
      final det = detectDocumentCvGray(bytes, w, h, rotationDegrees: 90);
      expect(det, isNotNull);
      final q = det!.quad;
      // Rotated frame is 200 wide × 260 tall; page becomes 40..160 × 40..220.
      expect(q.br.x, lessThanOrEqualTo(200));
      expect(q.br.y, lessThanOrEqualTo(260));
      expect(q.tl.x, closeTo(40, 12));
      expect(q.br.y, closeTo(220, 12));
    });
  });

  group('CvWorker', () {
    test('round-trips a detection through the isolate', skip: skipCv,
        () async {
      final worker = await CvWorker.spawn();
      try {
        final hit = await worker.detect(page(), 200, 260);
        expect(hit, isNotNull);
        expect(hit!.width, 200);
        expect(hit.height, 260);
        expect(hit.corners.length, 8);
        expect(hit.confidence, greaterThan(0.7));
      } finally {
        worker.dispose();
      }
    });

    test('reports rotated dimensions for 90° frames', skip: skipCv, () async {
      final worker = await CvWorker.spawn();
      try {
        final hit = await worker.detect(
          Uint8List(260 * 200)..fillRange(0, 260 * 200, 20),
          260,
          200,
          rotationDegrees: 90,
        );
        // Uniform frame → no quad, but dims logic is exercised via a real
        // page below.
        expect(hit, isNull);
        final bytes = Uint8List(260 * 200);
        for (var y = 0; y < 200; y++) {
          for (var x = 0; x < 260; x++) {
            final onPage = x >= 40 && x < 220 && y >= 40 && y < 160;
            bytes[y * 260 + x] = onPage ? 245 : 20;
          }
        }
        final hit2 =
            await worker.detect(bytes, 260, 200, rotationDegrees: 90);
        expect(hit2, isNotNull);
        expect(hit2!.width, 200);
        expect(hit2.height, 260);
      } finally {
        worker.dispose();
      }
    });

    test('latest-only mailbox supersedes queued frames', skip: skipCv,
        () async {
      final worker = await CvWorker.spawn();
      try {
        final frame = page();
        // Fire 5 without awaiting: #0 dispatches, #1..#3 get replaced in the
        // queue by #4, so they must resolve null; #0 and #4 must resolve.
        final futures = [
          for (var i = 0; i < 5; i++) worker.detect(frame, 200, 260),
        ];
        final results = await Future.wait(futures);
        expect(results[0], isNotNull, reason: 'in-flight frame completes');
        expect(results[1], isNull);
        expect(results[2], isNull);
        expect(results[3], isNull);
        expect(results[4], isNotNull, reason: 'latest queued frame completes');
      } finally {
        worker.dispose();
      }
    });

    test('dispose resolves pending requests with null and detect after '
        'dispose returns null', () async {
      final worker = await CvWorker.spawn();
      final pending = worker.detect(page(), 200, 260);
      worker.dispose();
      // In-flight may complete with a result or null depending on timing —
      // it must simply complete without throwing.
      await pending;
      expect(await worker.detect(page(), 200, 260), isNull);
    });
  });
}
