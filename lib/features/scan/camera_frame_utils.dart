import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// Builds a small grayscale [img.Image] from a live [CameraImage], subsampled
/// to about [targetWidth] px wide so document detection stays cheap enough to
/// run on preview frames. Handles the two formats the `camera` plugin emits:
/// YUV420 (Android — plane 0 is luminance) and BGRA8888 (iOS).
///
/// Returns null for unsupported formats rather than guessing.
img.Image? grayscaleFromCameraImage(CameraImage image, {int targetWidth = 320}) {
  final srcW = image.width;
  final srcH = image.height;
  if (srcW == 0 || srcH == 0) return null;

  final step = (srcW / targetWidth).floor().clamp(1, 64);
  final outW = srcW ~/ step;
  final outH = srcH ~/ step;
  if (outW < 8 || outH < 8) return null;

  final out = img.Image(width: outW, height: outH);

  switch (image.format.group) {
    case ImageFormatGroup.yuv420:
      final y = image.planes[0];
      final rowStride = y.bytesPerRow;
      final bytes = y.bytes;
      for (var oy = 0; oy < outH; oy++) {
        final sy = oy * step;
        final rowStart = sy * rowStride;
        for (var ox = 0; ox < outW; ox++) {
          final sx = ox * step;
          final lum = bytes[rowStart + sx];
          out.setPixelRgb(ox, oy, lum, lum, lum);
        }
      }
      return out;

    case ImageFormatGroup.bgra8888:
      final plane = image.planes[0];
      final rowStride = plane.bytesPerRow;
      final bytes = plane.bytes;
      for (var oy = 0; oy < outH; oy++) {
        final sy = oy * step;
        final rowStart = sy * rowStride;
        for (var ox = 0; ox < outW; ox++) {
          final sx = ox * step;
          final i = rowStart + sx * 4;
          final b = bytes[i];
          final g = bytes[i + 1];
          final r = bytes[i + 2];
          final lum = ((r * 30 + g * 59 + b * 11) ~/ 100);
          out.setPixelRgb(ox, oy, lum, lum, lum);
        }
      }
      return out;

    default:
      return null;
  }
}
