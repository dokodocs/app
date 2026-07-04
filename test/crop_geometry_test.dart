import 'package:dokodocs/features/scan/crop_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Conservative auto-crop math (spec §1). The runtime path uses the native
/// scanner (which crops internally and exposes no quad), so these are the
/// policy guarantees, independently verified and ready for a raw-frame
/// pipeline.
void main() {
  group('expandQuad', () {
    test('expands each corner outward by the margin fraction', () {
      // A centered 60x80 quad inside a 100x100 frame; 2.5% margin = 2.5px
      // per side.
      final quad = const [
        CropPoint(20, 10),
        CropPoint(80, 10),
        CropPoint(80, 90),
        CropPoint(20, 90),
      ];
      final expanded = expandQuad(
        quad,
        frameWidth: 100,
        frameHeight: 100,
        marginFraction: 0.025,
      );
      // Left/top corners move out (smaller), right/bottom move out (larger).
      expect(expanded[0].x, closeTo(17.5, 1e-9));
      expect(expanded[0].y, closeTo(7.5, 1e-9));
      expect(expanded[1].x, closeTo(82.5, 1e-9));
      expect(expanded[2].y, closeTo(92.5, 1e-9));
    });

    test('never expands beyond the frame bounds (no clipping of content)', () {
      // Quad already touching the frame edge stays clamped in-bounds.
      final quad = const [
        CropPoint(0, 0),
        CropPoint(100, 0),
        CropPoint(100, 100),
        CropPoint(0, 100),
      ];
      final expanded = expandQuad(quad, frameWidth: 100, frameHeight: 100);
      for (final pt in expanded) {
        expect(pt.x, inInclusiveRange(0, 100));
        expect(pt.y, inInclusiveRange(0, 100));
      }
    });

    test('rejects non-quads', () {
      expect(
        () => expandQuad(const [CropPoint(0, 0)],
            frameWidth: 10, frameHeight: 10),
        throwsArgumentError,
      );
    });
  });

  group('shouldKeepFullFrame', () {
    test('keeps full frame + flags review when quad covers <40%', () {
      // 50x50 quad in a 100x100 frame = 25% < 40%.
      final small = const [
        CropPoint(0, 0),
        CropPoint(50, 0),
        CropPoint(50, 50),
        CropPoint(0, 50),
      ];
      expect(
        shouldKeepFullFrame(small, frameWidth: 100, frameHeight: 100),
        isTrue,
      );
    });

    test('accepts a confident quad covering >=40%', () {
      // 80x80 quad in 100x100 = 64% >= 40%.
      final big = const [
        CropPoint(10, 10),
        CropPoint(90, 10),
        CropPoint(90, 90),
        CropPoint(10, 90),
      ];
      expect(
        shouldKeepFullFrame(big, frameWidth: 100, frameHeight: 100),
        isFalse,
      );
    });

    test('exactly at the 40% threshold is accepted', () {
      // sqrt(0.4) ~= 0.632; a 63.25x63.25 quad ~= 40.0%.
      final side = 100 * 0.6325;
      final quad = [
        const CropPoint(0, 0),
        CropPoint(side, 0),
        CropPoint(side, side),
        CropPoint(0, side),
      ];
      expect(
        shouldKeepFullFrame(quad, frameWidth: 100, frameHeight: 100),
        isFalse,
      );
    });
  });

  test('quadArea computes the shoelace area', () {
    final quad = const [
      CropPoint(0, 0),
      CropPoint(10, 0),
      CropPoint(10, 20),
      CropPoint(0, 20),
    ];
    expect(quadArea(quad), closeTo(200, 1e-9));
  });
}
