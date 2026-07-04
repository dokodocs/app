import 'package:dokodocs/core/database/database.dart';
import 'package:dokodocs/core/database/repositories/pages_repository.dart';
import 'package:dokodocs/features/scan/providers/scan_session_provider.dart';
// scan_page.dart types flow through the provider; no direct reference needed.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Revert-to-original must ALWAYS restore a page to its full, uncropped,
/// unfiltered original — both live in the scan session and later from the
/// saved document. The immutable original path is never touched (spec §1).
void main() {
  test('session revert restores the full frame (crop/filter/rotation reset)',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(scanSessionProvider.notifier);

    notifier.addPaths(['/tmp/original_0.jpg']);
    notifier.setFilter(0, 'bw');
    notifier.rotate(0);

    var page = container.read(scanSessionProvider).single;
    expect(page.filter, 'bw');
    expect(page.rotation, 90);
    expect(page.isReverted, isFalse);

    notifier.revertToOriginal(0);

    page = container.read(scanSessionProvider).single;
    expect(page.filter, 'original');
    expect(page.rotation, 0);
    expect(page.cropCoordinates, isNull);
    expect(page.isReverted, isTrue);
    // The original capture path is preserved through the revert.
    expect(page.imagePath, '/tmp/original_0.jpg');
  });

  test('saved page reverts to original in the database, original untouched',
      () async {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final pages = PagesRepository(db);

    // A document row to satisfy the FK, then an edited page.
    final documentId = await db.into(db.documents).insert(
          DocumentsCompanion.insert(title: 'Doc', localPath: '/tmp/doc.pdf'),
        );
    await pages.insertPages([
      PagesCompanion.insert(
        documentId: documentId,
        pageOrder: 0,
        originalImagePath: '/tmp/original_0.jpg',
        localImagePath: '/tmp/page_0.jpg',
        filter: const Value('grayscale'),
        rotation: const Value(180),
        cropCoordinates: const Value('[[1,1],[2,1],[2,2],[1,2]]'),
      ),
    ]);

    var page = (await pages.getForDocument(documentId)).single;
    expect(page.filter, 'grayscale');

    await pages.revertToOriginal(page.id);

    page = (await pages.getForDocument(documentId)).single;
    expect(page.filter, 'original');
    expect(page.rotation, 0);
    expect(page.cropCoordinates, isNull);
    expect(page.needsReview, isFalse);
    // The immutable original path survives the revert unchanged.
    expect(page.originalImagePath, '/tmp/original_0.jpg');
  });
}
