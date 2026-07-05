import 'package:dokodocs/core/render/image_enhancer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Guards the professional scan-mode enhancement layer (added on top of the
/// existing filters, not replacing them).
void main() {
  /// A synthetic "page": bright paper with a dark lighting gradient (shadow)
  /// across it, plus some dark "text" pixels.
  img.Image shadowedPage() {
    final im = img.Image(width: 120, height: 120);
    for (var y = 0; y < 120; y++) {
      for (var x = 0; x < 120; x++) {
        // Paper brightness falls off left→right (uneven illumination).
        final base = (230 - x).clamp(120, 230);
        im.setPixelRgb(x, y, base, base, base);
      }
    }
    // Dark text block.
    img.fillRect(im, x1: 20, y1: 50, x2: 100, y2: 60,
        color: img.ColorRgb8(20, 20, 20));
    return im;
  }

  test('removeIllumination flattens a lighting gradient toward white', () {
    final src = shadowedPage();
    final out = removeIllumination(src, strength: 1.0);

    // The dark (shadowed) right side should be lifted much closer to the
    // bright left side than it was originally.
    final leftBefore = img.getLuminance(src.getPixel(5, 5));
    final rightBefore = img.getLuminance(src.getPixel(115, 5));
    final leftAfter = img.getLuminance(out.getPixel(5, 5));
    final rightAfter = img.getLuminance(out.getPixel(115, 5));

    expect(rightBefore, lessThan(leftBefore)); // gradient present before
    // After normalisation both corners are near-white and close together.
    expect(rightAfter, greaterThan(200));
    expect((leftAfter - rightAfter).abs(),
        lessThan((leftBefore - rightBefore).abs()));
  });

  test('enhanceDocument runs each scan mode and preserves dimensions', () {
    final src = shadowedPage();
    for (final mode in ScanMode.values) {
      final out = enhanceDocument(src, mode);
      expect(out.width, src.width);
      expect(out.height, src.height);
    }
  });
}
