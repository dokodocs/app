import 'package:drift/drift.dart';

import 'documents.dart';
import 'tags.dart';

/// Many-to-many join between [Documents] and [Tags] — the spec's
/// `Document.tags[]` is modeled relationally rather than as a JSON/array
/// column so it stays queryable and indexable in SQLite.
class DocumentTags extends Table {
  IntColumn get documentId => integer().references(Documents, #id)();
  IntColumn get tagId => integer().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {documentId, tagId};
}
