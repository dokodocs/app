import 'package:drift/drift.dart';

import '../database.dart';

class FoldersRepository {
  FoldersRepository(this._db);

  final AppDatabase _db;

  /// Ordered for the Home folders section: the undeletable default folder
  /// first, then favorites, then the rest alphabetically.
  Stream<List<Folder>> watchAll() {
    return (_db.select(_db.folders)
          ..orderBy([
            (f) => OrderingTerm.desc(f.isDefault),
            (f) => OrderingTerm.desc(f.isFavorite),
            (f) => OrderingTerm.asc(f.name),
          ]))
        .watch();
  }

  Future<int> createFolder(String name) {
    return _db.into(_db.folders).insert(FoldersCompanion.insert(name: name));
  }

  Future<void> renameFolder(int id, String name) {
    return (_db.update(
      _db.folders,
    )..where((f) => f.id.equals(id))).write(FoldersCompanion(name: Value(name)));
  }

  Future<void> setFavorite(int id, bool value) {
    return (_db.update(_db.folders)..where((f) => f.id.equals(id)))
        .write(FoldersCompanion(isFavorite: Value(value)));
  }

  /// The single default *save* folder: new scans/imports that aren't started
  /// from within a specific folder land here. It's the `isDefault` folder
  /// (also favorited + pinned first + undeletable).
  Future<Folder?> getDefaultFolder() {
    return (_db.select(_db.folders)
          ..where((f) => f.isDefault.equals(true))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Lets the user CHOOSE which favourite folder is the default save folder.
  /// Moves the single `isDefault` flag to [id] (clearing it everywhere else)
  /// and stars it, all in one transaction so exactly one default exists.
  Future<void> setDefaultFolder(int id) {
    return _db.transaction(() async {
      await _db
          .update(_db.folders)
          .write(const FoldersCompanion(isDefault: Value(false)));
      await (_db.update(_db.folders)..where((f) => f.id.equals(id))).write(
        const FoldersCompanion(
          isDefault: Value(true),
          isFavorite: Value(true),
        ),
      );
    });
  }

  /// Deletes a folder unless it's the undeletable default. Returns true if
  /// deleted, false if it was the protected default folder.
  Future<bool> deleteFolder(int id) async {
    final folder =
        await (_db.select(_db.folders)..where((f) => f.id.equals(id)))
            .getSingleOrNull();
    if (folder == null || folder.isDefault) return false;
    await (_db.delete(_db.folders)..where((f) => f.id.equals(id))).go();
    return true;
  }

  /// Ensures the auto-created default folder ("My Documents") exists — a
  /// favorited, pinned-first, undeletable folder created on first run.
  /// [name] is the localized display name (rename allowed later).
  Future<void> ensureDefaultFolder(String name) async {
    final existing =
        await (_db.select(_db.folders)..where((f) => f.isDefault.equals(true)))
            .getSingleOrNull();
    if (existing != null) return;
    await _db.into(_db.folders).insert(
          FoldersCompanion.insert(
            name: name,
            isFavorite: const Value(true),
            isDefault: const Value(true),
          ),
        );
  }
}
