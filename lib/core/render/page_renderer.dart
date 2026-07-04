import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

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
Future<String> renderPage({
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

Future<String> _renderPageIsolate(_RenderArgs args) async {
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
  return args.destPath;
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

  // Fonts: the wordmark ~ nearest to 4% of width, tagline one step smaller.
  final wordFont = _fontForHeight(image.width * 0.04);
  final tagFont = _fontForHeight(image.width * 0.022);
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
      // Knock the mark back to ~40% opacity so it reads as a watermark.
      _fadeAlpha(logo, 0.40);
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
  final color = img.ColorRgba8(46, 125, 107, 200);
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
