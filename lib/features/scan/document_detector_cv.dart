import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartcv4/dartcv.dart' as cv;

import 'crop_processor.dart';

/// OpenCV-backed document detection (V2). This is the real fix for devices
/// where ML Kit never runs (e.g. an ML Kit Document Scanner 16.0.0 NPE on some
/// Samsung devices): a proper Canny + contour + quadrilateral detector that
/// works on ANY device, no Google Play services required.
///
/// Returns the four document corners in FULL-resolution pixel coordinates
/// (ordered TL, TR, BR, BL) with a 0..1 confidence, or null when no confident
/// quad is found. Pure top-level functions + primitives, safe for `compute`.
class CvDetection {
  const CvDetection(this.quad, this.confidence);
  final Quad quad;
  final double confidence;
}

/// Detect on an already-loaded byte buffer.
CvDetection? detectDocumentCvBytes(
  Uint8List bytes, {
  int workLongEdge = 700,
  double minAreaFraction = 0.10,
}) {
  cv.Mat? full, small, gray, blur, edges, kernel, closed;
  try {
    full = cv.imdecode(bytes, cv.IMREAD_COLOR);
    if (full.isEmpty) return null;
    final w = full.cols, h = full.rows;
    final longEdge = math.max(w, h);
    final scale = longEdge > workLongEdge ? workLongEdge / longEdge : 1.0;
    final sw = (w * scale).round(), sh = (h * scale).round();

    small = scale < 1.0 ? cv.resize(full, (sw, sh)) : full.clone();
    gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
    blur = cv.gaussianBlur(gray, (5, 5), 0);
    edges = cv.canny(blur, 50, 150);
    // Morphological CLOSE dilates then erodes → bridges small gaps in the
    // Canny edges so a page outline forms ONE closed contour instead of
    // broken segments (the main reason detection was flaky / stuck yellow).
    kernel = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
    closed = cv.morphologyEx(edges, cv.MORPH_CLOSE, kernel);

    final (contours, _) = cv.findContours(
      closed,
      cv.RETR_LIST,
      cv.CHAIN_APPROX_SIMPLE,
    );

    final frameArea = (sw * sh).toDouble();
    double bestArea = 0;
    List<cv.Point>? bestQuad;
    for (final c in contours) {
      final area = cv.contourArea(c);
      if (area < minAreaFraction * frameArea) continue;
      final peri = cv.arcLength(c, true);
      // Try a few epsilon tolerances so a slightly-noisy outline still
      // approximates to a 4-point quad.
      for (final eps in const [0.02, 0.03, 0.05]) {
        final approx = cv.approxPolyDP(c, eps * peri, true);
        if (approx.length == 4 && area > bestArea) {
          bestArea = area;
          bestQuad = [for (final p in approx) p];
          break;
        }
      }
    }
    if (bestQuad == null) return null;
    final quad = bestQuad;

    // Order corners: TL=min(x+y), BR=max(x+y), TR=min(y-x), BL=max(y-x).
    ({double x, double y}) up(cv.Point p) =>
        (x: p.x / scale, y: p.y / scale);
    cv.Point byKey(double Function(cv.Point) k, bool max) {
      var best = quad.first;
      var bestV = k(best);
      for (final p in quad) {
        final v = k(p);
        if (max ? v > bestV : v < bestV) {
          bestV = v;
          best = p;
        }
      }
      return best;
    }

    final tl = up(byKey((p) => (p.x + p.y).toDouble(), false));
    final br = up(byKey((p) => (p.x + p.y).toDouble(), true));
    final tr = up(byKey((p) => (p.y - p.x).toDouble(), false));
    final bl = up(byKey((p) => (p.y - p.x).toDouble(), true));

    // Confidence from DETECTION QUALITY, not just area — a well-formed
    // rectangle should read as high (green) even when the page fills only ~50%
    // of the frame (the reason the border was previously stuck on yellow).
    double d(({double x, double y}) a, ({double x, double y}) b) =>
        math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
    final topW = d(tl, tr), botW = d(bl, br);
    final leftH = d(tl, bl), rightH = d(tr, br);
    // Opposite sides should be similar (rectangular, low perspective skew).
    final wRatio = topW == 0 || botW == 0
        ? 0.0
        : math.min(topW, botW) / math.max(topW, botW);
    final hRatio = leftH == 0 || rightH == 0
        ? 0.0
        : math.min(leftH, rightH) / math.max(leftH, rightH);
    final rectScore = (wRatio + hRatio) / 2; // 0..1
    final frac = (bestArea / frameArea).clamp(0.0, 1.0);
    // Reward a filled, rectangular quad; only penalise a near-full-frame quad
    // (usually weak/false edges).
    final areaScore = frac > 0.95 ? 0.5 : (frac / 0.6).clamp(0.0, 1.0);
    var confidence = 0.35 + 0.5 * rectScore + 0.15 * areaScore;
    confidence = confidence.clamp(0.0, 0.99);

    return CvDetection(Quad(tl, tr, br, bl), confidence);
  } catch (_) {
    // Any FFI/decoding failure → let the caller fall back to the Dart detector.
    return null;
  } finally {
    full?.dispose();
    small?.dispose();
    gray?.dispose();
    blur?.dispose();
    edges?.dispose();
    kernel?.dispose();
    closed?.dispose();
  }
}

