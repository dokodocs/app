import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../editor/editor_screen.dart';
import 'crop_editor_screen.dart';
import 'document_builder.dart';
import 'filter_preview.dart';
import 'providers/scan_session_provider.dart';
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
    List<String>? paths;
    try {
      paths = await CunningDocumentScanner.getPictures(
        scannerSource: ScannerSource.camera,
      );
    } catch (_) {
      // Google Play services / ML Kit unavailable — fall back to basic camera.
      final shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (shot == null) return;
      paths = [shot.path];
    }
    if (paths == null || paths.isEmpty) return;
    ref.read(scanSessionProvider.notifier).addPaths(paths);
  }

  Future<void> _retakeSelected() async {
    List<String>? paths;
    try {
      paths = await CunningDocumentScanner.getPictures(
        scannerSource: ScannerSource.camera,
        noOfPages: 1,
      );
    } catch (_) {
      final shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (shot == null) return;
      paths = [shot.path];
    }
    if (paths == null || paths.isEmpty) return;
    ref
        .read(scanSessionProvider.notifier)
        .replaceAt(_selectedIndex, paths.first);
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
    ref.read(scanSessionProvider.notifier).removeAt(_selectedIndex);
    if (_selectedIndex >= pages.length - 1) {
      setState(() => _selectedIndex = (pages.length - 2).clamp(0, 1 << 30));
    }
  }

  Future<void> _save() async {
    final pages = ref.read(scanSessionProvider);
    if (pages.isEmpty || _isSaving) return;

    final format = await _chooseFormat(context);
    if (format == null || !mounted) return; // user dismissed the chooser

    final title = await _chooseName(context);
    if (title == null || !mounted) return; // user cancelled the name prompt

    setState(() => _isSaving = true);

    final l10n = AppLocalizations.of(context);
    final settings = await ref.read(userSettingsRepositoryProvider).get();

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

  /// Prompts for a document name, prefilled with `dokodocs_<epoch>` (the
  /// millisecond timestamp). Returns null if the user cancels.
  Future<String?> _chooseName(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(
      text: 'dokodocs_${DateTime.now().millisecondsSinceEpoch}',
    );
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.scanSaveNameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.scanSaveNameHint),
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.dialogSave),
          ),
        ],
      ),
    ).then((value) => (value == null || value.isEmpty) ? null : value);
  }

  Future<ExportFormat?> _chooseFormat(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<ExportFormat>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l10n.scanSaveAsTitle, style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(l10n.scanSaveAsPdf),
              subtitle: Text(l10n.scanSaveAsPdfBody),
              onTap: () => Navigator.of(sheetContext).pop(ExportFormat.pdf),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(l10n.scanSaveAsJpeg),
              subtitle: Text(l10n.scanSaveAsImageBody),
              onTap: () => Navigator.of(sheetContext).pop(ExportFormat.jpeg),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(l10n.scanSaveAsPng),
              subtitle: Text(l10n.scanSaveAsImageBody),
              onTap: () => Navigator.of(sheetContext).pop(ExportFormat.png),
            ),
          ],
        ),
      ),
    );
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
                      child: filteredPreview(
                        filter: page.filter,
                        child: Image.file(
                          File(page.imagePath),
                          fit: BoxFit.cover,
                        ),
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
