import 'dart:typed_data';

import 'package:dartcv4/dartcv.dart' as cv;

import 'image_enhancer.dart' show ScanMode;

/// OpenCV image-enhancement engine (V2.4). Produces the clean, sharp,
/// shadow-free "scan" look of CamScanner by combining CLAHE (local contrast),
/// unsharp masking (text sharpening), and — for the B&W/receipt modes —
/// adaptive thresholding. Each [ScanMode] only changes parameters, not the
/// algorithm family.
///
/// Takes encoded image [bytes], returns enhanced JPEG bytes, or null on any
/// failure so the caller can fall back to the pure-Dart enhancer. Pure
/// top-level function → safe inside the render isolate.
Uint8List? enhanceBytesCv(Uint8List bytes, ScanMode mode) {
  cv.Mat? src, gray, work, blurred, sharp, out, clahed;
  cv.CLAHE? clahe;
  try {
    src = cv.imdecode(bytes, cv.IMREAD_COLOR);
    if (src.isEmpty) return null;

    switch (mode) {
      case ScanMode.bwText:
      case ScanMode.receipt:
        // Clean bilevel text on white: adaptive threshold handles uneven
        // lighting far better than a global threshold.
        gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
        final block = mode == ScanMode.receipt ? 21 : 15;
        final c = mode == ScanMode.receipt ? 12.0 : 10.0;
        work = cv.adaptiveThreshold(
          gray, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY,
          block, c,
        );
        out = cv.cvtColor(work, cv.COLOR_GRAY2BGR);

      default:
        // Colour modes: CLAHE for local contrast + illumination evening, then
        // unsharp masking for crisp text. Parameters scale by mode.
        final (clip, sharpAmt, alpha) = switch (mode) {
          ScanMode.color => (1.5, 0.4, 1.02),
          ScanMode.book => (1.5, 0.4, 1.02),
          ScanMode.auto => (2.0, 0.6, 1.06),
          ScanMode.professional => (2.5, 0.8, 1.10),
          ScanMode.hd => (2.5, 1.0, 1.10),
          ScanMode.extremeClarity => (3.0, 1.4, 1.12),
          ScanMode.magic => (3.0, 0.8, 1.14),
          _ => (2.0, 0.6, 1.06),
        };
        // CLAHE works on a single channel; apply to grayscale luma then blend
        // back for a contrast/brightness lift while keeping colour.
        gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
        clahe = cv.CLAHE(clip, (8, 8));
        clahed = clahe.apply(gray);
        final claheBgr = cv.cvtColor(clahed, cv.COLOR_GRAY2BGR);
        // Blend original colour with CLAHE luma → contrast without wrecking hue.
        work = cv.addWeighted(src, 0.5, claheBgr, 0.5, 0);
        claheBgr.dispose();
        // Contrast/brightness trim.
        final scaled = cv.convertScaleAbs(work, alpha: alpha, beta: 4);
        work.dispose();
        work = scaled;
        // Unsharp mask: out = work*(1+amt) - blur*amt.
        blurred = cv.gaussianBlur(work, (0, 0), 3);
        sharp = cv.addWeighted(work, 1 + sharpAmt, blurred, -sharpAmt, 0);
        out = sharp;
    }

    final (ok, encoded) = cv.imencode('.jpg', out);
    if (!ok) return null;
    return encoded;
  } catch (_) {
    return null;
  } finally {
    src?.dispose();
    gray?.dispose();
    work?.dispose();
    blurred?.dispose();
    sharp?.dispose();
    out?.dispose();
    clahed?.dispose();
    clahe?.dispose();
  }
}
