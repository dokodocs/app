import 'dart:io';

import 'package:dokodocs/core/database/database.dart';
import 'package:dokodocs/core/database/repositories/documents_repository.dart';
import 'package:dokodocs/core/database/repositories/pages_repository.dart';
import 'package:dokodocs/features/scan/document_builder.dart';
import 'package:dokodocs/features/scan/models/scan_page.dart';
import 'package:drift/native.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// The native document scanner (ML Kit / VisionKit) can't be driven in this
/// dev environment — it requires a Play Store-signed-in device (see
/// docs/PHASE_1_SUMMARY.md). This test exercises the rest of the "scan"
/// money path — filter -> combine to PDF -> save Document+Pages rows —
/// against synthetic images, as a plain Dart test (no Flutter widget
/// binding), so it isn't a widget test that needs the app to run.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.tempDir);

  final Directory tempDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
}

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late DocumentsRepository documentsRepository;
  late PagesRepository pagesRepository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dokodocs_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    documentsRepository = DocumentsRepository(db);
    pagesRepository = PagesRepository(db);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('scan session (capture -> filter -> PDF -> save) round-trips through the DB', () async {
    // Two synthetic "captured pages" — a document builder doesn't care
    // where the source JPEGs came from (native scanner vs. this test).
    final page1Path = p.join(tempDir.path, 'capture_0.jpg');
    final page2Path = p.join(tempDir.path, 'capture_1.jpg');
    await File(
      page1Path,
    ).writeAsBytes(img.encodeJpg(img.Image(width: 300, height: 400)));
    await File(
      page2Path,
    ).writeAsBytes(img.encodeJpg(img.Image(width: 300, height: 400)));

    final pages = [
      const ScanPage(imagePath: '', filter: 'grayscale').copyWith(
        imagePath: page1Path,
      ),
      const ScanPage(imagePath: '', filter: 'bw').copyWith(
        imagePath: page2Path,
      ),
    ];

    final documentIds = await saveScanSessionAsDocument(
      pages: pages,
      documentsRepository: documentsRepository,
      pagesRepository: pagesRepository,
      title: 'Test scan',
    );
    expect(documentIds, hasLength(1));
    final documentId = documentIds.single;

    final document = await documentsRepository.getById(documentId);
    expect(document.title, 'Test scan');
    expect(document.fileType, 'pdf');
    expect(document.pageCount, 2);
    expect(File(document.localPath).existsSync(), isTrue);
    expect(document.sizeBytes, greaterThan(0));

    final savedPages = await pagesRepository.watchForDocument(documentId).first;
    expect(savedPages, hasLength(2));
    expect(savedPages[0].filter, 'grayscale');
    expect(savedPages[1].filter, 'bw');
    expect(File(savedPages[0].localImagePath).existsSync(), isTrue);
  });

  test('JPEG export creates one image Document per page', () async {
    final page1Path = p.join(tempDir.path, 'capture_0.jpg');
    final page2Path = p.join(tempDir.path, 'capture_1.jpg');
    await File(
      page1Path,
    ).writeAsBytes(img.encodeJpg(img.Image(width: 200, height: 300)));
    await File(
      page2Path,
    ).writeAsBytes(img.encodeJpg(img.Image(width: 200, height: 300)));

    final pages = [
      const ScanPage(imagePath: '').copyWith(imagePath: page1Path),
      const ScanPage(imagePath: '').copyWith(imagePath: page2Path),
    ];

    final documentIds = await saveScanSessionAsDocument(
      pages: pages,
      documentsRepository: documentsRepository,
      pagesRepository: pagesRepository,
      title: 'Receipt',
      format: ExportFormat.jpeg,
      folderId: null,
    );

    expect(documentIds, hasLength(2));
    for (final id in documentIds) {
      final document = await documentsRepository.getById(id);
      expect(document.fileType, 'image');
      expect(document.pageCount, 1);
      expect(File(document.localPath).existsSync(), isTrue);
    }
    final doc1 = await documentsRepository.getById(documentIds[0]);
    final doc2 = await documentsRepository.getById(documentIds[1]);
    expect(doc1.title, 'Receipt (1)');
    expect(doc2.title, 'Receipt (2)');
  });
}
