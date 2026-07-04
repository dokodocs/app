import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/share/share_helpers.dart';

/// Views a saved document. PDFs render in the pdfrx viewer; image documents
/// (JPEG/PNG saved via "Save as image") render in a pan/zoom image view — the
/// pdfrx viewer only understands PDFs, so pointing it at a .jpg/.png showed
/// nothing ("can view PDF but not JPEG/PNG").
class PdfViewerScreen extends StatelessWidget {
  const PdfViewerScreen({super.key, required this.path});

  final String path;

  bool get _isPdf => path.toLowerCase().endsWith('.pdf');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.pdfViewerTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: l10n.commonShare,
            onPressed: () => shareDocumentFile(path),
          ),
        ],
      ),
      body: _isPdf
          ? PdfViewer.file(path)
          : Container(
              color: Colors.black,
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Center(
                  child: Image.file(File(path), fit: BoxFit.contain),
                ),
              ),
            ),
    );
  }
}
