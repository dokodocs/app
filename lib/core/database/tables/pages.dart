import 'package:drift/drift.dart';

import 'documents.dart';

/// `filter`: 'original' | 'grayscale' | 'bw' | 'magic_color' | 'high_contrast'
/// `cropCoordinates` is a JSON-encoded list of the 4 corner points from the
/// perspective-correction step.
///
/// Data class renamed to `DocPage` via `@DataClassName` — the natural
/// singular of `Pages` is `Page`, which collides with Flutter's own
/// `Page` (routing, exported by `material.dart`).
/// Non-destructive pipeline (v3): `originalImagePath` is the immutable
/// capture — no code path overwrites or deletes it except document
/// deletion/trash purge. `filter`, `cropCoordinates` and `rotation` are
/// render-time metadata applied on export only; `localImagePath` is kept as
/// a cached processed preview/thumbnail (regenerated freely, never the
/// source of truth). `needsReview` flags a page where edge-detection
/// confidence was low and the full frame was kept instead of guessing.
@DataClassName('DocPage')
class Pages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get documentId => integer().references(Documents, #id)();
  IntColumn get pageOrder => integer()();
  TextColumn get originalImagePath => text()();
  TextColumn get localImagePath => text()();
  TextColumn get filter => text().withDefault(const Constant('original'))();
  TextColumn get cropCoordinates => text().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get rotation => integer().withDefault(const Constant(0))();
  BoolColumn get needsReview =>
      boolean().withDefault(const Constant(false))();
}
