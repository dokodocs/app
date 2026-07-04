import 'package:drift/drift.dart';

/// Single-row table (row `id` is always 0) holding the on-device settings
/// described in spec Section 3. `serverConfig` is flattened into
/// `server*` columns rather than stored as nested JSON, since SQLite has
/// no native object type and flat columns stay queryable.
///
/// `storageMode`: 'local' | 'gdrive' | 'onedrive' | 'dropbox' | 'webdav' |
///   'ftp' | 'customApi' | 'lanServer' — only 'local' is reachable until
///   Phase 2 ships the other connectors.
/// `language`: 'en' | 'hi' | 'ne'
class UserSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();
  TextColumn get authProvider => text().nullable()();
  TextColumn get storageMode => text().withDefault(const Constant('local'))();
  TextColumn get serverType => text().nullable()();
  TextColumn get serverUrl => text().nullable()();
  TextColumn get serverProtocol => text().nullable()();
  TextColumn get serverAuthToken => text().nullable()();
  IntColumn get serverPort => integer().nullable()();
  TextColumn get defaultFileNaming =>
      text().withDefault(const Constant('scan_{date}_{n}'))();
  TextColumn get defaultQuality =>
      text().withDefault(const Constant('medium'))();
  TextColumn get defaultColorMode =>
      text().withDefault(const Constant('original'))();
  TextColumn get theme => text().withDefault(const Constant('system'))();
  TextColumn get language => text().withDefault(const Constant('en'))();
  BoolColumn get appLockEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get biometricEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get secureFolderEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get onboardingComplete =>
      boolean().withDefault(const Constant(false))();

  /// `calendar`: 'ad' (Gregorian, default) | 'bs' (Bikram Sambat / Nepali).
  /// Drives the shared DateFormatter everywhere a date is displayed.
  TextColumn get calendar => text().withDefault(const Constant('ad'))();

  /// Batch-scan watermark defaults (spec §2). `watermarkOnBatch` on by
  /// default, single-page scans off by default (governed at render time,
  /// see WatermarkPosition). `watermarkPosition`: 'bottom_right' (default) |
  /// 'top_right'.
  BoolColumn get watermarkOnBatch =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get watermarkOnSingle =>
      boolean().withDefault(const Constant(false))();
  TextColumn get watermarkPosition =>
      text().withDefault(const Constant('bottom_right'))();

  @override
  Set<Column> get primaryKey => {id};
}
