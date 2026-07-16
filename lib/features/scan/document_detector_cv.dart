import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_core/opencv.dart' as cv;

import '../../core/cv/document_segmenter.dart';
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

/// HYBRID ADJUDICATOR — fuse the classical OpenCV detector ([cvHit]) with the
/// ML segmentation result ([mlHit]). Both must be in FULL-resolution pixel
/// coords. Design rule: **the ML result can only help, never hurt** — when in
/// doubt, the proven classical detector wins.
///
///   - ML absent/failed            -> CV result (unchanged behaviour).
///   - CV absent, ML present        -> ML result, confidence kept modest (this
///                                     is the win: cards in clutter where
///                                     classical CV finds nothing).
///   - Both present + high overlap   -> agreement: take ML's mask-snapped quad
///                                     (sharper edges) and bump confidence for
///                                     the mutual corroboration.
///   - Both present + low overlap    -> disagreement: take the more confident;
///                                     a user tap ([focus]) nudges toward ML
///                                     (the reliable path for small cards).
CvDetection? fuseCvAndMl(
  CvDetection? cvHit,
  DocSegResult? mlHit, {
  ({double x, double y})? focus,
}) {
  if (mlHit == null) return cvHit;
  final ml = CvDetection(mlHit.quad, mlHit.confidence);
  if (cvHit == null) return ml;
  final iou = _quadBboxIoU(cvHit.quad, ml.quad);
  if (iou >= 0.6) {
    final conf = (math.max(cvHit.confidence, ml.confidence) + 0.05)
        .clamp(0.0, 0.97);
    return CvDetection(ml.quad, conf);
  }
  // Disagreement: prefer the higher score. A tap biases toward ML (cards).
  var mlScore = ml.confidence;
  if (focus != null) mlScore += 0.05;
  return mlScore > cvHit.confidence ? ml : cvHit;
}

/// Axis-aligned bounding-box IoU of two quads — a cheap, robust "do they agree
/// on roughly the same region?" signal for [fuseCvAndMl]. (Runs every live
/// frame, so polygon IoU would be wasteful here.)
double _quadBboxIoU(Quad a, Quad b) {
  final pa = [a.tl, a.tr, a.br, a.bl];
  final pb = [b.tl, b.tr, b.br, b.bl];
  double xmin(List<({double x, double y})> ps) =>
      ps.fold<double>(1e18, (m, p) => math.min(m, p.x));
  double ymin(List<({double x, double y})> ps) =>
      ps.fold<double>(1e18, (m, p) => math.min(m, p.y));
  double xmax(List<({double x, double y})> ps) =>
      ps.fold<double>(-1e18, (m, p) => math.max(m, p.x));
  double ymax(List<({double x, double y})> ps) =>
      ps.fold<double>(-1e18, (m, p) => math.max(m, p.y));
  final ax0 = xmin(pa), ay0 = ymin(pa), ax1 = xmax(pa), ay1 = ymax(pa);
  final bx0 = xmin(pb), by0 = ymin(pb), bx1 = xmax(pb), by1 = ymax(pb);
  final iw = math.min(ax1, bx1) - math.max(ax0, bx0);
  final ih = math.min(ay1, by1) - math.max(ay0, by0);
  if (iw <= 0 || ih <= 0) return 0;
  final inter = iw * ih;
  final ua = (ax1 - ax0) * (ay1 - ay0) +
      (bx1 - bx0) * (by1 - by0) -
      inter;
  return ua <= 0 ? 0 : (inter / ua).clamp(0.0, 1.0);
}

/// Optional detection trace sink (diagnostics/harness only). When non-null,
/// every `_detectQuadOnGrayMat` call appends one JSON-ready map:
///   { candidates: [{source, corners, score, edgeSupport, rectangularity,
///     brightness, uniformity, areaScore}], winner: `index|-1` }
/// Set it in the SAME isolate that runs detection (the harness runs
/// in-isolate). Null in production — zero overhead.
List<Map<String, dynamic>>? detectionTraceSink;

