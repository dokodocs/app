import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/l10n/app_localizations.dart';
import 'crop_geometry.dart';
import 'crop_processor.dart';

/// A manual crop + perspective-correction editor for one captured page.
///
/// This fills the real gap the native ML Kit / VisionKit scanner leaves:
/// pages that arrive WITHOUT native edge-detection — gallery imports and the
/// basic-camera fallback (used when Google Play services / ML Kit is
/// unavailable) — otherwise get no crop at all. It shows the image full-bleed
/// with four draggable corner handles and a live green outline of exactly what
/// will be kept, then warps the selected quad flat (see [rectifyDocument]).
///
/// Returns the path to the new, perspective-corrected JPEG via
/// `Navigator.pop`, or null if the user cancels.
class CropEditorScreen extends StatefulWidget {
  const CropEditorScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<CropEditorScreen> createState() => _CropEditorScreenState();
}

class _CropEditorScreenState extends State<CropEditorScreen> {
  ui.Image? _image; // decoded, for its intrinsic dimensions
  Size _imageSize = Size.zero;

  /// Corners in IMAGE-pixel space, order TL, TR, BR, BL (clockwise).
  late List<Offset> _corners;
  int _dragging = -1;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _image = frame.image;
      _imageSize =
          Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      _corners = _defaultCorners(_imageSize);
    });
  }

  /// Default handles sit just inside the frame edges (by the shared
  /// [kSafetyMarginFraction]) so all four are visible and grabbable, and so
  /// "Reset" is an honest "keep (almost) the whole frame" — no invented
  /// document border where detection didn't run.
  List<Offset> _defaultCorners(Size s) {
    final mx = s.width * kSafetyMarginFraction;
    final my = s.height * kSafetyMarginFraction;
    return [
      Offset(mx, my),
      Offset(s.width - mx, my),
      Offset(s.width - mx, s.height - my),
      Offset(mx, s.height - my),
    ];
  }

  // ---- image <-> widget coordinate mapping for a BoxFit.contain layout ----
  ({double scale, Offset origin}) _fit(Size box) {
    final scale = math.min(
      box.width / _imageSize.width,
      box.height / _imageSize.height,
    );
    final dispW = _imageSize.width * scale;
    final dispH = _imageSize.height * scale;
    return (
      scale: scale,
      origin: Offset((box.width - dispW) / 2, (box.height - dispH) / 2),
    );
  }

  Offset _imageToWidget(Offset img, Size box) {
    final f = _fit(box);
    return Offset(
      f.origin.dx + img.dx * f.scale,
      f.origin.dy + img.dy * f.scale,
    );
  }

  Offset _widgetToImage(Offset w, Size box) {
    final f = _fit(box);
    final x = ((w.dx - f.origin.dx) / f.scale).clamp(0.0, _imageSize.width);
    final y = ((w.dy - f.origin.dy) / f.scale).clamp(0.0, _imageSize.height);
    return Offset(x, y);
  }

  void _onPanStart(Offset local, Size box) {
    // Grab the nearest corner within a comfortable touch radius.
    var best = -1;
    var bestDist = 44.0; // logical px
    for (var i = 0; i < 4; i++) {
      final d = (_imageToWidget(_corners[i], box) - local).distance;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    setState(() => _dragging = best);
  }

  void _onPanUpdate(Offset local, Size box) {
    if (_dragging < 0) return;
    setState(() => _corners[_dragging] = _widgetToImage(local, box));
  }

  void _reset() => setState(() => _corners = _defaultCorners(_imageSize));

  Future<void> _confirm() async {
    if (_processing) return;
    setState(() => _processing = true);
    final l10n = AppLocalizations.of(context);
    try {
      final dir = await getTemporaryDirectory();
      final outPath = p.join(
        dir.path,
        'crop_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final req = CropRequest(
        srcPath: widget.imagePath,
        corners: Quad(
          (x: _corners[0].dx, y: _corners[0].dy),
          (x: _corners[1].dx, y: _corners[1].dy),
          (x: _corners[2].dx, y: _corners[2].dy),
          (x: _corners[3].dx, y: _corners[3].dy),
        ).toList(),
        outPath: outPath,
      );
      final result = await compute(rectifyDocument, req.toMap());
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (_) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.cropFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l10n.cropTitle),
        actions: [
          TextButton(
            onPressed: _processing ? null : _reset,
            child: Text(l10n.cropReset),
          ),
        ],
      ),
      body: _image == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final box =
                          Size(constraints.maxWidth, constraints.maxHeight);
                      return GestureDetector(
                        onPanStart: (d) => _onPanStart(d.localPosition, box),
                        onPanUpdate: (d) => _onPanUpdate(d.localPosition, box),
                        onPanEnd: (_) => setState(() => _dragging = -1),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Center(
                              child: Image.file(
                                File(widget.imagePath),
                                fit: BoxFit.contain,
                              ),
                            ),
                            CustomPaint(
                              painter: _QuadPainter(
                                corners: [
                                  for (final c in _corners)
                                    _imageToWidget(c, box),
                                ],
                                color: const Color(0xFF3DDC84),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  color: Colors.black,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Text(
                    l10n.cropInstruction,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _processing
                                ? null
                                : () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white54),
                            ),
                            child: Text(l10n.dialogCancel),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _processing ? null : _confirm,
                            icon: _processing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.check),
                            label: Text(
                              _processing
                                  ? l10n.cropProcessing
                                  : l10n.cropConfirm,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Draws the live document outline: a filled dim scrim outside the quad, a
/// bright edge, and grab handles at each corner.
class _QuadPainter extends CustomPainter {
  _QuadPainter({required this.corners, required this.color});

  final List<Offset> corners;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;
    final path = Path()..addPolygon(corners, true);

    // Dim everything outside the selected quad so the user sees what's kept.
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addPolygon(corners, true)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, Paint()..color = Colors.black54);

    // Bright outline.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color,
    );

    // Corner handles.
    final fill = Paint()..color = color;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    for (final c in corners) {
      canvas.drawCircle(c, 10, fill);
      canvas.drawCircle(c, 10, ring);
    }
  }

  @override
  bool shouldRepaint(_QuadPainter old) =>
      old.corners != corners || old.color != color;
}
