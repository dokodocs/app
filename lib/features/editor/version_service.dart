import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../core/database/database.dart';
import '../../core/database/repositories/document_versions_repository.dart';
import '../../core/database/repositories/documents_repository.dart';
import '../../core/database/repositories/pages_repository.dart';
import '../../core/pdf/pdf_builder.dart';
import '../../core/render/document_export.dart';

/// Serializes a document's current page metadata to the JSON stored in a
/// `DocumentVersion.snapshotJson`. Captures only metadata + the immutable
/// original paths — never image bytes.
String encodePageSnapshot(List<DocPage> pages) {
  return jsonEncode({
    'pages': [
      for (final page in pages)
        {
          'originalImagePath': page.originalImagePath,
          'filter': page.filter,
          'rotation': page.rotation,
          'cropCoordinates': page.cropCoordinates,
          'needsReview': page.needsReview,
        },
    ],
  });
}

class _SnapshotPage {
  _SnapshotPage(this.originalImagePath, this.filter, this.rotation,
      this.cropCoordinates, this.needsReview);
  final String originalImagePath;
  final String filter;
  final int rotation;
  final String? cropCoordinates;
  final bool needsReview;
}

/// Returns just the original image paths from a snapshot, in page order —
/// used to render a read-only preview of a past version.
List<String> decodeSnapshotOriginals(String json) {
  return [for (final page in _decodePageSnapshot(json)) page.originalImagePath];
}

List<_SnapshotPage> _decodePageSnapshot(String json) {
  final map = jsonDecode(json) as Map<String, dynamic>;
  final pages = (map['pages'] as List).cast<Map<String, dynamic>>();
  return [
    for (final page in pages)
      _SnapshotPage(
        page['originalImagePath'] as String,
        page['filter'] as String? ?? 'original',
        page['rotation'] as int? ?? 0,
        page['cropCoordinates'] as String?,
        page['needsReview'] as bool? ?? false,
      ),
  ];
}

/// Captures a version snapshot of the document's current page state.
/// Called on every material edit (add/remove/reorder page, crop/filter/
/// rotation commit, revert, watermark change).
Future<void> captureVersion({
  required int documentId,
  required PagesRepository pagesRepository,
  required DocumentVersionsRepository versionsRepository,
  String? changeLabel,
}) async {
  final pages = await pagesRepository.getForDocument(documentId);
  if (pages.isEmpty) return;
  await versionsRepository.insertSnapshot(
    documentId: documentId,
    snapshotJson: encodePageSnapshot(pages),
    changeLabel: changeLabel,
  );
}

/// Restores [version] as the document's current state. First snapshots the
/// CURRENT state (so the restore is itself undoable via history), then
/// rebuilds the page rows + processed previews + PDF from the version's
/// metadata and immutable originals.
Future<void> restoreVersion({
  required Document document,
  required DocumentVersion version,
  required PagesRepository pagesRepository,
  required DocumentVersionsRepository versionsRepository,
  required DocumentsRepository documentsRepository,
  required UserSetting settings,
}) async {
  // Undo point: preserve the pre-restore state as a new version.
  await captureVersion(
    documentId: document.id,
    pagesRepository: pagesRepository,
    versionsRepository: versionsRepository,
    changeLabel: 'restored',
  );

  final snapshot = _decodePageSnapshot(version.snapshotJson);

  // Replace current page rows with the snapshot's (originals are untouched
  // on disk; we only rewrite metadata rows).
  await pagesRepository.deleteForDocument(document.id);
  final companions = <PagesCompanion>[
    for (var i = 0; i < snapshot.length; i++)
      PagesCompanion.insert(
        documentId: document.id,
        pageOrder: i,
        originalImagePath: snapshot[i].originalImagePath,
        // Preview is regenerated just below; seed with the original path.
        localImagePath: snapshot[i].originalImagePath,
        filter: Value(snapshot[i].filter),
        rotation: Value(snapshot[i].rotation),
        cropCoordinates: Value(snapshot[i].cropCoordinates),
        needsReview: Value(snapshot[i].needsReview),
      ),
  ];
  await pagesRepository.insertPages(companions);

  // Re-render previews to real preview paths, then rebuild the PDF.
  final pages = await pagesRepository.getForDocument(document.id);
  final docDir = p.dirname(document.localPath);
  for (var i = 0; i < pages.length; i++) {
    await pagesRepository.updatePreviewPath(
      pages[i].id,
      p.join(docDir, 'page_$i.jpg'),
    );
  }
  final refreshed = await pagesRepository.getForDocument(document.id);
  final watermark = resolveWatermark(settings, pageCount: refreshed.length);
  final processed = await renderProcessedPages(
    pages: refreshed,
    watermark: watermark,
    watermarkPosition: settings.watermarkPosition,
  );
  if (document.fileType == 'pdf') {
    await buildPdfFromImages(
      imagePaths: processed,
      outputPath: document.localPath,
    );
  }
  await documentsRepository.updateDocument(
    document.id,
    DocumentsCompanion(
      pageCount: Value(refreshed.length),
      updatedAt: Value(DateTime.now()),
    ),
  );
}
