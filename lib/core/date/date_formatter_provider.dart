import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_provider.dart';
import 'date_formatter.dart';

/// Live calendar setting ('ad' | 'bs') from the single UserSettings row.
final calendarSettingProvider = StreamProvider<String>((ref) {
  return ref
      .watch(userSettingsRepositoryProvider)
      .watch()
      .map((settings) => settings.calendar);
});

/// The shared [DateFormatter], rebuilt whenever the calendar setting
/// changes — so flipping AD/BS in Settings instantly re-renders every date
/// in the app. Defaults to AD while settings are still loading.
final dateFormatterProvider = Provider<DateFormatter>((ref) {
  final code = ref.watch(calendarSettingProvider).value ?? 'ad';
  return DateFormatter.fromCode(code);
});
