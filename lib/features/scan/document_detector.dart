import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'crop_processor.dart';

/// Isolate-safe entry point (for `compute`): decode the image at [path],
/// detect the document quad, and return its 8 corner doubles (TL,TR,BR,BL in
/// full-res pixels), or null if nothing confident was found.
List<double>? detectQuadInFile(String path) {
  final bytes = File(path).readAsBytesSync();
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  return detectDocumentQuad(image)?.toList();
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
Quad? detectDocumentQuad(
  img.Image image, {
  int workWidth = 320,
  double minAreaFraction = 0.12,
}) {
  final scale = workWidth / image.width;
  final w = workWidth;
  final h = (image.height * scale).round();
  if (w < 8 || h < 8) return null;
  final small = img.copyResize(image, width: w, height: h);

  // Adaptive brightness threshold: mean luminance of the frame, biased up a
  // little so only genuinely bright (paper) pixels pass.
  var sum = 0.0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y);
      sum += img.getLuminance(p);
    }
  }
  final mean = sum / (w * h);
  final threshold = math.min(245.0, mean * 1.08 + 12);

  double minSum = 1e9, maxSum = -1e9, minDiff = 1e9, maxDiff = -1e9;
  ({double x, double y})? tl, tr, br, bl;
  var count = 0;
  var minX = w, minY = h, maxX = 0, maxY = 0;

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y);
      final lum = img.getLuminance(p);
      if (lum < threshold) continue;
      // Low saturation guard: reject strongly coloured bright areas so a
      // bright background object is less likely to hijack the detection.
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

  // Reject when the detected region is too small (avoid false borders).
  final boxArea = (maxX - minX) * (maxY - minY);
  if (boxArea <= 0 || boxArea < minAreaFraction * w * h) return null;
  if (count < 0.04 * w * h) return null;

  // Map back to full-resolution coordinates.
  ({double x, double y}) up(({double x, double y}) pt) =>
      (x: pt.x / scale, y: pt.y / scale);

  return Quad(up(tl), up(tr), up(br), up(bl));
}
