import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Professional document-enhancement layer, applied on top of the existing
/// render pipeline (see [page_renderer]). This does NOT replace the existing
/// filters (`grayscale`/`bw`/`lighten`/`enhance`/`high_contrast`) — it adds
/// higher-quality "scan modes" that produce the shadow-free, clean-white,
/// crisp-text look of CamScanner / Adobe Scan.
///
/// Every stage is a small, independently callable function so the pipeline is
/// modular and tunable. All stages are pure `image`-package operations, so the
/// whole thing runs inside the existing render isolate — no UI jank, no extra
/// plugins.
///
/// The heart of the "magic" is [removeIllumination]: estimate the page's
/// lighting by heavily blurring a downscaled copy, then divide the image by
/// that estimate. Shadows, fold-gradients and uneven lighting are flattened
/// and the paper is normalised toward white, while text (much darker than its
/// local background) is preserved.
/// Scan modes inspired by document_scanner_flutter's filter set, implemented
/// purely as parameters on the shared pipeline below (they change enhancement
/// intensity only — they do NOT touch the scanner/detection technology).
enum ScanMode {
  /// Balanced colour enhancement: de-shadow, whiten, gentle contrast + sharpen.
  auto,

  /// "Magic colour": stronger whitening + saturation, colour text/stamps kept.
  magic,

  /// OCR-optimised bilevel-ish black text on white.
  bwText,

  /// Natural colours, light clean-up (closest to the original photo).
  color,

  /// Professional: strong whitening + crisp text, colours kept.
  professional,

  /// HD: professional + extra sharpening for fine print.
  hd,

  /// Extreme clarity: maximum text sharpening (use with care).
  extremeClarity,

  /// Receipt: high-contrast greyscale tuned for thermal-paper receipts.
  receipt,

  /// Book: gentle, keeps page tone and photos, mild fold-shadow removal.
  book,
}

/// Longest-edge cap for enhancement. The pure-Dart per-pixel work
/// (illumination removal, contrast, sharpen) scales with megapixels, so a
/// 12 MP phone capture is punishingly slow and needlessly large for a
/// document. ~2600 px long edge is ≈216 DPI on A4 — sharper than the PDF
/// builder's assumed 200 DPI — so capping here dramatically speeds up
/// enhancement (and shrinks output) with no visible quality loss for docs.
const kEnhanceMaxEdge = 2600;

img.Image enhanceDocument(img.Image src, ScanMode mode) {
  // Downscale oversized captures once, up front, so every stage below works on
  // a sensible resolution. Cheap resize now saves seconds of per-pixel work.
  final longEdge = src.width > src.height ? src.width : src.height;
  if (longEdge > kEnhanceMaxEdge) {
    src = src.width >= src.height
        ? img.copyResize(src, width: kEnhanceMaxEdge)
        : img.copyResize(src, height: kEnhanceMaxEdge);
  }
  switch (mode) {
    case ScanMode.auto:
      var out = removeIllumination(src, strength: 0.85);
      out = adaptiveContrast(out, contrast: 1.12, brightness: 1.02);
      out = sharpenText(out, amount: 0.6);
      return out;
    case ScanMode.magic:
      var out = removeIllumination(src, strength: 1.0);
      out = adaptiveContrast(out, contrast: 1.2, brightness: 1.04);
      out = img.adjustColor(out, saturation: 1.18);
      out = sharpenText(out, amount: 0.8);
      return out;
    case ScanMode.bwText:
      var out = removeIllumination(src, strength: 1.0);
      out = img.grayscale(out);
      out = adaptiveContrast(out, contrast: 1.6, brightness: 1.02);
      out = sharpenText(out, amount: 0.5);
      return out;
    case ScanMode.color:
      var out = removeIllumination(src, strength: 0.5);
      out = adaptiveContrast(out, contrast: 1.06, brightness: 1.01);
      out = sharpenText(out, amount: 0.35);
      return out;
    case ScanMode.professional:
      var out = removeIllumination(src, strength: 0.95);
      out = adaptiveContrast(out, contrast: 1.18, brightness: 1.03);
      out = img.adjustColor(out, saturation: 1.06);
      out = sharpenText(out, amount: 0.75);
      return out;
    case ScanMode.hd:
      var out = removeIllumination(src, strength: 0.95);
      out = adaptiveContrast(out, contrast: 1.22, brightness: 1.03);
      out = sharpenText(out, amount: 1.0);
      return out;
    case ScanMode.extremeClarity:
      var out = removeIllumination(src, strength: 1.0);
      out = adaptiveContrast(out, contrast: 1.3, brightness: 1.02);
      out = sharpenText(out, amount: 1.4);
      return out;
    case ScanMode.receipt:
      var out = removeIllumination(src, strength: 1.0);
      out = img.grayscale(out);
      out = adaptiveContrast(out, contrast: 1.75, brightness: 1.05);
      out = sharpenText(out, amount: 0.7);
      return out;
    case ScanMode.book:
      var out = removeIllumination(src, strength: 0.6);
      out = adaptiveContrast(out, contrast: 1.08, brightness: 1.02);
      out = sharpenText(out, amount: 0.4);
      return out;
  }
}

