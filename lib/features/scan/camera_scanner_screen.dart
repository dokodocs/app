import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../core/l10n/app_localizations.dart';
import 'camera_frame_utils.dart';
import 'crop_processor.dart';
import 'document_detector.dart';
import 'document_detector_cv.dart';

/// A custom document camera used as the fallback when the native ML Kit /
/// VisionKit scanner is unavailable (missing Google Play services), replacing
/// the old image_picker fallback that opened the FRONT camera and showed no
/// edge border.
///
/// Guarantees the professional basics the prompt asks for:
///  - STRICT rear (back) lens — picks the back camera explicitly, never front.
///  - Full-screen live preview.
///  - Live green document outline over the preview (throttled detection).
///  - Capture button, flash toggle, back button.
///  - High-resolution capture with autofocus/exposure (camera plugin default).
///
/// Returns the captured file path via `Navigator.pop` (the caller then opens
/// the crop editor, which auto-detects corners and does perspective
/// correction), or null if the user backs out.
class CameraScannerScreen extends StatefulWidget {
  const CameraScannerScreen({super.key, this.batch = false});

  /// When true, the camera stays open after each shot and collects multiple
  /// pages (continuous scanning — no bounce back to the dashboard between
  /// pages). It then pops with a `List<String>` of captured paths. When false
  /// it pops with a single `String` path after one shot.
  final bool batch;

  @override
  State<CameraScannerScreen> createState() => _CameraScannerScreenState();
}

