import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/share/share_helpers.dart';
import '../editor/editor_screen.dart';
import 'merge_service.dart';

/// What the multi-select screen does with the chosen documents.
enum MultiSelectAction { merge, share }

/// A checkbox list of every active document used by the Tools tab to either
/// merge several documents into one PDF or share several at once. Selection
/// order is preserved so merge output follows the order the user tapped.
class DocumentMultiSelectScreen extends ConsumerStatefulWidget {
  const DocumentMultiSelectScreen({super.key, required this.action});

  final MultiSelectAction action;

  @override
  ConsumerState<DocumentMultiSelectScreen> createState() =>
      _DocumentMultiSelectScreenState();
}

class _DocumentMultiSelectScreenState
    extends ConsumerState<DocumentMultiSelectScreen> {
  final _selected = <int>[]; // document ids, in tap order
  bool _working = false;

  bool get _isMerge => widget.action == MultiSelectAction.merge;

  void _toggle(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _confirm(List<Document> documents) async {
    final l10n = AppLocalizations.of(context);
    final min = _isMerge ? 2 : 1;
    if (_selected.length < min) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isMerge ? l10n.selectAtLeastTwo : l10n.selectAtLeastOne),
        ),
      );
      return;
    }

    final byId = {for (final d in documents) d.id: d};
    final chosen = [for (final id in _selected) byId[id]!];

    if (!_isMerge) {
      await shareDocumentFiles([for (final d in chosen) d.localPath]);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() => _working = true);
    try {
      final id = await mergeDocumentsToPdf(
        documents: chosen,
        documentsRepository: ref.read(documentsRepositoryProvider),
        pagesRepository: ref.read(pagesRepositoryProvider),
        title: 'dokodocs_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.mergeDoneSnack)));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => EditorScreen(documentId: id)),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final documentsAsync = ref.watch(_activeDocumentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isMerge ? l10n.mergeSelectTitle : l10n.shareSelectTitle),
      ),
      body: Column(
        children: [
          if (_working) const LinearProgressIndicator(),
          Expanded(
            child: documentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('$error')),
              data: (documents) => ListView.builder(
                itemCount: documents.length,
                itemBuilder: (context, index) {
                  final document = documents[index];
                  final order = _selected.indexOf(document.id);
                  return CheckboxListTile(
                    value: order != -1,
                    onChanged: _working ? null : (_) => _toggle(document.id),
                    title: Text(
                      document.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${document.pageCount} · ${document.fileType}'),
                    secondary: order != -1
                        ? CircleAvatar(radius: 12, child: Text('${order + 1}'))
                        : null,
                  );
                },
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text(l10n.selectedCount(_selected.length)),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _working
                        ? null
                        : () => _confirm(documentsAsync.value ?? const []),
                    icon: Icon(_isMerge ? Icons.merge_type : Icons.ios_share),
                    label: Text(_isMerge ? l10n.mergeAction : l10n.commonShare),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final _activeDocumentsProvider = StreamProvider<List<Document>>((ref) {
  return ref.watch(documentsRepositoryProvider).watchActive();
});