/// Shadow / uneven-lighting removal + paper whitening.
///
/// Divides each pixel by a blurred "illumination map" (the local background
/// brightness), which flattens gradients and pushes paper toward white.
/// [strength] 0..1 blends between the original and the fully normalised result.
img.Image removeIllumination(img.Image src, {double strength = 1.0}) {
  final w = src.width, h = src.height;
  // Estimate illumination on a downscaled copy (cheap) then sample it back up
  // — a large-radius blur on full res would be very slow.
  const smallW = 96;
  final scale = smallW / w;
  final smallH = math.max(1, (h * scale).round());
  final bgSmall = img.gaussianBlur(
    img.copyResize(src, width: smallW, height: smallH),
    radius: 12,
  );

  final out = img.Image(width: w, height: h, numChannels: 3);
  for (var y = 0; y < h; y++) {
    final sy = (y * scale).clamp(0, smallH - 1).toInt();
    for (var x = 0; x < w; x++) {
      final sx = (x * scale).clamp(0, smallW - 1).toInt();
      final sp = src.getPixel(x, y);
      final bp = bgSmall.getPixel(sx, sy);
      out.setPixelRgb(
        x, y,
        _normalize(sp.r.toDouble(), bp.r.toDouble(), strength),
        _normalize(sp.g.toDouble(), bp.g.toDouble(), strength),
        _normalize(sp.b.toDouble(), bp.b.toDouble(), strength),
      );
    }
  }
  return out;
}

/// One channel: value / background * 255, blended by [strength], clamped.
double _normalize(double v, double bg, double strength) {
  final norm = bg <= 1 ? v : (v / bg) * 255.0;
  final blended = v * (1 - strength) + norm * strength;
  return blended.clamp(0, 255);
}

int _toInt(double v) => v.clamp(0, 255).toInt();

/// Contrast around mid-grey plus a brightness lift. Kept as a named stage so
/// modes can dial it independently.
img.Image adaptiveContrast(
  img.Image src, {
  double contrast = 1.15,
  double brightness = 1.0,
}) {
  final out = img.Image.from(src);
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final p = out.getPixel(x, y);
      out.setPixelRgb(
        x, y,
        _toInt((p.r.toDouble() - 128) * contrast + 128 * brightness),
        _toInt((p.g.toDouble() - 128) * contrast + 128 * brightness),
        _toInt((p.b.toDouble() - 128) * contrast + 128 * brightness),
      );
    }
  }
  return out;
}

/// Unsharp-mask text sharpening: blend in the high-frequency detail (original
/// minus a blurred copy). [amount] 0..1.5. Gentle by default to avoid halos.
img.Image sharpenText(img.Image src, {double amount = 0.6}) {
  if (amount <= 0) return src;
  final blur = img.gaussianBlur(img.Image.from(src), radius: 1);
  final out = img.Image.from(src);
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final p = src.getPixel(x, y);
      final b = blur.getPixel(x, y);
      out.setPixelRgb(
        x, y,
        _toInt(p.r + (p.r - b.r) * amount),
        _toInt(p.g + (p.g - b.g) * amount),
        _toInt(p.b + (p.b - b.b) * amount),
      );
    }
  }
  return out;
}
