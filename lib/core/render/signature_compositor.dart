import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Bakes a signature PNG onto a page image, in place.
///
/// [centerX]/[centerY] are the signature centre as fractions (0..1) of the
/// page's width/height; [widthFraction] is the signature width as a fraction
/// of page width (height follows the signature's aspect ratio). Runs off the
/// main isolate (Nepal 3GB-RAM budget).
///
/// NOTE: this composites onto the processed preview (`localImagePath`), not
/// the immutable original — the signature is a deliberate additive edit. A
/// later filter/rotate/revert re-renders from the original and clears it, at
/// which point the signature can simply be re-applied.
Future<void> compositeSignatureOnImage({
  required String imagePath,
  required String signaturePath,
  required double centerX,
  required double centerY,
  required double widthFraction,
}) {
  return compute(
    _composite,
    _SigArgs(imagePath, signaturePath, centerX, centerY, widthFraction),
  );
}

class _SigArgs {
  const _SigArgs(
    this.imagePath,
    this.signaturePath,
    this.centerX,
    this.centerY,
    this.widthFraction,
  );
  final String imagePath;
  final String signaturePath;
  final double centerX;
  final double centerY;
  final double widthFraction;
}

Future<void> _composite(_SigArgs args) async {
  final page = img.decodeImage(await File(args.imagePath).readAsBytes());
  final sig = img.decodeImage(await File(args.signaturePath).readAsBytes());
  if (page == null || sig == null) {
    throw StateError('Could not decode page or signature image');
  }

  final targetW = (page.width * args.widthFraction).round().clamp(1, page.width);
  final resized = img.copyResize(sig, width: targetW);

  final dstX = (page.width * args.centerX - resized.width / 2).round();
  final dstY = (page.height * args.centerY - resized.height / 2).round();

  img.compositeImage(page, resized, dstX: dstX, dstY: dstY);

  await File(args.imagePath).writeAsBytes(img.encodeJpg(page, quality: 90));
}
