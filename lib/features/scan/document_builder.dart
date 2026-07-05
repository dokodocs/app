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
    // Copy the immutable originals first (cheap byte copies, kept for the
    // revert/version feature), then render pages with BOUNDED parallelism —
    // each renderPage runs in its own isolate, so a small concurrency cap
    // (kMaxRenderConcurrency) turns the old one-at-a-time save into a parallel
    // one without blowing the 2–3 GB RAM budget. Output order is preserved.
    final originalPaths = [
      for (var i = 0; i < pages.length; i++)
        p.join(docFolder.path, 'original_$i.jpg'),
    ];
    for (var i = 0; i < pages.length; i++) {
      await File(pages[i].imagePath).copy(originalPaths[i]);
    }

    final rendered = await _mapBounded<int, RenderedPage>(
      List.generate(pages.length, (i) => i),
      (i) => renderPage(
        originalPath: originalPaths[i],
        destPath: p.join(docFolder.path, 'page_$i.jpg'),
        filter: pages[i].filter,
        rotationDegrees: pages[i].rotation,
        watermark: applyWatermark,
        watermarkPosition: watermarkPosition,
        watermarkLogo: watermarkLogo,
      ),
    );

    final pdfPath = p.join(docFolder.path, 'document.pdf');
    await buildPdfFromSources(
      pages: [
        for (final r in rendered)
          PdfPageSource(path: r.path, width: r.width, height: r.height),
      ],
      outputPath: pdfPath,
    );
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
          localImagePath: rendered[i].path,
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

  final originalPaths = [
    for (var i = 0; i < pages.length; i++)
      p.join(docFolder.path, 'original_$i.jpg'),
  ];
  for (var i = 0; i < pages.length; i++) {
    await File(pages[i].imagePath).copy(originalPaths[i]);
  }

  // Render pages in bounded parallel (see PDF path), then do DB inserts
  // sequentially to keep document ids/order deterministic.
  final rendered = await _mapBounded<int, RenderedPage>(
    List.generate(pages.length, (i) => i),
    (i) => renderPage(
      originalPath: originalPaths[i],
      destPath: p.join(docFolder.path, 'page_$i.$ext'),
      filter: pages[i].filter,
      rotationDegrees: pages[i].rotation,
      watermark: applyWatermark,
      watermarkPosition: watermarkPosition,
      watermarkLogo: watermarkLogo,
      outputFormat: outputFormat,
    ),
  );

  for (var i = 0; i < pages.length; i++) {
    final destPath = rendered[i].path;
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
        originalImagePath: originalPaths[i],
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

/// Maximum number of page-render isolates to run at once. Kept small so N
/// full-resolution decodes don't spike memory on the 2–3 GB Nepal target.
const kMaxRenderConcurrency = 3;

/// Maps [items] through async [fn] with at most [kMaxRenderConcurrency]
/// in-flight at a time, preserving input order in the result. Used to turn the
/// previously one-at-a-time page render into a bounded-parallel one.
Future<List<R>> _mapBounded<T, R>(
  List<T> items,
  Future<R> Function(T item) fn,
) async {
  final results = List<R?>.filled(items.length, null);
  for (var start = 0; start < items.length; start += kMaxRenderConcurrency) {
    final end = (start + kMaxRenderConcurrency).clamp(0, items.length);
    await Future.wait([
      for (var i = start; i < end; i++)
        fn(items[i]).then((r) => results[i] = r),
    ]);
  }
  return results.cast<R>();
}
