import 'package:dokodocs/core/database/database.dart';
import 'package:dokodocs/core/database/repositories/document_versions_repository.dart';
import 'package:dokodocs/core/database/repositories/documents_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Version history keeps only the latest 10 versions per document (spec §3).
void main() {
  late AppDatabase db;
  late DocumentVersionsRepository versions;
  late DocumentsRepository documents;
  late int documentId;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    versions = DocumentVersionsRepository(db);
    documents = DocumentsRepository(db);
    documentId = await documents.insertDocument(
      DocumentsCompanion.insert(title: 'Doc', localPath: '/tmp/doc.pdf'),
    );
  });

  tearDown(() async => db.close());

  test('prunes to the latest 10 versions, keeping the newest', () async {
    for (var i = 1; i <= 13; i++) {
      await versions.insertSnapshot(
        documentId: documentId,
        snapshotJson: '{"pages":[],"v":$i}',
      );
    }

    final kept = await versions.getForDocument(documentId); // desc
    expect(kept, hasLength(10));
    // Newest first: version numbers 13 down to 4; 1–3 pruned.
    expect(kept.first.versionNumber, 13);
    expect(kept.last.versionNumber, 4);
    expect(
      kept.every((v) => v.versionNumber >= 4),
      isTrue,
    );
  });

  test('version numbers increment sequentially', () async {
    await versions.insertSnapshot(
      documentId: documentId,
      snapshotJson: '{}',
    );
    await versions.insertSnapshot(
      documentId: documentId,
      snapshotJson: '{}',
    );
    final all = await versions.getForDocument(documentId);
    expect(all.map((v) => v.versionNumber).toList(), [2, 1]);
  });
}
