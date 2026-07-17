import 'package:drift/drift.dart';

/// Single-row table (row `id` is always 0) holding the user's local profile
/// — display info only, no auth semantics. `avatarPath` points at a copy of
/// the picked image inside the app's documents directory (same pattern as
/// scanned pages), not the original picker cache path, so it survives OS
/// cache eviction.
class UserProfile extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get email => text().withDefault(const Constant(''))();
  TextColumn get mobileNumber => text().withDefault(const Constant(''))();
  TextColumn get avatarPath => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
