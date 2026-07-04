import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/pdf/pdf_builder.dart';
import '../../core/render/document_export.dart';
import '../../core/render/page_renderer.dart';
import '../../core/render/signature_compositor.dart';
import '../pdf_viewer/pdf_viewer_screen.dart';
import '../scan/widgets/filter_picker.dart';
import '../signature/signature_placement_screen.dart';
import '../signature/signatures_screen.dart';
import 'version_history_screen.dart';
import 'version_service.dart';

/// Document editor: reorder / delete / add pages, per-page Edit (filter,
/// rotate) and Revert-to-original, plus version history. All page rendering
/// goes through the immutable original (non-destructive rule): editing only
/// changes render-time metadata, and every material edit captures a version.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.documentId});

  final int documentId;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  bool _isWorking = false;

  /// Re-renders every page from its immutable original honoring the current
  /// watermark setting, rebuilds the PDF, and updates document metadata.
  /// Reading the watermark setting HERE (export time) is what lets toggling
  /// it off produce a clean export from the same document.
  Future<void> _regenerate(Document document) async {
    final pages =
        await ref.read(pagesRepositoryProvider).getForDocument(document.id);
    final settings = await ref.read(userSettingsRepositoryProvider).get();
    final watermark = resolveWatermark(settings, pageCount: pages.length);
    final processed = await renderProcessedPages(
      pages: pages,
      watermark: watermark,
      watermarkPosition: settings.watermarkPosition,
    );
    if (document.fileType == 'pdf') {
      await buildPdfFromImages(
        imagePaths: processed,
        outputPath: document.localPath,
      );
    }
    final sizeBytes = await File(document.localPath).length();
    await ref.read(documentsRepositoryProvider).updateDocument(
          document.id,
          DocumentsCompanion(
            pageCount: Value(pages.length),
            sizeBytes: Value(sizeBytes),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> _captureVersion(int documentId, String label) {
    return captureVersion(
      documentId: documentId,
      pagesRepository: ref.read(pagesRepositoryProvider),
      versionsRepository: ref.read(documentVersionsRepositoryProvider),
      changeLabel: label,
    );
  }

  Future<void> _deletePage(
    Document document,
    List<DocPage> pages,
    int index,
  ) async {
    if (pages.length <= 1) return; // a document needs at least one page
    setState(() => _isWorking = true);
    try {
      final page = pages[index];
      await ref.read(pagesRepositoryProvider).deletePage(page.id);
      final remaining = [...pages]..removeAt(index);
      for (var i = 0; i < remaining.length; i++) {
        await ref
            .read(pagesRepositoryProvider)
            .updatePageOrder(remaining[i].id, i);
      }
      await _regenerate(document);
      await _captureVersion(document.id, 'page_removed');
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _reorder(
    Document document,
    List<DocPage> pages,
    int oldIndex,
    int newIndex,
  ) async {
    setState(() => _isWorking = true);
    try {
      final reordered = [...pages];
      final item = reordered.removeAt(oldIndex);
      reordered.insert(newIndex, item);
      for (var i = 0; i < reordered.length; i++) {
        await ref
            .read(pagesRepositoryProvider)
            .updatePageOrder(reordered[i].id, i);
      }
      await _regenerate(document);
      await _captureVersion(document.id, 'pages_reordered');
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  /// Scans more pages and appends them to an already-saved PDF document.
  Future<void> _addPage(Document document, List<DocPage> pages) async {
    setState(() => _isWorking = true);
    try {
      List<String>? paths;
      try {
        paths = await CunningDocumentScanner.getPictures(
          scannerSource: ScannerSource.camera,
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).scanScannerError),
            ),
          );
        }
        return;
      }
      if (paths == null || paths.isEmpty) return;

      final docFolder = p.dirname(pages.first.originalImagePath);
      var nextOrder = pages.length;
      final newPages = <PagesCompanion>[];
      for (final sourcePath in paths) {
        // Persist the immutable original, then render the preview from it.
        final originalPath = p.join(docFolder, 'original_$nextOrder.jpg');
        await File(sourcePath).copy(originalPath);
        final previewPath = p.join(docFolder, 'page_$nextOrder.jpg');
        await renderPage(originalPath: originalPath, destPath: previewPath);
        newPages.add(
          PagesCompanion.insert(
            documentId: document.id,
            pageOrder: nextOrder,
            originalImagePath: originalPath,
            localImagePath: previewPath,
          ),
        );
        nextOrder++;
      }
      await ref.read(pagesRepositoryProvider).insertPages(newPages);
      await _regenerate(document);
      await _captureVersion(document.id, 'page_added');
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  /// Per-page Edit sheet: filter + rotate + revert-to-original.
  Future<void> _editPage(Document document, DocPage page) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _PageEditSheet(
        page: page,
        onFilter: (filter) async {
          Navigator.of(sheetContext).pop();
          setState(() => _isWorking = true);
          try {
            await ref
                .read(pagesRepositoryProvider)
                .updateMetadata(page.id, filter: filter);
            await _regenerate(document);
            await _captureVersion(document.id, 'filter_changed');
          } finally {
            if (mounted) setState(() => _isWorking = false);
          }
        },
        onRotate: () async {
          Navigator.of(sheetContext).pop();
          setState(() => _isWorking = true);
          try {
            final rotation = (page.rotation + 90) % 360;
            await ref
                .read(pagesRepositoryProvider)
                .updateMetadata(page.id, rotation: rotation);
            await _regenerate(document);
            await _captureVersion(document.id, 'rotated');
          } finally {
            if (mounted) setState(() => _isWorking = false);
          }
        },
        onRevert: () async {
          Navigator.of(sheetContext).pop();
          await _revertPage(document, page);
        },
      ),
    );
  }

  /// Restores a page to its original uncropped, unfiltered capture.
  Future<void> _revertPage(Document document, DocPage page) async {
    setState(() => _isWorking = true);
    try {
      await ref.read(pagesRepositoryProvider).revertToOriginal(page.id);
      await _regenerate(document);
      await _captureVersion(document.id, 'reverted');
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.editorRevertedSnack)));
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  /// Lets the user pick a saved signature (creating one if none exist yet),
  /// choose a page, position it, then bakes it into that page's preview and
  /// rebuilds the PDF from the current previews. Rebuilding from the previews
  /// (not re-rendering from the originals) is what preserves the signature —
  /// re-rendering would wipe it, since signatures are additive edits that live
  /// only on the processed copy.
  Future<void> _addSignature(Document document, List<DocPage> pages) async {
    final signature = await Navigator.of(context).push<Signature>(
      MaterialPageRoute(
        builder: (_) => const SignaturesScreen(picking: true),
      ),
    );
    if (signature == null || !mounted) return;

    final pageIndex = pages.length == 1 ? 0 : await _choosePage(pages);
    if (pageIndex == null || !mounted) return;
    final page = pages[pageIndex];

    final placement = await Navigator.of(context).push<SignaturePlacement>(
      MaterialPageRoute(
        builder: (_) => SignaturePlacementScreen(
          pageImagePath: page.localImagePath,
          signatureImagePath: signature.imagePath,
        ),
      ),
    );
    if (placement == null || !mounted) return;

    setState(() => _isWorking = true);
    try {
      await compositeSignatureOnImage(
        imagePath: page.localImagePath,
        signaturePath: signature.imagePath,
        centerX: placement.centerX,
        centerY: placement.centerY,
        widthFraction: placement.widthFraction,
      );
      if (document.fileType == 'pdf') {
        await buildPdfFromImages(
          imagePaths: [for (final p in pages) p.localImagePath],
          outputPath: document.localPath,
        );
      }
      final sizeBytes = await File(document.localPath).length();
      await ref.read(documentsRepositoryProvider).updateDocument(
            document.id,
            DocumentsCompanion(
              sizeBytes: Value(sizeBytes),
              updatedAt: Value(DateTime.now()),
            ),
          );
      await _captureVersion(document.id, 'signature_added');
      // The page file changed but its path did not — drop cached bitmaps so
      // the refreshed preview shows.
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  /// Simple page chooser used before placing a signature on a multi-page doc.
  Future<int?> _choosePage(List<DocPage> pages) {
    return showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < pages.length; i++)
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(pages[i].localImagePath),
                    width: 40,
                    height: 52,
                    fit: BoxFit.cover,
                  ),
                ),
                title: Text('${i + 1}'),
                onTap: () => Navigator.of(sheetContext).pop(i),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _share(Document document) async {
    // Ensure the exported file reflects the current watermark setting.
    setState(() => _isWorking = true);
    try {
      await _regenerate(document);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
    await SharePlus.instance
        .share(ShareParams(files: [XFile(document.localPath)]));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final documentAsync = ref.watch(_documentProvider(widget.documentId));
    final pagesAsync = ref.watch(_pagesProvider(widget.documentId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.editorTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: l10n.editorVersionHistory,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    VersionHistoryScreen(documentId: widget.documentId),
              ),
            ),
          ),
          documentAsync.when(
            data: (document) => document.fileType != 'pdf'
                ? const SizedBox.shrink()
                : pagesAsync.maybeWhen(
                    data: (pages) => IconButton(
                      icon: const Icon(Icons.add_a_photo_outlined),
                      tooltip: l10n.editorAddPage,
                      onPressed: _isWorking
                          ? null
                          : () => _addPage(document, pages),
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),
          documentAsync.maybeWhen(
            data: (document) => pagesAsync.maybeWhen(
              data: (pages) => IconButton(
                icon: const Icon(Icons.draw_outlined),
                tooltip: l10n.editorAddSignature,
                onPressed:
                    _isWorking ? null : () => _addSignature(document, pages),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          documentAsync.when(
            data: (document) => IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: l10n.editorShare,
              onPressed: _isWorking ? null : () => _share(document),
            ),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: documentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('$error')),
        data: (document) => pagesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(child: Text('$error')),
          data: (pages) => Column(
            children: [
              if (_isWorking) const LinearProgressIndicator(),
              Expanded(
                child: _PageList(
                  pages: pages,
                  onReorder: (oldIndex, newIndex) =>
                      _reorder(document, pages, oldIndex, newIndex),
                  onDelete: (index) => _deletePage(document, pages, index),
                  onEdit: (page) => _editPage(document, page),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _isWorking
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PdfViewerScreen(path: document.localPath),
                          ),
                        ),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(l10n.editorViewPdf),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageList extends StatelessWidget {
  const _PageList({
    required this.pages,
    required this.onReorder,
    required this.onDelete,
    required this.onEdit,
  });

  final List<DocPage> pages;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index) onDelete;
  final void Function(DocPage page) onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: pages.length,
      onReorderItem: onReorder,
      itemBuilder: (context, index) {
        final page = pages[index];
        return Padding(
          key: ValueKey(page.id),
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Text('${index + 1}'),
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(page.localImagePath),
                  width: 40,
                  height: 52,
                  fit: BoxFit.cover,
                ),
              ),
              if (page.needsReview)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Tooltip(
                    message: l10n.scanNeedsReviewHint,
                    child: Icon(
                      Icons.crop_free,
                      color: Theme.of(context).colorScheme.error,
                      size: 20,
                    ),
                  ),
                ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: l10n.editorEditPage,
                onPressed: () => onEdit(page),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDelete(index),
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PageEditSheet extends StatelessWidget {
  const _PageEditSheet({
    required this.page,
    required this.onFilter,
    required this.onRotate,
    required this.onRevert,
  });

  final DocPage page;
  final void Function(String filter) onFilter;
  final VoidCallback onRotate;
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  l10n.editorEditPage,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.rotate_right),
                  label: Text(l10n.editorRotate),
                  onPressed: onRotate,
                ),
              ],
            ),
          ),
          FilterPicker(selectedFilter: page.filter, onSelected: onFilter),
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.restore),
              label: Text(l10n.editorRevertToOriginal),
              onPressed: onRevert,
            ),
          ),
        ],
      ),
    );
  }
}

final _documentProvider = FutureProvider.family<Document, int>((ref, id) {
  return ref.watch(documentsRepositoryProvider).getById(id);
});

final _pagesProvider = StreamProvider.family<List<DocPage>, int>((ref, id) {
  return ref.watch(pagesRepositoryProvider).watchForDocument(id);
});
