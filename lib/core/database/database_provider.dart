import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';
import 'repositories/document_versions_repository.dart';
import 'repositories/documents_repository.dart';
import 'repositories/folders_repository.dart';
import 'repositories/pages_repository.dart';
import 'repositories/signatures_repository.dart';
import 'repositories/user_profile_repository.dart';
import 'repositories/user_settings_repository.dart';

/// App-wide singleton database connection. Overridden in widget tests with
/// an in-memory [AppDatabase.withExecutor] connection.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final documentsRepositoryProvider = Provider<DocumentsRepository>((ref) {
  return DocumentsRepository(ref.watch(databaseProvider));
});

final pagesRepositoryProvider = Provider<PagesRepository>((ref) {
  return PagesRepository(ref.watch(databaseProvider));
});

final foldersRepositoryProvider = Provider<FoldersRepository>((ref) {
  return FoldersRepository(ref.watch(databaseProvider));
});

final userSettingsRepositoryProvider = Provider<UserSettingsRepository>((ref) {
  return UserSettingsRepository(ref.watch(databaseProvider));
});

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return UserProfileRepository(ref.watch(databaseProvider));
});

final userProfileProvider = StreamProvider<UserProfileData>((ref) {
  return ref.watch(userProfileRepositoryProvider).watch();
});

final documentVersionsRepositoryProvider =
    Provider<DocumentVersionsRepository>((ref) {
      return DocumentVersionsRepository(ref.watch(databaseProvider));
    });

final signaturesRepositoryProvider = Provider<SignaturesRepository>((ref) {
  return SignaturesRepository(ref.watch(databaseProvider));
});

final signaturesProvider = StreamProvider<List<Signature>>((ref) {
  return ref.watch(signaturesRepositoryProvider).watchAll();
});
