import 'package:drift/drift.dart';

import 'folders.dart';

/// `fileType`: 'pdf' | 'image'
/// `syncStatus`: 'none' | 'pending' | 'synced' | 'failed' | 'conflict'
///
/// `syncStatus`/`remoteUrl` are unused until Phase 2 (the sync engine) but
/// are part of the schema now per spec Section 3, so no migration is needed
/// just to add sync support later.
/// `ocrText` stays null until Phase 4 (OCR).
class Documents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 255)();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  IntColumn get folderId => integer().nullable().references(Folders, #id)();
  IntColumn get pageCount => integer().withDefault(const Constant(0))();
  TextColumn get localPath => text()();
  TextColumn get fileType => text().withDefault(const Constant('pdf'))();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  TextColumn get syncStatus => text().withDefault(const Constant('none'))();
  TextColumn get remoteUrl => text().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isTrashed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get trashedAt => dateTime().nullable()();
  TextColumn get colorLabel => text().nullable()();
  BoolColumn get passwordProtected =>
      boolean().withDefault(const Constant(false))();
  TextColumn get ocrText => text().nullable()();
}
