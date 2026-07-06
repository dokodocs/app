/// In-memory representation of one captured page during an active scan
/// session, before it's committed to the database as a [DocPage] row.
///
/// [imagePath] is the immutable captured original (the native scanner's
/// output — see the "keep native scanner" decision). Filter, rotation and
/// crop are render-time metadata applied to a *copy*, never to [imagePath].
///
/// `filter`: 'original' | 'grayscale' | 'bw' | 'lighten' | 'enhance' |
/// 'high_contrast' — matches the allowed values documented on the `Pages`
/// drift table.
class ScanPage {
  const ScanPage({
    required this.imagePath,
    this.filter = 'original',
    this.rotation = 0,
    this.cropCoordinates,
    this.needsReview = false,
    this.processing = false,
  });

  /// The immutable captured original.
  final String imagePath;
  final String filter;
  final int rotation;

  /// JSON-encoded corner points for an optional manual crop applied at
  /// render time. Null = use the full (native-cropped) frame.
  final String? cropCoordinates;

  /// True when this page was kept as a full frame because edge-detection
  /// confidence was low — surfaced for review rather than silently guessed.
  final bool needsReview;

  /// True while the BACKGROUND auto-crop (full-res re-detect + perspective
  /// warp) is still running for this page. The review screen shows a badge
  /// and Save waits until every page is done (Phase 2 queue).
  final bool processing;

  bool get isReverted =>
      filter == 'original' &&
      rotation == 0 &&
      cropCoordinates == null;

  ScanPage copyWith({
    String? imagePath,
    String? filter,
    int? rotation,
    String? cropCoordinates,
    bool clearCrop = false,
    bool? needsReview,
    bool? processing,
  }) {
    return ScanPage(
      imagePath: imagePath ?? this.imagePath,
      filter: filter ?? this.filter,
      rotation: rotation ?? this.rotation,
      cropCoordinates:
          clearCrop ? null : (cropCoordinates ?? this.cropCoordinates),
      needsReview: needsReview ?? this.needsReview,
      processing: processing ?? this.processing,
    );
  }
}
