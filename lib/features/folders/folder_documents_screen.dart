import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/share/share_helpers.dart';
import '../../core/widgets/empty_state.dart';
import '../editor/editor_screen.dart';
import '../home/widgets/document_tile.dart';
import '../scan/scan_capture.dart';

/// Documents inside a single folder — reuses the same `DocumentTile` grid
/// as Home, scoped to one `folderId`.
class FolderDocumentsScreen extends ConsumerWidget {
  const FolderDocumentsScreen({super.key, required this.folder});

  final Folder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final documentsAsync = ref.watch(_folderDocumentsProvider(folder.id));

    return Scaffold(
      appBar: AppBar(title: Text(folder.name)),
      body: documentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('$error')),
        data: (documents) {
          if (documents.isEmpty) {
            return EmptyState(
              icon: Icons.document_scanner_outlined,
              title: l10n.homeEmptyTitle,
              body: l10n.homeEmptyBody,
              primaryActionLabel: l10n.homeScanNow,
              onPrimaryAction: () =>
                  startScanFlow(context, ref, folderId: folder.id),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.68,
            ),
            itemCount: documents.length,
            itemBuilder: (context, index) {
              final document = documents[index];
              return _FolderDocumentTile(document: document);
            },
          );
        },
      ),
    );
  }
}

class _FolderDocumentTile extends ConsumerWidget {
  const _FolderDocumentTile({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailAsync = ref.watch(_firstPageProvider(document.id));
    return DocumentTile(
      document: document,
      thumbnailPath: thumbnailAsync.value?.localImagePath,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditorScreen(documentId: document.id),
        ),
      ),
      onToggleFavorite: () => ref
          .read(documentsRepositoryProvider)
          .setFavorite(document.id, !document.isFavorite),
      onTrash: () =>
          ref.read(documentsRepositoryProvider).moveToTrash(document.id),
      onShare: () => shareDocumentFile(document.localPath),
    );
  }
}

final _folderDocumentsProvider =
    StreamProvider.family<List<Document>, int>((ref, folderId) {
      return ref
          .watch(documentsRepositoryProvider)
          .watchActive(folderId: folderId);
    });

final _firstPageProvider = FutureProvider.family<DocPage?, int>((ref, id) {
  return ref.watch(pagesRepositoryProvider).getFirstPage(id);
});