/// Isolate-friendly live detection for `compute`: takes encoded (PNG/JPEG)
/// bytes and returns 9 doubles [tlx,tly, trx,try, brx,bry, blx,bly, confidence]
/// or null. Returning a plain List keeps it sendable across isolates (a
/// CvDetection instance is not), so the heavy OpenCV work runs off the UI
/// thread and the camera preview stays smooth.
List<double>? detectQuadCvForIsolate(Uint8List bytes) {
  final hit = detectDocumentCvBytes(bytes);
  if (hit == null) return null;
  final q = hit.quad;
  return [
    q.tl.x, q.tl.y, q.tr.x, q.tr.y,
    q.br.x, q.br.y, q.bl.x, q.bl.y,
    hit.confidence,
  ];
}

/// Detect on a file path (isolate-safe entry for `compute`).
CvDetection? detectDocumentCvFile(String path) {
  try {
    return detectDocumentCvBytes(File(path).readAsBytesSync());
  } catch (_) {
    return null;
  }
}

/// Perspective-warp the quad [corners] (8 doubles TL,TR,BR,BL in source-image
/// pixels) of the image at [srcPath] to a flat rectangle, written as JPEG to
/// [outPath]. Uses OpenCV `getPerspectiveTransform` + `warpPerspective` — more
/// accurate than the pure-Dart bilinear warp. Returns [outPath], or null on
/// failure so the caller can fall back to [rectifyDocument].
String? warpQuadCv(String srcPath, List<double> corners, String outPath) {
  cv.Mat? src, m, out;
  cv.VecPoint? srcPts, dstPts;
  try {
    src = cv.imread(srcPath, flags: cv.IMREAD_COLOR);
    if (src.isEmpty) return null;
    final q = Quad.fromList(corners);
    double dist(({double x, double y}) a, ({double x, double y}) b) =>
        math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
    final wTop = dist(q.tl, q.tr), wBot = dist(q.bl, q.br);
    final hLeft = dist(q.tl, q.bl), hRight = dist(q.tr, q.br);
    final outW = ((wTop + wBot) / 2).round().clamp(1, 10000);
    final outH = ((hLeft + hRight) / 2).round().clamp(1, 10000);

    srcPts = cv.VecPoint.fromList([
      cv.Point(q.tl.x.round(), q.tl.y.round()),
      cv.Point(q.tr.x.round(), q.tr.y.round()),
      cv.Point(q.br.x.round(), q.br.y.round()),
      cv.Point(q.bl.x.round(), q.bl.y.round()),
    ]);
    dstPts = cv.VecPoint.fromList([
      cv.Point(0, 0),
      cv.Point(outW - 1, 0),
      cv.Point(outW - 1, outH - 1),
      cv.Point(0, outH - 1),
    ]);
    m = cv.getPerspectiveTransform(srcPts, dstPts);
    out = cv.warpPerspective(src, m, (outW, outH));
    final (ok, bytes) = cv.imencode('.jpg', out);
    if (!ok) return null;
    File(outPath).writeAsBytesSync(bytes);
    return outPath;
  } catch (_) {
    return null;
  } finally {
    src?.dispose();
    m?.dispose();
    out?.dispose();
    srcPts?.dispose();
    dstPts?.dispose();
  }
}
