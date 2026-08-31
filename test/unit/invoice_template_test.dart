import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/core/services/export_service.dart';
import 'package:atomid/core/utils/amount_in_words.dart';
import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/invoice_settings_model.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/domain/gst_rate_summary.dart';
import 'package:atomid/domain/invoice_template.dart';

/// A three-rate Tamil Nadu counter sale, priced exclusive of tax:
///   5%  on 1,000.00 -> CGST 25.00  + SGST 25.00
///   12% on 2,000.00 -> CGST 120.00 + SGST 120.00
///   18% on 1,000.00 -> CGST 90.00  + SGST 90.00
/// Taxable 4,000.00, GST 470.00, payable 4,470.00.
Sale _threeRateSale() {
  SaleItem line({
    required String name,
    required double taxable,
    required double rate,
    required double half,
  }) {
    return SaleItem(
      productId: name,
      productName: name,
      variantBarcode: 'BC-$name',
      variantSize: 'M',
      price: taxable,
      quantity: 1,
      total: taxable + half + half,
      hsn: '6109',
      uqc: 'PCS',
      gstRate: rate,
      gstTreatment: 'taxable',
      taxableValue: taxable,
      cgstAmount: half,
      sgstAmount: half,
    );
  }

  return Sale(
    id: 'S1',
    invoiceNumber: 'INV-00123',
    date: DateTime(2026, 8, 29),
    customerName: 'Walk-In Customer',
    items: [
      line(name: 'Kids T-Shirt', taxable: 1000, rate: 5, half: 25),
      line(name: 'Cotton Shirt', taxable: 2000, rate: 12, half: 120),
      line(name: 'Mens Jeans', taxable: 1000, rate: 18, half: 90),
    ],
    subtotal: 4000,
    taxAmount: 470,
    grandTotal: 4470,
    paymentMethod: 'UPI',
    taxableAmount: 4000,
    cgstAmount: 235,
    sgstAmount: 235,
    documentType: 'TAX INVOICE',
  );
}

