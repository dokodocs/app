import 'package:dokodocs/features/scan/document_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Guards the strict document detector — the fix for "always says document
/// detected" with wrong edges. It must (a) NOT fire on an all-bright frame
/// with no real page edges, and (b) fire on a clear page on a dark background
/// with a sensible bounding quad.
void main() {
  test('does not detect on a uniformly bright frame (no real edges)', () {
    final im = img.Image(width: 200, height: 200);
    img.fill(im, color: img.ColorRgb8(240, 240, 240)); // all "paper", no page
    expect(detectDocument(im), isNull);
  });

  test('detects a bright page on a dark background with a bounded quad', () {
    final im = img.Image(width: 200, height: 260);
    img.fill(im, color: img.ColorRgb8(20, 20, 20)); // dark desk
    // A page occupying the middle ~60%.
    img.fillRect(im, x1: 40, y1: 40, x2: 160, y2: 220,
        color: img.ColorRgb8(245, 245, 245));

    final det = detectDocument(im);
    expect(det, isNotNull);
    expect(det!.confidence, greaterThan(kMediumConfidence));

    // The detected quad should sit roughly on the page, NOT the full frame.
    final q = det.quad;
    expect(q.tl.x, greaterThan(20));
    expect(q.tl.y, greaterThan(20));
    expect(q.br.x, lessThan(190));
    expect(q.br.y, lessThan(250));
  });

  test('does not detect a tiny bright speck', () {
    final im = img.Image(width: 200, height: 200);
    img.fill(im, color: img.ColorRgb8(20, 20, 20));
    img.fillRect(im, x1: 90, y1: 90, x2: 110, y2: 110,
        color: img.ColorRgb8(250, 250, 250)); // ~1% of frame
    expect(detectDocument(im), isNull);
  });
}
