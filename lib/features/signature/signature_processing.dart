import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Turns a photographed signature (ink on paper) into a clean, transparent-
/// background PNG: crop to the chosen rectangle, optionally boost contrast,
/// then knock out the paper by making light pixels transparent and darkening
/// the ink. Runs off the main isolate (Nepal 3GB-RAM budget).
///
/// [crop] is left/top/right/bottom as fractions (0..1) of the source image.
/// [threshold] (0..1) is the lightness above which a pixel is treated as
/// paper and removed — higher keeps more, lower removes more.
Future<String> processSignatureImage({
  required String sourcePath,
  required String destPath,
  required List<double> crop,
  double threshold = 0.6,
  bool highContrast = true,
}) {
  return compute(
    _process,
    _Args(sourcePath, destPath, crop, threshold, highContrast),
  );
}

class _Args {
  const _Args(
    this.sourcePath,
    this.destPath,
    this.crop,
    this.threshold,
    this.highContrast,
  );
  final String sourcePath;
  final String destPath;
  final List<double> crop;
  final double threshold;
  final bool highContrast;
}

Future<String> _process(_Args args) async {
  var image = img.decodeImage(await File(args.sourcePath).readAsBytes());
  if (image == null) {
    throw StateError('Could not decode signature image at ${args.sourcePath}');
  }

  // Crop to the selected rectangle (clamped to bounds).
  final l = (args.crop[0] * image.width).round().clamp(0, image.width - 1);
  final t = (args.crop[1] * image.height).round().clamp(0, image.height - 1);
  final r = (args.crop[2] * image.width).round().clamp(l + 1, image.width);
  final b = (args.crop[3] * image.height).round().clamp(t + 1, image.height);
  image = img.copyCrop(image, x: l, y: t, width: r - l, height: b - t);

  image = image.convert(numChannels: 4); // ensure an alpha channel
  image = img.grayscale(image);
  if (args.highContrast) {
    image = img.contrast(image, contrast: 165);
  }

  // Paper → transparent, ink → dark. Alpha ramps just below the threshold so
  // stroke edges stay smooth rather than jagged.
  final cut = (args.threshold * 255).round();
  const soft = 40; // ramp width in luminance units
  for (final pixel in image) {
    final lum = img.getLuminance(pixel).toDouble();
    if (lum >= cut) {
      pixel.a = 0;
    } else {
      final a = lum <= cut - soft
          ? 255
          : (255 * (cut - lum) / soft).round().clamp(0, 255);
      // Push the ink toward near-black for a crisp, high-contrast mark.
      pixel
        ..r = 20
        ..g = 24
        ..b = 28
        ..a = a;
    }
  }

  await File(args.destPath).writeAsBytes(img.encodePng(image));
  return args.destPath;
}
