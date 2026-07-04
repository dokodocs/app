import 'package:drift/drift.dart';

import '../database.dart';

/// `UserSettings` is a single-row table (row `id` is always 0). This
/// repository guarantees that row exists before anything reads/watches it.
class UserSettingsRepository {
  UserSettingsRepository(this._db) {
    _ensureRow();
  }

  final AppDatabase _db;

  Future<void> _ensureRow() {
    return _db
        .into(_db.userSettings)
        .insert(const UserSettingsCompanion(id: Value(0)), mode: InsertMode.insertOrIgnore);
  }

  Stream<UserSetting> watch() {
    return (_db.select(
      _db.userSettings,
    )..where((s) => s.id.equals(0))).watchSingle();
  }

  Future<UserSetting> get() {
    return (_db.select(
      _db.userSettings,
    )..where((s) => s.id.equals(0))).getSingle();
  }

  Future<void> update(UserSettingsCompanion entry) {
    return (_db.update(
      _db.userSettings,
    )..where((s) => s.id.equals(0))).write(entry);
  }

  Future<void> setOnboardingComplete(bool value) {
    return update(UserSettingsCompanion(onboardingComplete: Value(value)));
  }

  Future<void> setLanguage(String languageCode) {
    return update(UserSettingsCompanion(language: Value(languageCode)));
  }

  Future<void> setTheme(String theme) {
    return update(UserSettingsCompanion(theme: Value(theme)));
  }
}