void main() {
  group('AmountInWords', () {
    test(
      'renders correct singular and plural wording for rupees and paise',
      () {
        expect(AmountInWords.rupees(1.00), 'One Rupee Only');
        expect(AmountInWords.rupees(2.00), 'Two Rupees Only');
        expect(AmountInWords.rupees(1.01), 'One Rupee and One Paise Only');
        expect(AmountInWords.rupees(1.05), 'One Rupee and Five Paise Only');
        expect(AmountInWords.rupees(1.50), 'One Rupee and Fifty Paise Only');
        expect(
          AmountInWords.rupees(10.99),
          'Ten Rupees and Ninety-Nine Paise Only',
        );
        expect(AmountInWords.rupees(100.00), 'One Hundred Rupees Only');
      },
    );

    test('renders the invoice footer figure accurately for large amounts', () {
      expect(
        AmountInWords.rupees(4838),
        'Four Thousand Eight Hundred Thirty-Eight Rupees Only',
      );
      expect(AmountInWords.rupees(0), 'Zero Rupees Only');
      expect(
        AmountInWords.rupees(1234567),
        'Twelve Lakh Thirty-Four Thousand Five Hundred Sixty-Seven Rupees Only',
      );
    });

    test('rounds to the figure printed beside it', () {
      // 0.005 rounds away from zero natively via fixed-point rendering
      // preventing IEEE 754 precision truncations from producing 0 Paise
      expect(AmountInWords.rupees(1.005), 'One Rupee and One Paise Only');
    });
  });

  group('GstRateSummary', () {
    test('groups the bill by GST rate', () {
      final summary = GstRateSummary.fromSale(_threeRateSale());

      expect(summary.rows.length, 3);
      expect(summary.hasMultipleRates, isTrue);
      expect(summary.stateLevyLabel, 'SGST');

      expect(summary.rows[0].gstRate, 5);
      expect(summary.rows[0].halfRate, 2.5);
      expect(summary.rows[0].taxable, 1000);
      expect(summary.rows[0].cgst, 25);
      expect(summary.rows[0].stateGst, 25);
      expect(summary.rows[0].totalGst, 50);

      expect(summary.rows[1].gstRate, 12);
      expect(summary.rows[1].halfRate, 6);
      expect(summary.rows[1].cgst, 120);

      expect(summary.rows[2].gstRate, 18);
      expect(summary.rows[2].halfRate, 9);
      expect(summary.rows[2].cgst, 90);
    });

    test('columns add up to the totals the invoice prints', () {
      final sale = _threeRateSale();
      final summary = GstRateSummary.fromSale(sale);

      expect(summary.taxable, sale.taxableAmount);
      expect(summary.cgst, sale.cgstAmount);
      expect(summary.stateGst, sale.sgstAmount + sale.utgstAmount);
      expect(summary.totalGst, sale.totalGst);
    });

    test('absorbs a paisa of document rounding on the largest group', () {
      final sale = _threeRateSale()..cgstAmount = 235.01;
      final summary = GstRateSummary.fromSale(sale);

      expect(summary.cgst, 235.01);
      // The 12% group carries the largest taxable value.
      expect(summary.rows[1].cgst, 120.01);
      expect(summary.rows[0].cgst, 25);
      expect(summary.rows[2].cgst, 90);
    });

    test('is empty for a sale saved before the GST engine existed', () {
      final legacy = Sale(
        id: 'S0',
        invoiceNumber: 'INV-00001',
        date: DateTime(2024, 1, 1),
        items: [
          SaleItem(
            productId: 'P',
            productName: 'Saree',
            variantBarcode: 'BC',
            variantSize: 'F',
            price: 999,
            quantity: 1,
            total: 999,
          ),
        ],
        grandTotal: 999,
      );

      expect(GstRateSummary.fromSale(legacy).isEmpty, isTrue);
    });
  });

  group('InvoiceTemplate', () {
    test('stored ids round-trip', () {
      for (final template in InvoiceTemplate.values) {
        expect(InvoiceTemplate.fromId(template.id), template);
      }
    });

    test('an unknown id falls back rather than throwing at the till', () {
      expect(InvoiceTemplate.fromId(null), InvoiceTemplate.thermal);
      expect(InvoiceTemplate.fromId(''), InvoiceTemplate.thermal);
      expect(InvoiceTemplate.fromId('A5_FUTURE'), InvoiceTemplate.thermal);
    });
  });

  group('template selection is presentation only', () {
    late Sale sale;
    late SettingsModel settings;
    late CompanyModel company;
    late InvoiceSettingsModel invoiceSettings;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      sale = _threeRateSale();
      settings = SettingsModel();
      company = CompanyModel();
      invoiceSettings = InvoiceSettingsModel();
    });

    test('every template renders the same sale, unchanged', () async {
      final before = _snapshot(sale);
      final summaryBefore = GstRateSummary.fromSale(sale);

      for (final template in InvoiceTemplate.values) {
        final pdf = await ExportService.generateInvoiceForTemplate(
          sale,
          settings,
          company,
          invoiceSettings,
          template: template,
        );
        final bytes = await pdf.save();
        expect(bytes.isNotEmpty, isTrue, reason: template.label);

        // Rendering must not touch the record. A historical invoice that
        // changes when it is reprinted is the defect this guards.
        expect(_snapshot(sale), before, reason: template.label);
        final summaryAfter = GstRateSummary.fromSale(sale);
        expect(summaryAfter.taxable, summaryBefore.taxable);
        expect(summaryAfter.cgst, summaryBefore.cgst);
        expect(summaryAfter.stateGst, summaryBefore.stateGst);
        expect(summaryAfter.totalGst, summaryBefore.totalGst);
      }
    });

    test('the shop default drives the dispatcher', () async {
      final thermal = SettingsModel(invoiceTemplate: 'THERMAL');
      final sheet = SettingsModel(invoiceTemplate: 'A4_DETAILED_GST');

      final rollBytes = await (await ExportService.generateInvoiceForTemplate(
        sale,
        thermal,
        company,
        invoiceSettings,
      )).save();
      final sheetBytes = await (await ExportService.generateInvoiceForTemplate(
        sale,
        sheet,
        company,
        invoiceSettings,
      )).save();

      expect(rollBytes.isNotEmpty, isTrue);
      expect(sheetBytes.isNotEmpty, isTrue);
      expect(rollBytes.length == sheetBytes.length, isFalse);
    });
  });
}

/// The figures a customer checks, as one comparable string.
String _snapshot(Sale sale) {
  final lines = sale.items
      .map(
        (i) =>
            '${i.productName}|${i.quantity}|${i.price}|${i.taxableValue}|'
            '${i.gstRate}|${i.cgstAmount}|${i.sgstAmount}|${i.total}',
      )
      .join(';');
  return '$lines||${sale.subtotal}|${sale.taxableAmount}|${sale.cgstAmount}|'
      '${sale.sgstAmount}|${sale.igstAmount}|${sale.cessAmount}|'
      '${sale.roundOff}|${sale.grandTotal}';
}
