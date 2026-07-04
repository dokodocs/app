import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';

/// The single `UserSettings` row, watched reactively — used by `main.dart`
/// to drive `locale`/`themeMode` live, and by the Settings screen to
/// display/edit values.
final userSettingsProvider = StreamProvider<UserSetting>((ref) {
  return ref.watch(userSettingsRepositoryProvider).watch();
});
