import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../editor/editor_screen.dart';
import 'camera_scanner_screen.dart';
import 'crop_editor_screen.dart';
import 'document_builder.dart';
import 'filter_preview.dart';
import 'providers/scan_session_provider.dart';
import 'scan_capture.dart' show autoCropSessionPagesInBackground;
import 'widgets/filter_picker.dart';

/// Multi-page tray: reorder / retake / delete / add-page / per-page filter,
/// then "Save" combines everything into one PDF document. Covers spec §4
/// screens 4-5 (Camera/Scan + Crop/Adjust) in one screen, since the native
/// scanner already handles capture + edge-detect + crop.
class ScanReviewScreen extends ConsumerStatefulWidget {
  const ScanReviewScreen({super.key, this.folderId});

  /// Folder the saved document(s) should belong to, if the scan was
  /// started from within a specific folder's context. Null saves to the
  /// root (matches prior behavior).
  final int? folderId;

  @override
  ConsumerState<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends ConsumerState<ScanReviewScreen> {
  int _selectedIndex = 0;
  bool _isSaving = false;

  Future<void> _addPage() async {
    final captured = await _capturePage();
    if (captured == null) return;
    ref.read(scanSessionProvider.notifier).addPaths([captured]);
    autoCropSessionPagesInBackground(ref, [captured]);
  }

  Future<void> _retakeSelected() async {
    final captured = await _capturePage();
    if (captured == null) return;
    ref.read(scanSessionProvider.notifier).replaceAt(_selectedIndex, captured);
    autoCropSessionPagesInBackground(ref, [captured]);
  }

  /// OpenCV rear-camera capture, shared by add-page and retake. The
  /// perspective crop runs in the BACKGROUND afterwards (no crop-editor
  /// stop — client feedback); returns the raw shot path, or null if the
  /// user backed out.
  Future<String?> _capturePage() async {
    final shot = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CameraScannerScreen()),
    );
    if (shot == null || !mounted) return null;
    return shot;
  }

  /// Opens the manual crop + perspective editor for the selected page and,
  /// on confirm, replaces the page image with the corrected result. Fills the
  /// gap for gallery imports and the basic-camera fallback, which arrive
  /// without the native scanner's automatic edge-detection/crop.
  Future<void> _cropSelected() async {
    final pages = ref.read(scanSessionProvider);
    if (pages.isEmpty) return;
    final page = pages[_selectedIndex.clamp(0, pages.length - 1)];
    final newPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CropEditorScreen(imagePath: page.imagePath),
      ),
    );
    if (newPath == null || !mounted) return;
    ref.read(scanSessionProvider.notifier).replaceAt(_selectedIndex, newPath);
  }

  void _deleteSelected() {
    final pages = ref.read(scanSessionProvider);
    if (pages.isEmpty) return;
    // Clamp BEFORE removing (the stale index could already exceed the list
    // after rapid deletes — the "error when deleting with multiple images"),
    // and always land the selection inside the NEW length afterwards.
    final idx = _selectedIndex.clamp(0, pages.length - 1);
    ref.read(scanSessionProvider.notifier).removeAt(idx);
    final newLength = pages.length - 1;
    if (newLength <= 0) {
      // Last page deleted — nothing left to review.
      Navigator.of(context).pop();
      return;
    }
    setState(() => _selectedIndex = idx.clamp(0, newLength - 1));
  }

  Future<void> _save() async {
    if (ref.read(scanSessionProvider).isEmpty || _isSaving) return;

    // ONE-TAP SAVE (client feedback): no format chooser, no name prompt —
    // PDF with an auto-generated name. Rename/re-export remain available
    // from the document actions afterwards.
    const format = ExportFormat.pdf;
    final title = 'dokodocs_${DateTime.now().millisecondsSinceEpoch}';

    setState(() => _isSaving = true);

    final l10n = AppLocalizations.of(context);
    final settings = await ref.read(userSettingsRepositoryProvider).get();

    // Phase 2 queue: wait for any BACKGROUND auto-crops still in flight so a
    // fast Save never persists a raw, uncropped page. Bounded at 20 s — a
    // stuck crop then saves whatever state the page is in rather than
    // hanging the save forever.
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (ref.read(scanSessionProvider).any((p) => p.processing) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (!mounted) return;
    // Re-read AFTER the wait — background crops swap page paths in place.
    final pages = ref.read(scanSessionProvider);
    if (pages.isEmpty) {
      setState(() => _isSaving = false);
      return;
    }

    try {
      final documentIds = await saveScanSessionAsDocument(
        pages: pages,
        documentsRepository: ref.read(documentsRepositoryProvider),
        pagesRepository: ref.read(pagesRepositoryProvider),
        title: title,
        format: format,
        folderId: widget.folderId,
        // Watermark is always applied (not user-disableable).
        applyWatermark: true,
        watermarkPosition: settings.watermarkPosition,
      );
      final documents = [
        for (final id in documentIds)
          await ref.read(documentsRepositoryProvider).getById(id),
      ];

      ref.read(scanSessionProvider.notifier).clear();
      if (!mounted) return;

      await _showPostSaveSheet(title, documents);
    } catch (error) {
      // Previously any failure here (e.g. a gallery image the decoder can't
      // read) threw silently and the document just never appeared — looking
      // like "import from gallery can't save". Surface it instead.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.scanSaveFailed('$error'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// After a successful save, offer to Open the new document, Share it, or
  /// Close back to Home — with an explicit close (✕) affordance. Replaces the
  /// old fire-and-forget snackbar.
  Future<void> _showPostSaveSheet(
    String title,
    List<Document> documents,
  ) async {
    final l10n = AppLocalizations.of(context);
    final first = documents.first;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(l10n.scanSavedBody),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.dialogClose,
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                first.fileType == 'image'
                    ? Icons.image_outlined
                    : Icons.picture_as_pdf_outlined,
              ),
              title: Text(l10n.scanOpen),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).popUntil((route) => route.isFirst);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EditorScreen(documentId: first.id),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: Text(l10n.commonShare),
              onTap: () {
                Navigator.of(sheetContext).pop();
                SharePlus.instance.share(
                  ShareParams(
                    files: [for (final d in documents) XFile(d.localPath)],
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text(l10n.scanDone),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      ),
    );
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = ref.watch(scanSessionProvider);

    if (pages.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.scanReviewTitle)),
        body: Center(child: Text(l10n.scanNoPagesYet)),
      );
    }

    final selectedIndex = _selectedIndex.clamp(0, pages.length - 1);
    final selectedPage = pages[selectedIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scanReviewTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_a_photo_outlined),
            tooltip: l10n.scanAddPage,
            onPressed: _isSaving ? null : _addPage,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    child: Transform.rotate(
                      angle: selectedPage.rotation * 3.1415926535 / 180,
                      child: filteredPreview(
                        filter: selectedPage.filter,
                        child: Image.file(
                          File(selectedPage.imagePath),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
                if (selectedPage.needsReview)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Chip(
                      avatar: Icon(
                        Icons.crop_free,
                        size: 18,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      label: Text(l10n.scanNeedsReviewHint),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.crop),
                label: Text(l10n.scanCrop),
                onPressed: _isSaving ? null : _cropSelected,
              ),
              TextButton.icon(
                icon: const Icon(Icons.rotate_right),
                label: Text(l10n.editorRotate),
                onPressed: () =>
                    ref.read(scanSessionProvider.notifier).rotate(selectedIndex),
              ),
              TextButton.icon(
                icon: const Icon(Icons.restore),
                label: Text(l10n.editorRevertToOriginal),
                onPressed: () => ref
                    .read(scanSessionProvider.notifier)
                    .revertToOriginal(selectedIndex),
              ),
            ],
          ),
          FilterPicker(
            selectedFilter: selectedPage.filter,
            onSelected: (filter) => ref
                .read(scanSessionProvider.notifier)
                .setFilter(selectedIndex, filter),
          ),
          SizedBox(
            height: 88,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: pages.length,
              onReorderItem: (oldIndex, newIndex) {
                ref
                    .read(scanSessionProvider.notifier)
                    .reorder(oldIndex, newIndex);
                setState(() {
                  if (_selectedIndex == oldIndex) {
                    _selectedIndex = newIndex > oldIndex
                        ? newIndex - 1
                        : newIndex;
                  }
                });
              },
              itemBuilder: (context, index) {
                final page = pages[index];
                final isSelected = index == selectedIndex;
                return GestureDetector(
                  key: ValueKey(page.imagePath + index.toString()),
                  onTap: () => setState(() => _selectedIndex = index),
                  child: Container(
                    width: 64,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          filteredPreview(
                            filter: page.filter,
                            child: Image.file(
                              File(page.imagePath),
                              fit: BoxFit.cover,
                            ),
                          ),
                          // Background auto-crop still running for this page.
                          if (page.processing)
                            Container(
                              color: Colors.black.withValues(alpha: 0.35),
                              alignment: Alignment.center,
                              child: const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : _retakeSelected,
                    icon: const Icon(Icons.replay),
                    label: Text(l10n.scanRetake),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : _deleteSelected,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.scanDelete),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_isSaving ? l10n.scanSavingDocument : l10n.scanSave),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
