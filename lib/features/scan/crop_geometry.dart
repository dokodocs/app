import 'dart:math' as math;

/// Conservative auto-crop geometry (spec §1). Pure math, isolated and
/// unit-tested, so the crop policy is correct and ready to wire to a
/// raw-frame + quad pipeline later. NOTE: the current native scanner
/// (cunning_document_scanner) crops internally and does not expose the raw
/// frame, the detected quad, or a confidence score, so at runtime these
/// helpers are not fed real quads today — they encode the policy the app
/// will apply the moment a raw-frame source exists.

/// A detected document corner (normalized 0..1 within the frame, or in
/// pixels — the helpers are unit-agnostic as long as [frameWidth]/
/// [frameHeight] use the same units).
class CropPoint {
  const CropPoint(this.x, this.y);
  final double x;
  final double y;
}

/// Fraction of area below which a detected quad is considered untrustworthy
/// and the FULL frame is kept instead of guessing (spec §1: "<40% of the
/// frame → keep the full frame uncropped and flag for review").
const kMinQuadAreaFraction = 0.40;

/// Default per-side safety margin (spec §1: "expand the detected quad
/// outward by ~2–3% of frame per side").
const kSafetyMarginFraction = 0.025;

/// Expands a detected quad outward by [marginFraction] of the frame on each
/// side, clamped to the frame bounds, so content near the paper edge is
/// never clipped. Returns the four expanded corners in the same order.
List<CropPoint> expandQuad(
  List<CropPoint> quad, {
  required double frameWidth,
  required double frameHeight,
  double marginFraction = kSafetyMarginFraction,
}) {
  if (quad.length != 4) {
    throw ArgumentError('A quad must have exactly 4 points');
  }
  final cx = quad.map((pt) => pt.x).reduce((a, b) => a + b) / 4;
  final cy = quad.map((pt) => pt.y).reduce((a, b) => a + b) / 4;
  final dx = frameWidth * marginFraction;
  final dy = frameHeight * marginFraction;

  return [
    for (final pt in quad)
      CropPoint(
        // Push each corner away from the centroid, then clamp to the frame.
        (pt.x + (pt.x >= cx ? dx : -dx)).clamp(0.0, frameWidth),
        (pt.y + (pt.y >= cy ? dy : -dy)).clamp(0.0, frameHeight),
      ),
  ];
}

/// Shoelace area of a quad (absolute value).
double quadArea(List<CropPoint> quad) {
  var sum = 0.0;
  for (var i = 0; i < quad.length; i++) {
    final a = quad[i];
    final b = quad[(i + 1) % quad.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum.abs() / 2.0;
}

/// Whether to discard a detected quad and keep the full frame (flagging the
/// page for review): true when the quad is degenerate or covers less than
/// [kMinQuadAreaFraction] of the frame.
bool shouldKeepFullFrame(
  List<CropPoint> quad, {
  required double frameWidth,
  required double frameHeight,
}) {
  if (quad.length != 4) return true;
  final frameArea = frameWidth * frameHeight;
  if (frameArea <= 0) return true;
  final fraction = quadArea(quad) / frameArea;
  return fraction < kMinQuadAreaFraction || !fraction.isFinite;
}

/// Convenience: the axis-aligned full-frame quad, used as the safe fallback.
List<CropPoint> fullFrameQuad(double frameWidth, double frameHeight) {
  final w = math.max(0.0, frameWidth);
  final h = math.max(0.0, frameHeight);
  return [
    const CropPoint(0, 0),
    CropPoint(w, 0),
    CropPoint(w, h),
    CropPoint(0, h),
  ];
}
