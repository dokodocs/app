import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/date/date_formatter_provider.dart';
import '../../core/l10n/app_localizations.dart';
import 'version_service.dart';

/// Lists a document's saved versions (latest 10), each with a formatted date
/// (per the calendar setting) and a change label. Tapping previews a version;
/// "Restore this version" makes it current (restoring itself creates a new
/// version, so it's undoable).
class VersionHistoryScreen extends ConsumerWidget {
  const VersionHistoryScreen({super.key, required this.documentId});

  final int documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final versionsAsync = ref.watch(_versionsProvider(documentId));
    final formatter = ref.watch(dateFormatterProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.versionHistoryTitle)),
      body: versionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (versions) {
          if (versions.isEmpty) {
            return Center(child: Text(l10n.versionHistoryEmpty));
          }
          return ListView.separated(
            itemCount: versions.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final version = versions[index];
              return ListTile(
                leading: CircleAvatar(child: Text('${version.versionNumber}')),
                title: Text(formatter.mediumWithTime(version.createdAt)),
                subtitle: Text(_changeLabel(l10n, version.changeLabel)),
                onTap: () => _preview(context, ref, version),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _preview(
    BuildContext context,
    WidgetRef ref,
    DocumentVersion version,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _VersionPreviewScreen(
          documentId: documentId,
          version: version,
        ),
      ),
    );
  }

  static String _changeLabel(AppLocalizations l10n, String? label) {
    switch (label) {
      case 'pages_reordered':
        return l10n.versionChangeReordered;
      case 'filter_changed':
        return l10n.versionChangeFilter;
      case 'page_added':
        return l10n.versionChangePageAdded;
      case 'page_removed':
        return l10n.versionChangePageRemoved;
      case 'reverted':
        return l10n.versionChangeReverted;
      case 'restored':
        return l10n.versionChangeRestored;
      case 'watermark_changed':
        return l10n.versionChangeWatermark;
      default:
        return l10n.versionChangeEdited;
    }
  }
}

class _VersionPreviewScreen extends ConsumerWidget {
  const _VersionPreviewScreen({
    required this.documentId,
    required this.version,
  });

  final int documentId;
  final DocumentVersion version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final paths = decodeSnapshotOriginals(version.snapshotJson);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.versionPreviewTitle)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: paths.length,
              itemBuilder: (context, index) {
                final file = File(paths[index]);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: file.existsSync()
                      ? Image.file(file, fit: BoxFit.contain)
                      : const SizedBox.shrink(),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                icon: const Icon(Icons.restore),
                label: Text(l10n.versionRestore),
                onPressed: () => _restore(context, ref),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final document =
        await ref.read(documentsRepositoryProvider).getById(documentId);
    final settings = await ref.read(userSettingsRepositoryProvider).get();
    await restoreVersion(
      document: document,
      version: version,
      pagesRepository: ref.read(pagesRepositoryProvider),
      versionsRepository: ref.read(documentVersionsRepositoryProvider),
      documentsRepository: ref.read(documentsRepositoryProvider),
      settings: settings,
    );
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.versionRestoredSnack)));
  }
}

final _versionsProvider =
    StreamProvider.family<List<DocumentVersion>, int>((ref, id) {
      return ref.watch(documentVersionsRepositoryProvider).watchForDocument(id);
    });
