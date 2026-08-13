/// How large a printed price tag should be.
///
/// A tag's dimensions come from how many fit across and down a sheet, so the
/// grid divides the page exactly and leaves no wasted margin. Typography is
/// specified per size rather than scaled from one base, because a barcode that
/// has been shrunk by a multiplier stops scanning long before it stops looking
/// reasonable on screen.
enum PriceTagSize {
  /// Roughly 42 x 30 mm on A4. Shelf-edge labels, where the barcode and the
  /// price are all that matter — the logo is dropped to keep the barcode
  /// large enough for a scanner.
  small(
    label: 'Small',
    columns: 5,
    rows: 10,
    padding: 2,
    showLogo: false,
    logoSize: 0,
    nameFontSize: 6.5,
    codeFontSize: 5,
    sizeFontSize: 6.5,
    priceFontSize: 8,
    barcodeWidth: 95,
    barcodeHeight: 16,
    barcodeTextSize: 4,
  ),

  /// Roughly 52 x 49 mm on A4. The long-standing default.
  medium(
    label: 'Medium',
    columns: 4,
    rows: 6,
    padding: 4,
    showLogo: true,
    logoSize: 24,
    nameFontSize: 10,
    codeFontSize: 8,
    sizeFontSize: 10,
    priceFontSize: 12,
    barcodeWidth: 100,
    barcodeHeight: 30,
    barcodeTextSize: 6,
  ),

  /// Roughly 70 x 74 mm on A4. Display and promotional tags.
  large(
    label: 'Large',
    columns: 3,
    rows: 4,
    padding: 6,
    showLogo: true,
    logoSize: 34,
    nameFontSize: 14,
    codeFontSize: 11,
    sizeFontSize: 14,
    priceFontSize: 17,
    barcodeWidth: 150,
    barcodeHeight: 42,
    barcodeTextSize: 8,
  );

  const PriceTagSize({
    required this.label,
    required this.columns,
    required this.rows,
    required this.padding,
    required this.showLogo,
    required this.logoSize,
    required this.nameFontSize,
    required this.codeFontSize,
    required this.sizeFontSize,
    required this.priceFontSize,
    required this.barcodeWidth,
    required this.barcodeHeight,
    required this.barcodeTextSize,
  });

  final String label;
  final int columns;
  final int rows;
  final double padding;
  final bool showLogo;
  final double logoSize;
  final double nameFontSize;
  final double codeFontSize;
  final double sizeFontSize;
  final double priceFontSize;
  final double barcodeWidth;
  final double barcodeHeight;
  final double barcodeTextSize;

  /// Tags per printed sheet.
  int get perPage => columns * rows;

  /// What the picker shows under each option.
  String get description => '$perPage per sheet';
}
