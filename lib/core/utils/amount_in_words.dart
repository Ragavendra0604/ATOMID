/// Renders a money amount as English words in the Indian numbering system
/// (thousand / lakh / crore), for the "Amount in Words" line a tax invoice
/// carries.
///
/// Display only. The figure printed alongside is always the authority.
class AmountInWords {
  const AmountInWords._();

  static const List<String> _units = [
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen',
  ];

  static const List<String> _tens = [
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety',
  ];

  /// e.g. 4838.00 -> 'Four Thousand Eight Hundred Thirty-Eight Rupees Only'.
  ///
  /// Paise are included when there are any, and the amount is rounded to two
  /// places first so the words match the printed figure exactly.
  static String rupees(double amount) {
    final negative = amount < 0;
    // Add epsilon to ensure exact halves (.005) round up instead of truncating
    // due to IEEE 754 precision representation.
    final fixedStr = (amount.abs() + 1e-9).toStringAsFixed(2);
    final parts = fixedStr.split('.');
    final whole = int.parse(parts[0]);
    final paise = int.parse(parts[1]);

    final buffer = StringBuffer();
    if (negative) buffer.write('Minus ');
    buffer.write(whole == 0 ? 'Zero' : _words(whole));
    buffer.write(whole == 1 ? ' Rupee' : ' Rupees');
    if (paise > 0) {
      buffer.write(' and ');
      buffer.write(_words(paise));
      buffer.write(' Paise');
    }
    buffer.write(' Only');
    return buffer.toString();
  }

  static String _words(int value) {
    if (value == 0) return 'Zero';
    final parts = <String>[];
    var rest = value;

    final crore = rest ~/ 10000000;
    rest %= 10000000;
    final lakh = rest ~/ 100000;
    rest %= 100000;
    final thousand = rest ~/ 1000;
    rest %= 1000;
    final hundred = rest ~/ 100;
    rest %= 100;

    if (crore > 0) parts.add('${_words(crore)} Crore');
    if (lakh > 0) parts.add('${_below100(lakh)} Lakh');
    if (thousand > 0) parts.add('${_below100(thousand)} Thousand');
    if (hundred > 0) parts.add('${_below100(hundred)} Hundred');
    if (rest > 0) parts.add(_below100(rest));
    return parts.join(' ');
  }

  static String _below100(int value) {
    if (value < 20) return _units[value];
    final ten = _tens[value ~/ 10];
    final unit = value % 10;
    return unit == 0 ? ten : '$ten-${_units[unit]}';
  }
}
