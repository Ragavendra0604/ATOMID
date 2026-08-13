import 'package:intl/intl.dart';

/// Central formatting helpers.
///
/// Every user-visible number and date goes through here so the app never
/// prints a raw `double` (`₹3899.7000000000003`) or invents a new date layout.
class Fmt {
  const Fmt._();

  static final NumberFormat _decimal = NumberFormat('#,##0.00');
  static final NumberFormat _whole = NumberFormat('#,##0');
  static final DateFormat _date = DateFormat('dd MMM yyyy');
  static final DateFormat _dateTime = DateFormat('dd MMM yyyy · hh:mm a');
  static final DateFormat _compactDate = DateFormat('yyyy-MM-dd');

  /// Money with the store's currency symbol, always two decimals.
  ///
  /// A negative amount reads `-₹45.50`, not `₹-45.50`.
  static String money(num value, String symbol) =>
      _signed(value, symbol, _decimal);

  /// Money rounded to whole units — for dense dashboard tiles only.
  static String moneyCompact(num value, String symbol) =>
      _signed(value, symbol, _whole);

  static String _signed(num value, String symbol, NumberFormat format) {
    final negative = value < 0;
    return '${negative ? '-' : ''}$symbol${format.format(value.abs())}';
  }

  /// Bare two-decimal amount with no symbol (table cells, PDF columns).
  static String amount(num value) => _decimal.format(value);

  /// Integer quantities and counts.
  static String count(num value) => _whole.format(value);

  /// Loyalty points — whole numbers, never fractional in the UI.
  static String points(num value) => '${_whole.format(value)} pts';

  static String date(DateTime value) => _date.format(value);

  static String dateTime(DateTime value) => _dateTime.format(value);

  /// Sortable form, used for document numbers and file names.
  static String compactDate(DateTime value) => _compactDate.format(value);

  /// Rounds to 2 decimals so accumulated float error never reaches a ledger.
  static double round2(double value) => (value * 100).roundToDouble() / 100;
}
