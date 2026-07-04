import 'package:intl/intl.dart' as intl;
import 'package:nepali_utils/nepali_utils.dart';

/// Calendar systems the app can display dates in (persisted as
/// `UserSettings.calendar`).
enum CalendarSystem {
  ad,
  bs;

  static CalendarSystem fromCode(String code) =>
      code == 'bs' ? CalendarSystem.bs : CalendarSystem.ad;

  String get code => this == CalendarSystem.bs ? 'bs' : 'ad';
}

/// The ONE date-formatting service used everywhere a date is shown (home
/// recent list, document details, version history, trash, folder info).
/// AD → "12 Jul 2026"; BS → Devanagari digits + Nepali month, e.g.
/// "२० असार २०८३" (day month year).
///
/// Pure and side-effect-free: it sets the nepali_utils language locally per
/// call rather than mutating global state, so callers never have to think
/// about ordering.
class DateFormatter {
  const DateFormatter(this.calendar);

  final CalendarSystem calendar;

  factory DateFormatter.fromCode(String code) =>
      DateFormatter(CalendarSystem.fromCode(code));

  /// Primary medium date, e.g. AD "12 Jul 2026" / BS "२० असार २०८३".
  String medium(DateTime date) {
    if (calendar == CalendarSystem.bs) {
      final nepali = date.toNepaliDateTime();
      return NepaliDateFormat('d MMMM y', Language.nepali).format(nepali);
    }
    return intl.DateFormat('d MMM y').format(date);
  }

  /// Medium date + time, used where a timestamp matters (version history).
  String mediumWithTime(DateTime date) {
    if (calendar == CalendarSystem.bs) {
      final nepali = date.toNepaliDateTime();
      return NepaliDateFormat('d MMMM y, h:mm a', Language.nepali)
          .format(nepali);
    }
    return intl.DateFormat('d MMM y, h:mm a').format(date);
  }

  /// The AD rendering regardless of the active calendar — used as the small
  /// secondary line under a BS date in detail screens so official-document
  /// workflows always have both.
  String alwaysAd(DateTime date) => intl.DateFormat('d MMM y').format(date);

  /// Whether a secondary AD line should be shown beneath the primary date
  /// (only meaningful when BS is the active calendar).
  bool get showsSecondaryAd => calendar == CalendarSystem.bs;
}
