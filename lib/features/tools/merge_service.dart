import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/database/database.dart';
import '../../core/database/repositories/documents_repository.dart';
import '../../core/database/repositories/pages_repository.dart';
import '../../core/pdf/pdf_builder.dart';

/// Merges the pages of several existing documents (in the given order) into a
/// single new PDF document. The already-processed page previews are copied
/// into a fresh document folder and combined — the source documents are left
/// untouched, and the new document owns its own copies (so deleting a source
/// later can't break the merged file). Returns the new document id.
Future<int> mergeDocumentsToPdf({
  required List<Document> documents,
  required DocumentsRepository documentsRepository,
  required PagesRepository pagesRepository,
  required String title,
  int? folderId,
}) async {
  if (documents.length < 2) {
    throw ArgumentError('Merge needs at least two documents');
  }

  final appDir = await getApplicationDocumentsDirectory();
  final docFolder = Directory(
    p.join(
      appDir.path,
      'documents',
      DateTime.now().microsecondsSinceEpoch.toString(),
    ),
  );
  await docFolder.create(recursive: true);

  final processedPaths = <String>[];
  final pageMeta = <({String original, String processed, String filter, int rotation})>[];
  var order = 0;

  for (final document in documents) {
    final pages = await pagesRepository.getForDocument(document.id);
    for (final page in pages) {
      // Copy the processed preview (falls back to the original if the cached
      // preview is somehow missing) and the immutable original.
      final srcProcessed = await File(page.localImagePath).exists()
          ? page.localImagePath
          : page.originalImagePath;
      final destProcessed = p.join(docFolder.path, 'page_$order.jpg');
      await File(srcProcessed).copy(destProcessed);
      processedPaths.add(destProcessed);

      final destOriginal = p.join(docFolder.path, 'original_$order.jpg');
      final srcOriginal = await File(page.originalImagePath).exists()
          ? page.originalImagePath
          : srcProcessed;
      await File(srcOriginal).copy(destOriginal);

      pageMeta.add((
        original: destOriginal,
        processed: destProcessed,
        filter: page.filter,
        rotation: page.rotation,
      ));
      order++;
    }
  }

  final pdfPath = p.join(docFolder.path, 'document.pdf');
  await buildPdfFromImages(imagePaths: processedPaths, outputPath: pdfPath);
  final sizeBytes = await File(pdfPath).length();
  final now = DateTime.now();

  final documentId = await documentsRepository.insertDocument(
    DocumentsCompanion.insert(
      title: title,
      localPath: pdfPath,
      fileType: const Value('pdf'),
      pageCount: Value(order),
      sizeBytes: Value(sizeBytes),
      folderId: Value(folderId),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );

  await pagesRepository.insertPages([
    for (var i = 0; i < pageMeta.length; i++)
      PagesCompanion.insert(
        documentId: documentId,
        pageOrder: i,
        originalImagePath: pageMeta[i].original,
        localImagePath: pageMeta[i].processed,
        filter: Value(pageMeta[i].filter),
        rotation: Value(pageMeta[i].rotation),
      ),
  ]);

  return documentId;
}
