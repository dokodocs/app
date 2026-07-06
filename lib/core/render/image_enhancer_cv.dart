import 'dart:io';
import 'dart:typed_data';

import 'package:opencv_core/opencv.dart' as cv;

import 'image_enhancer.dart' show ScanMode;

/// FULLY-NATIVE page render (V3 save-speed fix): decode → cap to 2600 px →
/// filter → rotate → watermark → JPEG encode, all in OpenCV. The pure-Dart
/// `image` pipeline decoded a 12 MP capture and re-encoded it in Dart —
/// ~20 s per page on a budget phone, i.e. the ">2 minutes for 5 pages"
/// complaint. This path does the same work natively in well under a second.
///
/// Returns the final (width, height) written to [destPath], or null when the
/// filter isn't cv-mappable or anything fails — the caller then falls back
/// to the pure-Dart renderer, so output is never lost.
({int width, int height})? renderDocumentCv({
  required String srcPath,
  required String destPath,
  required String filter,
  required int rotationDegrees,
  required bool watermark,
  String watermarkPosition = 'bottom_right',
}) {
  // Filters this native path can produce. Legacy pure-Dart-only filters
  // ('bw', 'lighten', 'enhance', 'high_contrast') fall back.
  final mode = switch (filter) {
    'auto' => ScanMode.auto,
    'magic' => ScanMode.magic,
    'bw_text' => ScanMode.bwText,
    'color' => ScanMode.color,
    'professional' => ScanMode.professional,
    'hd' => ScanMode.hd,
    'extreme_clarity' => ScanMode.extremeClarity,
    'receipt' => ScanMode.receipt,
    'book' => ScanMode.book,
    'original' || 'grayscale' => null, // handled inline below
    _ => ScanMode.auto, // unknown → safe default enhancement
  };
  if (!const {
    'original', 'grayscale', 'auto', 'magic', 'bw_text', 'color',
    'professional', 'hd', 'extreme_clarity', 'receipt', 'book',
  }.contains(filter)) {
    return null; // legacy filter → pure-Dart fallback renders it
  }

  cv.Mat? src, work, rotated;
  try {
    final bytes = File(srcPath).readAsBytesSync();
    final decoded = cv.imdecode(bytes, cv.IMREAD_COLOR);
    if (decoded.isEmpty) {
      decoded.dispose();
      return null;
    }
    const maxEdge = 2600;
    final longEdge = decoded.cols > decoded.rows ? decoded.cols : decoded.rows;
    if (longEdge > maxEdge) {
      final s = maxEdge / longEdge;
      src = cv.resize(
          decoded, ((decoded.cols * s).round(), (decoded.rows * s).round()));
      decoded.dispose();
    } else {
      src = decoded;
    }

    if (filter == 'grayscale') {
      final g = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
      work = cv.cvtColor(g, cv.COLOR_GRAY2BGR);
      g.dispose();
    } else if (mode != null) {
      work = enhanceMatCv(src, mode);
      if (work == null) return null;
    } else {
      work = src.clone(); // 'original'
    }

    rotated = switch (rotationDegrees % 360) {
      90 => cv.rotate(work, cv.ROTATE_90_CLOCKWISE),
      180 => cv.rotate(work, cv.ROTATE_180),
      270 => cv.rotate(work, cv.ROTATE_90_COUNTERCLOCKWISE),
      _ => work,
    };
    if (identical(rotated, work)) {
      // Alias — null `work` so the finally block can't double-free the Mat.
      work = null;
    } else {
      work.dispose();
      work = null;
    }

    if (watermark) {
      _drawWatermarkCv(rotated, watermarkPosition);
    }

    final (ok, encoded) = cv.imencode('.jpg', rotated);
    if (!ok) return null;
    File(destPath).writeAsBytesSync(encoded);
    return (width: rotated.cols, height: rotated.rows);
  } catch (_) {
    return null;
  } finally {
    src?.dispose();
    work?.dispose();
    rotated?.dispose();
  }
}

