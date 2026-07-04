import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/share/share_helpers.dart';

/// Phase 1 scope: view a saved PDF with a page-thumbnail sidebar. Inline
/// annotate/sign lands in Phase 3 (see README.md in this folder).
class PdfViewerScreen extends StatelessWidget {
  const PdfViewerScreen({super.key, required this.path});

  final String path;

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
      body: PdfViewer.file(path),
    );
  }
}
