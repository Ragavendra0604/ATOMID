import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:atomid/domain/price_tag_size.dart';

void main() {
  group('PriceTagSize', () {
    test('per-page count matches the grid', () {
      for (final size in PriceTagSize.values) {
        expect(
          size.perPage,
          size.columns * size.rows,
          reason: '${size.label} must report its own grid',
        );
      }
    });

    test('a bigger tag means fewer on a sheet', () {
      expect(PriceTagSize.small.perPage, greaterThan(PriceTagSize.medium.perPage));
      expect(
        PriceTagSize.medium.perPage,
        greaterThan(PriceTagSize.large.perPage),
      );
    });

    // The generator lays tags out with Wrap, so a tag whose contents are wider
    // than its cell silently pushes the row to fewer columns than intended and
    // the sheet stops tiling.
    test('barcode and padding fit the cell on every supported page', () {
      for (final format in [PdfPageFormat.a4, PdfPageFormat.letter]) {
        for (final size in PriceTagSize.values) {
          final cellWidth = format.width / size.columns;
          expect(
            size.barcodeWidth + size.padding * 2,
            lessThanOrEqualTo(cellWidth),
            reason:
                '${size.label} overflows a ${format.width.round()}pt-wide page',
          );
        }
      }
    });

    test('the small tag drops the logo to protect the barcode', () {
      expect(PriceTagSize.small.showLogo, isFalse);
      expect(PriceTagSize.small.barcodeHeight, greaterThanOrEqualTo(16));
    });

    test('medium still matches the long-standing default layout', () {
      // Existing sheets must keep printing exactly as before.
      const medium = PriceTagSize.medium;
      expect(medium.columns, 4);
      expect(medium.rows, 6);
      expect(medium.perPage, 24);
      expect(medium.nameFontSize, 10);
      expect(medium.priceFontSize, 12);
      expect(medium.barcodeWidth, 100);
      expect(medium.barcodeHeight, 30);
    });
  });
}
