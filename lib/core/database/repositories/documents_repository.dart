import 'package:drift/drift.dart';

import '../database.dart';

/// Plain Dart wrapper around `AppDatabase.documents` — no drift codegen
/// needed beyond the table itself, since drift's fluent query builder is
/// already generated on `AppDatabase`.
class DocumentsRepository {
  DocumentsRepository(this._db);

  final AppDatabase _db;

  Stream<List<Document>> watchActive({int? folderId}) {
    final query = _db.select(_db.documents)
      ..where((d) => d.isTrashed.equals(false) & d.isArchived.equals(false))
      ..orderBy([(d) => OrderingTerm.desc(d.updatedAt)]);
    if (folderId != null) {
      query.where((d) => d.folderId.equals(folderId));
    }
    return query.watch();
  }

  Stream<int> watchActiveCount() {
    final query = _db.selectOnly(_db.documents)
      ..addColumns([_db.documents.id.count()])
      ..where(
        _db.documents.isTrashed.equals(false) &
            _db.documents.isArchived.equals(false),
      );
    return query
        .map((row) => row.read(_db.documents.id.count()) ?? 0)
        .watchSingle();
  }

  Stream<List<Document>> watchFavorites() {
    return (_db.select(_db.documents)
          ..where(
            (d) =>
                d.isFavorite.equals(true) &
                d.isTrashed.equals(false) &
                d.isArchived.equals(false),
          )
          ..orderBy([(d) => OrderingTerm.desc(d.updatedAt)]))
        .watch();
  }

  /// The most-recently-updated active documents (Home "Recent" section).
  Stream<List<Document>> watchRecent({int limit = 10}) {
    return (_db.select(_db.documents)
          ..where(
            (d) => d.isTrashed.equals(false) & d.isArchived.equals(false),
          )
          ..orderBy([(d) => OrderingTerm.desc(d.updatedAt)])
          ..limit(limit))
        .watch();
  }

  Stream<List<Document>> watchTrashed() {
    return (_db.select(_db.documents)
          ..where((d) => d.isTrashed.equals(true))
          ..orderBy([(d) => OrderingTerm.desc(d.trashedAt)]))
        .watch();
  }

  Stream<List<Document>> watchSearch(String query) {
    final pattern = '%$query%';
    return (_db.select(_db.documents)
          ..where(
            (d) =>
                d.title.like(pattern) &
                d.isTrashed.equals(false) &
                d.isArchived.equals(false),
          )
          ..orderBy([(d) => OrderingTerm.desc(d.updatedAt)]))
        .watch();
  }

  Future<Document> getById(int id) {
    return (_db.select(
      _db.documents,
    )..where((d) => d.id.equals(id))).getSingle();
  }

  Future<int> insertDocument(DocumentsCompanion entry) {
    return _db.into(_db.documents).insert(entry);
  }

  Future<void> updateDocument(int id, DocumentsCompanion entry) {
    return (_db.update(
      _db.documents,
    )..where((d) => d.id.equals(id))).write(entry);
  }

  Future<void> setFavorite(int id, bool value) {
    return updateDocument(id, DocumentsCompanion(isFavorite: Value(value)));
  }

  Future<void> moveToTrash(int id) {
    return updateDocument(
      id,
      DocumentsCompanion(
        isTrashed: const Value(true),
        trashedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> restoreFromTrash(int id) {
    return updateDocument(
      id,
      const DocumentsCompanion(
        isTrashed: Value(false),
        trashedAt: Value(null),
      ),
    );
  }

  Future<void> permanentlyDelete(int id) {
    return (_db.delete(_db.documents)..where((d) => d.id.equals(id))).go();
  }
}
