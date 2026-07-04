import 'package:dokodocs/core/date/date_formatter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nepali_utils/nepali_utils.dart';

/// Dual-calendar formatting (spec §4). AD is the default; BS renders with
/// Devanagari digits and Nepali month names. The known conversion is checked
/// against the nepali_utils package itself, per the acceptance criteria.
void main() {
  final date = DateTime(2026, 7, 4);

  test('nepali_utils converts 2026-07-04 AD to 2083-03-21 BS', () {
    final bs = date.toNepaliDateTime();
    expect(bs.year, 2083);
    expect(bs.month, 3); // Ashadh / असार
    expect(bs.day, 21);
  });

  test('AD is the default and formats in Gregorian', () {
    const formatter = DateFormatter(CalendarSystem.ad);
    expect(formatter.medium(date), '4 Jul 2026');
    expect(formatter.showsSecondaryAd, isFalse);
  });

  test('BS formats with Devanagari digits and Nepali month', () {
    const formatter = DateFormatter(CalendarSystem.bs);
    final formatted = formatter.medium(date);
    // Package output for this date: "२१ आषाढ २०८३".
    expect(formatted, contains('२०८३'));
    expect(formatted, contains('आषाढ'));
    expect(formatted, contains('२१'));
    // No ASCII digits leaked through.
    expect(RegExp(r'[0-9]').hasMatch(formatted), isFalse);
  });

  test('BS mode always exposes an AD secondary line', () {
    const formatter = DateFormatter(CalendarSystem.bs);
    expect(formatter.showsSecondaryAd, isTrue);
    expect(formatter.alwaysAd(date), '4 Jul 2026');
  });

  test('fromCode maps setting strings to calendars', () {
    expect(DateFormatter.fromCode('bs').calendar, CalendarSystem.bs);
    expect(DateFormatter.fromCode('ad').calendar, CalendarSystem.ad);
    expect(DateFormatter.fromCode('unknown').calendar, CalendarSystem.ad);
  });
}
