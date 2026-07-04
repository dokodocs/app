import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/document_tags.dart';
import 'tables/document_versions.dart';
import 'tables/documents.dart';
import 'tables/folders.dart';
import 'tables/pages.dart';
import 'tables/signatures.dart';
import 'tables/stamps.dart';
import 'tables/tags.dart';
import 'tables/user_settings.dart';

part 'database.g.dart';

/// Local-first source of truth (spec Section 3). Phase 0 wires this up
/// with local tables only — no network/sync code exists yet; `Document
/// .syncStatus` and `UserSettings.server*` are already in the schema so
/// Phase 2 doesn't need a breaking migration to introduce sync.
@DriftDatabase(
  tables: [
    Documents,
    Pages,
    Folders,
    Tags,
    DocumentTags,
    Signatures,
    Stamps,
    UserSettings,
    DocumentVersions,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v2: onboarding flow (Phase 1) needs a persisted "seen it" flag.
        await m.addColumn(userSettings, userSettings.onboardingComplete);
      }
      if (from < 3) {
        // v3: non-destructive pipeline + favorites + version history +
        // dual calendar + watermark defaults.
        // Pages: add the immutable original + review flag. originalImagePath
        // is NOT NULL, so add it via raw SQL with a transient default ('')
        // (drift's addColumn can't emit a default, which SQLite requires to
        // add a NOT NULL column to a populated table), then backfill it from
        // the current localImagePath so existing pages become their own
        // "original" (non-destructive: nothing is overwritten or deleted).
        await customStatement(
          'ALTER TABLE pages ADD COLUMN original_image_path TEXT NOT NULL '
          "DEFAULT ''",
        );
        await customStatement(
          'UPDATE pages SET original_image_path = local_image_path',
        );
        await m.addColumn(pages, pages.needsReview);

        // Folders: favorite + undeletable-default flags.
        await m.addColumn(folders, folders.isFavorite);
        await m.addColumn(folders, folders.isDefault);

        // UserSettings: calendar + watermark defaults.
        await m.addColumn(userSettings, userSettings.calendar);
        await m.addColumn(userSettings, userSettings.watermarkOnBatch);
        await m.addColumn(userSettings, userSettings.watermarkOnSingle);
        await m.addColumn(userSettings, userSettings.watermarkPosition);

        // Version history table.
        await m.createTable(documentVersions);
      }
    },
  );
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'dokodocs_db');
}
