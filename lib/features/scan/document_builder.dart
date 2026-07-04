import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/database/database.dart';
import '../../core/database/repositories/documents_repository.dart';
import '../../core/database/repositories/pages_repository.dart';
import '../../core/pdf/pdf_builder.dart';
import '../../core/render/page_renderer.dart';
import '../../core/render/watermark_asset.dart';
import 'models/scan_page.dart';

/// User-chosen save format for a scan session.
enum ExportFormat { pdf, jpeg, png }

/// Turns a reviewed [ScanPage] session into one or more saved [Document]s.
///
/// NON-DESTRUCTIVE (spec §1, absolute rule): every page's untouched capture
/// is persisted as `original_$i.jpg` and stored on `DocPage.originalImagePath`;
/// filter/rotation/crop/watermark are applied only to a *copy* rendered via
/// [renderPage] and stored as the cached preview (`localImagePath`). No
/// original is ever overwritten. Any page can later be reverted to its
/// original by re-rendering from `originalImagePath` with default metadata.
///
/// [applyWatermark]/[watermarkPosition] are resolved by the caller from the
/// user's scan-default settings + whether this was a batch capture.
///
/// Returns the id(s) of the created document(s) — a single-element list for
/// PDF, one element per page for JPEG/PNG.
Future<List<int>> saveScanSessionAsDocument({
  required List<ScanPage> pages,
  required DocumentsRepository documentsRepository,
  required PagesRepository pagesRepository,
  required String title,
  ExportFormat format = ExportFormat.pdf,
  int? folderId,
  bool applyWatermark = false,
  String watermarkPosition = 'bottom_right',
}) async {
  if (pages.isEmpty) {
    throw ArgumentError('Cannot save a scan session with zero pages');
  }

  final watermarkLogo = applyWatermark ? await loadWatermarkLogo() : null;
  final appDir = await getApplicationDocumentsDirectory();
  final docFolder = Directory(
    p.join(
      appDir.path,
      'documents',
      DateTime.now().microsecondsSinceEpoch.toString(),
    ),
  );
  await docFolder.create(recursive: true);

  if (format == ExportFormat.pdf) {
    final originalPaths = <String>[];
    final processedPaths = <String>[];
    for (var i = 0; i < pages.length; i++) {
      // Persist the immutable original (a copy of the capture), then render
      // the processed preview from it — never the other way round.
      final originalPath = p.join(docFolder.path, 'original_$i.jpg');
      await File(pages[i].imagePath).copy(originalPath);
      originalPaths.add(originalPath);

      final destPath = p.join(docFolder.path, 'page_$i.jpg');
      processedPaths.add(
        await renderPage(
          originalPath: originalPath,
          destPath: destPath,
          filter: pages[i].filter,
          rotationDegrees: pages[i].rotation,
          watermark: applyWatermark,
          watermarkPosition: watermarkPosition,
          watermarkLogo: watermarkLogo,
        ),
      );
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
        pageCount: Value(pages.length),
        sizeBytes: Value(sizeBytes),
        folderId: Value(folderId),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    await pagesRepository.insertPages([
      for (var i = 0; i < pages.length; i++)
        PagesCompanion.insert(
          documentId: documentId,
          pageOrder: i,
          originalImagePath: originalPaths[i],
          localImagePath: processedPaths[i],
          filter: Value(pages[i].filter),
          rotation: Value(pages[i].rotation),
          cropCoordinates: Value(pages[i].cropCoordinates),
          needsReview: Value(pages[i].needsReview),
        ),
    ]);

    return [documentId];
  }

  // JPEG/PNG: each page becomes its own image Document, since there's no
  // single-file container for "N images" the way a PDF provides one.
  final ext = format == ExportFormat.png ? 'png' : 'jpg';
  final outputFormat = format == ExportFormat.png ? 'png' : 'jpg';
  final documentIds = <int>[];
  final now = DateTime.now();

  for (var i = 0; i < pages.length; i++) {
    final originalPath = p.join(docFolder.path, 'original_$i.jpg');
    await File(pages[i].imagePath).copy(originalPath);

    final destPath = p.join(docFolder.path, 'page_$i.$ext');
    await renderPage(
      originalPath: originalPath,
      destPath: destPath,
      filter: pages[i].filter,
      rotationDegrees: pages[i].rotation,
      watermark: applyWatermark,
      watermarkPosition: watermarkPosition,
      watermarkLogo: watermarkLogo,
      outputFormat: outputFormat,
    );
    final sizeBytes = await File(destPath).length();
    final pageTitle = pages.length > 1 ? '$title (${i + 1})' : title;

    final documentId = await documentsRepository.insertDocument(
      DocumentsCompanion.insert(
        title: pageTitle,
        localPath: destPath,
        fileType: const Value('image'),
        pageCount: const Value(1),
        sizeBytes: Value(sizeBytes),
        folderId: Value(folderId),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    await pagesRepository.insertPages([
      PagesCompanion.insert(
        documentId: documentId,
        pageOrder: 0,
        originalImagePath: originalPath,
        localImagePath: destPath,
        filter: Value(pages[i].filter),
        rotation: Value(pages[i].rotation),
        cropCoordinates: Value(pages[i].cropCoordinates),
        needsReview: Value(pages[i].needsReview),
      ),
    ]);

    documentIds.add(documentId);
  }

  return documentIds;
}
