import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';

/// Result of placing a signature: the centre position and width as fractions
/// of the page image (0..1), ready to hand to the compositor.
class SignaturePlacement {
  const SignaturePlacement(this.centerX, this.centerY, this.widthFraction);
  final double centerX;
  final double centerY;
  final double widthFraction;
}

/// Lets the user drag a signature over a page preview and size it, then Apply.
/// Pops a [SignaturePlacement], or null if cancelled.
class SignaturePlacementScreen extends StatefulWidget {
  const SignaturePlacementScreen({
    super.key,
    required this.pageImagePath,
    required this.signatureImagePath,
  });

  final String pageImagePath;
  final String signatureImagePath;

  @override
  State<SignaturePlacementScreen> createState() =>
      _SignaturePlacementScreenState();
}

class _SignaturePlacementScreenState extends State<SignaturePlacementScreen> {
  double _cx = 0.5;
  double _cy = 0.8;
  double _widthFraction = 0.35;

  double? _pageAspect; // width / height
  double _sigAspect = 3; // width / height, updated after decode

  @override
  void initState() {
    super.initState();
    _loadAspects();
  }

  Future<void> _loadAspects() async {
    final page = await _decodeSize(widget.pageImagePath);
    final sig = await _decodeSize(widget.signatureImagePath);
    if (!mounted) return;
    setState(() {
      _pageAspect = page.width / page.height;
      _sigAspect = sig.width / sig.height;
    });
  }

  Future<ui.Image> _decodeSize(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pageAspect = _pageAspect;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.editorAddSignature),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              SignaturePlacement(_cx, _cy, _widthFraction),
            ),
            child: Text(l10n.signatureApply),
          ),
        ],
      ),
      body: pageAspect == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(l10n.signaturePlaceHint),
                ),
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: pageAspect,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final boxW = constraints.maxWidth;
                          final boxH = constraints.maxHeight;
                          final sigW = _widthFraction * boxW;
                          final sigH = sigW / _sigAspect;
                          return Stack(
                            children: [
                              Positioned.fill(
                                child: Image.file(
                                  File(widget.pageImagePath),
                                  fit: BoxFit.fill,
                                ),
                              ),
                              Positioned(
                                left: _cx * boxW - sigW / 2,
                                top: _cy * boxH - sigH / 2,
                                width: sigW,
                                height: sigH,
                                child: GestureDetector(
                                  onPanUpdate: (details) {
                                    setState(() {
                                      _cx = (_cx + details.delta.dx / boxW)
                                          .clamp(0.0, 1.0);
                                      _cy = (_cy + details.delta.dy / boxH)
                                          .clamp(0.0, 1.0);
                                    });
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: const Color(0xFF9CCC8E),
                                      ),
                                    ),
                                    child: Image.file(
                                      File(widget.signatureImagePath),
                                      fit: BoxFit.fill,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.photo_size_select_small),
                        Expanded(
                          child: Slider(
                            value: _widthFraction,
                            min: 0.1,
                            max: 0.9,
                            onChanged: (v) =>
                                setState(() => _widthFraction = v),
                          ),
                        ),
                        const Icon(Icons.photo_size_select_large),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
