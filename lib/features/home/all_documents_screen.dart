import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/date/date_formatter_provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/share/share_helpers.dart';
import '../editor/editor_screen.dart';
import '../folders/folder_documents_screen.dart';
import 'widgets/document_tile.dart';

/// The full library ("See all") — reached from Home's Recent/Folders section
/// headers. Shows every active document, or the full folder list when
/// [foldersView] is true. A route-only addition; navigation shell untouched.
class AllDocumentsScreen extends ConsumerWidget {
  const AllDocumentsScreen({super.key, this.foldersView = false});

  final bool foldersView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(foldersView ? l10n.homeFolders : l10n.homeAllDocuments),
      ),
      body: foldersView ? const _AllFolders() : const _AllDocuments(),
    );
  }
}

class _AllDocuments extends ConsumerWidget {
  const _AllDocuments();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documentsAsync = ref.watch(_allDocumentsProvider);
    final formatter = ref.watch(dateFormatterProvider);
    return documentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (documents) => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.68,
        ),
        itemCount: documents.length,
        itemBuilder: (context, index) {
          final document = documents[index];
          final thumbnail = ref.watch(_firstPageProvider(document.id));
          return DocumentTile(
            document: document,
            thumbnailPath: thumbnail.value?.localImagePath,
            dateText: formatter.medium(document.updatedAt),
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
        },
      ),
    );
  }
}

class _AllFolders extends ConsumerWidget {
  const _AllFolders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(_allFoldersProvider);
    return foldersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (folders) => ListView(
        children: [
          for (final folder in folders)
            ListTile(
              leading: Icon(
                Icons.folder,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(folder.name),
              trailing: IconButton(
                icon: Icon(
                  folder.isFavorite ? Icons.star : Icons.star_border,
                  color: folder.isFavorite ? Colors.amber : null,
                ),
                onPressed: () => ref
                    .read(foldersRepositoryProvider)
                    .setFavorite(folder.id, !folder.isFavorite),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FolderDocumentsScreen(folder: folder),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final _allDocumentsProvider = StreamProvider<List<Document>>((ref) {
  return ref.watch(documentsRepositoryProvider).watchActive();
});

final _allFoldersProvider = StreamProvider<List<Folder>>((ref) {
  return ref.watch(foldersRepositoryProvider).watchAll();
});

final _firstPageProvider = FutureProvider.family<DocPage?, int>((ref, id) {
  return ref.watch(pagesRepositoryProvider).getFirstPage(id);
});
