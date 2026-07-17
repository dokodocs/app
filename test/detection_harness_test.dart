import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:opencv_core/opencv.dart' as cv;
import 'package:dokodocs/features/scan/document_detector_cv.dart';
import 'package:flutter_test/flutter_test.dart';

/// Offline detection harness (V3 Step 1 → v2 benchmarking): drops real photos
/// into `test/fixtures/detection/` (recursively — the tracked
/// `synthetic/` set ships 162 DokoDocs-generated composites; a maintainer may
/// add gitignored `raw/` frames) and runs
///   flutter test test/detection_harness_test.dart
/// on a host with the OpenCV natives. For every image it writes to
/// `docs/detection_results/` (gitignored):
///   `name.trace.json` — every candidate with its full score breakdown
///     (edgeSupport / rectangularity / brightness / uniformity / areaScore)
///     plus the winner index, the final quad + confidence, and — when a sibling
///     `<name>.json` fixture exists — the IoU vs ground truth.
/// plus:
///   `summary.json`     — per-image row table.
///   `by_category.json` — per-category aggregates (count, mean/median/min IoU,
///                        pass-rate at IoU≥0.75, mean confidence + time).
///   `iou_report.md`    — human-readable per-category table.
///
/// The harness is diagnostic — it must complete and report, not judge. It
/// skips (does not fail) when natives or fixtures are absent, so the normal
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

  test('detection harness over fixture images (per-category IoU)', () async {
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
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.jpg') ||
            f.path.endsWith('.jpeg') ||
            f.path.endsWith('.png'))
        .where((f) => !f.path.endsWith('.thumbnail.png'))
        .toList();
    if (images.isEmpty) {
      markTestSkipped('no fixture images found');
      return;
    }

    final outDir = Directory('docs/detection_results')
      ..createSync(recursive: true);
    final summary = <Map<String, dynamic>>[];
    final byCategory = <String, _CategoryAccum>{};

    for (final f in images) {
      final name = f.uri.pathSegments.last;
      final sink = <Map<String, dynamic>>[];
      detectionTraceSink = sink;
      final sw = Stopwatch()..start();
      final det = detectDocumentCvBytes(f.readAsBytesSync());
      sw.stop();
      detectionTraceSink = null;

      // Optional sibling fixture JSON: ground-truth corners + tags.
      final baseName = f.uri.pathSegments.last;
      final jsonPath =
          '${f.parent.path}/${baseName.replaceAll(RegExp(r'\.(jpg|jpeg|png)$'), '.json')}';
      final fixtureFile = File(jsonPath);
      Map<String, dynamic>? fixture;
      if (fixtureFile.existsSync()) {
        try {
          fixture =
              jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
        } catch (_) {
          fixture = null;
        }
      }

      final predQuad = det == null
          ? null
          : [
              [det.quad.tl.x, det.quad.tl.y],
              [det.quad.tr.x, det.quad.tr.y],
              [det.quad.br.x, det.quad.br.y],
              [det.quad.bl.x, det.quad.bl.y],
            ];

      final gtCorners = (fixture?['corners'] as List?)
          ?.map((e) => (e as List).map((c) => (c as num).toDouble()).toList())
          .toList();
      final iou = (gtCorners != null && gtCorners.length == 4)
          ? (predQuad != null ? quadIoU(gtCorners, predQuad) : 0.0)
          : null;

      final result = {
        'image': name,
        'engine': 'classical',
        'timeMs': sw.elapsedMilliseconds,
        'confidence': det?.confidence,
        'quad': predQuad,
        'groundTruth': gtCorners,
        'iou': iou,
        'tags': fixture?['tags'],
        'trace': sink,
      };
      File('${outDir.path}/$name.trace.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(result));
      summary.add({
        'image': name,
        'found': det != null,
        'confidence': det?.confidence,
        'timeMs': sw.elapsedMilliseconds,
        'iou': iou,
        'tags': fixture?['tags'],
        'candidates':
            sink.isEmpty ? 0 : (sink.last['candidates'] as List).length,
      });

      if (iou != null) {
        final category = _categoryOf(fixture?['tags']);
        byCategory.putIfAbsent(category, () => _CategoryAccum())
          ..ious.add(iou)
          ..confidences.add(det?.confidence ?? 0.0)
          ..timesMs.add(sw.elapsedMilliseconds);
      }
    }

    File('${outDir.path}/summary.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(summary));

    // Per-category aggregates.
    final catRows = <Map<String, dynamic>>[];
    byCategory.forEach((cat, a) {
      catRows.add({
        'category': cat,
        'count': a.ious.length,
        'meanIoU': _mean(a.ious),
        'medianIoU': _median(a.ious),
        'minIoU': a.ious.reduce(_min),
        'passRateIoU075': a.ious.where((v) => v >= 0.75).length /
            a.ious.length,
        'meanConfidence': _mean(a.confidences),
        'meanTimeMs': _mean(a.timesMs.map((t) => t.toDouble()).toList()),
      });
    });
    catRows.sort((a, b) =>
        (a['category'] as String).compareTo(b['category'] as String));
    File('${outDir.path}/by_category.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(catRows));

    // Human-readable report.
    final buf = StringBuffer('# Detection harness — per-category IoU\n\n')
      ..writeln('Images with ground truth: '
          '${byCategory.values.fold<int>(0, (s, a) => s + a.ious.length)}')
      ..writeln();
    buf.writeln('| category | n | mean IoU | median IoU | min IoU | '
        'pass@0.75 | mean conf | mean ms |');
    buf.writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
    for (final r in catRows) {
      buf.writeln('| ${r['category']} | ${r['count']} | '
          '${(r['meanIoU'] as double).toStringAsFixed(3)} | '
          '${(r['medianIoU'] as double).toStringAsFixed(3)} | '
          '${(r['minIoU'] as double).toStringAsFixed(3)} | '
          '${((r['passRateIoU075'] as double) * 100).toStringAsFixed(0)}% | '
          '${(r['meanConfidence'] as double).toStringAsFixed(3)} | '
          '${(r['meanTimeMs'] as double).toStringAsFixed(0)} |');
    }
    File('${outDir.path}/iou_report.md').writeAsStringSync(buf.toString());

    // Echo the table to the test log for at-a-glance reading.
    // ignore: avoid_print
    print(buf.toString);

    expect(summary, isNotEmpty);
    if (byCategory.isNotEmpty) {
      expect(catRows, isNotEmpty);
    }
  });
}

// --------------------------------------------------------------------------- //
// Per-category accumulator
// --------------------------------------------------------------------------- //
class _CategoryAccum {
  final List<double> ious = [];
  final List<double> confidences = [];
  final List<int> timesMs = [];
}

String _categoryOf(Object? tags) {
  if (tags is List) {
    for (final t in tags) {
      if (t is String && t != 'synthdocs') return t;
    }
  }
  return 'untagged';
}

double _mean(List<double> xs) => xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

double _median(List<double> xs) {
  if (xs.isEmpty) return 0;
  final s = List<double>.of(xs)..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

double _min(double a, double b) => a < b ? a : b;

// --------------------------------------------------------------------------- //
// Polygon IoU between two convex quads (pure Dart, no OpenCV binding guess).
// Intersection via Sutherland–Hodgman clipping (centroid-side inside test, so
// it is robust to either winding); area via the shoelace formula.
// --------------------------------------------------------------------------- //
typedef _Pt = ({double x, double y});

List<_Pt> _orderQuad(List<List<double>> raw) {
  final pts = raw
      .map((p) => (x: p[0].toDouble(), y: p[1].toDouble()))
      .toList();
  _Pt byKey(double Function(_Pt) k, bool max) {
    var best = pts.first;
    var bv = k(best);
    for (final p in pts) {
      final v = k(p);
      if (max ? v > bv : v < bv) {
        bv = v;
        best = p;
      }
    }
    return best;
  }

  return [
    byKey((p) => p.x + p.y, false), // TL
    byKey((p) => p.y - p.x, false), // TR
    byKey((p) => p.x + p.y, true), // BR
    byKey((p) => p.y - p.x, true), // BL
  ];
}

double _polyArea(List<_Pt> poly) {
  var s = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i], b = poly[(i + 1) % poly.length];
    s += a.x * b.y - b.x * a.y;
  }
  return s.abs() / 2;
}

