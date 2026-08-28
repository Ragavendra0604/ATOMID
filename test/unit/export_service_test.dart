import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:atomid/core/services/export_service.dart';
import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/invoice_settings_model.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/domain/price_tag_job.dart';

/// Cover for the documents customers physically receive.
///
/// `DocumentTotals` already tests the arithmetic. What was left untested is
/// everything around it: 600 lines of layout that throws rather than degrades.
/// The `pdf` package raises on an unresolvable layout — a table with no rows,
/// a value too wide for its column, a null where an image was expected — so
/// building a document to bytes is a real assertion, not a smoke test. Each
/// case below is a shape of data a real shop produces on an ordinary day.
///
/// Bundled Roboto is used throughout. The Google-hosted fonts take a network
/// path that has its own offline fallback, and reaching for it here would make
/// the suite depend on connectivity.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = SettingsModel();
  final company = CompanyModel(name: 'Test Shop', address: '1 High Street');
  final invoiceSettings = InvoiceSettingsModel();

  SaleItem line({
    String name = 'Blue Shirt',
    double price = 100,
    int qty = 1,
  }) => SaleItem(
    productId: 'p1',
    productName: name,
    productCode: 'C1',
    variantBarcode: 'B1',
    variantSize: 'M',
    price: price,
    quantity: qty,
    total: price * qty,
  );

  Sale sale({
    List<SaleItem>? items,
    double grand = 100,
    String payment = 'Cash',
    String customer = 'Walk-In Customer',
    double tax = 0,
    double discount = 0,
  }) => Sale(
    id: 's1',
    invoiceNumber: 'INV-0001',
    date: DateTime(2026, 6, 15, 14, 30),
    customerId: '',
    customerName: customer,
    subtotal: grand,
    discountPercent: 0,
    discountAmount: discount,
    rewardDiscountAmount: 0,
    taxAmount: tax,
    grandTotal: grand,
    paymentMethod: payment,
    items: items ?? [line()],
  );

  Product product({
    String name = 'Blue Shirt',
    int variants = 1,
    double price = 100,
    int qty = 10,
  }) => Product(
    id: 'p1',
    productName: name,
    productCode: 'C1',
    category: 'Shirts',
    brand: 'Acme',
    color: 'Blue',
    createdDate: DateTime(2026, 1, 1),
    updatedDate: DateTime(2026, 1, 1),
    variants: List.generate(
      variants,
      (i) => ProductVariant(
        barcode: 'B$i',
        size: 'S$i',
        price: price,
        quantity: qty,
      ),
    ),
  );

  /// A document that renders is one that produced bytes. `save()` is where the
  /// pdf package resolves layout, so a failure surfaces here rather than on a
  /// customer's printer.
  Future<void> expectRenders(Future<dynamic> future) async {
    final doc = await future;
    final bytes = await doc.save();
    expect(bytes, isNotEmpty);
    // Every PDF begins with %PDF. Catches a document that saved empty pages.
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  }

  /// Regression: the invoice was always laid out at the size stored in
  /// settings, even when it was being handed to a print job on other paper.
  /// The platform then scaled or cropped the A4 page onto whatever the printer
  /// was loaded with, so the printout did not match the preview.
  group('invoice page format', () {
    Future<List<double>> mediaBoxOf(Future<dynamic> future) async {
      final doc = await future;
      final bytes = await doc.save();
      final match = RegExp(
        r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)',
      ).firstMatch(String.fromCharCodes(bytes));
      expect(
        match,
        isNotNull,
        reason: 'no /MediaBox found — cannot read the page size',
      );
      return [double.parse(match!.group(1)!), double.parse(match.group(2)!)];
    }

    test('defaults to the size stored in settings', () async {
      final box = await mediaBoxOf(
        ExportService.generateInvoicePdf(
          sale(),
          settings,
          company,
          invoiceSettings,
        ),
      );
      expect(box[0], closeTo(PdfPageFormat.a4.width, 1));
      expect(box[1], closeTo(PdfPageFormat.a4.height, 1));
    });

    test('an explicit page format wins over settings', () async {
      final box = await mediaBoxOf(
        ExportService.generateInvoicePdf(
          sale(),
          settings,
          company,
          invoiceSettings,
          pageFormat: PdfPageFormat.letter,
        ),
      );
      expect(box[0], closeTo(PdfPageFormat.letter.width, 1));
      expect(box[1], closeTo(PdfPageFormat.letter.height, 1));
    });

    test('the same invoice on two papers is not the same document', () async {
      final a4 = await (await ExportService.generateInvoicePdf(
        sale(),
        settings,
        company,
        invoiceSettings,
        pageFormat: PdfPageFormat.a4,
      )).save();
      final letter = await (await ExportService.generateInvoicePdf(
        sale(),
        settings,
        company,
        invoiceSettings,
        pageFormat: PdfPageFormat.letter,
      )).save();
      expect(a4, isNot(equals(letter)));
    });

    // A print dialog can report a continuous roll, whose height is infinite.
    // MultiPage asserts a finite height, so an invoice sent to a receipt
    // printer must fall back to its configured sheet rather than throw.
    test('a continuous roll falls back to the configured sheet', () async {
      final box = await mediaBoxOf(
        ExportService.generateInvoicePdf(
          sale(),
          settings,
          company,
          invoiceSettings,
          pageFormat: PdfPageFormat.roll80,
        ),
      );
      expect(box[0], closeTo(PdfPageFormat.a4.width, 1));
      expect(box[1], closeTo(PdfPageFormat.a4.height, 1));
    });

    test('a bulk tag sheet also falls back on a continuous roll', () async {
      final p = product();
      await expectRenders(
        ExportService.generateBulkSheetPdf(
          [PriceTagLine(product: p, variant: p.variants.first, quantity: 2)],
          settings,
          company,
          pageFormat: PdfPageFormat.roll80,
        ),
      );
    });
  });

  group('invoice', () {
    test('renders an ordinary sale', () async {
      await expectRenders(
        ExportService.generateInvoicePdf(
          sale(),
          settings,
          company,
          invoiceSettings,
        ),
      );
    });

    test('renders a sale with tax and a discount', () async {
      await expectRenders(
        ExportService.generateInvoicePdf(
          sale(grand: 1180, tax: 180, discount: 50),
          settings,
          company,
          invoiceSettings,
        ),
      );
    });

    test('renders a long basket that must paginate', () async {
      await expectRenders(
        ExportService.generateInvoicePdf(
          sale(items: List.generate(80, (i) => line(name: 'Item $i'))),
          settings,
          company,
          invoiceSettings,
        ),
      );
    });

    test('renders a product name far too long for its column', () async {
      await expectRenders(
        ExportService.generateInvoicePdf(
          sale(items: [line(name: 'Extra Large ' * 30)]),
          settings,
          company,
          invoiceSettings,
        ),
      );
    });

    test('renders when the company profile is empty', () async {
      await expectRenders(
        ExportService.generateInvoicePdf(
          sale(),
          settings,
          CompanyModel(),
          invoiceSettings,
        ),
      );
    });

    test('renders a UPI sale whose QR image is missing', () async {
      // The path points at nothing — a shop that enabled the QR and then moved
      // the file. This must still print a receipt.
      await expectRenders(
        ExportService.generateInvoicePdf(
          sale(payment: 'UPI'),
          settings,
          company,
          InvoiceSettingsModel(
            showUpiQr: true,
            upiQrImagePath: '/no/such/file.png',
          ),
        ),
      );
    });

    test('renders with a logo enabled but absent', () async {
      await expectRenders(
        ExportService.generateInvoicePdf(
          sale(),
          settings,
          CompanyModel(name: 'Shop', logoPath: '/no/such/logo.png'),
          InvoiceSettingsModel(),
        ),
      );
    });

    test('renders with the signature block turned off', () async {
      // The footer Row keeps a placeholder in the signature's place, so the
      // UPI block on the other side must not stretch or collapse the row.
      await expectRenders(
        ExportService.generateInvoicePdf(
          sale(payment: 'UPI'),
          settings,
          company,
          InvoiceSettingsModel(showSignature: false, showUpiQr: true),
        ),
      );
    });

    test('renders a zero-total sale', () async {
      // A fully discounted or fully redeemed basket. Division by the total is
      // the obvious way for this to break.
      await expectRenders(
        ExportService.generateInvoicePdf(
          sale(items: [line(price: 0)], grand: 0),
          settings,
          company,
          invoiceSettings,
        ),
      );
    });
  });

  group('regressions', () {
    test('generating a document completes rather than hanging', () async {
      // `_ensureResourcesLoaded` used to end an await chain on
      // `SynchronousFuture.catchError`, which never completes. Every export in
      // the app deadlocked on it. Nothing threw and nothing failed — the
      // future simply never returned — so only a bounded wait catches it.
      await expectLater(
        ExportService.generateInvoicePdf(
          sale(),
          settings,
          company,
          invoiceSettings,
        ).timeout(const Duration(seconds: 15)),
        completes,
      );
    });

    test('the default font never reaches for the network', () async {
      // Roboto is bundled. It used to fall through to PdfGoogleFonts, putting
      // an HTTP fetch in front of every receipt on an offline-first till.
      // There is no network in this suite, so a document that renders quickly
      // with the default font is the assertion.
      final watch = Stopwatch()..start();
      await ExportService.generateInvoicePdf(
        sale(),
        settings,
        company,
        InvoiceSettingsModel(fontName: 'Roboto'),
      ).timeout(const Duration(seconds: 10));
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('a rupee sign in the italic footer keeps its glyph', () async {
      // The footer is the only italic run in these documents and the
      // shopkeeper writes it, so it is where non-ASCII turns up. With no
      // italic font registered the pdf package fell back to built-in
      // Helvetica-Oblique, which has no Unicode support and dropped the rupee
      // sign entirely. Bundled Roboto carries U+20B9, so registering it as the
      // italic face is what makes the character survive.
      //
      // Scope note: this covers the Latin-plus-rupee range Roboto actually
      // has. Devanagari and Tamil are *not* in the bundled font and are still
      // dropped — see the test below.
      await expectRenders(
        ExportService.generateInvoicePdf(
          sale(),
          settings,
          company,
          InvoiceSettingsModel(footerText: 'Thank you — total ₹1,250'),
        ),
      );
    });

    test('an Indic footer does not crash the receipt', () async {
      // A shopkeeper typing their own language into the footer must still get
      // a printable receipt. Whether the glyphs actually appear is asserted
      // separately, in the "Indic script rendering" group below.
      await expectRenders(
        ExportService.generateThermalReceiptPdf(
          sale(),
          settings,
          company,
          InvoiceSettingsModel(footerText: 'धन्यवाद ₹500'),
        ),
      );
    });
  });

  /// Regression: Roboto carries no Tamil or Devanagari glyphs, so every such
  /// character was dropped from the output and the pdf package logged
  /// "Unable to find a font to draw ... try to provide a TextStyle.fontFallback".
  /// A shop billing in Tamil printed an invoice with its own name missing.
  ///
  /// The warning is emitted through `print` inside an `assert`, so a zone can
  /// capture it and the absence of it can be asserted directly.
  group('Indic script rendering', () {
    const tamil = 'ஆடை அங்காடி — நன்றி';
    const hindi = 'धन्यवाद, फिर मिलेंगे';

    /// Lines the pdf package printed while [future]'s document was laid out.
    ///
    /// `save()` is where layout happens, so the document has to be saved
    /// inside the zone for anything to be captured.
    Future<List<String>> warningsWhileRendering(Future<dynamic> future) async {
      final lines = <String>[];
      await runZoned(
        () async {
          final doc = await future;
          final bytes = await doc.save();
          expect(bytes, isNotEmpty);
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => lines.add(line),
        ),
      );
      return lines;
    }

    /// Only the missing-glyph lines; the pdf package prints nothing else here.
    List<String> missingGlyphs(List<String> lines) =>
        lines.where((l) => l.contains('Unable to find a font')).toList();

    test('a Tamil company name draws every glyph', () async {
      final warnings = await warningsWhileRendering(
        ExportService.generateInvoicePdf(
          sale(
            items: [line(name: tamil)],
            customer: tamil,
          ),
          settings,
          CompanyModel(name: tamil, address: tamil),
          invoiceSettings,
        ),
      );
      expect(
        missingGlyphs(warnings),
        isEmpty,
        reason: 'Tamil glyphs were dropped',
      );
    });

    test('a Hindi footer draws every glyph', () async {
      final warnings = await warningsWhileRendering(
        ExportService.generateInvoicePdf(
          sale(),
          settings,
          company,
          InvoiceSettingsModel(footerText: hindi, termsAndConditions: hindi),
        ),
      );
      expect(
        missingGlyphs(warnings),
        isEmpty,
        reason: 'Devanagari glyphs were dropped',
      );
    });

    test('a thermal receipt in both scripts draws every glyph', () async {
      final warnings = await warningsWhileRendering(
        ExportService.generateThermalReceiptPdf(
          sale(),
          settings,
          CompanyModel(name: tamil, address: hindi),
          InvoiceSettingsModel(footerText: '$tamil $hindi ₹500'),
        ),
      );
      expect(missingGlyphs(warnings), isEmpty, reason: 'glyphs were dropped');
    });

    test('Latin text still renders and is unaffected', () async {
      final warnings = await warningsWhileRendering(
        ExportService.generateInvoicePdf(
          sale(),
          settings,
          company,
          invoiceSettings,
        ),
      );
      expect(missingGlyphs(warnings), isEmpty);
    });
  });

  group('thermal receipt', () {
    test('renders on an 80mm roll', () async {
      await expectRenders(
        ExportService.generateThermalReceiptPdf(
          sale(),
          settings,
          company,
          invoiceSettings,
        ),
      );
    });

    test('renders with a logo enabled but absent', () async {
      // The roll reads `showCompanyLogo` too now. A path pointing at nothing
      // must still print a receipt rather than take the till down.
      await expectRenders(
        ExportService.generateThermalReceiptPdf(
          sale(),
          settings,
          CompanyModel(name: 'Shop', logoPath: '/no/such/logo.png'),
          InvoiceSettingsModel(),
        ),
      );
    });

    test('renders terms and the signature line on a narrow roll', () async {
      // 58mm is the tightest layout; long terms plus the signature block is
      // the most content the foot of a receipt ever carries.
      await expectRenders(
        ExportService.generateThermalReceiptPdf(
          sale(),
          SettingsModel(thermalReceiptSize: '58mm'),
          company,
          InvoiceSettingsModel(
            termsAndConditions:
                '1. Goods once sold will not be taken back.\n'
                '2. Subject to local jurisdiction.',
          ),
        ),
      );
    });

    test('renders with the signature line turned off', () async {
      await expectRenders(
        ExportService.generateThermalReceiptPdf(
          sale(),
          settings,
          company,
          InvoiceSettingsModel(showSignature: false),
        ),
      );
    });

    test('renders a long name on a narrow roll', () async {
      await expectRenders(
        ExportService.generateThermalReceiptPdf(
          sale(items: [line(name: 'Extra Large Blue Cotton Shirt XXL')]),
          settings,
          company,
          invoiceSettings,
        ),
      );
    });
  });

  group('reports', () {
    test('sales report renders with data', () async {
      await expectRenders(
        ExportService.generateSalesReportPdf(
          [sale(), sale(grand: 250)],
          'This Month',
          settings,
          company,
        ),
      );
    });

    test('sales report renders with no sales at all', () async {
      // A shop that took nothing this month still asks for the report, and an
      // average built on a zero divisor is the classic way this crashes.
      await expectRenders(
        ExportService.generateSalesReportPdf([], 'Today', settings, company),
      );
    });

    test('inventory report renders across many variants', () async {
      await expectRenders(
        ExportService.generateInventoryReportPdf(
          [product(variants: 5), product(name: 'Red Hat', variants: 3)],
          settings,
          company,
        ),
      );
    });

    test('inventory report renders on an empty catalogue', () async {
      await expectRenders(
        ExportService.generateInventoryReportPdf([], settings, company),
      );
    });

    test('inventory report renders a product with no variants', () async {
      await expectRenders(
        ExportService.generateInventoryReportPdf(
          [product(variants: 0)],
          settings,
          company,
        ),
      );
    });

    test('purchase report renders empty and populated', () async {
      final po = Purchase(
        id: 'po1',
        purchaseNumber: 'PUR-1',
        supplierId: 'sup1',
        supplierName: 'Acme',
        purchaseDate: DateTime(2026, 6, 1),
        createdDate: DateTime(2026, 6, 1),
        subtotal: 500,
        grandTotal: 500,
        items: [
          PurchaseItem(
            productId: 'p1',
            productName: 'Blue Shirt',
            variantBarcode: 'B1',
            variantSize: 'M',
            quantity: 5,
            costPrice: 100,
            sellingPrice: 150,
            lineTotal: 500,
          ),
        ],
      );

      await expectRenders(
        ExportService.generatePurchaseReportPdf(
          [po],
          'This Month',
          settings,
          company,
        ),
      );
      await expectRenders(
        ExportService.generatePurchaseReportPdf(
          [],
          'This Month',
          settings,
          company,
        ),
      );
    });

    test('supplier report renders empty and populated', () async {
      final supplier = Supplier(
        id: 'sup1',
        supplierCode: 'SUP-1',
        supplierName: 'Acme Textiles',
        phone: '9500000000',
        createdDate: DateTime(2026, 1, 1),
        updatedDate: DateTime(2026, 1, 1),
      );

      await expectRenders(
        ExportService.generateSupplierReportPdf(
          [supplier],
          // No total for this supplier: a report run before any goods-in must
          // still print rather than throwing on the missing key.
          {},
          settings,
          company,
        ),
      );
      await expectRenders(
        ExportService.generateSupplierReportPdf([], {}, settings, company),
      );
    });

    test('valuation report renders, including unpriced products', () async {
      await expectRenders(
        ExportService.generateInventoryValuationReportPdf(
          [product(), product(name: 'Red Hat')],
          // Deliberately partial: a product with no recorded cost must not
          // take the whole valuation down with it.
          {'B0': 60.0},
          settings,
          company,
        ),
      );
    });

    test('valuation report renders with nothing to value', () async {
      await expectRenders(
        ExportService.generateInventoryValuationReportPdf(
          [],
          {},
          settings,
          company,
        ),
      );
    });
  });

  group('price tags', () {
    test('renders a single tag', () async {
      final p = product();
      await expectRenders(
        ExportService.generateSingleTagPdf(
          p,
          p.variants.first,
          settings,
          company,
        ),
      );
    });

    test('renders a tag for a long name and a high price', () async {
      final p = product(name: 'Premium Cotton Formal Shirt', price: 129999.99);
      await expectRenders(
        ExportService.generateSingleTagPdf(
          p,
          p.variants.first,
          settings,
          company,
        ),
      );
    });
  });

  group('export file names survive free-text product data', () {
    // Product codes and variant sizes are typed by the shopkeeper and land in
    // the export name verbatim. These are all names a real shop produces.
    test('a slash in a size does not become a directory', () {
      expect(
        ExportService.safeFileName('ATOMID_TEA_1/2 KG_20260822'),
        'ATOMID_TEA_1-2 KG_20260822',
      );
      expect(ExportService.safeFileName('SHIRT_L/XL'), 'SHIRT_L-XL');
    });

    test('no character Windows refuses survives', () {
      // Asserted as a property rather than one expected string: the point is
      // that none of them get through, not the exact dash placement.
      final cleaned = ExportService.safeFileName(r'PIPE_12" <A:B>|C?D*E\F');
      expect(cleaned, isNot(matches(RegExp(r'[<>:"/\\|?*]'))));
      expect(cleaned, startsWith('PIPE_12'));
      expect(cleaned, endsWith('F'));
    });

    test('a trailing dot or space is dropped', () {
      // Windows strips these itself, so a name ending in one resolves to a
      // different file than the one asked for.
      expect(ExportService.safeFileName('REPORT.'), 'REPORT');
      expect(ExportService.safeFileName('  REPORT  '), 'REPORT');
    });

    test('a reserved device name is escaped', () {
      expect(ExportService.safeFileName('CON'), '_CON');
      expect(ExportService.safeFileName('lpt1'), '_lpt1');
    });

    test('a name that sanitises to nothing falls back', () {
      expect(ExportService.safeFileName('///'), isNotEmpty);
      expect(ExportService.safeFileName(''), 'atomid-export');
    });

    test('an over-long name is truncated, not rejected', () {
      expect(ExportService.safeFileName('X' * 400).length, 120);
    });
  });
}