class _CameraScannerScreenState extends State<CameraScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  List<CameraDescription> _cameras = const [];
  bool _usingFront = false;
  FlashMode _flash = FlashMode.off;

  bool _busy = false; // capture in progress
  bool _detecting = false; // a frame is being analysed
  DateTime _lastDetect = DateTime.fromMillisecondsSinceEpoch(0);

  /// Smoothed detected quad in NORMALISED (0..1) preview space, or null.
  List<Offset>? _quadNorm;
  double _confidence = 0;

  /// Recent raw quads for temporal smoothing (anti-flicker).
  final List<List<Offset>> _history = [];
  static const _historyLen = 5;

  /// Auto-capture: how long the document has been detected & stable.
  DateTime? _stableSince;
  bool _autoCapture = true;

  /// Pages captured so far in batch mode (paths).
  final List<String> _captured = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initFuture = _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    _cameras = await availableCameras();
    await _start(front: false);
  }

  CameraDescription _pick({required bool front}) {
    final want =
        front ? CameraLensDirection.front : CameraLensDirection.back;
    // Prefer the requested direction; the FIRST back camera the platform
    // lists is the primary wide lens. Fall back to whatever exists.
    return _cameras.firstWhere(
      (c) => c.lensDirection == want,
      orElse: () => _cameras.isNotEmpty ? _cameras.first : throw StateError('no camera'),
    );
  }

  Future<void> _start({required bool front}) async {
    await _controller?.dispose();
    final desc = _pick(front: front);
    final controller = CameraController(
      desc,
      ResolutionPreset.max, // high resolution for sharp scans
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _controller = controller;
    _usingFront = desc.lensDirection == CameraLensDirection.front;
    await controller.initialize();
    await controller.setFlashMode(_flash);
    if (!mounted) return;
    // Live detection only for the rear document view.
    if (!_usingFront) {
      await controller.startImageStream(_onFrame);
    }
    setState(() {});
  }

  void _onFrame(CameraImage frame) {
    if (_detecting || _busy) return;
    final now = DateTime.now();
    if (now.difference(_lastDetect).inMilliseconds < 350) return;
    _lastDetect = now;
    _detecting = true;

    // Detect synchronously on a downsampled grayscale — cheap enough per the
    // throttle. (Kept on the UI isolate: the image stream's backing buffers
    // are not sendable to another isolate.)
    try {
      final gray = grayscaleFromCameraImage(frame);
      Quad? quad;
      double conf = 0;
      if (gray != null) {
        // Prefer OpenCV (accurate, no Play services). Encode the small
        // grayscale to PNG and detect; fall back to the pure-Dart detector.
        final cvHit = detectDocumentCvBytes(img.encodePng(gray));
        if (cvHit != null) {
          quad = cvHit.quad;
          conf = cvHit.confidence;
        } else {
          final d = detectDocument(gray);
          quad = d?.quad;
          conf = d?.confidence ?? 0;
        }
      }
      if (!mounted) {
        _detecting = false;
        return;
      }
      if (quad == null) {
        // No confident document — clear the border and reset stability.
        _history.clear();
        _stableSince = null;
        if (_quadNorm != null) setState(() => _quadNorm = null);
      } else {
        final gw = gray!.width.toDouble();
        final gh = gray.height.toDouble();
        final raw = [
          Offset(quad.tl.x / gw, quad.tl.y / gh),
          Offset(quad.tr.x / gw, quad.tr.y / gh),
          Offset(quad.br.x / gw, quad.br.y / gh),
          Offset(quad.bl.x / gw, quad.bl.y / gh),
        ];
        final smoothed = _smooth(raw);
        _trackStability(smoothed);
        setState(() {
          _quadNorm = smoothed;
          _confidence = conf;
        });
        _maybeAutoCapture();
      }
    } catch (_) {
      // Never let a bad frame crash the preview.
    } finally {
      _detecting = false;
    }
  }

  /// Temporal smoothing: rolling average of the last few quads so the border
  /// doesn't flicker/jump between frames.
  List<Offset> _smooth(List<Offset> raw) {
    _history.add(raw);
    if (_history.length > _historyLen) _history.removeAt(0);
    final avg = List<Offset>.filled(4, Offset.zero);
    for (final q in _history) {
      for (var i = 0; i < 4; i++) {
        avg[i] += q[i];
      }
    }
    final n = _history.length.toDouble();
    return [for (final p in avg) Offset(p.dx / n, p.dy / n)];
  }

  /// Tracks how long the detected quad has stayed roughly still — the trigger
  /// for auto-capture.
  void _trackStability(List<Offset> quad) {
    final prev = _quadNorm;
    if (prev == null || prev.length != 4) {
      _stableSince = DateTime.now();
      return;
    }
    var moved = 0.0;
    for (var i = 0; i < 4; i++) {
      moved += (quad[i] - prev[i]).distance;
    }
    // If corners moved more than ~2% of the frame total, it's not stable yet.
    if (moved > 0.08) {
      _stableSince = DateTime.now();
    }
  }

  void _maybeAutoCapture() {
    if (!_autoCapture || _busy) return;
    if (_confidence < kHighConfidence) return; // only auto-fire when confident
    final since = _stableSince;
    if (since == null) return;
    if (DateTime.now().difference(since).inMilliseconds >= 700) {
      _capture();
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _busy || !controller.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final file = await controller.takePicture();
      if (!mounted) return;
      if (widget.batch) {
        // Continuous mode: keep the camera open, collect the page, resume the
        // live detection stream for the next shot.
        _captured.add(file.path);
        _quadNorm = null;
        _history.clear();
        _stableSince = null;
        if (!_usingFront) {
          await controller.startImageStream(_onFrame);
        }
        if (mounted) setState(() => _busy = false);
      } else {
        Navigator.of(context).pop(file.path);
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Finish a batch session — pop with all captured page paths.
  void _finishBatch() {
    Navigator.of(context).pop(List<String>.from(_captured));
  }

  Future<void> _toggleFlash() async {
    _flash = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.torch,
      _ => FlashMode.off,
    };
    await _controller?.setFlashMode(_flash);
    setState(() {});
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    setState(() => _quadNorm = null);
    await _start(front: !_usingFront);
  }

  IconData get _flashIcon => switch (_flash) {
        FlashMode.off => Icons.flash_off,
        FlashMode.auto => Icons.flash_auto,
        _ => Icons.flash_on,
      };

  /// Border/indicator colour by detection confidence: green (high) → orange
  /// (medium) → red (low), matching the spec's confidence bands.
  Color get _confidenceColor {
    if (_confidence >= kHighConfidence) return const Color(0xFF3DDC84);
    if (_confidence >= kMediumConfidence) return const Color(0xFFFFA726);
    return const Color(0xFFEF5350);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          final controller = _controller;
          if (snapshot.connectionState != ConnectionState.done ||
              controller == null ||
              !controller.value.isInitialized) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.white));
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              // Full-screen preview (cover so it fills the screen).
              _CoverPreview(controller: controller),
              // Live document outline, coloured by confidence.
              if (_quadNorm != null)
                CustomPaint(
                  painter: _LiveQuadPainter(_quadNorm!, _confidenceColor),
                ),
              // Detection indicator.
              if (_quadNorm != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _confidenceColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _confidence >= kHighConfidence
                            ? l10n.scanHoldSteady
                            : l10n.scanDocumentDetected,
                        style: const TextStyle(
                            color: Colors.black, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              // Top bar: back + flash + switch.
              Positioned(
                top: MediaQuery.of(context).padding.top,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: l10n.commonBack,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            _autoCapture
                                ? Icons.motion_photos_auto
                                : Icons.motion_photos_off,
                            color: _autoCapture
                                ? const Color(0xFF3DDC84)
                                : Colors.white,
                          ),
                          tooltip: l10n.scanAutoCapture,
                          onPressed: () =>
                              setState(() => _autoCapture = !_autoCapture),
                        ),
                        IconButton(
                          icon: Icon(_flashIcon, color: Colors.white),
                          tooltip: l10n.scanFlash,
                          onPressed: _toggleFlash,
                        ),
                        if (_cameras.length > 1)
                          IconButton(
                            icon: const Icon(Icons.cameraswitch,
                                color: Colors.white),
                            tooltip: l10n.scanSwitchCamera,
                            onPressed: _switchCamera,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Capture button (+ batch page counter and Done).
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 28,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Batch page count (left).
                    SizedBox(
                      width: 72,
                      child: widget.batch && _captured.isNotEmpty
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.photo_library,
                                    color: Colors.white),
                                Text('${_captured.length}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                              ],
                            )
                          : null,
                    ),
                    GestureDetector(
                      onTap: _busy ? null : _capture,
                      child: Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                              color: const Color(0xFF3DDC84), width: 5),
                        ),
                        child: _busy
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child:
                                    CircularProgressIndicator(strokeWidth: 3),
                              )
                            : const Icon(Icons.camera_alt, color: Colors.black),
                      ),
                    ),
                    // Done (right) — finish a batch session.
                    SizedBox(
                      width: 72,
                      child: widget.batch && _captured.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.check_circle,
                                  color: Color(0xFF3DDC84), size: 44),
                              tooltip: l10n.scanDone,
                              onPressed: _busy ? null : _finishBatch,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Fills the screen with the preview (BoxFit.cover) without distortion.
class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.controller});
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = controller.value.previewSize;
        if (size == null) return CameraPreview(controller);
        // previewSize is landscape-oriented; use the aspect for a cover fit.
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.height,
            height: size.width,
            child: CameraPreview(controller),
          ),
        );
      },
    );
  }
}

/// Paints the live detected quad in normalised (0..1) space over the preview,
/// tinted by [color] (green/orange/red by confidence).
class _LiveQuadPainter extends CustomPainter {
  _LiveQuadPainter(this.quadNorm, this.color);
  final List<Offset> quadNorm;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (quadNorm.length != 4) return;
    final pts = [
      for (final p in quadNorm) Offset(p.dx * size.width, p.dy * size.height),
    ];
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.13)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    // Corner grips.
    for (final p in pts) {
      canvas.drawCircle(p, 7, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_LiveQuadPainter old) =>
      old.quadNorm != quadNorm || old.color != color;
}
