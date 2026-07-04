import 'dart:io';

import 'package:drift/drift.dart';

import '../database.dart';

/// CRUD for saved signatures. Signatures are guest-friendly (no owning user
/// required) — see the Signatures table definition.
class SignaturesRepository {
  SignaturesRepository(this._db);

  final AppDatabase _db;

  Stream<List<Signature>> watchAll() {
    return (_db.select(_db.signatures)
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
        .watch();
  }

  Future<List<Signature>> getAll() {
    return (_db.select(_db.signatures)
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
        .get();
  }

  Future<int> add(String imagePath) {
    return _db.into(_db.signatures).insert(
          SignaturesCompanion.insert(imagePath: imagePath),
        );
  }

  /// Deletes the row and its backing image file (best-effort).
  Future<void> delete(Signature signature) async {
    await (_db.delete(_db.signatures)
          ..where((s) => s.id.equals(signature.id)))
        .go();
    final file = File(signature.imagePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
