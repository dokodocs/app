// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:opencv_core/opencv.dart' as cv;

// tflite_flutter pulls in a native library (libtensorflowlite_c). It may be
// absent on a dev host (Windows) — every call below is guarded so the segmenter
// no-ops to null and the classical detector stays the source of truth.
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../features/scan/crop_processor.dart';

/// The square input size the model was trained/exported at (see
/// `tool/dataset/train_seg_model.py --img-size`). Must match the bundled
/// `assets/models/docseg.tflite` (+ its `.tflite.json` sidecar).
const int kDocSegModelSize = 160;

/// Path of the bundled model asset.
const String kDocSegAsset = 'assets/models/docseg.tflite';

/// One ML document-detection result, in the SAME coordinate space as the
/// [cv.Mat] it was run on (working-scale pixels), ordered TL,TR,BR,BL —
/// directly comparable to a [CvDetection].
class DocSegResult {
  const DocSegResult(this.quad, this.confidence, this.maskAreaFraction);
  final Quad quad;
  final double confidence;

  /// Fraction of the mask that is foreground (diagnostic + fusion signal).
  final double maskAreaFraction;
}

// --------------------------------------------------------------------------- //
// Main-isolate: stage the model on disk so any background isolate can read it
// with plain File I/O (rootBundle/platform channels are NOT available in a
// `compute()` isolate without extra setup; a cached file works everywhere).
// --------------------------------------------------------------------------- //
String? _cachedModelPath;

/// Copies the bundled `.tflite` asset into the app's cache directory (once) and
/// returns its path, or null when the model asset is missing/unreadable. Call
/// from the MAIN isolate (e.g. camera setup) and pass the returned path to the
/// worker isolate / `compute` args. Cross-platform: works identically on
/// Android and iOS (Flutter asset bundle + platform cache dir).
Future<String?> ensureDocSegModelFile({bool force = false}) async {
  if (_cachedModelPath != null && !force) return _cachedModelPath;
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/dokodocs_docseg.tflite');
    if (!file.existsSync() || force) {
      final bytes = await rootBundle.load(kDocSegAsset);
      final data = bytes.buffer.asUint8List();
      await file.writeAsBytes(data, flush: true);
    }
    _cachedModelPath = file.path;
    return _cachedModelPath;
  } catch (_) {
    // Asset missing or FS unwritable → ML disabled; classical CV still works.
    return null;
  }
}

// --------------------------------------------------------------------------- //
// Isolate-side inference. A static interpreter cache means each isolate builds
// it at most once (the live worker is persistent; a `compute` isolate builds it
// once per call — cheap for a 1.9 MB model).
// --------------------------------------------------------------------------- //
Interpreter? _interpreter;
String? _interpreterForPath;

Interpreter? _interpreterFor(String? modelPath) {
  if (modelPath == null) return null;
  if (_interpreter != null && _interpreterForPath == modelPath) {
    return _interpreter;
  }
  try {
    final bytes = File(modelPath).readAsBytesSync();
    _interpreter?.close();
    _interpreter = Interpreter.fromBuffer(bytes);
    _interpreterForPath = modelPath;
    return _interpreter;
  } catch (_) {
    // TFLite native lib missing / model unreadable → no ML this isolate.
    _interpreter = null;
    _interpreterForPath = null;
    return null;
  }
}

/// Run the segmentation model on [gray] (a CV_8UC1 Mat at working scale) and
/// return the detected document quad in FULL-resolution pixels (TL,TR,BR,BL)
/// with an honest 0..1 confidence, or null when the model is unavailable / finds
/// no document. [scaleToFull] converts working-scale -> full-res (working/scale);
/// pass 1.0 when the Mat is already full-res (the live path).
///
/// This is a thin wrapper over [segmentGrayMatWithMask] that discards the
/// mask — kept for callers that only need the quad/confidence.
DocSegResult? segmentGrayMat(
  cv.Mat gray, {
  String? modelPath,
  double scaleToFull = 1.0,
}) {
  final r = segmentGrayMatWithMask(gray, modelPath: modelPath, scaleToFull: scaleToFull);
  r.mask?.dispose();
  return r.result;
}

