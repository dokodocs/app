import 'package:drift/drift.dart';

import 'documents.dart';

/// Version history for a [Document] (spec Section 3). A snapshot stores the
/// page-metadata state as JSON (`snapshotJson`) — NOT duplicate full-res
/// images. Since originals are immutable, the original paths + metadata in
/// the JSON reconstruct any past version. `snapshotPath` is retained from
/// the spec's field list but stays null in this implementation (JSON is the
/// snapshot); it exists so a future "export this version as a file" feature
/// doesn't need a migration.
///
/// `changeLabel` is a short, localizable key describing what changed
/// (e.g. 'pages_reordered', 'filter_changed', 'page_added', 'restored').
///
/// Only the latest 10 versions per document are kept; older ones are pruned.
class DocumentVersions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get documentId => integer().references(Documents, #id)();
  IntColumn get versionNumber => integer()();
  TextColumn get snapshotJson => text()();
  TextColumn get snapshotPath => text().nullable()();
  TextColumn get changeLabel => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}
