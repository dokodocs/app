import 'package:drift/drift.dart';

import '../database.dart';

/// Version history persistence (spec §3). Snapshots are page-metadata JSON,
/// not duplicated images (originals are immutable, so metadata + original
/// paths reconstruct any version). Only the latest [maxVersionsPerDocument]
/// versions per document are kept.
class DocumentVersionsRepository {
  DocumentVersionsRepository(this._db);

  final AppDatabase _db;

  static const maxVersionsPerDocument = 10;

  Stream<List<DocumentVersion>> watchForDocument(int documentId) {
    return (_db.select(_db.documentVersions)
          ..where((v) => v.documentId.equals(documentId))
          ..orderBy([(v) => OrderingTerm.desc(v.versionNumber)]))
        .watch();
  }

  Future<List<DocumentVersion>> getForDocument(int documentId) {
    return (_db.select(_db.documentVersions)
          ..where((v) => v.documentId.equals(documentId))
          ..orderBy([(v) => OrderingTerm.desc(v.versionNumber)]))
        .get();
  }

  Future<DocumentVersion> getById(int id) {
    return (_db.select(
      _db.documentVersions,
    )..where((v) => v.id.equals(id))).getSingle();
  }

  /// Inserts a new snapshot with the next sequential version number, then
  /// prunes anything older than the latest [maxVersionsPerDocument].
  Future<void> insertSnapshot({
    required int documentId,
    required String snapshotJson,
    String? changeLabel,
  }) async {
    final existing = await getForDocument(documentId);
    final nextNumber =
        existing.isEmpty ? 1 : existing.first.versionNumber + 1;

    await _db.into(_db.documentVersions).insert(
          DocumentVersionsCompanion.insert(
            documentId: documentId,
            versionNumber: nextNumber,
            snapshotJson: snapshotJson,
            changeLabel: Value(changeLabel),
          ),
        );

    await _pruneOldest(documentId);
  }

  Future<void> _pruneOldest(int documentId) async {
    final all = await getForDocument(documentId); // desc by versionNumber
    if (all.length <= maxVersionsPerDocument) return;
    final toDelete = all.skip(maxVersionsPerDocument).map((v) => v.id).toList();
    await (_db.delete(_db.documentVersions)
          ..where((v) => v.id.isIn(toDelete)))
        .go();
  }

  Future<void> deleteForDocument(int documentId) {
    return (_db.delete(_db.documentVersions)
          ..where((v) => v.documentId.equals(documentId)))
        .go();
  }
}
