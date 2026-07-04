import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Applies a filter to [sourcePath] and writes the result to [destPath] in
/// the requested [outputFormat], off the main isolate — required by the
/// Nepal 3GB-RAM performance budget (spec Nepal override §3: "every image
/// operation off the main isolate").
///
/// `filter`: 'original' | 'grayscale' | 'bw' | 'lighten' | 'enhance' |
/// 'high_contrast' — matches the allowed values on the `Pages` drift table.
/// `outputFormat`: 'jpg' | 'png'.
Future<String> applyFilter({
  required String sourcePath,
  required String destPath,
  required String filter,
  String outputFormat = 'jpg',
}) {
  return compute(
    _applyFilterIsolate,
    _FilterArgs(sourcePath, destPath, filter, outputFormat),
  );
}

class _FilterArgs {
  const _FilterArgs(
    this.sourcePath,
    this.destPath,
    this.filter,
    this.outputFormat,
  );
  final String sourcePath;
  final String destPath;
  final String filter;
  final String outputFormat;
}

Future<String> _applyFilterIsolate(_FilterArgs args) async {
  final bytes = await File(args.sourcePath).readAsBytes();
  var image = img.decodeImage(bytes);
  if (image == null) {
    throw StateError('Could not decode image at ${args.sourcePath}');
  }

  switch (args.filter) {
    case 'grayscale':
      image = img.grayscale(image);
    case 'bw':
      image = img.grayscale(image);
      image = img.contrast(image, contrast: 180);
    case 'lighten':
      // Brightness only, no contrast change — for dim/underexposed scans.
      image = img.adjustColor(image, brightness: 1.3);
    case 'enhance':
      image = img.adjustColor(image, brightness: 1.08, contrast: 1.15);
    case 'high_contrast':
      // Contrast boost while keeping color, unlike 'bw' which desaturates —
      // makes text pop on colored backgrounds (whiteboards, colored paper).
      image = img.contrast(image, contrast: 160);
    case 'warm':
      // Warm-tone paper look: lift red, ease off blue, small contrast bump —
      // flatters photographed documents under cool/office lighting.
      image = img.colorOffset(image, red: 18, green: 4, blue: -18);
      image = img.adjustColor(image, contrast: 1.08);
    case 'original':
    default:
      break;
  }

  final encoded = args.outputFormat == 'png'
      ? img.encodePng(image)
      : img.encodeJpg(image, quality: 90);
  await File(args.destPath).writeAsBytes(encoded);
  return args.destPath;
}
