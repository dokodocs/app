import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/widgets/empty_state.dart';
import 'folder_documents_screen.dart';

/// Folders tab: list/create/rename/delete folders, tap to view its
/// documents. Home's inline folder-chip filter (Stage A) stays as the
/// fast path; this tab is the dedicated management view.
class FoldersScreen extends ConsumerWidget {
  const FoldersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final foldersAsync = ref.watch(_foldersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navFolders),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: l10n.homeNewFolder,
            onPressed: () => _createFolder(context, ref),
          ),
        ],
      ),
      body: foldersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('$error')),
        data: (folders) {
          if (folders.isEmpty) {
            return EmptyState(
              icon: Icons.folder_outlined,
              title: l10n.homeFoldersEmptyTitle,
              body: l10n.homeFoldersEmptyBody,
              primaryActionLabel: l10n.homeNewFolder,
              onPrimaryAction: () => _createFolder(context, ref),
            );
          }
          return ListView.builder(
            itemCount: folders.length,
            itemBuilder: (context, index) {
              final folder = folders[index];
              return ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.name),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => ref
                      .read(foldersRepositoryProvider)
                      .deleteFolder(folder.id),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FolderDocumentsScreen(folder: folder),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createFolder(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final l10n = AppLocalizations.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.homeNewFolder),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.dialogCreate),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(foldersRepositoryProvider).createFolder(name);
    }
  }
}

final _foldersProvider = StreamProvider<List<Folder>>((ref) {
  return ref.watch(foldersRepositoryProvider).watchAll();
});