double _cross(_Pt a, _Pt b, _Pt p) =>
    (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);

_Pt _segIntersect(_Pt p1, _Pt p2, _Pt p3, _Pt p4) {
  final d = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x);
  if (d == 0) return p2; // parallel — degenerate, snap to endpoint.
  final t = ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / d;
  return (x: p1.x + t * (p2.x - p1.x), y: p1.y + t * (p2.y - p1.y));
}

/// Clip convex `subject` by convex `clip` (Sutherland–Hodgman, centroid-side
/// inside test — winding-agnostic).
List<_Pt> _clip(List<_Pt> subject, List<_Pt> clip) {
  double cx = 0, cy = 0;
  for (final p in clip) {
    cx += p.x;
    cy += p.y;
  }
  final cen = (x: cx / clip.length, y: cy / clip.length);
  var output = List<_Pt>.of(subject);
  for (var i = 0; i < clip.length; i++) {
    final a = clip[i], b = clip[(i + 1) % clip.length];
    final cenSide = _cross(a, b, cen);
    final input = output;
    output = [];
    if (input.isEmpty) break;
    var s = input.last;
    for (final e in input) {
      final eIn = _cross(a, b, e) * cenSide >= 0;
      final sIn = _cross(a, b, s) * cenSide >= 0;
      if (eIn) {
        if (!sIn) output.add(_segIntersect(s, e, a, b));
        output.add(e);
      } else if (sIn) {
        output.add(_segIntersect(s, e, a, b));
      }
      s = e;
    }
  }
  return output;
}

/// Intersection-over-union of two quadrilaterals (each 4 [x,y] points, any
/// order). Returns 0 when either has zero area or there is no overlap.
double quadIoU(List<List<double>> a, List<List<double>> b) {
  if (a.length != 4 || b.length != 4) return 0;
  final qa = _orderQuad(a), qb = _orderQuad(b);
  final aa = _polyArea(qa), ab = _polyArea(qb);
  if (aa <= 0 || ab <= 0) return 0;
  final inter = _polyArea(_clip(qa, qb));
  final union = aa + ab - inter;
  return union <= 0 ? 0 : (inter / union).clamp(0.0, 1.0);
}
