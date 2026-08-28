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
      expect(
        PriceTagSize.small.perPage,
        greaterThan(PriceTagSize.medium.perPage),
      );
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

    test('every size carries the logo', () {
      for (final size in PriceTagSize.values) {
        expect(
          size.showLogo,
          isTrue,
          reason: '${size.label} must show the company logo',
        );
        expect(
          size.logoSize,
          greaterThan(0),
          reason: '${size.label} logo must have a drawable size',
        );
      }
    });

    test('the small tag keeps the logo inline to protect the barcode', () {
      expect(PriceTagSize.small.logoInline, isTrue);
      expect(PriceTagSize.small.barcodeHeight, greaterThanOrEqualTo(16));
      // The taller sizes have room for a row of their own.
      expect(PriceTagSize.medium.logoInline, isFalse);
      expect(PriceTagSize.large.logoInline, isFalse);
    });

    test('an inline logo leaves the name room on the same row', () {
      for (final size in PriceTagSize.values.where((s) => s.logoInline)) {
        final cellWidth = PdfPageFormat.a4.width / size.columns;
        expect(
          size.logoSize + size.padding * 3,
          lessThan(cellWidth / 2),
          reason: '${size.label} logo crowds out the product name',
        );
      }
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