/// Faint corner watermark drawn natively (Hershey font): "dokodocs" +
/// tagline. Text-only — the logo bitmap composite stays in the pure-Dart
/// fallback; visual weight matches (small, gray, unobtrusive).
void _drawWatermarkCv(cv.Mat img, String position) {
  final w = img.cols, h = img.rows;
  final scale = w / 1600.0;
  final pad = (w * 0.02).round();
  final wordScale = 0.9 * scale, tagScale = 0.55 * scale;
  final color = cv.Scalar(110, 110, 110);
  const font = cv.FONT_HERSHEY_SIMPLEX;
  final thick = (1.5 * scale).round().clamp(1, 3);
  final wordH = (28 * scale).round();
  final tagH = (18 * scale).round();
  final wordW = (140 * scale).round();
  final isTop = position == 'top_right';
  final x = w - pad - wordW;
  final yWord = isTop ? pad + wordH : h - pad - tagH - 6 - wordH ~/ 2;
  final yTag = yWord + wordH;
  cv.putText(img, 'dokodocs', cv.Point(x, yWord), font, wordScale, color,
      thickness: thick, lineType: cv.LINE_AA);
  cv.putText(img, 'made with love in nepal', cv.Point(x, yTag), font,
      tagScale, color,
      thickness: 1, lineType: cv.LINE_AA);
}

/// OpenCV image-enhancement engine (V2.4). Produces the clean, sharp,
/// shadow-free "scan" look of CamScanner by combining CLAHE (local contrast),
/// unsharp masking (text sharpening), and — for the B&W/receipt modes —
/// adaptive thresholding. Each [ScanMode] only changes parameters, not the
/// algorithm family.
///
/// Takes encoded image [bytes], returns enhanced JPEG bytes, or null on any
/// failure so the caller can fall back to the pure-Dart enhancer. Pure
/// top-level function → safe inside the render isolate.
/// Illumination normalisation ("shadow removal"): divide an 8-bit channel by
/// its own heavily-blurred background so uneven lighting flattens out while
/// text/detail (which the heavy blur erases) is preserved. scale≈235 keeps
/// paper just below pure white so nothing clips.
cv.Mat _normalizeIllumination(cv.Mat channel) {
  final sigma = (channel.cols / 8).clamp(15.0, 200.0);
  final bg = cv.gaussianBlur(channel, (0, 0), sigma);
  final out = cv.divide(channel, bg, scale: 235, dtype: cv.MatType.CV_8U);
  bg.dispose();
  return out;
}

/// Nearest odd integer ≥ max(n, minimum) — adaptiveThreshold needs odd ≥ 3.
int _oddAtLeast(int n, int minimum) {
  var v = n < minimum ? minimum : n;
  if (v.isEven) v += 1;
  return v;
}

Uint8List? enhanceBytesCv(Uint8List bytes, ScanMode mode) {
  cv.Mat? src, out;
  try {
    final decoded = cv.imdecode(bytes, cv.IMREAD_COLOR);
    if (decoded.isEmpty) {
      decoded.dispose();
      return null;
    }
    // Cap working resolution (~2600px long edge ≈ 216 DPI on A4) so
    // enhancement is fast — a 12 MP capture is needlessly large for a doc.
    const maxEdge = 2600;
    final longEdge = decoded.cols > decoded.rows ? decoded.cols : decoded.rows;
    if (longEdge > maxEdge) {
      final s = maxEdge / longEdge;
      src = cv.resize(
        decoded,
        ((decoded.cols * s).round(), (decoded.rows * s).round()),
      );
      decoded.dispose();
    } else {
      src = decoded;
    }
    out = enhanceMatCv(src, mode);
    if (out == null) return null;
    final (ok, encoded) = cv.imencode('.jpg', out);
    if (!ok) return null;
    return encoded;
  } catch (_) {
    return null;
  } finally {
    src?.dispose();
    out?.dispose();
  }
}

