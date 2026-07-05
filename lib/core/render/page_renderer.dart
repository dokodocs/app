import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'image_enhancer.dart';
import 'image_enhancer_cv.dart';

/// Centralized, render-time page pipeline for the NON-DESTRUCTIVE model:
/// always reads the immutable [originalPath], applies (in order) filter →
/// rotation → optional corner watermark, and writes the processed result to
/// [destPath]. The original file is only ever read here, never written —
/// upholding the absolute rule that nothing overwrites an original capture.
///
/// Runs off the main isolate (Nepal 3GB-RAM budget: "every image operation
/// off the main isolate"). This is the single place both first-save
/// (document_builder) and later re-export/PDF-rebuild (editor) go through,
/// so a page renders identically wherever it's produced.
///
/// `filter`: 'original' | 'grayscale' | 'bw' | 'lighten' | 'enhance' |
///   'high_contrast'.
/// `rotationDegrees`: 0 | 90 | 180 | 270 (clockwise).
/// `outputFormat`: 'jpg' | 'png'.
///
/// Returns the written [RenderedPage.path] plus the final pixel [width]/[height]
/// (after rotation), so downstream consumers (e.g. the PDF builder) don't have
/// to re-decode the image just to learn its size.
Future<RenderedPage> renderPage({
  required String originalPath,
  required String destPath,
  String filter = 'original',
  int rotationDegrees = 0,
  bool watermark = false,
  String watermarkPosition = 'bottom_right',
  Uint8List? watermarkLogo,
  String outputFormat = 'jpg',
  int jpegQuality = 90,
}) {
  return compute(
    _renderPageIsolate,
    _RenderArgs(
      originalPath: originalPath,
      destPath: destPath,
      filter: filter,
      rotationDegrees: rotationDegrees,
      watermark: watermark,
      watermarkPosition: watermarkPosition,
      watermarkLogo: watermarkLogo,
      outputFormat: outputFormat,
      jpegQuality: jpegQuality,
    ),
  );
}

/// A rendered page: the written file [path] and its final pixel dimensions.
/// Carrying the dimensions forward lets the PDF builder size pages without a
/// second full-image decode.
class RenderedPage {
  const RenderedPage({
    required this.path,
    required this.width,
    required this.height,
  });
  final String path;
  final int width;
  final int height;
}

class _RenderArgs {
  const _RenderArgs({
    required this.originalPath,
    required this.destPath,
    required this.filter,
    required this.rotationDegrees,
    required this.watermark,
    required this.watermarkPosition,
    required this.watermarkLogo,
    required this.outputFormat,
    required this.jpegQuality,
  });

  final String originalPath;
  final String destPath;
  final String filter;
  final int rotationDegrees;
  final bool watermark;
  final String watermarkPosition;
  final Uint8List? watermarkLogo;
  final String outputFormat;
  final int jpegQuality;
}

Future<RenderedPage> _renderPageIsolate(_RenderArgs args) async {
  final bytes = await File(args.originalPath).readAsBytes();
  var image = img.decodeImage(bytes);
  if (image == null) {
    throw StateError('Could not decode image at ${args.originalPath}');
  }

  switch (args.filter) {
    case 'grayscale':
      image = img.grayscale(image);
    case 'bw':
      image = img.grayscale(image);
      image = img.contrast(image, contrast: 180);
    case 'lighten':
      image = img.adjustColor(image, brightness: 1.3);
    case 'enhance':
      image = img.adjustColor(image, brightness: 1.08, contrast: 1.15);
    case 'high_contrast':
      image = img.contrast(image, contrast: 160);
    // Professional scan modes — OpenCV enhancement (CLAHE + unsharp +
    // adaptive threshold; see image_enhancer_cv.dart) with a pure-Dart
    // fallback (image_enhancer.dart) if OpenCV fails.
    case 'auto':
      image = _enhance(image, bytes, ScanMode.auto);
    case 'magic':
      image = _enhance(image, bytes, ScanMode.magic);
    case 'bw_text':
      image = _enhance(image, bytes, ScanMode.bwText);
    case 'color':
      image = _enhance(image, bytes, ScanMode.color);
    case 'professional':
      image = _enhance(image, bytes, ScanMode.professional);
    case 'hd':
      image = _enhance(image, bytes, ScanMode.hd);
    case 'extreme_clarity':
      image = _enhance(image, bytes, ScanMode.extremeClarity);
    case 'receipt':
      image = _enhance(image, bytes, ScanMode.receipt);
    case 'book':
      image = _enhance(image, bytes, ScanMode.book);
    case 'original':
    default:
      break;
  }

  if (args.rotationDegrees % 360 != 0) {
    image = img.copyRotate(image, angle: args.rotationDegrees);
  }

  if (args.watermark) {
    _drawCornerWatermark(image, args.watermarkPosition, args.watermarkLogo);
  }

  final encoded = args.outputFormat == 'png'
      ? img.encodePng(image)
      : img.encodeJpg(image, quality: args.jpegQuality);
  await File(args.destPath).writeAsBytes(encoded);
  // Return the FINAL dimensions (post-rotation) so the PDF builder can size
  // pages without decoding the image a second time.
  return RenderedPage(
    path: args.destPath,
    width: image.width,
    height: image.height,
  );
}

