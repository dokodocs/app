import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_localizations.dart';
import '../scan/scan_capture.dart';
import '../signature/signatures_screen.dart';
import 'document_multi_select_screen.dart';

/// Tools tab: grid of Phase-appropriate utilities. Future tiles are simply
/// not rendered (not shown-and-disabled) until their feature ships.
class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tools = <_Tool>[
      _Tool(
        icon: Icons.picture_as_pdf_outlined,
        label: l10n.toolsCombineToPdf,
        onTap: () => startScanFlow(context, ref),
      ),
      _Tool(
        icon: Icons.perm_media_outlined,
        label: l10n.toolsImportImages,
        onTap: () => startImportFromGalleryFlow(context, ref),
      ),
      _Tool(
        icon: Icons.merge_type,
        label: l10n.toolsMergePdfs,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const DocumentMultiSelectScreen(
              action: MultiSelectAction.merge,
            ),
          ),
        ),
      ),
      _Tool(
        icon: Icons.ios_share,
        label: l10n.toolsShareMultiple,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const DocumentMultiSelectScreen(
              action: MultiSelectAction.share,
            ),
          ),
        ),
      ),
      _Tool(
        icon: Icons.draw_outlined,
        label: l10n.signatureTitle,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SignaturesScreen()),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navTools)),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.1,
        ),
        itemCount: tools.length,
        itemBuilder: (context, index) => _ToolTile(tool: tools[index]),
      ),
    );
  }
}

class _Tool {
  const _Tool({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool});

  final _Tool tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tool.onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(tool.icon, size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              tool.label,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
