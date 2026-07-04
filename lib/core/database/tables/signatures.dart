import 'package:drift/drift.dart';

/// `userId` is nullable to support Guest mode (spec 1.2 — local-first with
/// no account required); a signature captured as a guest simply has no
/// owning user until/unless the device later signs in.
class Signatures extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get userId => text().nullable()();
  TextColumn get imagePath => text()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}