/// Applies a professional scan [mode] using the OpenCV engine (CLAHE +
/// unsharp + adaptive threshold), falling back to the pure-Dart enhancer if
/// OpenCV fails. [srcBytes] are the original encoded bytes; [decoded] is the
/// already-decoded image used for the fallback path.
img.Image _enhance(img.Image decoded, Uint8List srcBytes, ScanMode mode) {
  final cvBytes = enhanceBytesCv(srcBytes, mode);
  if (cvBytes != null) {
    final cvImage = img.decodeImage(cvBytes);
    if (cvImage != null) return cvImage;
  }
  return enhanceDocument(decoded, mode);
}

/// The DokoDocs corner watermark: the doko logo mark next to the "dokodocs"
/// wordmark, with a small "made with love in nepal" tagline beneath — all
/// faint, edge-padded, bottom-right by default (or top-right). The logo is
/// composited from bytes passed in from the main isolate (rootBundle is
/// unavailable here); text is drawn with bundled bitmap fonts. When no logo
/// bytes are supplied it degrades gracefully to text only. Applied to the
/// PROCESSED copy only — never the immutable original.
const _watermarkText = 'dokodocs';
const _watermarkTagline = 'made with love in nepal';

void _drawCornerWatermark(
  img.Image image,
  String position,
  Uint8List? logoBytes,
) {
  final padding = (image.width * 0.02).round();
  final isTop = position == 'top_right';

  // Fonts: small and unobtrusive — the wordmark ~2.6% of width, tagline one
  // step smaller. Kept deliberately tiny so it reads as a faint mark.
  final wordFont = _fontForHeight(image.width * 0.026);
  final tagFont = _fontForHeight(image.width * 0.016);
  final wordH = wordFont.lineHeight.toDouble();
  final tagH = tagFont.lineHeight.toDouble();
  final wordW = _watermarkText.length * wordH * 0.6;
  final tagW = _watermarkTagline.length * tagH * 0.6;

  // Logo sized to sit beside the wordmark (a touch taller than the word).
  img.Image? logo;
  if (logoBytes != null) {
    final decoded = img.decodeImage(logoBytes);
    if (decoded != null) {
      final target = (wordH * 1.3).round().clamp(12, image.width);
      logo = img.copyResize(decoded, width: target, height: target);
      // Desaturate to grayscale and knock back to ~25% opacity so the mark
      // reads as a faint black-and-white watermark, not a coloured logo.
      img.grayscale(logo);
      _fadeAlpha(logo, 0.25);
    }
  }

  final logoW = logo?.width ?? 0;
  final gap = logo != null ? (wordH * 0.25).round() : 0;
  final blockW = (logoW + gap + [wordW, tagW].reduce((a, b) => a > b ? a : b))
      .round();
  final blockH = (logo != null ? logo.height.toDouble() : wordH + tagH + 2)
      .clamp(wordH + tagH + 2, image.height.toDouble())
      .round();

  final left = (image.width - blockW - padding).round().clamp(0, image.width);
  final top = (isTop ? padding : image.height - blockH - padding)
      .clamp(0, image.height);

  if (logo != null) {
    img.compositeImage(image, logo, dstX: left, dstY: top);
  }

  final textX = left + logoW + gap;
  // Dim neutral gray (black-and-white), semi-transparent so it stays faint.
  final color = img.ColorRgba8(80, 80, 80, 130);
  img.drawString(
    image,
    _watermarkText,
    font: wordFont,
    x: textX,
    y: top,
    color: color,
  );
  img.drawString(
    image,
    _watermarkTagline,
    font: tagFont,
    x: textX,
    y: (top + wordH).round(),
    color: color,
  );
}

/// Multiplies every pixel's alpha by [factor] (0..1) in place, so an opaque
/// logo composites as a faint watermark.
void _fadeAlpha(img.Image image, double factor) {
  for (final pixel in image) {
    pixel.a = (pixel.a * factor).round();
  }
}

img.BitmapFont _fontForHeight(double targetHeight) {
  if (targetHeight >= 40) return img.arial48;
  if (targetHeight >= 20) return img.arial24;
  return img.arial14;
}
