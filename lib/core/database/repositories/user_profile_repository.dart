import 'package:drift/drift.dart';

import '../database.dart';

/// `UserProfile` is a single-row table (row `id` is always 0). This
/// repository guarantees that row exists before anything reads/watches it.
class UserProfileRepository {
  UserProfileRepository(this._db) {
    _ensureRow();
  }

  final AppDatabase _db;

  Future<void> _ensureRow() {
    return _db
        .into(_db.userProfile)
        .insert(const UserProfileCompanion(id: Value(0)), mode: InsertMode.insertOrIgnore);
  }

  Stream<UserProfileData> watch() {
    return (_db.select(
      _db.userProfile,
    )..where((p) => p.id.equals(0))).watchSingle();
  }

  Future<UserProfileData> get() {
    return (_db.select(
      _db.userProfile,
    )..where((p) => p.id.equals(0))).getSingle();
  }

  Future<void> update(UserProfileCompanion entry) {
    return (_db.update(
      _db.userProfile,
    )..where((p) => p.id.equals(0))).write(entry);
  }
}
