import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/domain/date_window.dart';

/// The expense list built "this week" as
/// `date.isAfter(startOfWeek.subtract(const Duration(days: 1)))`, where
/// `startOfWeek` kept the current time of day. Two mistakes that did not
/// cancel: the window opened a day early, and it never closed.
void main() {
  // A Wednesday, mid-afternoon. Monday of this week is the 19th.
  final now = DateTime(2026, 8, 26, 15, 30);

  group('This Week', () {
    final week = DateWindow.forTimeframe('This Week', now)!;

    test('starts at midnight on Monday, not at this time on Monday', () {
      expect(week.from, DateTime(2026, 8, 24));
      expect(
        week.contains(DateTime(2026, 8, 24, 7, 0)),
        isTrue,
        reason: 'Monday morning is in the week that began that morning',
      );
    });

    test('excludes the Sunday before', () {
      expect(
        week.contains(DateTime(2026, 8, 23, 18, 0)),
        isFalse,
        reason: 'the old window counted Sunday evening toward the new week',
      );
    });

    test('includes today up to midnight but not tomorrow', () {
      expect(week.contains(DateTime(2026, 8, 26, 23, 59, 59, 999)), isTrue);
      expect(week.contains(DateTime(2026, 8, 27)), isFalse);
    });

    test('excludes a future-dated record', () {
      // The old expense filter had no upper bound at all, so a rent payment
      // entered ahead of time counted toward the current week.
      expect(week.contains(DateTime(2026, 9, 30)), isFalse);
    });
  });

  group('Today', () {
    final today = DateWindow.forTimeframe('Today', now)!;

    test('covers exactly the calendar day', () {
      expect(today.from, DateTime(2026, 8, 26));
      expect(today.until, DateTime(2026, 8, 27));
      expect(today.contains(DateTime(2026, 8, 26)), isTrue);
      expect(today.contains(DateTime(2026, 8, 25, 23, 59, 59)), isFalse);
      expect(today.contains(DateTime(2026, 8, 27)), isFalse);
    });
  });

  group('This Month', () {
    final month = DateWindow.forTimeframe('This Month', now)!;

    test('runs from the first of the month to the end of today', () {
      expect(month.from, DateTime(2026, 8));
      expect(month.contains(DateTime(2026, 8, 1)), isTrue);
      expect(month.contains(DateTime(2026, 7, 31, 23, 59)), isFalse);
    });

    test('is month-to-date, matching the sales dashboard', () {
      expect(month.contains(DateTime(2026, 8, 31)), isFalse);
    });
  });

  test('an unknown or All Time label means no window', () {
    expect(DateWindow.forTimeframe('All Time', now), isNull);
    expect(DateWindow.forTimeframe('Anything Else', now), isNull);
  });

  test('a Monday reports a week that starts that same day', () {
    final monday = DateTime(2026, 8, 24, 9, 0);
    expect(DateWindow.forTimeframe('This Week', monday)!.from,
        DateTime(2026, 8, 24));
  });

  test('a Sunday reports a week that started six days earlier', () {
    final sunday = DateTime(2026, 8, 30, 20, 0);
    expect(DateWindow.forTimeframe('This Week', sunday)!.from,
        DateTime(2026, 8, 24));
  });
}