/// Mat-level enhancement core shared by [enhanceBytesCv] and
/// [renderDocumentCv]. Returns a NEW Mat (caller disposes) or null.
cv.Mat? enhanceMatCv(cv.Mat src, ScanMode mode) {
  cv.Mat? gray, work, blurred, sharp, out, clahed;
  cv.CLAHE? clahe;
  try {
    switch (mode) {
      case ScanMode.bwText:
      case ScanMode.receipt:
        // Bilevel text modes ONLY — thresholding is destructive and must
        // never run outside these explicit modes. Shadow removal
        // (illumination normalisation) FIRST so an uneven light gradient
        // doesn't turn half the page black, then adaptive Gaussian threshold
        // with a block size scaled to the image (~width/20, odd) instead of
        // a fixed 15/21 px which is far too small at 2600 px and eats faint
        // strokes.
        gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
        final flat = _normalizeIllumination(gray);
        final block = _oddAtLeast(src.cols ~/ 20, 15);
        final c = mode == ScanMode.receipt ? 12.0 : 9.0;
        final thresh = cv.adaptiveThreshold(
          flat, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY,
          block, c,
        );
        flat.dispose();
        // medianBlur cleans up speckle noise left by the threshold.
        work = cv.medianBlur(thresh, 3);
        thresh.dispose();
        out = cv.cvtColor(work, cv.COLOR_GRAY2BGR);

      default:
        // Colour/default modes: NON-destructive scan look —
        //   white balance → illumination correction → CLAHE → mild unsharp.
        // No convertScaleAbs brightness/contrast push and no thresholding:
        // the old alpha·x+4 push clipped bright paper to white and washed
        // out faint text.
        final (clip, sharpAmt) = switch (mode) {
          ScanMode.color => (1.5, 0.4),
          ScanMode.book => (1.5, 0.4),
          ScanMode.auto => (2.0, 0.5),
          ScanMode.professional => (2.0, 0.7),
          ScanMode.hd => (2.5, 0.9),
          ScanMode.extremeClarity => (3.0, 1.2),
          ScanMode.magic => (2.5, 0.7),
          _ => (2.0, 0.5),
        };
        // Illumination correction + local contrast on the LUMA, blended back
        // over the original colour. Deliberately NO split/merge/VecMat: the
        // previous YCrCb implementation freed the same native Mats through
        // both the VecMat and the channel vector → double-free → native
        // abort, which crashed the whole app at save time.
        gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
        final flat = _normalizeIllumination(gray); // shadow removal
        clahe = cv.CLAHE(clip, (8, 8));
        clahed = clahe.apply(flat);
        flat.dispose();
        final lumBgr = cv.cvtColor(clahed, cv.COLOR_GRAY2BGR);
        // Enhanced luma dominates; original colour keeps the hue natural.
        work = cv.addWeighted(src, 0.45, lumBgr, 0.55, 0);
        lumBgr.dispose();
        // Mild unsharp mask: out = work*(1+amt) - blur*amt.
        blurred = cv.gaussianBlur(work, (0, 0), 3);
        sharp = cv.addWeighted(work, 1 + sharpAmt, blurred, -sharpAmt, 0);
        out = sharp;
        // CRITICAL: null the alias — `finally` disposes both `sharp` and
        // `out`; leaving both pointing at the SAME native Mat double-frees
        // it → native abort → the whole app dies at save time. (This bug
        // predates V3 but never fired while the natives were missing.)
        sharp = null;
        // `work` feeds the returned Mat's data lineage only via addWeighted
        // copies — safe to dispose below; `out` is RETURNED, so it must NOT
        // be disposed here.
    }
    final result = out;
    out = null;
    return result;
  } catch (_) {
    return null;
  } finally {
    // NOTE: `src` is the caller's Mat — never disposed here.
    gray?.dispose();
    work?.dispose();
    blurred?.dispose();
    sharp?.dispose();
    out?.dispose(); // only non-null when an exception skipped the return
    clahed?.dispose();
    clahe?.dispose();
  }
}
