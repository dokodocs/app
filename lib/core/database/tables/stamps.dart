import 'package:drift/drift.dart';

/// `userId` nullable — see [Signatures] for the same Guest-mode rationale.
class Stamps extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get userId => text().nullable()();
  TextColumn get imagePath => text()();
  TextColumn get label => text()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}