/// Native image dimensions probe (no pure-Dart decode). Returns null when
/// the bytes can't be decoded or the natives are unavailable.
({int width, int height})? imageDimsCv(Uint8List bytes) {
  cv.Mat? m;
  try {
    // Reduced decode (1/8 size) — we only need dimensions.
    m = cv.imdecode(bytes, cv.IMREAD_REDUCED_GRAYSCALE_8);
    if (m.isEmpty) return null;
    return (width: m.cols * 8, height: m.rows * 8);
  } catch (_) {
    return null;
  } finally {
    m?.dispose();
  }
}

/// Detect on an already-loaded byte buffer.
CvDetection? detectDocumentCvBytes(
  Uint8List bytes, {
  int workLongEdge = 700,
  double minAreaFraction = 0.10,
  String? modelPath,
}) {
  cv.Mat? full, small, gray;
  try {
    full = cv.imdecode(bytes, cv.IMREAD_COLOR);
    if (full.isEmpty) return null;
    final w = full.cols, h = full.rows;
    final longEdge = math.max(w, h);
    final scale = longEdge > workLongEdge ? workLongEdge / longEdge : 1.0;
    final sw = (w * scale).round(), sh = (h * scale).round();

    small = scale < 1.0 ? cv.resize(full, (sw, sh)) : full.clone();
    gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
    final cvHit = _detectQuadOnGrayMat(gray, scale, minAreaFraction);
    if (modelPath == null) return cvHit; // ML disabled -> classical only
    final mlHit = segmentGrayMat(gray, modelPath: modelPath, scaleToFull: scale);
    return fuseCvAndMl(cvHit, mlHit);
  } catch (_) {
    // Any FFI/decoding failure → let the caller fall back to the Dart detector.
    return null;
  } finally {
    full?.dispose();
    small?.dispose();
    gray?.dispose();
  }
}

/// Zero-codec detection on RAW grayscale pixels (V3 live path): builds a Mat
/// straight from [grayBytes] (row-major, [width]×[height], 8-bit) — no PNG or
/// JPEG anywhere — optionally rotates it clockwise by [rotationDegrees]
/// (0/90/180/270, the camera sensor orientation) using native cv.rotate, and
/// runs the shared quad pipeline. Returned corners are in the ROTATED
/// (upright) pixel space; callers normalise against the rotated dimensions
/// ([width]/[height] swapped for 90/270).
CvDetection? detectDocumentCvGray(
  Uint8List grayBytes,
  int width,
  int height, {
  int rotationDegrees = 0,
  double minAreaFraction = 0.10,
  double? focusX,
  double? focusY,
  String? modelPath,
}) {
  cv.Mat? raw, gray;
  try {
    raw = cv.Mat.fromList(height, width, cv.MatType.CV_8UC1, grayBytes);
    switch (rotationDegrees % 360) {
      case 90:
        gray = cv.rotate(raw, cv.ROTATE_90_CLOCKWISE);
      case 180:
        gray = cv.rotate(raw, cv.ROTATE_180);
      case 270:
        gray = cv.rotate(raw, cv.ROTATE_90_COUNTERCLOCKWISE);
      default:
        gray = raw;
    }
    // [focusX]/[focusY] are the user's tap in NORMALISED (0..1) upright
    // preview space — "detect THIS object, ignore the rest".
    final focus = (focusX != null && focusY != null)
        ? (x: focusX * gray.cols, y: focusY * gray.rows)
        : null;
    final cvHit =
        _detectQuadOnGrayMat(gray, 1.0, minAreaFraction, focus: focus);
    if (modelPath == null) return cvHit; // ML disabled -> classical only
    final mlHit = segmentGrayMat(gray, modelPath: modelPath);
    return fuseCvAndMl(cvHit, mlHit, focus: focus);
  } catch (_) {
    return null;
  } finally {
    if (!identical(gray, raw)) gray?.dispose();
    raw?.dispose();
  }
}

