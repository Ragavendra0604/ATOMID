import 'package:atomid/core/utils/platform_io.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/data/models/sale_model.dart' as import_sale;
import 'package:atomid/data/models/purchase_model.dart' as import_purchase;
import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/invoice_settings_model.dart';
import 'package:atomid/domain/price_tag_size.dart';

class ExportService {
  static pw.Font? _cachedRegularFont;
  static pw.Font? _cachedBoldFont;
  static final Map<String, pw.ThemeData> _cachedThemes = {};
  static pw.ThemeData? _cachedTheme; // fallback
  static pw.MemoryImage? _cachedLogo;
  static bool _resourcesLoaded = false;

  static Future<pw.MemoryImage?> _getCompanyLogo(CompanyModel company) async {
    if (company.logoPath.isNotEmpty && !kIsWeb) {
      try {
        final file = PlatformFile(company.logoPath);
        if (await file.exists()) {
          return pw.MemoryImage(await file.readAsBytes());
        }
      } catch (_) {}
    }
    return _logo;
  }

  static Future<pw.MemoryImage?> _getImage(String path) async {
    if (path.isNotEmpty && !kIsWeb) {
      try {
        final file = PlatformFile(path);
        if (await file.exists()) {
          return pw.MemoryImage(await file.readAsBytes());
        }
      } catch (_) {}
    }
    return null;
  }

