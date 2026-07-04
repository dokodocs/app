import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/database/database_provider.dart';
import '../../core/l10n/app_localizations.dart';
import 'signature_processing.dart';

/// Import a signature from a photo: crop to the signature, clean the paper
/// away with a high-contrast threshold, preview, then save as a transparent
/// PNG. Pops `true` when a signature was saved.
class SignatureImportScreen extends ConsumerStatefulWidget {
  const SignatureImportScreen({super.key, required this.sourcePath});

  final String sourcePath;

  @override
  ConsumerState<SignatureImportScreen> createState() =>
      _SignatureImportScreenState();
}

class _SignatureImportScreenState
    extends ConsumerState<SignatureImportScreen> {
  // Crop rectangle as fractions (0..1) of the source image.
  double _l = 0.08, _t = 0.08, _r = 0.92, _b = 0.92;
  double _threshold = 0.62;
  bool _highContrast = true;

  double? _imageAspect; // w / h
  String? _previewPath;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadAspect();
  }

  Future<void> _loadAspect() async {
    final bytes = await File(widget.sourcePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() =>
        _imageAspect = frame.image.width / frame.image.height);
  }

  Future<String> _runProcessing(String destPath) {
    return processSignatureImage(
      sourcePath: widget.sourcePath,
      destPath: destPath,
      crop: [_l, _t, _r, _b],
      threshold: _threshold,
      highContrast: _highContrast,
    );
  }

  Future<void> _preview() async {
    setState(() => _busy = true);
    try {
      final dir = await getTemporaryDirectory();
      final path = p.join(
        dir.path,
        'sig_preview_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await _runProcessing(path);
      // Bust the image cache so the same-widget preview actually updates.
      await File(path).exists();
      if (mounted) {
        setState(() => _previewPath = path);
        imageCache.clear();
        imageCache.clearLiveImages();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDir.path, 'signatures'));
      await dir.create(recursive: true);
      final path = p.join(
        dir.path,
        'sig_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await _runProcessing(path);
      await ref.read(signaturesRepositoryProvider).add(path);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final aspect = _imageAspect;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.signatureImportTitle),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: Text(l10n.dialogSave),
          ),
        ],
      ),
      body: aspect == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_busy) const LinearProgressIndicator(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _previewPath != null
                        ? _buildPreview(l10n)
                        : _buildCropper(aspect),
                  ),
                ),
                _buildControls(l10n),
              ],
            ),
    );
  }

  Widget _buildPreview(AppLocalizations l10n) {
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFF9CCC8E)),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.file(
              File(_previewPath!),
              key: ValueKey(_previewPath),
              fit: BoxFit.contain,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: _busy ? null : () => setState(() => _previewPath = null),
          icon: const Icon(Icons.crop),
          label: Text(l10n.signatureBackToCrop),
        ),
      ],
    );
  }

  Widget _buildCropper(double aspect) {
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            double px(double frac) => frac * w;
            double py(double frac) => frac * h;

            return Stack(
              children: [
                Positioned.fill(
                  child: Image.file(File(widget.sourcePath), fit: BoxFit.fill),
                ),
                // Crop rectangle.
                Positioned(
                  left: px(_l),
                  top: py(_t),
                  width: px(_r - _l),
                  height: py(_b - _t),
                  child: GestureDetector(
                    onPanUpdate: (d) => setState(() {
                      final dx = d.delta.dx / w;
                      final dy = d.delta.dy / h;
                      final width = _r - _l, height = _b - _t;
                      _l = (_l + dx).clamp(0.0, 1.0 - width);
                      _t = (_t + dy).clamp(0.0, 1.0 - height);
                      _r = _l + width;
                      _b = _t + height;
                    }),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFF2E7D6B),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                _handle(px(_l), py(_t), (dx, dy) {
                  setState(() {
                    _l = (_l + dx / w).clamp(0.0, _r - 0.05);
                    _t = (_t + dy / h).clamp(0.0, _b - 0.05);
                  });
                }),
                _handle(px(_r), py(_t), (dx, dy) {
                  setState(() {
                    _r = (_r + dx / w).clamp(_l + 0.05, 1.0);
                    _t = (_t + dy / h).clamp(0.0, _b - 0.05);
                  });
                }),
                _handle(px(_l), py(_b), (dx, dy) {
                  setState(() {
                    _l = (_l + dx / w).clamp(0.0, _r - 0.05);
                    _b = (_b + dy / h).clamp(_t + 0.05, 1.0);
                  });
                }),
                _handle(px(_r), py(_b), (dx, dy) {
                  setState(() {
                    _r = (_r + dx / w).clamp(_l + 0.05, 1.0);
                    _b = (_b + dy / h).clamp(_t + 0.05, 1.0);
                  });
                }),
              ],
            );
          },
        ),
      ),
    );
  }

  /// A draggable corner handle centred on ([cx], [cy]) in box pixels.
  Widget _handle(double cx, double cy, void Function(double, double) onDrag) {
    const size = 28.0;
    return Positioned(
      left: cx - size / 2,
      top: cy - size / 2,
      child: GestureDetector(
        onPanUpdate: (d) => onDrag(d.delta.dx, d.delta.dy),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFF2E7D6B),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(AppLocalizations l10n) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.contrast, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.signatureThreshold)),
                Expanded(
                  flex: 3,
                  child: Slider(
                    value: _threshold,
                    min: 0.3,
                    max: 0.9,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _threshold = v),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(l10n.signatureHighContrast),
              value: _highContrast,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _highContrast = v),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _preview,
                    icon: const Icon(Icons.visibility_outlined),
                    label: Text(l10n.signaturePreview),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(l10n.dialogSave),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
