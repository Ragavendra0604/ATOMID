/// The span of time a named timeframe covers, as a half-open window.
///
/// Three screens were each deriving "this week" for themselves and only the
/// sales one had it right. `getSalesByDateRange` carries a comment about the
/// window it replaced — `isAfter(start - 1 day)`, which quietly pulled in an
/// extra day — and the expense list still had exactly that shape, so a
/// Sunday-evening expense counted toward the week that had not started yet.
///
/// Half-open (`[from, until)`) rather than an inclusive end, because a
/// closing bound of "end of day" has no exact representation: 23:59:59 drops
/// the final second, and 23:59:59.999 drops a millisecond. The first instant
/// of the next day is exact.
class DateWindow {
  /// First instant included.
  final DateTime from;

  /// First instant *excluded*.
  final DateTime until;

  const DateWindow({required this.from, required this.until});

  bool contains(DateTime value) =>
      !value.isBefore(from) && value.isBefore(until);

  /// Midnight starting [value]'s calendar day, in local time.
  ///
  /// Business dates are what the shop reads on a report, so they are local.
  /// Sync timestamps are a separate concern.
  static DateTime startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// The window a timeframe label covers, or null for "everything".
  ///
  /// Every window ends at the start of tomorrow, so a record dated in the
  /// future is not counted toward a period that has not reached it. The
  /// month figure is therefore month-to-date, which is what the sales
  /// dashboard already showed.
  static DateWindow? forTimeframe(String timeframe, DateTime now) {
    final today = startOfDay(now);
    final tomorrow = today.add(const Duration(days: 1));

    switch (timeframe) {
      case 'Today':
        return DateWindow(from: today, until: tomorrow);
      case 'This Week':
        // weekday is 1 (Monday) through 7 (Sunday), so this lands on the
        // Monday of the current week — built from `today`, not `now`, or the
        // window would start at this time of day on Monday and miss that
        // morning's records.
        return DateWindow(
          from: today.subtract(Duration(days: now.weekday - 1)),
          until: tomorrow,
        );
      case 'This Month':
        return DateWindow(from: DateTime(now.year, now.month), until: tomorrow);
      default:
        return null;
    }
  }
}