/// True when convex quad [q] (ordered TL,TR,BR,BL) contains point [p].
bool _quadContains(List<({double x, double y})> q, ({double x, double y}) p) {
  var sign = 0;
  for (var i = 0; i < 4; i++) {
    final a = q[i], b = q[(i + 1) % 4];
    final cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
    final s = cross > 0 ? 1 : (cross < 0 ? -1 : 0);
    if (s == 0) continue;
    if (sign == 0) {
      sign = s;
    } else if (s != sign) {
      return false;
    }
  }
  return true;
}

/// Shared quad pipeline on an already-grayscale Mat (V3 Step-2 rebuild):
/// SCORED candidate selection instead of "largest 4-point contour wins" —
/// the old rule locked onto any strong rectangle (keyboards, monitors) and
/// its confidence formula (0.35 floor + rectangularity) rated those wrong
/// quads 75–88%.
///
/// Candidates come from TWO sources (auto-Canny edges + Otsu brightness
/// mask), pass HARD rejection filters (border touch, area bounds, convexity,
/// corner angles, degenerate aspect), and the survivors are scored by
/// document-ness: edge support, rectangularity, brighter-inside-than-outside,
/// interior smoothness, and a moderate area preference. Confidence IS the
/// winning score — a wrong quad now scores low instead of green.
CvDetection? _detectQuadOnGrayMat(
  cv.Mat gray,
  double scale,
  double minAreaFraction, {
  ({double x, double y})? focus,
}) {
  cv.Mat? blur, edges, kernel, closed, binary, binClosed;
  try {
    final sw = gray.cols, sh = gray.rows;
    blur = cv.gaussianBlur(gray, (5, 5), 0);
    // ADAPTIVE Canny thresholds from the MEDIAN intensity (more robust to a
    // bright page or dark desk skewing the statistic than the mean).
    final med = _medianU8(blur);
    final lower = (0.66 * med).clamp(0, 255).toDouble();
    final upper = (1.33 * med).clamp(0, 255).toDouble();
    edges = cv.canny(blur, lower, upper);
    // Morphological CLOSE bridges broken paper edges on low-contrast
    // backgrounds (white paper on light wood).
    kernel = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
    closed = cv.morphologyEx(edges, cv.MORPH_CLOSE, kernel);

    // Candidate source 1: contours of the closed edge map.
    final (edgeContours, _) =
        cv.findContours(closed, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
    // Candidate source 2: Otsu binarisation — a document is a BRIGHT,
    // roughly uniform region, so it shows up as a blob in the bright mask
    // even when its Canny outline is broken (the low-contrast failure mode).
    final (_, bin) =
        cv.threshold(blur, 0, 255, cv.THRESH_BINARY + cv.THRESH_OTSU);
    binary = bin;
    // OPEN (erode→dilate), NOT close: the page must be SEPARATED from other
    // bright objects (adjacent papers, notebooks) — close fuses them into one
    // border-touching mega-blob that then fails the border filter (harness
    // fixtures showed exactly this).
    binClosed = cv.morphologyEx(binary, cv.MORPH_OPEN, kernel);
    final (binContours, _) =
        cv.findContours(binClosed, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

    // Candidate source 3: CENTRE-SEEDED FLOOD FILL — the document is where
    // the user aims. Global Otsu fails when a pale desk is nearly as bright
    // as the paper (real-device finding: light wooden desk); a flood fill
    // from centre seeds grows across the page's smooth surface and stops at
    // its printed/physical edges, giving the page region directly even when
    // it runs off-frame or has a card lying on it (interior holes don't
    // affect the outer contour).
    final floodContours = <cv.VecPoint>[];
    // The user's tap (focus) becomes the FIRST flood seed — grow the tapped
    // object's own region directly.
    final seeds = <(double, double)>[
      if (focus != null) (focus.x / sw, focus.y / sh),
      (0.50, 0.55),
      (0.35, 0.50),
      (0.65, 0.50),
      (0.50, 0.35),
      (0.50, 0.72),
    ];
    for (final seed in seeds) {
      cv.Mat? ffMask;
      try {
        ffMask = cv.Mat.zeros(sh + 2, sw + 2, cv.MatType.CV_8UC1);
        // FIXED_RANGE (compare to the SEED's value, not the neighbour):
        // neighbour-diff leaks across the soft, blurred page→desk boundary
        // pixel by pixel (harness: every flood region ballooned past 95% and
        // was area-rejected). Fixed ±25 keeps the fill on paper-bright
        // pixels only — a pale desk is still measurably darker than paper.
        cv.floodFill(
          blur,
          cv.Point((seed.$1 * sw).round(), (seed.$2 * sh).round()),
          cv.Scalar.all(0),
          mask: ffMask,
          loDiff: cv.Scalar.all(25),
          upDiff: cv.Scalar.all(25),
          flags: 4 |
              cv.FLOODFILL_MASK_ONLY |
              cv.FLOODFILL_FIXED_RANGE |
              (255 << 8),
        );
        // floodFill marks the mask's 1-px rim internally, so contouring the
        // raw mask returns ONE whole-mask component (harness: every flood
        // candidate showed area≈1.005 and was rejected). Cut the rim ROI and
        // keep only the 255-filled pixels — this also re-aligns coordinates
        // with the image (the mask is offset by +1).
        final roi = ffMask.region(cv.Rect(1, 1, sw, sh));
        final (_, fill) = cv.threshold(roi, 127, 255, cv.THRESH_BINARY);
        roi.dispose();
        final (cs, _) =
            cv.findContours(fill, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
        fill.dispose();
        // Keep only the largest region per seed (the fill itself).
        cv.VecPoint? largest;
        var largestArea = 0.0;
        for (final c in cs) {
          final a = cv.contourArea(c);
          if (a > largestArea) {
            largestArea = a;
            largest = c;
          }
        }
        if (largest != null && largestArea > 0.03 * sw * sh) {
          // DEEP COPY: `largest` is a view into `cs` (VecVecPoint), which is
          // GC-eligible once this block exits — a dangling native pointer
          // would silently kill the candidate via the catch.
          floodContours
              .add(cv.VecPoint.fromList([for (final p in largest) p]));
        }
      } catch (_) {
        // A failed seed is fine — the other sources still run.
      } finally {
        ffMask?.dispose();
      }
    }

    final frameArea = (sw * sh).toDouble();
    final borderMargin = 0.02 * math.min(sw, sh);

    final trace =
        detectionTraceSink == null ? null : <Map<String, dynamic>>[];
    final rejects = detectionTraceSink == null
        ? null
        : <String, int>{
            'area': 0,
            'no4pt': 0,
            'convex': 0,
            'border': 0,
            'angles': 0,
            'sides': 0,
          };
    var contourCount = 0;
    var winnerIndex = -1;
    _ScoredQuad? best;
    final sources = <(String, Iterable<cv.VecPoint>)>[
      ('canny', edgeContours),
      ('otsu', binContours),
      ('flood', floodContours),
    ];
    for (final (sourceName, contours) in sources) {
      for (final c in contours) {
        contourCount++;
        final area = cv.contourArea(c);
        // HARD filter: area 5%–95% of the frame. 5% admits ID cards and
        // licenses (harness: a real ID card contour measured 6.7%) while the
        // scoring (not area) decides the winner; 15% proved far too strict on
        // real photos where overlapping objects fragment the page contour.
        final minFrac = math.min(minAreaFraction, 0.05);
        if (area < minFrac * frameArea || area > 0.95 * frameArea) {
          if (area > 0.02 * frameArea) {
            rejects?.update('area', (v) => v + 1);
            trace?.add({
              'source': 'rejected:area',
              'areaFrac': area / frameArea,
            });
          }
          continue;
        }
        final peri = cv.arcLength(c, true);
        // Iterate epsilon 1.5%→5% of perimeter for a 4-point approximation.
        cv.VecPoint? quad4;
        for (final eps in const [0.015, 0.02, 0.03, 0.04, 0.05]) {
          final approx = cv.approxPolyDP(c, eps * peri, true);
          if (approx.length == 4) {
            quad4 = approx;
            break;
          }
          approx.dispose();
        }
        if (quad4 == null || !cv.isContourConvex(quad4)) {
          // Retry on the CONVEX HULL: a page whose outline merges with a
          // small overlapping object (stapler, adjacent sheet corner) has a
          // messy contour, but its hull is still essentially the page quad —
          // the scoring then judges whether it's document-like (harness: the
          // attendance-sheet fixtures died here with no4pt).
          quad4?.dispose();
          quad4 = null;
          final hullMat = cv.convexHull(c, returnPoints: true);
          final hull = cv.VecPoint.fromMat(hullMat);
          hullMat.dispose();
          final hullPeri = cv.arcLength(hull, true);
          for (final eps in const [0.02, 0.03, 0.05]) {
            final approx = cv.approxPolyDP(hull, eps * hullPeri, true);
            if (approx.length == 4) {
              quad4 = approx;
              break;
            }
            approx.dispose();
          }
          hull.dispose();
        }
        if (quad4 == null) {
          rejects?.update('no4pt', (v) => v + 1);
          continue;
        }
        // HARD filter: convexity.
        if (!cv.isContourConvex(quad4)) {
          rejects?.update('convex', (v) => v + 1);
          quad4.dispose();
          continue;
        }
        var pts = [for (final p in quad4) (x: p.x.toDouble(), y: p.y.toDouble())];
        // RECTANGLE FALLBACK: if the 4-point approx is not rectangle-shaped
        // (occluded corner under a keyboard, page mid-turn, stacked-page
        // merge), snap to the contour's minAreaRect — a TRUE rotated
        // rectangle by construction (client: detections must be rectangles/
        // squares only), which also reconstructs a hidden corner.
        if (!_anglesSane(_orderCorners(pts)) ||
            !_sidesSane(_orderCorners(pts))) {
          final rr = cv.minAreaRect(c);
          final rrPts = rr.points;
          pts = [for (final p in rrPts) (x: p.x.toDouble(), y: p.y.toDouble())];
          rrPts.dispose();
        }
        final ordered = _orderCorners(pts);
        // HARD filter: no corner within ~2% of the image border — real pages
        // being scanned don't touch the frame edge; frame-hugging quads are
        // the classic false positive.
        var borderCorners = 0;
        for (final p in ordered) {
          if (p.x < borderMargin ||
              p.y < borderMargin ||
              p.x > sw - 1 - borderMargin ||
              p.y > sh - 1 - borderMargin) {
            borderCorners++;
          }
        }
        final touchesBorder = borderCorners > 0;
        // HARD filters: interior angles 55°–125°; opposite sides ratio ≤ 3.
        if (!_anglesSane(ordered) || !_sidesSane(ordered)) {
          if (!_anglesSane(ordered)) {
            rejects?.update('angles', (v) => v + 1);
          } else {
            rejects?.update('sides', (v) => v + 1);
          }
          quad4.dispose();
          continue;
        }
        if (touchesBorder) rejects?.update('border', (v) => v + 1);

        final s = _scoreCandidate(
          gray: gray,
          rawEdges: edges,
          closedEdges: closed,
          quad: quad4,
          ordered: ordered,
          area: area,
          frameArea: frameArea,
        );
        quad4.dispose();
        // HARD filter: rectangle/square ONLY (client requirement). Merged
        // shapes from stacked pages or a page mid-turn approximate to skewed
        // quads that poorly fill their minAreaRect; a real document under
        // moderate perspective stays ≥ ~0.65.
        if (s.rectangularity < 0.6) {
          rejects?.update('sides', (v) => v + 1);
          continue;
        }
        // Border-touching quads are SOFT-penalised, not rejected — and the
        // penalty is GRADUATED by how many corners touch. Harness finding:
        // a real document whose merged blob merely grazes the frame edge
        // (1–2 corners) was being crushed to 0.46 by a flat ×0.65 despite a
        // perfect document-like interior (brightness 1.0, uniformity 0.9);
        // a frame-hugging false positive has 3–4 corners out and still gets
        // squashed hard.
        final borderFactor = switch (borderCorners) {
          0 => 1.0,
          1 => 0.9,
          2 => 0.8,
          _ => 0.6,
        };
        // Tap-to-target: when the user has tapped an object, candidates NOT
        // containing the tap are heavily demoted and the containing ones get
        // a boost — "only draw the green in that object, ignore other". The
        // boost lets a busy little card cross the confidence threshold once
        // the user has explicitly pointed at it.
        final focusFactor = focus == null
            ? 1.0
            : (_quadContains(ordered, focus) ? 1.25 : 0.25);
        final total = s.total * borderFactor * focusFactor;
        trace?.add({
          'source': sourceName,
          'borderPenalty': touchesBorder,
          'corners': [for (final p in ordered) [p.x, p.y]],
          'score': total,
          'edgeSupport': s.edgeSupport,
          'rectangularity': s.rectangularity,
          'brightness': s.brightness,
          'uniformity': s.uniformity,
          'areaScore': s.areaScore,
        });
        if (best == null || total > best.score) {
          best = _ScoredQuad(ordered, total);
          if (trace != null) winnerIndex = trace.length - 1;
        }
      }
    }
    detectionTraceSink?.add({
      'candidates': trace ?? const [],
      'winner': winnerIndex,
      'contours': contourCount,
      'floodContours': floodContours.length,
      'rejects': rejects,
    });
    if (best == null) return null;

    // CORNER REFINEMENT: snap the winning corners to the strongest local
    // gradient corner (sub-pixel) so the green outline hugs the physical
    // page edges instead of the contour approximation — client: "adjust the
    // corner to match edges properly", removes the need to re-crop.
    var refined = best.corners;
    cv.VecPoint2f? cps;
    // cornerSubPix requires every point's (winSize) search window to stay
    // fully inside the image, or it throws a native assertion — which real
    // captures hit constantly (a page filling most of the frame puts corners
    // within a few px of the border). Skip refinement outright when any
    // corner is too close, instead of paying for a native throw/catch on
    // (near enough) every detection.
    const winSize = 11;
    final canRefine = refined.every((p) =>
        p.x >= winSize &&
        p.x <= gray.cols - 1 - winSize &&
        p.y >= winSize &&
        p.y <= gray.rows - 1 - winSize);
    try {
      if (!canRefine) throw StateError('corner too close to border');
      cps = cv.VecPoint2f.fromList([
        for (final p in refined) cv.Point2f(p.x, p.y),
      ]);
      final snapped = cv.cornerSubPix(gray, cps, (winSize, winSize), (-1, -1));
      final cand = [
        for (final p in snapped) (x: p.x.toDouble(), y: p.y.toDouble()),
      ];
      // Accept only small snaps (≤ 2% of the frame per corner) — a corner
      // yanked further than that latched onto text/clutter, not the edge.
      final maxDrift = 0.02 * math.max(gray.cols, gray.rows);
      var ok = true;
      for (var i = 0; i < 4; i++) {
        if (_dist(cand[i], refined[i]) > maxDrift) {
          ok = false;
          break;
        }
      }
      if (ok) refined = cand;
    } catch (_) {
      // Refinement is best-effort — keep the raw corners.
    } finally {
      cps?.dispose();
    }

    ({double x, double y}) up(({double x, double y}) p) =>
        (x: p.x / scale, y: p.y / scale);
    return CvDetection(
      Quad(up(refined[0]), up(refined[1]), up(refined[2]), up(refined[3])),
      best.score.clamp(0.0, 0.99),
    );
  } catch (_) {
    // Any FFI failure → let the caller fall back to the Dart detector.
    return null;
  } finally {
    blur?.dispose();
    edges?.dispose();
    kernel?.dispose();
    closed?.dispose();
    binary?.dispose();
    binClosed?.dispose();
  }
}

class _ScoredQuad {
  const _ScoredQuad(this.corners, this.score);

  /// Ordered TL, TR, BR, BL in working-scale pixels.
  final List<({double x, double y})> corners;
  final double score;
}

/// Median of an 8-bit single-channel Mat via a 256-bin histogram over its
/// raw data — O(n), no sort, no extra Mat.
int _medianU8(cv.Mat m) {
  final data = m.data;
  final hist = List<int>.filled(256, 0);
  for (final v in data) {
    hist[v]++;
  }
  final half = data.length ~/ 2;
  var acc = 0;
  for (var i = 0; i < 256; i++) {
    acc += hist[i];
    if (acc >= half) return i;
  }
  return 128;
}

/// Orders 4 corners TL, TR, BR, BL (TL=min(x+y), BR=max(x+y), TR=min(y−x),
/// BL=max(y−x)).
List<({double x, double y})> _orderCorners(List<({double x, double y})> pts) {
  ({double x, double y}) byKey(
      double Function(({double x, double y})) k, bool max) {
    var best = pts.first;
    var bestV = k(best);
    for (final p in pts) {
      final v = k(p);
      if (max ? v > bestV : v < bestV) {
        bestV = v;
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

double _dist(({double x, double y}) a, ({double x, double y}) b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

/// Every interior angle must be 62°–118° — documents are rectangles/squares
/// under moderate perspective; wider tolerances admitted skewed multi-page
/// merges (stacked pages / page-turning scenes). Client requirement: only
/// rectangle- or square-shaped detections.
bool _anglesSane(List<({double x, double y})> q) {
  for (var i = 0; i < 4; i++) {
    final prev = q[(i + 3) % 4], cur = q[i], next = q[(i + 1) % 4];
    final v1 = (x: prev.x - cur.x, y: prev.y - cur.y);
    final v2 = (x: next.x - cur.x, y: next.y - cur.y);
    final dot = v1.x * v2.x + v1.y * v2.y;
    final n1 = math.sqrt(v1.x * v1.x + v1.y * v1.y);
    final n2 = math.sqrt(v2.x * v2.x + v2.y * v2.y);
    if (n1 == 0 || n2 == 0) return false;
    final deg = math.acos((dot / (n1 * n2)).clamp(-1.0, 1.0)) * 180 / math.pi;
    if (deg < 62 || deg > 118) return false;
  }
  return true;
}

/// Opposite side lengths must be within 3× of each other (degenerate-quad
/// guard).
bool _sidesSane(List<({double x, double y})> q) {
  final top = _dist(q[0], q[1]), bottom = _dist(q[3], q[2]);
  final left = _dist(q[0], q[3]), right = _dist(q[1], q[2]);
  if (top <= 0 || bottom <= 0 || left <= 0 || right <= 0) return false;
  final wr = math.max(top, bottom) / math.min(top, bottom);
  final hr = math.max(left, right) / math.min(left, right);
  return wr <= 3 && hr <= 3;
}

/// Document-ness score, 0..1. Weighted sum of:
///  - edge support (0.30): fraction of the quad's perimeter lying on real
///    (closed) Canny edges — kills quads whose sides cross empty desk.
///  - rectangularity (0.15): quad area / minAreaRect area.
///  - brightness contrast (0.20): interior mean gray minus a surrounding
///    ring's mean — paper is brighter than desks/keyboards.
///  - interior uniformity (0.20): low raw-edge density inside — paper with
///    text is mostly smooth; a keyboard is wall-to-wall gradients.
///  - area (0.15): log-scaled moderate preference, never dominant.
typedef _ScoreBreakdown = ({
  double edgeSupport,
  double rectangularity,
  double brightness,
  double uniformity,
  double areaScore,
  double total,
});

const _ScoreBreakdown _zeroScore = (
  edgeSupport: 0,
  rectangularity: 0,
  brightness: 0,
  uniformity: 0,
  areaScore: 0,
  total: 0,
);

_ScoreBreakdown _scoreCandidate({
  required cv.Mat gray,
  required cv.Mat rawEdges,
  required cv.Mat closedEdges,
  required cv.VecPoint quad,
  required List<({double x, double y})> ordered,
  required double area,
  required double frameArea,
}) {
  cv.Mat? mask, ringKernel, dilated, ring;
  cv.VecVecPoint? polys;
  try {
    final sw = gray.cols, sh = gray.rows;

    // Edge support: sample points along each side, count hits on the closed
    // edge map (3px tolerance via the 9x9-closed map itself).
    final edgeData = closedEdges.data;
    var hits = 0;
    const samplesPerSide = 24;
    // ±2px neighbourhood at each sample: real paper edges are slightly wavy
    // or bent, so a straight quad side drifts a few px off the edge map
    // between corners — strict single-pixel sampling scored REAL documents
    // ~0.34 edge support (harness finding) and kept them below green.
    bool nearEdge(int cx, int cy) {
      for (var dy = -2; dy <= 2; dy++) {
        final y = cy + dy;
        if (y < 0 || y >= sh) continue;
        final row = y * sw;
        for (var dx = -2; dx <= 2; dx++) {
          final x = cx + dx;
          if (x < 0 || x >= sw) continue;
          if (edgeData[row + x] != 0) return true;
        }
      }
      return false;
    }

    for (var s = 0; s < 4; s++) {
      final a = ordered[s], b = ordered[(s + 1) % 4];
      for (var i = 0; i < samplesPerSide; i++) {
        final t = i / (samplesPerSide - 1);
        final x = (a.x + (b.x - a.x) * t).round().clamp(0, sw - 1);
        final y = (a.y + (b.y - a.y) * t).round().clamp(0, sh - 1);
        if (nearEdge(x, y)) hits++;
      }
    }
    final edgeSupport = hits / (4 * samplesPerSide);

    // Rectangularity: area vs the minimal rotated bounding rect.
    final rr = cv.minAreaRect(quad);
    final rrArea = rr.size.width * rr.size.height;
    final rectangularity =
        rrArea <= 0 ? 0.0 : (area / rrArea).clamp(0.0, 1.0);

    // Interior mask + exterior ring.
    mask = cv.Mat.zeros(sh, sw, cv.MatType.CV_8UC1);
    polys = cv.VecVecPoint.fromList([
      [
        for (final p in ordered) cv.Point(p.x.round(), p.y.round()),
      ]
    ]);
    cv.fillPoly(mask, polys, cv.Scalar.all(255));
    ringKernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (25, 25));
    dilated = cv.dilate(mask, ringKernel);
    ring = cv.subtract(dilated, mask);

    // Brightness contrast: |inside − outside|. ABSOLUTE, not signed — an ID
    // card / license / passport is often DARKER than a pale desk; what marks
    // a document is that it differs from its surroundings, either way.
    final inner = cv.mean(gray, mask: mask).val1;
    final outer = cv.mean(gray, mask: ring).val1;
    final brightness = ((inner - outer).abs() / 60.0).clamp(0.0, 1.0);

    // Interior uniformity: raw Canny density inside the quad. Printed text
    // is sparse (~5–10%); a keyboard interior is dense.
    final interiorEdgeDensity = cv.mean(rawEdges, mask: mask).val1 / 255.0;
    final uniformity = (1.0 - interiorEdgeDensity * 4.0).clamp(0.0, 1.0);

    // Moderate, log-scaled area preference.
    final frac = (area / frameArea).clamp(0.0, 1.0);
    final areaScore =
        (math.log(1 + 9 * frac) / math.log(10)).clamp(0.0, 1.0);

    // Card-sized candidates (ID card, license, passport — < 15% of frame)
    // are BUSY by design (photo, hologram, dense print), so interior
    // uniformity would punish them unfairly; their sharp physical edges are
    // the strongest signal instead.
    final small = frac < 0.15;
    final total = small
        ? 0.40 * edgeSupport +
            0.20 * rectangularity +
            0.25 * brightness +
            0.05 * uniformity +
            0.10 * areaScore
        : 0.30 * edgeSupport +
            0.15 * rectangularity +
            0.20 * brightness +
            0.20 * uniformity +
            0.15 * areaScore;
    return (
      edgeSupport: edgeSupport,
      rectangularity: rectangularity,
      brightness: brightness,
      uniformity: uniformity,
      areaScore: areaScore,
      total: total,
    );
  } catch (_) {
    return _zeroScore;
  } finally {
    mask?.dispose();
    ringKernel?.dispose();
    dilated?.dispose();
    ring?.dispose();
    polys?.dispose();
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
