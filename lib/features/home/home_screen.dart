import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/date/date_formatter_provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/share/share_helpers.dart';
import '../../core/widgets/empty_state.dart';
import '../editor/editor_screen.dart';
import '../folders/folder_documents_screen.dart';
import '../scan/scan_capture.dart';
import '../tools/document_multi_select_screen.dart';
import 'all_documents_screen.dart';
import 'widgets/document_tile.dart';
import 'widgets/home_tagline.dart';

/// Home: a styled tagline band, a favorite-first folders row, and the ten
/// most-recently-updated documents. The zero-document [EmptyState] still owns
/// the fully-empty case; this richer layout appears once at least one
/// document or user-created folder exists.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _ensuredDefaultFolder = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-create the undeletable, favorited default folder on first run.
    if (!_ensuredDefaultFolder) {
      _ensuredDefaultFolder = true;
      final name = AppLocalizations.of(context).folderDefaultName;
      ref.read(foldersRepositoryProvider).ensureDefaultFolder(name);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final foldersAsync = ref.watch(_foldersProvider);
    final recentAsync = ref.watch(_recentProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        leadingWidth: 60,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: SvgPicture.asset(
            'assets/logo/logo_dokodocs.svg',
            width: 44,
            height: 44,
          ),
        ),
        // Search lives in the app bar itself. Kept compact so the (now
        // larger) logo stays prominent.
        title: SizedBox(
          height: 38,
          child: TextField(
            controller: _searchController,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 18),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 34, minHeight: 34),
              hintText: l10n.homeSearchHint,
              hintStyle: const TextStyle(fontSize: 14),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: l10n.homeShareMultiple,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DocumentMultiSelectScreen(
                  action: MultiSelectAction.share,
                ),
              ),
            ),
          ),
        ],
      ),
      // Soft basket-weave cover behind the whole home body: a single scaled
      // image (not a hard tile) kept faint so content stays readable.
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF7F9F8),
          image: DecorationImage(
            image: AssetImage('assets/background.png'),
            fit: BoxFit.cover,
            opacity: 0.5,
          ),
        ),
        child: SafeArea(
          child: _query.isNotEmpty
              ? _SearchResults(query: _query)
              : _HomeBody(
                  folders: foldersAsync.value ?? const [],
                  recent: recentAsync.value ?? const [],
                  loading: foldersAsync.isLoading || recentAsync.isLoading,
                  onCreateFolder: () => _createFolder(context),
                ),
        ),
      ),
    );
  }

  Future<void> _createFolder(BuildContext context) async {
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

/// The scrolling body once the app is non-empty: tagline (scrolls away),
/// folders section, recent section.
class _HomeBody extends ConsumerWidget {
  const _HomeBody({
    required this.folders,
    required this.recent,
    required this.loading,
    required this.onCreateFolder,
  });

  final List<Folder> folders;
  final List<Document> recent;
  final bool loading;
  final VoidCallback onCreateFolder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final userFolders = folders.where((f) => !f.isDefault).toList();
    // Fully empty: no documents AND no user-created folders — the classic
    // empty state owns this case (the auto default folder alone doesn't
    // count as "content").
    if (recent.isEmpty && userFolders.isEmpty) {
      return EmptyState(
        icon: Icons.document_scanner_outlined,
        title: l10n.homeEmptyTitle,
        body: l10n.homeEmptyBody,
        secondaryLine: Localizations.localeOf(context).languageCode == 'ne'
            ? l10n.homeTaglineSecondary
            : null,
        primaryActionLabel: l10n.homeScanNow,
        onPrimaryAction: () => startScanFlow(context, ref),
        secondaryActionLabel: l10n.homeImportFromGallery,
        onSecondaryAction: () => startImportFromGalleryFlow(context, ref),
      );
    }

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: HomeTagline()),
        SliverToBoxAdapter(
          child: _FoldersSection(folders: folders, onCreateFolder: onCreateFolder),
        ),
        SliverToBoxAdapter(
          child: _SectionHeader(
            title: l10n.homeRecent,
            onSeeAll: recent.isEmpty
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AllDocumentsScreen(),
                      ),
                    ),
          ),
        ),
        if (recent.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                l10n.homeRecentEmptyHint,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(10),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.68,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _RecentTile(document: recent[index]),
                childCount: recent.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _FoldersSection extends ConsumerWidget {
  const _FoldersSection({required this.folders, required this.onCreateFolder});

  final List<Folder> folders;
  final VoidCallback onCreateFolder;

  static const _maxShown = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shown = folders.take(_maxShown).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: l10n.homeFolders,
          onSeeAll: folders.length > _maxShown
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AllDocumentsScreen(foldersView: true),
                    ),
                  )
              : null,
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final folder in shown)
                _FolderChipTile(folder: folder),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.create_new_folder_outlined, size: 16),
                  label: Text(l10n.homeNewFolder),
                  onPressed: onCreateFolder,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FolderChipTile extends ConsumerWidget {
  const _FolderChipTile({required this.folder});

  final Folder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 160),
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FolderDocumentsScreen(folder: folder),
            ),
          ),
          onLongPress: () => _showFolderMenu(context, ref, folder),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  folder.isDefault ? Icons.bookmark : Icons.folder,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => ref
                      .read(foldersRepositoryProvider)
                      .setFavorite(folder.id, !folder.isFavorite),
                  child: Icon(
                    folder.isFavorite ? Icons.star : Icons.star_border,
                    size: 16,
                    color: folder.isFavorite
                        ? Colors.amber
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Long-press folder actions: choose the default save folder, rename, delete.
Future<void> _showFolderMenu(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  final l10n = AppLocalizations.of(context);
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!folder.isDefault)
            ListTile(
              leading: const Icon(Icons.bookmark_added_outlined),
              title: Text(l10n.folderSetAsDefault),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await ref
                    .read(foldersRepositoryProvider)
                    .setDefaultFolder(folder.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.folderSetDefaultDone)),
                  );
                }
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.bookmark),
              title: Text(l10n.folderIsDefault),
              enabled: false,
            ),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: Text(l10n.folderRename),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await _renameFolder(context, ref, folder);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.folderDelete),
            enabled: !folder.isDefault,
            onTap: () async {
              Navigator.of(sheetContext).pop();
              final deleted = await ref
                  .read(foldersRepositoryProvider)
                  .deleteFolder(folder.id);
              if (!deleted && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.folderDefaultCannotDelete)),
                );
              }
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _renameFolder(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController(text: folder.name);
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.folderRename),
      content: TextField(controller: controller, autofocus: true),
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
  );
  if (name != null && name.isNotEmpty) {
    await ref.read(foldersRepositoryProvider).renameFolder(folder.id, name);
  }
}

