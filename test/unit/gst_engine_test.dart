import 'package:flutter_test/flutter_test.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/domain/gst/gst_engine.dart';
import 'package:atomid/domain/gst/gst_models.dart';
import 'package:atomid/domain/gst/gst_states.dart';
import 'package:atomid/domain/gst/gst_treatment.dart';

void main() {
  final testDate = DateTime(2026, 1, 1);

  group('GstStates & GSTIN Validation', () {
    test('contains 37 states and UTs with correct codes', () {
      expect(GstStates.allStates.length, 37);
      expect(GstStates.findByCode('33')?.name, 'Tamil Nadu');
      expect(GstStates.findByCode('27')?.name, 'Maharashtra');
      expect(GstStates.findByCode('29')?.name, 'Karnataka');
      expect(GstStates.findByCode('07')?.name, 'Delhi');
      expect(GstStates.findByCode('38')?.name, 'Ladakh');
    });

    test('correctly identifies UTGST jurisdictions', () {
      expect(
        GstStates.isUtgstState('33'),
        false,
      ); // Tamil Nadu has state legislature
      expect(
        GstStates.isUtgstState('07'),
        false,
      ); // Delhi has legislative assembly
      expect(GstStates.isUtgstState('35'), true); // Andaman and Nicobar Islands
      expect(GstStates.isUtgstState('04'), true); // Chandigarh
      expect(GstStates.isUtgstState('31'), true); // Lakshadweep
      expect(GstStates.isUtgstState('38'), true); // Ladakh
    });

    test('validates GSTIN structure and 2-digit state prefix', () {
      expect(GstStates.isValidGstin('33AAAAA0000A1Z5'), true);
      expect(GstStates.isValidGstin('27ABCDE1234F1Z5'), true);
      expect(
        GstStates.isValidGstin('99AAAAA0000A1Z5'),
        false,
      ); // 99 is invalid state code
      expect(
        GstStates.isValidGstin('33AAAA0000A1Z5'),
        false,
      ); // 14 chars (too short)
      expect(GstStates.isValidGstin(''), false);
    });

    test('extractStateCode extracts prefix safely', () {
      expect(GstStates.extractStateCode('33AAAAA0000A1Z5'), '33');
      expect(GstStates.extractStateCode('27ABCDE1234F1Z5'), '27');
      expect(GstStates.extractStateCode('invalid'), null);
    });
  });

  group('tax-inclusive rounding is the shop\'s choice', () {
    // The canonical disagreement: 0.91 at 28% GST + 1% cess. Extracting at
    // 29% gives 0.71 taxable, and from there the two readings cannot both be
    // exact — the marked price and `rate x taxable` differ by a paisa.
    // Neither has been confirmed as the legally required one, so the shop
    // picks. Round-off is off here or the whole rupee would hide the paisa.
    GstCalculationInput inputWith(String policy) => GstCalculationInput(
      transactionDate: testDate,
      sellerState: 'Tamil Nadu',
      sellerStateCode: '33',
      destinationStateCode: '33',
      pricingMode: 'inclusive',
      roundOffEnabled: false,
      inclusiveTaxRounding: policy,
      lines: const [
        GstLineInput(
          productId: '1',
          productName: 'Loose Sweet',
          variantBarcode: 'BAR-1',
          variantSize: 'NA',
          unitPrice: 0.91,
          gstRate: 28.0,
          cessRate: 1.0,
          quantity: 1,
        ),
      ],
    );

    test('SHELF_PRICE bills the marked price exactly', () {
      final line = Gst.compute(inputWith('SHELF_PRICE')).lines.first;

      expect(line.taxableValue, 0.71);
      expect(line.cgstAmount, 0.10);
      expect(line.sgstAmount, 0.09);
      expect(line.cessAmount, 0.01);
      // 0.91 - 0.71. A paisa under 28% of 0.71, which is the trade-off.
      expect(line.totalTax, 0.20);
      expect(line.lineTotal, 0.91);
      expect(Gst.compute(inputWith('SHELF_PRICE')).grandTotal, 0.91);
    });

    test('TAX_RATE bills a paisa over so the tax matches the rate', () {
      final line = Gst.compute(inputWith('TAX_RATE')).lines.first;

      expect(line.taxableValue, 0.71);
      // 28% of 0.71 = 0.1988 -> 0.20, split evenly; 1% cess = 0.0071 -> 0.01.
      expect(line.cgstAmount, 0.10);
      expect(line.sgstAmount, 0.10);
      expect(line.cessAmount, 0.01);
      expect(line.totalTax, 0.21);
      // 0.71 + 0.21. The customer pays a paisa above the shelf price.
      expect(line.lineTotal, 0.92);
      expect(Gst.compute(inputWith('TAX_RATE')).grandTotal, 0.92);
    });

    test('the default is SHELF_PRICE', () {
      // An existing shop that never opens the setting must keep billing the
      // way it billed yesterday.
      expect(SettingsModel().inclusiveTaxRounding, 'SHELF_PRICE');
      expect(
        Gst.compute(
          GstCalculationInput(
            transactionDate: testDate,
            sellerState: 'Tamil Nadu',
            sellerStateCode: '33',
            destinationStateCode: '33',
            pricingMode: 'inclusive',
            roundOffEnabled: false,
            lines: const [
              GstLineInput(
                productId: '1',
                productName: 'Loose Sweet',
                variantBarcode: 'BAR-1',
                variantSize: 'NA',
                unitPrice: 0.91,
                gstRate: 28.0,
                cessRate: 1.0,
                quantity: 1,
              ),
            ],
          ),
        ).grandTotal,
        0.91,
      );
    });

    test('the two policies agree where the paisa falls out evenly', () {
      // 1050 at 5% extracts to exactly 1000 taxable and 50 tax either way.
      // A shop on a plain rate list will never see the setting do anything.
      GstCalculationInput evenCase(String policy) => GstCalculationInput(
        transactionDate: testDate,
        sellerState: 'Tamil Nadu',
        sellerStateCode: '33',
        destinationStateCode: '33',
        pricingMode: 'inclusive',
        roundOffEnabled: false,
        inclusiveTaxRounding: policy,
        lines: const [
          GstLineInput(
            productId: '1',
            productName: 'Cotton Kurti',
            variantBarcode: 'BAR-1',
            variantSize: 'M',
            unitPrice: 1050.0,
            gstRate: 5.0,
            quantity: 1,
          ),
        ],
      );

      final shelf = Gst.compute(evenCase('SHELF_PRICE')).lines.first;
      final derived = Gst.compute(evenCase('TAX_RATE')).lines.first;

      expect(shelf.taxableValue, 1000.0);
      expect(derived.taxableValue, 1000.0);
      expect(shelf.totalTax, 50.0);
      expect(derived.totalTax, 50.0);
      expect(shelf.lineTotal, derived.lineTotal);
    });
  });

  group('Statutory Rate Computations (Intra-State)', () {
    test('Standard 5% dress item with inclusive pricing', () {
      final input = GstCalculationInput(
        transactionDate: testDate,
        sellerState: 'Tamil Nadu',
        sellerStateCode: '33',
        destinationStateCode: '33',
        pricingMode: 'inclusive',
        roundOffEnabled: true,
        lines: const [
          GstLineInput(
            productId: '1',
            productName: 'Cotton Kurti',
            variantBarcode: 'BAR-1',
            variantSize: 'M',
            unitPrice: 1050.0,
            gstRate: 5.0,
            quantity: 1,
          ),
        ],
      );

      final result = Gst.compute(input);
      expect(result.isValid, true);
      expect(result.isInterState, false);
      expect(result.isUtgst, false);

      final line = result.lines.first;
      // Taxable = 1050 / 1.05 = 1000.0
      expect(line.taxableValue, 1000.0);
      expect(line.cgstAmount, 25.0);
      expect(line.sgstAmount, 25.0);
      expect(line.igstAmount, 0.0);
      expect(line.totalTax, 50.0);
      expect(result.grandTotal, 1050.0);
      expect(result.roundOff, 0.0);
    });

    test('Standard 12% dress item with exclusive pricing', () {
      final input = GstCalculationInput(
        transactionDate: testDate,
        sellerState: 'Tamil Nadu',
        sellerStateCode: '33',
        destinationStateCode: '33',
        pricingMode: 'exclusive',
        roundOffEnabled: true,
        lines: const [
          GstLineInput(
            productId: '1',
            productName: 'Silk Saree',
            variantBarcode: 'BAR-1',
            variantSize: 'Free',
            unitPrice: 2000.0,
            gstRate: 12.0,
            quantity: 1,
          ),
        ],
      );

      final result = Gst.compute(input);
      expect(result.isValid, true);
      final line = result.lines.first;
      expect(line.taxableValue, 2000.0);
      expect(line.cgstAmount, 120.0);
      expect(line.sgstAmount, 120.0);
      expect(line.totalTax, 240.0);
      expect(result.grandTotal, 2240.0);
    });

    test('Statutory 0.25%, 3%, 18%, 28% rates', () {
      final rates = [0.25, 3.0, 18.0, 28.0];
      for (final rate in rates) {
        final input = GstCalculationInput(
          transactionDate: testDate,
          sellerState: 'Tamil Nadu',
          sellerStateCode: '33',
          destinationStateCode: '33',
          pricingMode: 'exclusive',
          roundOffEnabled: false,
          lines: [
            GstLineInput(
              productId: '1',
              productName: 'Item $rate',
              variantBarcode: 'BAR-1',
              variantSize: 'M',
              unitPrice: 1000.0,
              gstRate: rate,
              quantity: 1,
            ),
          ],
        );
        final result = Gst.compute(input);
        final line = result.lines.first;
        final expectedTax = 1000.0 * (rate / 100.0);
        expect(line.cgstAmount + line.sgstAmount, closeTo(expectedTax, 0.01));
        expect(line.cgstAmount, closeTo(line.sgstAmount, 0.01));
      }
    });
  });

  group('Inter-State and UTGST Computations', () {
    test('Inter-State sale (Tamil Nadu to Karnataka) applies 100% IGST', () {
      final input = GstCalculationInput(
        transactionDate: testDate,
        sellerState: 'Tamil Nadu',
        sellerStateCode: '33', // TN
        destinationStateCode: '29', // KA
        pricingMode: 'inclusive',
        roundOffEnabled: true,
        lines: const [
          GstLineInput(
            productId: '1',
            productName: 'Designer Lehenga',
            variantBarcode: 'BAR-1',
            variantSize: 'XL',
            unitPrice: 5900.0,
            gstRate: 18.0,
            quantity: 1,
          ),
        ],
      );

      final result = Gst.compute(input);
      expect(result.isInterState, true);
      final line = result.lines.first;
      expect(line.taxableValue, 5000.0);
      expect(line.cgstAmount, 0.0);
      expect(line.sgstAmount, 0.0);
      expect(line.utgstAmount, 0.0);
      expect(line.igstAmount, 900.0);
      expect(result.igstAmount, 900.0);
    });

    test('Intra-UT sale (Chandigarh) applies CGST + UTGST', () {
      final input = GstCalculationInput(
        transactionDate: testDate,
        sellerState: 'Chandigarh',
        sellerStateCode: '04', // Chandigarh
        destinationStateCode: '04', // Chandigarh
        pricingMode: 'inclusive',
        roundOffEnabled: true,
        lines: const [
          GstLineInput(
            productId: '1',
            productName: 'Dress in Chandigarh',
            variantBarcode: 'BAR-1',
            variantSize: 'M',
            unitPrice: 1050.0,
            gstRate: 5.0,
            quantity: 1,
          ),
        ],
      );

      final result = Gst.compute(input);
      expect(result.isInterState, false);
      expect(result.isUtgst, true);
      final line = result.lines.first;
      expect(line.taxableValue, 1000.0);
      expect(line.cgstAmount, 25.0);
      expect(line.sgstAmount, 0.0);
      expect(line.utgstAmount, 25.0);
      expect(line.igstAmount, 0.0);
      expect(result.utgstAmount, 25.0);
    });
  });

  group('Statutory Treatments and Exemptions', () {
    test('EXEMPT, NIL_RATED, NON_GST items have 0 tax regardless of rate', () {
      final treatments = [
        GstTreatment.exempt,
        GstTreatment.nilRated,
        GstTreatment.nonGst,
        GstTreatment.zeroRated,
      ];

      for (final treatment in treatments) {
        final input = GstCalculationInput(
          transactionDate: testDate,
          sellerState: 'Tamil Nadu',
          sellerStateCode: '33',
          destinationStateCode: '33',
          pricingMode: 'inclusive',
          roundOffEnabled: true,
          lines: [
            GstLineInput(
              productId: '1',
              productName: 'Raw Fabric ($treatment)',
              variantBarcode: 'BAR-1',
              variantSize: 'Free',
              unitPrice: 1000.0,
              gstTreatment: treatment,
              gstRate: 18.0, // should be ignored for exempt/nil-rated
              quantity: 1,
            ),
          ],
        );

        final result = Gst.compute(input);
        final line = result.lines.first;
        expect(line.taxableValue, 1000.0);
        expect(line.totalTax, 0.0);
        expect(line.cgstAmount, 0.0);
        expect(line.sgstAmount, 0.0);
      }
    });

    test('UNCONFIGURED treatment raises error', () {
      final input = GstCalculationInput(
        transactionDate: testDate,
        sellerState: 'Tamil Nadu',
        sellerStateCode: '33',
        destinationStateCode: '33',
        pricingMode: 'inclusive',
        lines: const [
          GstLineInput(
            productId: '1',
            productName: 'Unconfigured Item',
            variantBarcode: 'BAR-1',
            variantSize: 'M',
            unitPrice: 500.0,
            gstTreatment: GstTreatment.unconfigured,
            gstRate: null,
            quantity: 1,
          ),
        ],
      );

      final result = Gst.compute(input);
      expect(result.isValid, false);
      expect(
        result.errors.any((e) => e.contains('tax treatment is unconfigured')),
        true,
      );
    });
  });

  group('Compensation Cess & Proportional Discounts', () {
    test('Cess rate is computed accurately on taxable value', () {
      final input = GstCalculationInput(
        transactionDate: testDate,
        sellerState: 'Tamil Nadu',
        sellerStateCode: '33',
        destinationStateCode: '33',
        pricingMode: 'exclusive',
        roundOffEnabled: true,
        lines: const [
          GstLineInput(
            productId: '1',
            productName: 'Luxury Embroidered Gown',
            variantBarcode: 'BAR-1',
            variantSize: 'Free',
            unitPrice: 10000.0,
            gstRate: 28.0,
            cessRate: 12.0,
            quantity: 1,
          ),
        ],
      );

      final result = Gst.compute(input);
      final line = result.lines.first;
      expect(line.taxableValue, 10000.0);
      expect(line.cgstAmount, 1400.0);
      expect(line.sgstAmount, 1400.0);
      expect(line.cessAmount, 1200.0);
      expect(line.totalTax, 4000.0);
      expect(result.grandTotal, 14000.0);
    });

    test('Document discount is proportionally allocated across line items', () {
      final input = GstCalculationInput(
        transactionDate: testDate,
        sellerState: 'Tamil Nadu',
        sellerStateCode: '33',
        destinationStateCode: '33',
        pricingMode: 'exclusive',
        manualDiscountAmount: 300.0, // allocated 1:2 across 1000 and 2000 lines
        lines: const [
          GstLineInput(
            productId: '1',
            productName: 'Dress A',
            variantBarcode: 'BAR-1',
            variantSize: 'M',
            unitPrice: 1000.0,
            gstRate: 5.0,
            quantity: 1,
          ),
          GstLineInput(
            productId: '2',
            productName: 'Dress B',
            variantBarcode: 'BAR-2',
            variantSize: 'L',
            unitPrice: 2000.0,
            gstRate: 12.0,
            quantity: 1,
          ),
        ],
      );

      final result = Gst.compute(input);
      final line1 = result.lines[0];
      final line2 = result.lines[1];

      // Line 1 discount: 100, taxable: 900, 5% tax = 45 (22.50 CGST + 22.50 SGST)
      expect(line1.discountAllocated, 100.0);
      expect(line1.taxableValue, 900.0);
      expect(line1.cgstAmount, 22.50);
      expect(line1.sgstAmount, 22.50);

      // Line 2 discount: 200, taxable: 1800, 12% tax = 216 (108 CGST + 108 SGST)
      expect(line2.discountAllocated, 200.0);
      expect(line2.taxableValue, 1800.0);
      expect(line2.cgstAmount, 108.0);
      expect(line2.sgstAmount, 108.0);

      expect(result.taxableAmount, 2700.0);
      expect(result.grandTotal, 2961.0);
    });

    // Documents the CURRENT rounding policy so a change to it has to be
    // deliberate. CGST takes the rounded half and SGST takes the remainder, so
    // on an odd paisa the two halves differ by 0.01 while their sum stays
    // exactly equal to the tax extracted from the line. The alternative —
    // rounding each half independently so they match — moves the paisa into
    // the document total instead. Which is correct is an accounting policy
    // decision, not a code one; this test only pins what the engine does today.
    test('CGST and SGST may differ by one paisa on an odd split', () {
      final input = GstCalculationInput(
        transactionDate: testDate,
        sellerState: 'Tamil Nadu',
        sellerStateCode: '33',
        destinationStateCode: '33',
        pricingMode: 'inclusive',
        roundOffEnabled: true,
        lines: const [
          GstLineInput(
            productId: '1',
            productName: 'Odd Paisa Dress',
            variantBarcode: 'BAR-1',
            variantSize: 'M',
            unitPrice: 6190.58,
            gstRate: 12.0,
            quantity: 2,
          ),
        ],
      );

      final result = Gst.compute(input);
      final line = result.lines.first;

      expect(line.taxableValue, 11054.61);
      expect(line.cgstAmount, 663.28);
      expect(line.sgstAmount, 663.27);
      // The halves differ, but the sum is exact and the line still balances.
      expect(line.totalTax, 1326.55);
      expect(line.taxableValue + line.totalTax, closeTo(line.lineTotal, 0.001));
      expect(line.lineTotal, 12381.16);
    });

    test(
      'Round-off computes nearest integer and preserves mathematical balance',
      () {
        final input = GstCalculationInput(
          transactionDate: testDate,
          sellerState: 'Tamil Nadu',
          sellerStateCode: '33',
          destinationStateCode: '33',
          pricingMode: 'exclusive',
          roundOffEnabled: true,
          lines: const [
            GstLineInput(
              productId: '1',
              productName: 'Dress',
              variantBarcode: 'BAR-1',
              variantSize: 'M',
              unitPrice: 99.50,
              gstRate: 5.0,
              quantity: 1,
            ),
          ],
        );

        final result = Gst.compute(input);
        // Taxable: 99.50, Tax: 4.98 -> Pre-round total: 104.48 -> Rounded: 104.0 -> RoundOff: -0.48
        expect(result.grandTotal, 104.0);
        expect(result.preRoundTotal, 104.48);
        expect(result.roundOff, -0.48);
        expect(
          result.preRoundTotal + result.roundOff,
          closeTo(result.grandTotal, 0.001),
        );
      },
    );
  });
}