/// Like [segmentGrayMat], but ALSO returns the model's document mask
/// upscaled to [gray]'s own resolution and dilated for margin — a binary
/// (0/255) [cv.Mat] the SAME size as [gray], regardless of [scaleToFull].
///
/// This lets a caller restrict classical CV contour search (Canny/Otsu) to
/// the region the neural net actually believes is the document, BEFORE
/// scoring — mask-first, not fuse-after. A keyboard or monitor sitting
/// outside the mask simply never generates a CV candidate, rather than
/// being scored and possibly winning. The returned mask is null whenever
/// [result] is null (model unavailable or no confident document region);
/// callers own it and must dispose it.
({DocSegResult? result, cv.Mat? mask}) segmentGrayMatWithMask(
  cv.Mat gray, {
  String? modelPath,
  double scaleToFull = 1.0,
}) {
  final interp = _interpreterFor(modelPath);
  if (interp == null) return (result: null, mask: null);
  final sw = gray.cols, sh = gray.rows;
  if (sw < 8 || sh < 8) return (result: null, mask: null);
  final N = kDocSegModelSize;

  cv.Mat? resized, bin, maskN, upMask, marginKernel, dilatedMask;
  cv.VecVecPoint? maskPoly;
  try {
    // 1) Build the float input: resize gray -> NxN (aspect squashed, matching
    //    training), normalise to 0..1.
    resized = cv.resize(gray, (N, N));
    final px = resized.data; // Uint8List, length N*N
    // Nested list shaped [1,N,N,1] (tflite_flutter infers float32 from double).
    final rows = List.generate(
      N,
      (y) => List.generate(
        N,
        (x) => <double>[px[y * N + x] / 255.0],
      ),
    );
    final input = [rows];
    final out = [
      List.generate(N, (y) => List.generate(N, (x) => <double>[0.0]))
    ];
    interp.run(input, {0: out});

    // 2) Flatten the mask + statistics.
    final flat = Float32List(N * N);
    var sum = 0.0;
    for (var y = 0; y < N; y++) {
      for (var x = 0; x < N; x++) {
        final v = out[0][y][x][0].clamp(0.0, 1.0);
        flat[y * N + x] = v;
        sum += v;
      }
    }
    final areaFraction = (sum / (N * N)).clamp(0.0, 1.0);
    // A document should occupy a sane fraction of the frame.
    if (areaFraction < 0.02 || areaFraction > 0.98) {
      return (result: null, mask: null);
    }

    // 3) Threshold -> binary mask Mat, find the LARGEST contour -> quad.
    final binBytes = Uint8List(N * N);
    var white = 0;
    var certSum = 0.0;
    for (var i = 0; i < flat.length; i++) {
      final on = flat[i] > 0.5;
      binBytes[i] = on ? 255 : 0;
      if (on) {
        white++;
        certSum += flat[i];
      }
    }
    final certainty = white == 0 ? 0.0 : (certSum / white);
    bin = cv.Mat.fromList(N, N, cv.MatType.CV_8UC1, binBytes);
    final (contours, _) =
        cv.findContours(bin, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
    if (contours.isEmpty) return (result: null, mask: null);
    cv.VecPoint? largest;
    var largestArea = 0.0;
    for (final c in contours) {
      final a = cv.contourArea(c);
      if (a > largestArea) {
        largestArea = a;
        largest = c;
      }
    }
    if (largest == null) return (result: null, mask: null);
    // ROBUST quad: minAreaRect over the document region. approxPolyDP can
    // return coincident / degenerate points on a real-photo mask (seen on
    // actual user scans: two corners collapsed to one point, producing a
    // triangle instead of a quad); minAreaRect ALWAYS yields a valid rotated
    // rectangle. The precise corners are refined downstream by the
    // mask-constrained CV detector + cornerSubPix, so a tight bounding
    // rectangle here is the right trade (robustness over sub-pixel exactness).
    final rrDoc = cv.minAreaRect(largest);
    final rrDocPts = rrDoc.points;
    final quadPts = _orderCornersDart(
        [for (final p in rrDocPts) (p.x.toDouble(), p.y.toDouble())]);
    rrDocPts.dispose();

    // 4) Rescale from N x N mask space -> working-scale, then working -> FULL-res
    //    (working/scaleToFull) so the result matches the CV detector's coords.
    final wx = sw / N, wy = sh / N;
    final s = scaleToFull <= 0 ? 1.0 : scaleToFull;
    ({double x, double y}) up(double x, double y) =>
        (x: x * wx / s, y: y * wy / s);
    final quad = Quad(
      up(quadPts[0].$1, quadPts[0].$2),
      up(quadPts[1].$1, quadPts[1].$2),
      up(quadPts[2].$1, quadPts[2].$2),
      up(quadPts[3].$1, quadPts[3].$2),
    );

    // 5) Honest confidence: blend log-scaled area preference with model
    //    certainty. Kept modest (<= 0.9) so the FUSION logic, not this number
    //    alone, decides ML vs CV — ML can only win when it genuinely agrees or
    //    when the classical detector failed.
    final frac = (largestArea / (N * N)).clamp(0.0, 1.0);
    final areaScore = (math.log(1 + 9 * frac) / math.log(10)).clamp(0.0, 1.0);
    final conf = (0.45 * areaScore + 0.55 * certainty).clamp(0.0, 0.9);
    final result = DocSegResult(quad, conf, frac);

    // 6) Build the working-scale search mask: fill the LARGEST contour (not
    //    the raw thresholded blob — that can have stray specks) at N x N,
    //    upscale to gray's own resolution with NEAREST (a mask has no
    //    business being interpolated), then dilate by ~6% of the shorter
    //    side so a slightly-tight segmentation doesn't clip the true page
    //    edge out of the CV search region.
    maskN = cv.Mat.zeros(N, N, cv.MatType.CV_8UC1);
    maskPoly = cv.VecVecPoint.fromList([
      [for (final p in largest) p]
    ]);
    cv.fillPoly(maskN, maskPoly, cv.Scalar.all(255));
    upMask = cv.resize(maskN, (sw, sh), interpolation: cv.INTER_NEAREST);
    final dilatePx = math.max(3, (0.06 * math.min(sw, sh)).round());
    marginKernel =
        cv.getStructuringElement(cv.MORPH_ELLIPSE, (dilatePx, dilatePx));
    dilatedMask = cv.dilate(upMask, marginKernel);

    final ownedMask = dilatedMask;
    dilatedMask = null; // ownership transferred to the caller
    return (result: result, mask: ownedMask);
  } catch (_) {
    return (result: null, mask: null);
  } finally {
    resized?.dispose();
    bin?.dispose();
    maskN?.dispose();
    upMask?.dispose();
    marginKernel?.dispose();
    dilatedMask?.dispose();
    maskPoly?.dispose();
  }
}

/// Order 4 points TL,TR,BR,BL (same rule as the classical detector's
/// `_orderCorners`): TL=min(x+y), BR=max(x+y), TR=min(y-x), BL=max(y-x).
List<(double, double)> _orderCornersDart(List<(double, double)> pts) {
  (double, double) byKey(
      double Function((double, double)) k, bool max) {
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
    byKey((p) => p.$1 + p.$2, false), // TL
    byKey((p) => p.$2 - p.$1, false), // TR
    byKey((p) => p.$1 + p.$2, true), // BR
    byKey((p) => p.$2 - p.$1, true), // BL
  ];
}

