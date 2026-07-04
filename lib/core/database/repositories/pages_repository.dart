import 'package:drift/drift.dart';

import '../database.dart';

class PagesRepository {
  PagesRepository(this._db);

  final AppDatabase _db;

  Future<DocPage?> getFirstPage(int documentId) {
    return (_db.select(_db.pages)
          ..where((p) => p.documentId.equals(documentId))
          ..orderBy([(p) => OrderingTerm.asc(p.pageOrder)])
          ..limit(1))
        .getSingleOrNull();
  }

  Stream<List<DocPage>> watchForDocument(int documentId) {
    return (_db.select(_db.pages)
          ..where((p) => p.documentId.equals(documentId))
          ..orderBy([(p) => OrderingTerm.asc(p.pageOrder)]))
        .watch();
  }

  Future<void> insertPages(List<PagesCompanion> pages) {
    return _db.batch((batch) => batch.insertAll(_db.pages, pages));
  }

  /// Updates only the cached processed-preview path (`localImagePath`).
  /// The immutable `originalImagePath` is never changed here.
  Future<void> updatePreviewPath(int pageId, String previewPath) {
    return (_db.update(_db.pages)..where((p) => p.id.equals(pageId))).write(
      PagesCompanion(localImagePath: Value(previewPath)),
    );
  }

  Future<void> updatePageOrder(int pageId, int order) {
    return (_db.update(_db.pages)..where((p) => p.id.equals(pageId))).write(
      PagesCompanion(pageOrder: Value(order)),
    );
  }

  Future<void> updateFilter(int pageId, String filter) {
    return (_db.update(_db.pages)..where((p) => p.id.equals(pageId))).write(
      PagesCompanion(filter: Value(filter)),
    );
  }

  Future<List<DocPage>> getForDocument(int documentId) {
    return (_db.select(_db.pages)
          ..where((p) => p.documentId.equals(documentId))
          ..orderBy([(p) => OrderingTerm.asc(p.pageOrder)]))
        .get();
  }

  /// Commits a render-time metadata edit (filter/rotation/crop). Never
  /// touches `originalImagePath` — the immutable capture is untouchable.
  Future<void> updateMetadata(
    int pageId, {
    String? filter,
    int? rotation,
    String? cropCoordinates,
    bool clearCrop = false,
    bool? needsReview,
  }) {
    return (_db.update(_db.pages)..where((p) => p.id.equals(pageId))).write(
      PagesCompanion(
        filter: filter == null ? const Value.absent() : Value(filter),
        rotation: rotation == null ? const Value.absent() : Value(rotation),
        cropCoordinates: clearCrop
            ? const Value(null)
            : (cropCoordinates == null
                  ? const Value.absent()
                  : Value(cropCoordinates)),
        needsReview:
            needsReview == null ? const Value.absent() : Value(needsReview),
      ),
    );
  }

  /// Reverts a page to its original capture: filter -> 'original',
  /// rotation -> 0, crop cleared, review flag cleared. The processed
  /// preview is re-rendered by the caller from `originalImagePath`.
  Future<void> revertToOriginal(int pageId) {
    return (_db.update(_db.pages)..where((p) => p.id.equals(pageId))).write(
      const PagesCompanion(
        filter: Value('original'),
        rotation: Value(0),
        cropCoordinates: Value(null),
        needsReview: Value(false),
      ),
    );
  }

  Future<void> deletePage(int pageId) {
    return (_db.delete(_db.pages)..where((p) => p.id.equals(pageId))).go();
  }

  Future<void> deleteForDocument(int documentId) {
    return (_db.delete(
      _db.pages,
    )..where((p) => p.documentId.equals(documentId))).go();
  }
}
