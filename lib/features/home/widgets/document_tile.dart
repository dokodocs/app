import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/database/database.dart';
import '../../../core/l10n/app_localizations.dart';

class DocumentTile extends StatelessWidget {
  const DocumentTile({
    super.key,
    required this.document,
    required this.thumbnailPath,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onTrash,
    this.onShare,
    this.dateText,
  });

  final Document document;
  final String? thumbnailPath;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTrash;

  /// Optional per-tile share action. When null the Share menu item is hidden.
  final VoidCallback? onShare;

  /// Pre-formatted date (via the shared DateFormatter, calendar-aware). When
  /// null the tile falls back to a plain AD date.
  final String? dateText;

  /// Soft light-green border drawn around every document tile and its
  /// scanned-image preview.
  static const _borderGreen = Color(0xFF9CCC8E);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _borderGreen, width: 1.2),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The scan preview shown a touch smaller (inset + its own
                  // light-green frame) rather than bleeding to the tile edges.
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _borderGreen, width: 1),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: thumbnailPath != null
                          ? Image.file(File(thumbnailPath!), fit: BoxFit.cover)
                          : Icon(
                              Icons.description_outlined,
                              size: 26,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                    ),
                  ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: PopupMenuButton<String>(
                      iconSize: 16,
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) {
                        if (value == 'favorite') onToggleFavorite();
                        if (value == 'trash') onTrash();
                        if (value == 'share') onShare?.call();
                      },
                      itemBuilder: (context) => [
                        if (onShare != null)
                          PopupMenuItem(
                            value: 'share',
                            child: Text(AppLocalizations.of(context).commonShare),
                          ),
                        PopupMenuItem(
                          value: 'favorite',
                          child: Text(
                            document.isFavorite ? 'Unfavorite' : 'Favorite',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'trash',
                          child: Text('Move to trash'),
                        ),
                      ],
                    ),
                  ),
                  if (document.isFavorite)
                    const Positioned(
                      top: 3,
                      left: 3,
                      child: Icon(Icons.star, size: 13, color: Colors.amber),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    '${document.pageCount} · ${dateText ?? DateFormat.yMMMd().format(document.updatedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
