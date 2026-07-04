import 'package:drift/drift.dart';

/// A user-created (or, from Phase 3, rule-based "smart") folder.
///
/// `smartRule` holds a JSON-encoded rule (e.g. "all PDFs tagged Invoice
/// from this month") and is only populated once Phase 3 ships smart
/// folders — the column exists now so the schema doesn't need a
/// Phase-3 migration just to add it.
class Folders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 255)();
  IntColumn get parentId => integer().nullable().references(Folders, #id)();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isSmartFolder =>
      boolean().withDefault(const Constant(false))();
  TextColumn get smartRule => text().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();

  /// The auto-created default folder ("My Documents") is undeletable
  /// (rename still allowed). Flagged rather than special-cased by name so
  /// it survives a rename.
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
}
