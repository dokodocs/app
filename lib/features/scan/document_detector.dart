import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../../core/perf/scan_perf.dart';
import 'crop_processor.dart';
import 'document_detector_cv.dart';

/// Isolate-safe entry point (for `compute`): decode the image at [path],
/// detect the document quad, and return its 8 corner doubles (TL,TR,BR,BL in
/// full-res pixels), or null if nothing confident was found.
List<double>? detectQuadInFile(String path) {
  // Prefer the OpenCV detector (V2) — far more accurate and works with no
  // Google Play services. Fall back to the pure-Dart detector if OpenCV
  // finds nothing or is unavailable.
  final cvHit = detectDocumentCvFile(path);
  if (cvHit != null) return cvHit.quad.toList();
  final bytes = File(path).readAsBytesSync();
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  return detectDocumentQuad(image)?.toList();
}

/// Confidence thresholds shared by the capture flow (mirrors the spec):
/// ≥ high → auto-crop and skip the editor; ≥ medium → auto-crop but open the
/// editor for optional tweaks; below → open the editor for manual correction.
/// Recalibrated for the V3 scored-candidate detector: confidence is now an
/// HONEST document-ness score (edge support + rectangularity + brightness +
/// uniformity + area), not the old 0.35-floor formula that rated keyboards
/// 75–88%. A clean page in fair light scores ~0.6–0.9; clutter scores <0.5.
const kHighConfidence = 0.65;
const kMediumConfidence = 0.50;

/// Isolate-safe full-resolution re-detection + confidence-gated auto-crop.
///
/// After capture we re-run detection on the FULL-resolution still (not the
/// low-res preview), expand the quad by a small safety margin so no edge is
/// clipped, perspective-correct it flat, and write the result. Returns a map:
///   { 'path': String, 'confidence': double, 'cropped': bool }
/// `cropped` is false (and `path` is the untouched original) when confidence
/// is too low to trust — the caller then opens the manual editor.
Map<String, dynamic> autoDetectAndCrop(Map<String, dynamic> args) {
  final srcPath = args['srcPath'] as String;
  final outPath = args['outPath'] as String;
  final bytes =
      ScanPerf.time('page.read', () => File(srcPath).readAsBytesSync());

  // NATIVE-FIRST — no pure-Dart 12 MP decode. The old flow started with
  // `img.decodeImage(bytes)` (~20–30 s per page on a budget phone: the
  // ">4 minutes to save 3 pages" complaint) even when OpenCV then did all
  // the real work. Now: native detect → native dims → native warp; the
  // Dart decode happens ONLY on the no-natives fallback path.
  final cvHit =
      ScanPerf.time('page.detectCv', () => detectDocumentCvBytes(bytes));
  if (cvHit != null) {
    if (cvHit.confidence < kMediumConfidence) {
      return {'path': srcPath, 'confidence': cvHit.confidence, 'cropped': false};
    }
    final dims = ScanPerf.time('page.dimsCv', () => imageDimsCv(bytes));
    if (dims != null) {
      final expanded =
          _expandQuad(cvHit.quad, dims.width, dims.height);
      final warped = ScanPerf.time(
          'page.warpCv', () => warpQuadCv(srcPath, expanded.toList(), outPath));
      if (warped != null) {
        return {
          'path': outPath,
          'confidence': cvHit.confidence,
          'cropped': true,
        };
      }
    }
    // Native warp failed → fall through to the Dart pipeline below.
  }

  // PURE-DART FALLBACK (OpenCV unavailable/failed): decode + weak detector +
  // bilinear warp — slow, but only ever runs when the natives are missing.
  final image = ScanPerf.time('page.decode', () => img.decodeImage(bytes));
  if (image == null) {
    return {'path': srcPath, 'confidence': 0.0, 'cropped': false};
  }
  final dartHit = detectDocument(image);
  final quad = cvHit?.quad ?? dartHit?.quad;
  final confidence = cvHit?.confidence ?? dartHit?.confidence ?? 0.0;
  if (quad == null || confidence < kMediumConfidence) {
    return {'path': srcPath, 'confidence': confidence, 'cropped': false};
  }
  final expanded = _expandQuad(quad, image.width, image.height);
  rectifyDocument(CropRequest(
    srcPath: srcPath,
    corners: expanded.toList(),
    outPath: outPath,
  ).toMap());
  return {'path': outPath, 'confidence': confidence, 'cropped': true};
}

/// Expands [q] outward by ~2.5% of the frame per side (clamped) so text /
/// stamps near the edge are never clipped.
Quad _expandQuad(Quad q, int width, int height) {
  final mx = width * 0.025;
  final my = height * 0.025;
  ({double x, double y}) grow(({double x, double y}) p, double dx, double dy) =>
      (
        x: (p.x + dx).clamp(0, width - 1).toDouble(),
        y: (p.y + dy).clamp(0, height - 1).toDouble(),
      );
  return Quad(
    grow(q.tl, -mx, -my),
    grow(q.tr, mx, -my),
    grow(q.br, mx, my),
    grow(q.bl, -mx, my),
  );
}

