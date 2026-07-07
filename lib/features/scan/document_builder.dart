import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/database/database.dart';
import '../../core/database/repositories/documents_repository.dart';
import '../../core/database/repositories/pages_repository.dart';
import '../../core/pdf/pdf_builder.dart';
import '../../core/perf/scan_perf.dart';
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

    // The pdf package holds every page's JPEG bytes in memory at once (it
    // only writes to disk on the final save — there's no incremental/
    // streaming write), so an unbounded single PDF risks an OOM on the
    // 2–3 GB Nepal target as page count grows into the hundreds. Split into
    // multiple documents instead — the same practice CamScanner/Adobe Scan
    // use for very long scans.
    final chunks = [
      for (var start = 0; start < pages.length; start += kMaxPagesPerPdf)
        (
          start: start,
          end: (start + kMaxPagesPerPdf).clamp(0, pages.length),
        ),
    ];
    final documentIds = <int>[];
    final now = DateTime.now();

    for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
      final (:start, :end) = chunks[chunkIndex];
      final chunkTitle =
          chunks.length > 1 ? '$title (Part ${chunkIndex + 1})' : title;
      final pdfPath = p.join(docFolder.path, 'document_$chunkIndex.pdf');

      await ScanPerf.timeAsync(
          'save.pdfBuild',
          () => buildPdfFromSources(
                pages: [
                  for (var i = start; i < end; i++)
                    PdfPageSource(
                      path: rendered[i].path,
                      width: rendered[i].width,
                      height: rendered[i].height,
                    ),
                ],
                outputPath: pdfPath,
              ));
      final sizeBytes = await File(pdfPath).length();

      final documentId = await documentsRepository.insertDocument(
        DocumentsCompanion.insert(
          title: chunkTitle,
          localPath: pdfPath,
          fileType: const Value('pdf'),
          pageCount: Value(end - start),
          sizeBytes: Value(sizeBytes),
          folderId: Value(folderId),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      await pagesRepository.insertPages([
        for (var i = start; i < end; i++)
          PagesCompanion.insert(
            documentId: documentId,
            pageOrder: i - start,
            originalImagePath: originalPaths[i],
            localImagePath: rendered[i].path,
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
/// full-resolution decodes don't spike memory on the 2–3 GB Nepal target —
/// each render holds a pure-Dart decode AND OpenCV working Mats at once, so
/// 2 is the safe ceiling (3 produced save-time OOM crashes on-device).
const kMaxRenderConcurrency = 2;

/// Maximum pages in a single PDF document. `package:pdf` holds every page's
/// JPEG bytes in memory until the final `doc.save()` — there's no
/// incremental/streaming write — so an unbounded page count risks OOM on the
/// 2–3 GB Nepal target as a scan grows into the hundreds of pages. Beyond
/// this cap, [saveScanSessionAsDocument] auto-splits into multiple documents
/// ("Title (Part 1)", "Title (Part 2)", ...), the same practice CamScanner/
/// Adobe Scan use for very long scans. 200 pages of ~1-2 MB JPEG each keeps
/// peak resident memory for one document in the ~200-400 MB range.
const kMaxPagesPerPdf = 200;

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