  static pw.Widget _buildCompanyHeader(
    CompanyModel company,
    pw.MemoryImage? logo,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null) pw.Image(logo, width: 80, height: 80),
        if (logo != null) pw.SizedBox(width: 16),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              company.name.isNotEmpty ? company.name : 'ATOMID',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            if (company.address.isNotEmpty) pw.Text(company.address),
            if (company.city.isNotEmpty || company.state.isNotEmpty)
              pw.Text('${company.city}, ${company.state} - ${company.pincode}'),
            if (company.phone1.isNotEmpty || company.phone2.isNotEmpty)
              pw.Text('Phone: ${company.phone1} ${company.phone2}'),
            if (company.gstNumber.isNotEmpty)
              pw.Text('GST: ${company.gstNumber}'),
            if (company.email.isNotEmpty) pw.Text('Email: ${company.email}'),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildReportHeader(
    String title,
    CompanyModel company,
    String timeframe,
    SettingsModel settings,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          company.name.isNotEmpty ? company.name : settings.companyName,
          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          title + (timeframe.isNotEmpty ? ' - $timeframe' : ''),
          style: const pw.TextStyle(fontSize: 16),
        ),
        pw.Text(
          'Generated: ${DateTime.now().toString().split('.')[0]}',
          style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
        ),
        pw.Divider(),
      ],
    );
  }

  static Future<void> _ensureResourcesLoaded() async {
    if (_resourcesLoaded) return;

    final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    _cachedRegularFont = pw.Font.ttf(fontData);

    final fontDataBold = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    _cachedBoldFont = pw.Font.ttf(fontDataBold);

    _cachedTheme = pw.ThemeData.withFont(
      base: _cachedRegularFont!,
      bold: _cachedBoldFont!,
    );

    final logoBytes = await rootBundle
        .load('assets/images/logo.png')
        .catchError((_) => ByteData(0));
    if (logoBytes.lengthInBytes > 0) {
      _cachedLogo = pw.MemoryImage(logoBytes.buffer.asUint8List());
    }

    _resourcesLoaded = true;
  }

  static Future<pw.ThemeData> _getTheme(String fontName) async {
    if (_cachedThemes.containsKey(fontName)) {
      return _cachedThemes[fontName]!;
    }

    pw.Font regular;
    pw.Font bold;

    try {
      switch (fontName) {
        case 'Open Sans':
          regular = await PdfGoogleFonts.openSansRegular();
          bold = await PdfGoogleFonts.openSansBold();
          break;
        case 'Lato':
          regular = await PdfGoogleFonts.latoRegular();
          bold = await PdfGoogleFonts.latoBold();
          break;
        case 'Montserrat':
          regular = await PdfGoogleFonts.montserratRegular();
          bold = await PdfGoogleFonts.montserratBold();
          break;
        case 'Oswald':
          regular = await PdfGoogleFonts.oswaldRegular();
          bold = await PdfGoogleFonts.oswaldBold();
          break;
        case 'Merriweather':
          regular = await PdfGoogleFonts.merriweatherRegular();
          bold = await PdfGoogleFonts.merriweatherBold();
          break;
        case 'Roboto':
        default:
          regular = await PdfGoogleFonts.robotoRegular();
          bold = await PdfGoogleFonts.robotoBold();
          break;
      }
    } catch (_) {
      // Fallback to bundled Roboto if network fails
      regular = _cachedRegularFont!;
      bold = _cachedBoldFont!;
    }

    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    _cachedThemes[fontName] = theme;
    return theme;
  }

  static pw.ThemeData get _theme => _cachedTheme!;
  static pw.MemoryImage? get _logo => _cachedLogo;

  static PdfColor _getColorFromName(String colorName) {
    switch (colorName.trim().toLowerCase()) {
      case 'red':
        return PdfColors.red;
      case 'blue':
      case 'navy':
        return PdfColors.blue;
      case 'green':
        return PdfColors.green;
      case 'yellow':
        return PdfColors.yellow;
      case 'orange':
        return PdfColors.orange;
      case 'purple':
        return PdfColors.purple;
      case 'pink':
        return PdfColors.pink;
      case 'brown':
        return PdfColors.brown;
      case 'grey':
      case 'gray':
        return PdfColors.grey;
      case 'white':
        return PdfColors.black; // Prevent invisible text on white background
      case 'black':
      default:
        return PdfColors.black;
    }
  }

  static Future<pw.Document> generateSingleTagPdf(
    Product product,
    ProductVariant variant,
    SettingsModel settings,
    CompanyModel company,
  ) async {
    await _ensureResourcesLoaded();
    final pdf = pw.Document();
    final logoImage = await _getCompanyLogo(company);

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          200 * PdfPageFormat.point,
          300 * PdfPageFormat.point,
        ),
        theme: _theme,
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
              border: pw.Border.all(color: PdfColors.black, width: 1),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null)
                  pw.Image(logoImage, width: 60, height: 40)
                else
                  pw.Text(
                    company.name.isNotEmpty
                        ? company.name
                        : settings.companyName,
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                pw.SizedBox(height: 4),
                pw.Divider(),
                pw.Text(
                  product.productName,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  maxLines: 1,
                ),
                pw.Text(
                  product.productCode,
                  style: const pw.TextStyle(
                    fontSize: 12,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Color:', style: const pw.TextStyle(fontSize: 14)),
                    pw.Text(
                      product.color,
                      style: pw.TextStyle(
                        fontSize: 14,
                        color: _getColorFromName(product.color),
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Size:', style: const pw.TextStyle(fontSize: 14)),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.black,
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(4),
                        ),
                      ),
                      child: pw.Text(
                        variant.size,
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: variant.barcode,
                  width: 140,
                  height: 40,
                  drawText: true,
                  textStyle: const pw.TextStyle(fontSize: 10, letterSpacing: 2),
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  'MRP',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  '${settings.currencySymbol}${variant.price.toStringAsFixed(2)}',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  '(Incl. of all taxes)',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Qty: ${variant.quantity}',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf;
  }

  static Future<PlatformFile> exportPdf(
    pw.Document pdf,
    String fileName,
  ) async {
    if (kIsWeb) throw UnsupportedError('File export is not supported on Web');
    final dir = await _getExportDirectory('PDF');
    final file = PlatformFile('${dir.path}/$fileName.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static Future<PlatformFile> exportPng(
    pw.Document pdf,
    String fileName, {
    double dpi = 300.0,
  }) async {
    if (kIsWeb) throw UnsupportedError('File export is not supported on Web');
    final dir = await _getExportDirectory('Images');
    final file = PlatformFile('${dir.path}/$fileName.png');

    await for (var page in Printing.raster(await pdf.save(), dpi: dpi)) {
      final pngData = await page.toPng();
      await file.writeAsBytes(pngData);
      break; // Only export the first page for single tags
    }

    return file;
  }

  static Future<void> shareFile(PlatformFile file, String text) async {
    if (kIsWeb) return;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: text),
    );
  }

  static Future<PlatformDirectory> _getExportDirectory(String subFolder) async {
    if (kIsWeb) {
      throw UnsupportedError('Directory access is not supported on Web');
    }
    PlatformDirectory? baseDir;
    if (PlatformIo.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        baseDir = PlatformDirectory('${extDir.path}/Atomid Store/$subFolder');
      } else {
        baseDir = PlatformDirectory(
          '${(await getApplicationDocumentsDirectory()).path}/Atomid Store/$subFolder',
        );
      }
    } else if (PlatformIo.isIOS) {
      baseDir = PlatformDirectory(
        '${(await getApplicationDocumentsDirectory()).path}/Atomid Store/$subFolder',
      );
    } else {
      // Windows / Desktop
      baseDir = PlatformDirectory(
        '${(await getApplicationDocumentsDirectory()).path}/Atomid Store/$subFolder',
      );
    }

    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    return baseDir;
  }

  static Future<pw.Document> generateBulkSheetPdf(
    Product product,
    List<ProductVariant> variantsToPrint,
    SettingsModel settings,
    CompanyModel company, {
    PriceTagSize tagSize = PriceTagSize.medium,
  }) async {
    await _ensureResourcesLoaded();
    final pdf = pw.Document();
    final logoImage = tagSize.showLogo ? await _getCompanyLogo(company) : null;

    final pageFormat = settings.pdfPageSize == 'Letter'
        ? PdfPageFormat.letter
        : PdfPageFormat.a4;

    // Derived from the page actually being printed. These were fixed at A4's
    // 595 x 842 regardless of the setting, so a Letter sheet — shorter at 792
    // — lost the bottom row of every page.
    final double tagWidth = pageFormat.width / tagSize.columns;
    final double tagHeight = pageFormat.height / tagSize.rows;

    final perPage = tagSize.perPage;
    final pages = (variantsToPrint.length / perPage).ceil();

    for (var i = 0; i < pages; i++) {
      final startIndex = i * perPage;
      final endIndex = (startIndex + perPage > variantsToPrint.length)
          ? variantsToPrint.length
          : startIndex + perPage;
      final pageVariants = variantsToPrint.sublist(startIndex, endIndex);

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(0),
          theme: _theme,
          build: (pw.Context context) {
            return pw.Wrap(
              children: pageVariants.map((variant) {
                return pw.Container(
                  width: tagWidth,
                  height: tagHeight,
                  padding: pw.EdgeInsets.all(tagSize.padding),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      if (logoImage != null)
                        pw.Image(
                          logoImage,
                          width: tagSize.logoSize,
                          height: tagSize.logoSize,
                        ),
                      pw.Text(
                        product.productName,
                        style: pw.TextStyle(
                          fontSize: tagSize.nameFontSize,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        maxLines: 1,
                      ),
                      pw.Text(
                        product.productCode,
                        style: pw.TextStyle(fontSize: tagSize.codeFontSize),
                      ),
                      pw.SizedBox(height: tagSize.padding / 2),
                      pw.Text(
                        'Size: ${variant.size}',
                        style: pw.TextStyle(
                          fontSize: tagSize.sizeFontSize,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: tagSize.padding),
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: variant.barcode,
                        width: tagSize.barcodeWidth,
                        height: tagSize.barcodeHeight,
                        drawText: true,
                        textStyle: pw.TextStyle(
                          fontSize: tagSize.barcodeTextSize,
                          letterSpacing: 1,
                        ),
                      ),
                      pw.Spacer(),
                      pw.Text(
                        '${settings.currencySymbol}${variant.price.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: tagSize.priceFontSize,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      );
    }
    return pdf;
  }

  static Future<pw.Document> generateInvoicePdf(
    import_sale.Sale sale,
    SettingsModel settings,
    CompanyModel company,
    InvoiceSettingsModel invoiceSettings,
  ) async {
    await _ensureResourcesLoaded();
    final theme = await _getTheme(invoiceSettings.fontName);
    final pdf = pw.Document();
    final logoImage = invoiceSettings.showCompanyLogo
        ? await _getCompanyLogo(company)
        : null;
    final upiQrImage =
        (invoiceSettings.showUpiQr && sale.paymentMethod == 'UPI')
        ? await _getImage(invoiceSettings.upiQrImagePath)
        : null;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildCompanyHeader(company, logoImage),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'INVOICE',
                        style: pw.TextStyle(
                          fontSize: 28,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text('Invoice #: ${sale.invoiceNumber}'),
                      pw.Text(
                        'Date: ${sale.date.year}-${sale.date.month.toString().padLeft(2, '0')}-${sale.date.day.toString().padLeft(2, '0')}',
                      ),
                      pw.SizedBox(height: 16),
                      pw.Text('Bill To:'),
                      pw.Text(
                        sale.customerName,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 32),

              // Items Table
              pw.TableHelper.fromTextArray(
                context: context,
                border: null,
                headerAlignment: pw.Alignment.centerLeft,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellHeight: 30,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.center,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                },
                headers: ['Item', 'Qty', 'Price', 'Total'],
                data: sale.items.map((item) {
                  return [
                    '${item.productName} (${item.variantSize})',
                    item.quantity.toString(),
                    '${settings.currencySymbol}${item.price.toStringAsFixed(2)}',
                    '${settings.currencySymbol}${item.total.toStringAsFixed(2)}',
                  ];
                }).toList(),
              ),
              pw.Divider(),

              // Totals
              pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Subtotal:'),
                        if (sale.discountAmount > 0)
                          pw.Text(
                            sale.discountPercent > 0
                                ? 'Discount (${sale.discountPercent}%):'
                                : 'Discount:',
                          ),
                        if (sale.rewardDiscountAmount > 0)
                          pw.Text('Reward points:'),
                        if (sale.taxAmount > 0)
                          pw.Text('Tax (${settings.taxRate}%):'),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          'Grand Total:',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                    pw.SizedBox(width: 24),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          Fmt.money(sale.subtotal, settings.currencySymbol),
                        ),
                        if (sale.discountAmount > 0)
                          pw.Text(
                            '-${Fmt.money(sale.discountAmount, settings.currencySymbol)}',
                          ),
                        if (sale.rewardDiscountAmount > 0)
                          pw.Text(
                            '-${Fmt.money(sale.rewardDiscountAmount, settings.currencySymbol)}',
                          ),
                        if (sale.taxAmount > 0)
                          pw.Text(
                            Fmt.money(sale.taxAmount, settings.currencySymbol),
                          ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          Fmt.money(sale.grandTotal, settings.currencySymbol),
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 32),

              // Footer
              pw.Text('Payment Method: ${sale.paymentMethod}'),
              if (sale.notes.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Text('Notes: ${sale.notes}'),
              ],
              pw.SizedBox(height: 16),
              if (invoiceSettings.termsAndConditions.isNotEmpty) ...[
                pw.Text(
                  'Terms & Conditions:',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
                pw.Text(
                  invoiceSettings.termsAndConditions,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (upiQrImage != null)
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Scan to Pay (UPI)',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                        if (invoiceSettings.upiId.isNotEmpty)
                          pw.Text(
                            invoiceSettings.upiId,
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        pw.SizedBox(height: 4),
                        pw.Image(upiQrImage, width: 80, height: 80),
                      ],
                    )
                  else
                    pw.SizedBox(),
                  pw.Text(
                    invoiceSettings.footerText.isNotEmpty
                        ? invoiceSettings.footerText
                        : 'Thank you for your business!',
                    style: pw.TextStyle(fontStyle: pw.FontStyle.italic),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    return pdf;
  }

  static Future<pw.Document> generateThermalReceiptPdf(
    import_sale.Sale sale,
    SettingsModel settings,
    CompanyModel company,
    InvoiceSettingsModel invoiceSettings,
  ) async {
    await _ensureResourcesLoaded();
    final theme = await _getTheme(invoiceSettings.fontName);
    final pdf = pw.Document();
    final upiQrImage =
        (invoiceSettings.showUpiQr && sale.paymentMethod == 'UPI')
        ? await _getImage(invoiceSettings.upiQrImagePath)
        : null;

    // Roll80 page format (80mm) -> approx 226 points wide
    final format = PdfPageFormat.roll80;

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        theme: theme,
        margin: const pw.EdgeInsets.all(12),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              if (invoiceSettings.showCompanyLogo)
                pw.Text(
                  company.name.isNotEmpty ? company.name : settings.companyName,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              if (invoiceSettings.showCompanyLogo) pw.SizedBox(height: 4),
              pw.Text(
                'Receipt: ${sale.invoiceNumber}',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.Text(
                'Date: ${sale.date.year}-${sale.date.month.toString().padLeft(2, '0')}-${sale.date.day.toString().padLeft(2, '0')} ${sale.date.hour.toString().padLeft(2, '0')}:${sale.date.minute.toString().padLeft(2, '0')}',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 4),

              // Items
              ...sale.items.map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(
                          '${item.productName} (${item.variantSize})',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Text(
                          '${item.quantity}x',
                          style: const pw.TextStyle(fontSize: 10),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                          '${settings.currencySymbol}${item.total.toStringAsFixed(2)}',
                          style: const pw.TextStyle(fontSize: 10),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                );
              }),

              pw.SizedBox(height: 4),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 4),

              // Totals
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Subtotal:', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(
                    Fmt.money(sale.subtotal, settings.currencySymbol),
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
              if (sale.discountAmount > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      sale.discountPercent > 0
                          ? 'Discount (${sale.discountPercent}%):'
                          : 'Discount:',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      '-${Fmt.money(sale.discountAmount, settings.currencySymbol)}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              if (sale.rewardDiscountAmount > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Reward points:',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      '-${Fmt.money(sale.rewardDiscountAmount, settings.currencySymbol)}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              if (sale.taxAmount > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Tax:', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text(
                      Fmt.money(sale.taxAmount, settings.currencySymbol),
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL:',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    Fmt.money(sale.grandTotal, settings.currencySymbol),
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 8),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 8),
              pw.Text(
                'Paid via ${sale.paymentMethod}',
                style: const pw.TextStyle(fontSize: 10),
              ),
              if (upiQrImage != null) ...[
                pw.SizedBox(height: 8),
                pw.Text(
                  'Scan to Pay (UPI)',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                if (invoiceSettings.upiId.isNotEmpty)
                  pw.Text(
                    invoiceSettings.upiId,
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                pw.SizedBox(height: 4),
                pw.Image(upiQrImage, width: 80, height: 80),
              ],
              pw.SizedBox(height: 16),
              if (invoiceSettings.termsAndConditions.isNotEmpty) ...[
                pw.Text(
                  'Terms & Conditions:',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 8,
                  ),
                ),
                pw.Text(
                  invoiceSettings.termsAndConditions,
                  style: const pw.TextStyle(fontSize: 8),
                ),
                pw.SizedBox(height: 8),
              ],
              pw.Text(
                invoiceSettings.footerText.isNotEmpty
                    ? invoiceSettings.footerText
                    : 'Thank you for your business!',
                style: const pw.TextStyle(
                  fontSize: 10,
                  fontStyle: pw.FontStyle.italic,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 24), // Extra spacing for tear off
            ],
          );
        },
      ),
    );
    return pdf;
  }

  static Future<pw.Document> generateSalesReportPdf(
    List<import_sale.Sale> sales,
    String timeframe,
    SettingsModel settings,
    CompanyModel company,
  ) async {
    await _ensureResourcesLoaded();
    final pdf = pw.Document();

    final double totalRevenue = sales.fold(0, (sum, s) => sum + s.grandTotal);
    final int totalItems = sales.fold(
      0,
      (sum, s) => sum + s.items.fold(0, (iSum, item) => iSum + item.quantity),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: _theme,
        header: (context) {
          return _buildReportHeader(
            'Sales Report',
            company,
            timeframe,
            settings,
          );
        },
        build: (context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total Invoices: ${sales.length}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Total Items Sold: $totalItems',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Total Revenue: ${settings.currencySymbol}${totalRevenue.toStringAsFixed(2)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              context: context,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              headers: ['Date', 'Invoice', 'Customer', 'Items', 'Total'],
              data: sales.map((s) {
                return [
                  '${s.date.year}-${s.date.month.toString().padLeft(2, '0')}-${s.date.day.toString().padLeft(2, '0')}',
                  s.invoiceNumber,
                  s.customerName,
                  s.items.fold(0, (sum, i) => sum + i.quantity).toString(),
                  '${settings.currencySymbol}${s.grandTotal.toStringAsFixed(2)}',
                ];
              }).toList(),
            ),
          ];
        },
      ),
    );
    return pdf;
  }

  static Future<pw.Document> generateInventoryReportPdf(
    List<Product> products,
    SettingsModel settings,
    CompanyModel company,
  ) async {
    await _ensureResourcesLoaded();
    final pdf = pw.Document();

    int totalVariants = 0;
    int totalStock = 0;
    double totalValue = 0;
    final List<List<String>> tableData = [];

    for (var p in products) {
      for (var v in p.variants) {
        totalVariants++;
        totalStock += v.quantity;
        totalValue += (v.quantity * v.price);
        tableData.add([
          p.productName,
          p.productCode,
          v.size,
          v.barcode,
          v.quantity.toString(),
          '${settings.currencySymbol}${v.price.toStringAsFixed(2)}',
        ]);
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: _theme,
        header: (context) {
          return _buildReportHeader(
            'Inventory Valuation Report',
            company,
            '',
            settings,
          );
        },
        build: (context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total Variants: $totalVariants',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Total Stock Units: $totalStock',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Total Inventory Value: ${settings.currencySymbol}${totalValue.toStringAsFixed(2)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              context: context,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              headers: ['Product', 'Code', 'Size', 'Barcode', 'Qty', 'Price'],
              data: tableData,
            ),
          ];
        },
      ),
    );
    return pdf;
  }

  static Future<pw.Document> generatePurchaseReportPdf(
    List<import_purchase.Purchase> purchases,
    String timeframe,
    SettingsModel settings,
    CompanyModel company,
  ) async {
    await _ensureResourcesLoaded();
    final pdf = pw.Document();

    final double totalCost = purchases.fold(0, (sum, p) => sum + p.grandTotal);
    final int totalItems = purchases.fold(
      0,
      (sum, p) => sum + p.items.fold(0, (iSum, item) => iSum + item.quantity),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: _theme,
        header: (context) {
          return _buildReportHeader(
            'Purchase Report',
            company,
            timeframe,
            settings,
          );
        },
        build: (context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total Purchases: ${purchases.length}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Total Items: $totalItems',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Total Cost: ${settings.currencySymbol}${totalCost.toStringAsFixed(2)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              context: context,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              headers: ['Date', 'Purchase #', 'Supplier', 'Items', 'Total'],
              data: purchases.map((p) {
                return [
                  '${p.purchaseDate.year}-${p.purchaseDate.month.toString().padLeft(2, '0')}-${p.purchaseDate.day.toString().padLeft(2, '0')}',
                  p.purchaseNumber,
                  p.supplierName,
                  p.items.fold(0, (sum, i) => sum + i.quantity).toString(),
                  '${settings.currencySymbol}${p.grandTotal.toStringAsFixed(2)}',
                ];
              }).toList(),
            ),
          ];
        },
      ),
    );
    return pdf;
  }

  static Future<pw.Document> generateSupplierReportPdf(
    List<Supplier> suppliers,
    Map<String, double> supplierTotals,
    SettingsModel settings,
    CompanyModel company,
  ) async {
    await _ensureResourcesLoaded();
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: _theme,
        header: (context) {
          return _buildReportHeader('Supplier Report', company, '', settings);
        },
        build: (context) {
          return [
            pw.Text(
              'Total Suppliers: ${suppliers.length}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              context: context,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              headers: [
                'Code',
                'Name',
                'Phone',
                'GST',
                'Status',
                'Total Purchases',
              ],
              data: suppliers.map((s) {
                return [
                  s.supplierCode,
                  s.supplierName,
                  s.phone,
                  s.gstNumber,
                  s.isActive ? 'Active' : 'Inactive',
                  '${settings.currencySymbol}${(supplierTotals[s.id] ?? 0).toStringAsFixed(2)}',
                ];
              }).toList(),
            ),
          ];
        },
      ),
    );
    return pdf;
  }

  static Future<pw.Document> generateInventoryValuationReportPdf(
    List<Product> products,
    Map<String, double> valuation,
    SettingsModel settings,
    CompanyModel company,
  ) async {
    await _ensureResourcesLoaded();
    final pdf = pw.Document();

    final List<List<String>> tableData = [];
    for (var p in products) {
      for (var v in p.variants) {
        tableData.add([
          p.productName,
          v.size,
          v.quantity.toString(),
          '${settings.currencySymbol}${v.price.toStringAsFixed(2)}',
          '${settings.currencySymbol}${(v.price * v.quantity).toStringAsFixed(2)}',
        ]);
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: _theme,
        header: (context) {
          return _buildReportHeader(
            'Inventory Valuation Report',
            company,
            '',
            settings,
          );
        },
        build: (context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Cost Value: ${settings.currencySymbol}${(valuation['costValue'] ?? 0).toStringAsFixed(2)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Retail Value: ${settings.currencySymbol}${(valuation['retailValue'] ?? 0).toStringAsFixed(2)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Potential Profit: ${settings.currencySymbol}${(valuation['potentialProfit'] ?? 0).toStringAsFixed(2)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              context: context,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              headers: ['Product', 'Size', 'Qty', 'Price', 'Value'],
              data: tableData,
            ),
          ];
        },
      ),
    );
    return pdf;
  }
}