/// Lightweight, dependency-free document-quad detector.
///
/// The native ML Kit / VisionKit scanner does this far better, but it isn't
/// available on every device (missing Google Play services) and never runs on
/// gallery imports. This gives those paths a real detected border instead of
/// nothing — good enough to seed the crop editor's draggable corners and to
/// paint a live green outline over the camera preview.
///
/// Approach (classic + cheap): downscale, build a mask of "page-like" pixels
/// (bright and low-saturation — white/most paper on a darker/contrasting
/// background), then take the mask's extreme points as the four corners:
///   top-left  = min(x+y),  bottom-right = max(x+y)
///   top-right = max(x-y),  bottom-left  = min(x-y)
/// Returns corners in FULL-resolution [srcW]x[srcH] coordinates, or null when
/// the page fills too little of the frame (so we never show a false border).
/// A detected document with a 0..1 [confidence] (used to colour the live
/// border green/orange/red and to gate the "document detected" indicator).
class DocDetection {
  const DocDetection(this.quad, this.confidence);
  final Quad quad;
  final double confidence;
}

/// Back-compat convenience: returns just the quad when a document is detected
/// with usable confidence, else null.
Quad? detectDocumentQuad(
  img.Image image, {
  int workWidth = 320,
}) =>
    detectDocument(image, workWidth: workWidth)?.quad;

/// Strict document detection. Returns null unless a genuinely page-like region
/// is found — one that is bounded (NOT the whole frame), reasonably large, and
/// densely fills its own bounding box (real paper does; scattered bright
/// clutter doesn't). This is what stops the previous behaviour of "always
/// detected" with edges that were really just the extremes of every bright
/// pixel in the frame.
DocDetection? detectDocument(
  img.Image image, {
  int workWidth = 320,
  double minAreaFraction = 0.10,
  double maxAreaFraction = 0.96,
  double minFillRatio = 0.55,
}) {
  final scale = workWidth / image.width;
  final w = workWidth;
  final h = (image.height * scale).round();
  if (w < 8 || h < 8) return null;
  final small = img.copyResize(image, width: w, height: h);

  var sum = 0.0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      sum += img.getLuminance(small.getPixel(x, y));
    }
  }
  final mean = sum / (w * h);
  final threshold = math.min(245.0, mean * 1.10 + 14);

  double minSum = 1e9, maxSum = -1e9, minDiff = 1e9, maxDiff = -1e9;
  ({double x, double y})? tl, tr, br, bl;
  var count = 0;
  var minX = w, minY = h, maxX = 0, maxY = 0;

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y);
      if (img.getLuminance(p) < threshold) continue;
      final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
      final mx = math.max(r, math.max(g, b));
      final mn = math.min(r, math.min(g, b));
      final sat = mx <= 0 ? 0 : (mx - mn) / mx;
      if (sat > 0.5) continue;

      count++;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      final s = (x + y).toDouble();
      final d = (x - y).toDouble();
      if (s < minSum) { minSum = s; tl = (x: x.toDouble(), y: y.toDouble()); }
      if (s > maxSum) { maxSum = s; br = (x: x.toDouble(), y: y.toDouble()); }
      if (d > maxDiff) { maxDiff = d; tr = (x: x.toDouble(), y: y.toDouble()); }
      if (d < minDiff) { minDiff = d; bl = (x: x.toDouble(), y: y.toDouble()); }
    }
  }
  if (tl == null || tr == null || br == null || bl == null) return null;

  final boxW = (maxX - minX).toDouble();
  final boxH = (maxY - minY).toDouble();
  final boxArea = boxW * boxH;
  if (boxArea <= 0) return null;

  final frameArea = (w * h).toDouble();
  final areaFrac = boxArea / frameArea;
  // Too small → not a page. Nearly the whole frame → no real edges were
  // found (the old false-positive), so report nothing rather than a fake
  // full-frame border.
  if (areaFrac < minAreaFraction || areaFrac > maxAreaFraction) return null;

  // Fill ratio: how much of the bounding box is actually bright paper. Real
  // pages fill their box densely; scattered bright clutter does not.
  final fillRatio = count / boxArea;
  if (fillRatio < minFillRatio) return null;

  // Quad must be a sane convex-ish rectangle: opposite sides comparable.
  final topW = _dist(tl, tr), botW = _dist(bl, br);
  final leftH = _dist(tl, bl), rightH = _dist(tr, br);
  if (topW < 8 || botW < 8 || leftH < 8 || rightH < 8) return null;
  final wRatio = math.min(topW, botW) / math.max(topW, botW);
  final hRatio = math.min(leftH, rightH) / math.max(leftH, rightH);
  if (wRatio < 0.55 || hRatio < 0.55) return null; // too skewed → distrust

  // Confidence blends fill density and rectangularity.
  final confidence =
      (fillRatio.clamp(0.0, 1.0) * 0.5 + (wRatio + hRatio) / 2 * 0.5)
          .clamp(0.0, 1.0);

  ({double x, double y}) up(({double x, double y}) pt) =>
      (x: pt.x / scale, y: pt.y / scale);
  return DocDetection(Quad(up(tl), up(tr), up(br), up(bl)), confidence);
}

double _dist(({double x, double y}) a, ({double x, double y}) b) {
  final dx = a.x - b.x, dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}