class _RecentTile extends ConsumerWidget {
  const _RecentTile({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailAsync = ref.watch(_firstPageProvider(document.id));
    final formatter = ref.watch(dateFormatterProvider);
    return DocumentTile(
      document: document,
      thumbnailPath: thumbnailAsync.value?.localImagePath,
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
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (onSeeAll != null)
            TextButton(onPressed: onSeeAll, child: Text(l10n.homeSeeAll)),
        ],
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final resultsAsync = ref.watch(_searchProvider(query));
    return resultsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (documents) {
        if (documents.isEmpty) {
          return EmptyState(
            icon: Icons.search_off_outlined,
            title: l10n.homeSearchNoResultsTitle,
            body: l10n.homeSearchNoResultsBody,
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
          itemBuilder: (context, index) =>
              _RecentTile(document: documents[index]),
        );
      },
    );
  }
}

final _foldersProvider = StreamProvider<List<Folder>>((ref) {
  return ref.watch(foldersRepositoryProvider).watchAll();
});

final _recentProvider = StreamProvider<List<Document>>((ref) {
  return ref.watch(documentsRepositoryProvider).watchRecent();
});

final _searchProvider = StreamProvider.family<List<Document>, String>(
  (ref, query) => ref.watch(documentsRepositoryProvider).watchSearch(query),
);

final _firstPageProvider = FutureProvider.family<DocPage?, int>((ref, id) {
  return ref.watch(pagesRepositoryProvider).getFirstPage(id);
});
