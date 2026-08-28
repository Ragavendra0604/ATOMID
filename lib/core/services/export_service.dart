import 'dart:math' as math;

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
import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/domain/document_totals.dart';
import 'package:atomid/domain/price_tag_job.dart';
import 'package:atomid/domain/price_tag_size.dart';

class ExportService {
  static pw.Font? _cachedRegularFont;
  static pw.Font? _cachedBoldFont;

  /// Faces covering the scripts the main font does not.
  ///
  /// Roboto — and every Google font offered in the invoice settings — carries
  /// no Tamil or Devanagari glyphs, so a shop name, address or footer typed in
  /// either script printed as nothing at all: the pdf package logged "Unable
  /// to find a font to draw" once per character and left a blank. These faces
  /// are handed to every theme as `fontFallback`, which the widget layer walks
  /// in order for any rune the main face cannot draw. Latin text never reaches
  /// them, so existing invoices are set exactly as before.
  ///
  /// Regular cuts only: the fallback search takes the first face that has the
  /// glyph and does not weight-match, so shipping a bold cut would add a
  /// megabyte to the bundle that nothing would ever select. Indic text in a
  /// bold run is drawn at regular weight.
  ///
  /// To cover another script, drop its Noto face in `assets/fonts/` and add
  /// the path to [_fallbackFontAssets].
  static const List<String> _fallbackFontAssets = [
    'assets/fonts/NotoSansTamil-Regular.ttf',
    'assets/fonts/NotoSansDevanagari-Regular.ttf',
  ];

  static final List<pw.Font> _fallbackFonts = [];
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

    for (final asset in _fallbackFontAssets) {
      // A missing or unreadable face must not stop an invoice printing: the
      // document is still correct in Latin without it.
      try {
        _fallbackFonts.add(pw.Font.ttf(await rootBundle.load(asset)));
      } catch (_) {}
    }

    // Italic is mapped to the regular face rather than left unset.
    //
    // Unset, the pdf package falls back to built-in Helvetica-Oblique, which
    // has no Unicode support — so an italic run containing ₹, or any Indic
    // script, renders as blanks. The only italic text in these documents is
    // the invoice footer, which the shopkeeper writes themselves, so that is
    // precisely where non-ASCII shows up. There is no bundled Roboto-Italic;
    // an upright footer is a small loss next to a footer of empty boxes.
    _cachedTheme = _themeWithFallback(_cachedRegularFont!, _cachedBoldFont!);

    // try/catch rather than `.catchError`, which hangs here forever.
    //
    // `rootBundle.load` returns a `SynchronousFuture` when the bundle can
    // answer without going to the platform, and `SynchronousFuture.catchError`
    // is implemented as `Completer().future` — a future that is never
    // completed. Awaiting it never returns, so the previous form deadlocked
    // this method, and with it every invoice, receipt and report the app can
    // produce. It survived because the success path is what looks tested: the
    // asset is present, nothing throws, and the await simply never finishes.
    try {
      final logoBytes = await rootBundle.load('assets/images/logo.png');
      if (logoBytes.lengthInBytes > 0) {
        _cachedLogo = pw.MemoryImage(logoBytes.buffer.asUint8List());
      }
    } catch (_) {
      // No bundled logo. Documents fall back to the company name.
      _cachedLogo = null;
    }

    _resourcesLoaded = true;
  }

  static Future<pw.ThemeData> _getTheme(String fontName) async {
    if (_cachedThemes.containsKey(fontName)) {
      return _cachedThemes[fontName]!;
    }

    pw.Font regular;
    pw.Font bold;

    // Roboto ships in the bundle, so it must never take the network path.
    //
    // It used to fall through to `PdfGoogleFonts.robotoRegular()` with the
    // rest, which meant the *default* font — what almost every shop prints
    // with — put an HTTP fetch in front of every invoice, only to fall back to
    // the byte-identical file already sitting in `_cachedRegularFont`. On a
    // till with no connection that is a wasted round-trip before each receipt;
    // on a captive-portal or half-open network it is a print that hangs
    // instead of failing. An offline-first app should not reach for the
    // network to render its own default.
    if (fontName == 'Roboto') {
      final theme = _themeWithFallback(_cachedRegularFont!, _cachedBoldFont!);
      _cachedThemes[fontName] = theme;
      return theme;
    }

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
        default:
          // An unrecognised name — a settings record from a newer build, or
          // one hand-edited. Bundled Roboto rather than a fetch for a font
          // this version has no case for.
          regular = _cachedRegularFont!;
          bold = _cachedBoldFont!;
          break;
      }
    } catch (_) {
      // The fetch failed — this app is offline-first, so that is routine,
      // not exceptional. Fall back to bundled Roboto for *this* document,
      // but do not cache it under the requested font's key: that would lock
      // every later invoice to Roboto for the rest of the session, even
      // after connectivity came back, because the cache never retries.
      return _themeWithFallback(_cachedRegularFont!, _cachedBoldFont!);
    }

    final theme = _themeWithFallback(regular, bold);
    _cachedThemes[fontName] = theme;
    return theme;
  }

  /// A theme for [regular]/[bold] that can also draw the fallback scripts.
  ///
  /// Every theme in this file is built here so no document can be created
  /// without the fallback list attached.
  static pw.ThemeData _themeWithFallback(pw.Font regular, pw.Font bold) {
    return pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
      fontFallback: _fallbackFonts,
    );
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
                  // Explicit font: BarcodeWidget otherwise draws its
                  // human-readable line in built-in Courier, which is both
                  // inconsistent with the rest of the tag and warns on every
                  // build. Code128 data is ASCII by construction, so this is
                  // typography rather than correctness.
                  textStyle: pw.TextStyle(
                    font: _cachedRegularFont,
                    fontSize: 10,
                    letterSpacing: 2,
                  ),
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

  /// Makes a caller's label safe to use as a file name on every platform.
  ///
  /// Export names are built from free text — `ATOMID_<productCode>_<size>_…`.
  /// A variant sized `1/2 kg` or `L/XL` turns that into a path containing a
  /// directory that does not exist, and `12"` is illegal on Windows. Either
  /// way the write throws and the shop sees an export fail for a product
  /// whose only sin was a realistic size.
  ///
  /// Windows has the strictest rules of the three platforms, so they are
  /// applied everywhere: the same product then exports under the same name on
  /// the till, the phone and the tablet.
  static String safeFileName(
    String value, {
    String fallback = 'atomid-export',
  }) {
    var name = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Windows silently strips a trailing dot or space, so a name ending in
    // one resolves to something other than what was asked for.
    name = name.replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');

    // Reserved device names, which cannot be used even with an extension.
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$',
      caseSensitive: false,
    ).hasMatch(name)) {
      name = '_$name';
    }

    if (name.isEmpty) return fallback;

    // Leaves room for the directory, the extension and the path limit.
    return name.length <= 120 ? name : name.substring(0, 120);
  }

  static Future<PlatformFile> exportPdf(
    pw.Document pdf,
    String fileName,
  ) async {
    if (kIsWeb) throw UnsupportedError('File export is not supported on Web');
    final dir = await _getExportDirectory('PDF');
    final file = PlatformFile('${dir.path}/${safeFileName(fileName)}.pdf');
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
    final file = PlatformFile('${dir.path}/${safeFileName(fileName)}.png');

    var rendered = false;
    await for (var page in Printing.raster(await pdf.save(), dpi: dpi)) {
      final pngData = await page.toPng();
      await file.writeAsBytes(pngData);
      rendered = true;
      break; // Only export the first page for single tags
    }

    // Raster yields nothing for an empty document. Returning the handle
    // anyway meant the caller went straight on to share a path with no file
    // behind it, and the share sheet failed with nothing explaining why.
    if (!rendered) {
      throw const AppException('There was nothing to export.');
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

  /// Lays tags out on printed sheets, packed continuously.
  ///
  /// Tags flow from one line into the next without a page break between
  /// products, so a sheet is filled before another is started. Printing five
  /// products used to cost five part-empty sheets.
  /// A page format that a sheet document can actually be laid out on.
  ///
  /// A print dialog can report a continuous roll — `PdfPageFormat.roll80` and
  /// friends carry `double.infinity` as their height — and `MultiPage` asserts
  /// a finite height, so honouring such a format verbatim would throw instead
  /// of printing. A sheet document falls back to its configured size rather
  /// than failing when someone sends an invoice to a receipt printer.
  static PdfPageFormat _sheetOrFallback(
    PdfPageFormat? format,
    PdfPageFormat fallback,
  ) {
    if (format == null) return fallback;
    final usable =
        format.width.isFinite &&
        format.width > 0 &&
        format.height.isFinite &&
        format.height > 0;
    return usable ? format : fallback;
  }

  static Future<pw.Document> generateBulkSheetPdf(
    List<PriceTagLine> lines,
    SettingsModel settings,
    CompanyModel company, {
    PriceTagSize tagSize = PriceTagSize.medium,
    PdfPageFormat? pageFormat,
  }) async {
    await _ensureResourcesLoaded();
    final pdf = pw.Document();
    final logoImage = tagSize.showLogo ? await _getCompanyLogo(company) : null;

    final tags = <PriceTagLine>[];
    for (final line in lines) {
      for (var i = 0; i < line.quantity; i++) {
        tags.add(
          PriceTagLine(
            product: line.product,
            variant: line.variant,
            quantity: 1,
          ),
        );
      }
    }
    if (tags.isEmpty) return pdf;

    // Derived from the page actually being printed — the format the print
    // dialog reports when there is one, the configured size otherwise. These
    // were fixed at A4's 595 x 842 regardless, so a shorter sheet lost the
    // bottom row of every page.
    final sheetFormat = _sheetOrFallback(
      pageFormat,
      settings.pdfPageSize == 'Letter'
          ? PdfPageFormat.letter
          : PdfPageFormat.a4,
    );

    final double tagWidth = sheetFormat.width / tagSize.columns;
    final double tagHeight = sheetFormat.height / tagSize.rows;

    final perPage = tagSize.perPage;
    final pages = (tags.length / perPage).ceil();

    for (var i = 0; i < pages; i++) {
      final startIndex = i * perPage;
      final endIndex = (startIndex + perPage > tags.length)
          ? tags.length
          : startIndex + perPage;
      final pageTags = tags.sublist(startIndex, endIndex);

      pdf.addPage(
        pw.Page(
          pageFormat: sheetFormat,
          margin: const pw.EdgeInsets.all(0),
          theme: _theme,
          build: (pw.Context context) {
            return pw.Wrap(
              children: pageTags
                  .map(
                    (tag) => _buildBulkTag(
                      tag: tag,
                      tagSize: tagSize,
                      width: tagWidth,
                      height: tagHeight,
                      logoImage: logoImage,
                      settings: settings,
                    ),
                  )
                  .toList(),
            );
          },
        ),
      );
    }
    return pdf;
  }

  /// One tag in the bulk sheet.
  ///
  /// The rows are spaced evenly rather than pushed apart by a single
  /// [pw.Spacer], which used to collect every spare point into one gap above
  /// the price and leave the tag looking half empty on the taller sizes.
  static pw.Widget _buildBulkTag({
    required PriceTagLine tag,
    required PriceTagSize tagSize,
    required double width,
    required double height,
    required pw.ImageProvider? logoImage,
    required SettingsModel settings,
  }) {
    final product = tag.product;
    final variant = tag.variant;

    final nameText = pw.Text(
      product.productName,
      style: pw.TextStyle(
        fontSize: tagSize.nameFontSize,
        fontWeight: pw.FontWeight.bold,
      ),
      maxLines: 1,
      textAlign: pw.TextAlign.center,
    );

    // On the short sizes the logo shares the name's row: a row of its own
    // would cost more height than the barcode can spare.
    final pw.Widget header = (logoImage != null && tagSize.logoInline)
        ? pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Image(
                logoImage,
                width: tagSize.logoSize,
                height: tagSize.logoSize,
                fit: pw.BoxFit.contain,
              ),
              pw.SizedBox(width: tagSize.padding),
              pw.Flexible(child: nameText),
            ],
          )
        : pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logoImage != null) ...[
                pw.Image(
                  logoImage,
                  width: tagSize.logoSize,
                  height: tagSize.logoSize,
                  fit: pw.BoxFit.contain,
                ),
                pw.SizedBox(height: tagSize.padding / 2),
              ],
              nameText,
            ],
          );

    // The barcode is the one element that must not shrink, so it keeps its
    // configured size and the remaining height is shared by the text rows.
    final barcodeWidth = math.min(
      tagSize.barcodeWidth,
      width - tagSize.padding * 2,
    );

    return pw.Container(
      width: width,
      height: height,
      padding: pw.EdgeInsets.all(tagSize.padding),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
        children: [
          header,
          pw.Text(
            product.productCode,
            style: pw.TextStyle(
              fontSize: tagSize.codeFontSize,
              color: PdfColors.grey700,
            ),
            maxLines: 1,
          ),
          pw.Text(
            'Size: ${variant.size}',
            style: pw.TextStyle(
              fontSize: tagSize.sizeFontSize,
              fontWeight: pw.FontWeight.bold,
            ),
            maxLines: 1,
          ),
          pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: variant.barcode,
            width: barcodeWidth,
            height: tagSize.barcodeHeight,
            drawText: true,
            textStyle: pw.TextStyle(
              font: _cachedRegularFont,
              fontSize: tagSize.barcodeTextSize,
              letterSpacing: 1,
            ),
          ),
          pw.Text(
            '${settings.currencySymbol}${variant.price.toStringAsFixed(2)}',
            style: pw.TextStyle(
              fontSize: tagSize.priceFontSize,
              fontWeight: pw.FontWeight.bold,
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  /// Builds the A4/Letter tax invoice.
  ///
  /// [pageFormat] overrides the size stored in settings and must be passed the
  /// format the print dialog reports. Laying the document out at A4 and then
  /// handing it to a print job whose paper is something else leaves the
  /// platform to scale or crop it, which is why a printed invoice could come
  /// out squeezed while the on-screen preview looked correct.
  static Future<pw.Document> generateInvoicePdf(
    import_sale.Sale sale,
    SettingsModel settings,
    CompanyModel company,
    InvoiceSettingsModel invoiceSettings, {
    PdfPageFormat? pageFormat,
  }) async {
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

    final sellerLegal = sale.sellerLegalName.isNotEmpty
        ? sale.sellerLegalName
        : (company.name.isNotEmpty ? company.name : 'ATOMID STORE');
    final sellerGstin = sale.sellerGstin.isNotEmpty
        ? sale.sellerGstin
        : company.gstNumber;
    final sellerState = sale.sellerState.isNotEmpty
        ? sale.sellerState
        : company.state;
    final sellerStateCode = sale.sellerStateCode.isNotEmpty
        ? sale.sellerStateCode
        : company.stateCode;
    final sellerAddr = sale.sellerAddress.isNotEmpty
        ? sale.sellerAddress
        : company.address;

    final docTitle = sale.documentType.isNotEmpty
        ? sale.documentType
        : (sellerGstin.isNotEmpty ? 'TAX INVOICE' : 'BILL OF SUPPLY');

    // HSN aggregation from snapshot lines
    final hsnMap = <String, Map<String, dynamic>>{};
    for (final item in sale.items) {
      final key = item.hsn.isNotEmpty ? item.hsn : 'General';
      final entry = hsnMap.putIfAbsent(
        key,
        () => {
          'hsn': key,
          'uqc': item.uqc.isNotEmpty ? item.uqc : 'PCS',
          'taxable': 0.0,
          'cgst': 0.0,
          'sgst': 0.0,
          'utgst': 0.0,
          'igst': 0.0,
          'cess': 0.0,
          'totalTax': 0.0,
        },
      );
      entry['taxable'] = (entry['taxable'] as double) + item.taxableValue;
      entry['cgst'] = (entry['cgst'] as double) + item.cgstAmount;
      entry['sgst'] = (entry['sgst'] as double) + item.sgstAmount;
      entry['utgst'] = (entry['utgst'] as double) + item.utgstAmount;
      entry['igst'] = (entry['igst'] as double) + item.igstAmount;
      entry['cess'] = (entry['cess'] as double) + item.cessAmount;
      entry['totalTax'] =
          (entry['totalTax'] as double) +
          (item.cgstAmount +
              item.sgstAmount +
              item.utgstAmount +
              item.igstAmount +
              item.cessAmount);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: _sheetOrFallback(
          pageFormat,
          settings.pdfPageSize == 'Letter'
              ? PdfPageFormat.letter
              : PdfPageFormat.a4,
        ),
        theme: theme,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return [
            // Top Document Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logoImage != null)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(right: 12),
                        child: pw.Image(logoImage, width: 64, height: 64),
                      ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          sellerLegal,
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if (company.tradeName.isNotEmpty &&
                            company.tradeName != sellerLegal)
                          pw.Text(
                            '(${company.tradeName})',
                            style: const pw.TextStyle(
                              fontSize: 11,
                              color: PdfColors.grey700,
                            ),
                          ),
                        if (sellerAddr.isNotEmpty)
                          pw.Text(
                            sellerAddr,
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        if (sellerState.isNotEmpty)
                          pw.Text(
                            'State: $sellerState${sellerStateCode.isNotEmpty ? " (Code: $sellerStateCode)" : ""}',
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        if (sellerGstin.isNotEmpty)
                          pw.Text(
                            'GSTIN: $sellerGstin',
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        if (company.phone1.isNotEmpty)
                          pw.Text(
                            'Phone: ${company.phone1}',
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey200,
                        borderRadius: pw.BorderRadius.all(
                          pw.Radius.circular(4),
                        ),
                      ),
                      child: pw.Text(
                        docTitle.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey800,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Invoice #: ${sale.invoiceNumber}',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                    pw.Text(
                      'Date: ${sale.date.year}-${sale.date.month.toString().padLeft(2, '0')}-${sale.date.day.toString().padLeft(2, '0')}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    if (sale.placeOfSupply.isNotEmpty)
                      pw.Text(
                        'Place of Supply: ${sale.placeOfSupply}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    pw.Text(
                      'Reverse Charge: No',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 6),

            // Billed To / Customer Section
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Billed To (Customer / Consignee):',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.Text(
                        sale.customerName.isNotEmpty
                            ? sale.customerName
                            : 'Walk-In Customer',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (sale.customerAddress.isNotEmpty)
                        pw.Text(
                          sale.customerAddress,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      if (sale.customerState.isNotEmpty)
                        pw.Text(
                          'State: ${sale.customerState}${sale.customerStateCode.isNotEmpty ? " (${sale.customerStateCode})" : ""}',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      if (sale.customerPhone.isNotEmpty)
                        pw.Text(
                          'Phone: ${sale.customerPhone}',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                    ],
                  ),
                  if (sale.customerGstin.isNotEmpty)
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'Customer GSTIN:',
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.Text(
                          sale.customerGstin,
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Items Table
            pw.TableHelper.fromTextArray(
              context: context,
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                bottom: pw.BorderSide(color: PdfColors.grey400, width: 1),
              ),
              headerAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              cellHeight: 22,
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.center,
                2: pw.Alignment.center,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.center,
                7: pw.Alignment.centerRight,
                8: pw.Alignment.centerRight,
              },
              headers: [
                'Item Description',
                'HSN',
                'Qty',
                'Rate',
                'Disc',
                'Taxable',
                'GST %',
                'Tax',
                'Total',
              ],
              data: sale.items.map((item) {
                final taxAmt =
                    item.cgstAmount +
                    item.sgstAmount +
                    item.utgstAmount +
                    item.igstAmount +
                    item.cessAmount;
                final rateStr = item.gstRate != null
                    ? '${Fmt.amount(item.gstRate!)}%'
                    : '0%';
                return [
                  '${item.productName} (${item.variantSize})',
                  item.hsn.isNotEmpty ? item.hsn : '-',
                  '${item.quantity} ${item.uqc.isNotEmpty ? item.uqc : "PCS"}',
                  Fmt.money(item.price, settings.currencySymbol),
                  item.discountAmount > 0
                      ? Fmt.money(item.discountAmount, settings.currencySymbol)
                      : '-',
                  Fmt.money(
                    item.taxableValue > 0 ? item.taxableValue : item.total,
                    settings.currencySymbol,
                  ),
                  rateStr,
                  taxAmt > 0 ? Fmt.money(taxAmt, settings.currencySymbol) : '-',
                  Fmt.money(item.total, settings.currencySymbol),
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 12),

            // Summary Totals
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  flex: 5,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Payment Mode: ${sale.paymentMethod}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      if (sale.notes.isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 4),
                          child: pw.Text(
                            'Notes: ${sale.notes}',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                      if (invoiceSettings.termsAndConditions.isNotEmpty) ...[
                        pw.SizedBox(height: 6),
                        pw.Text(
                          'Terms & Conditions:',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          invoiceSettings.termsAndConditions,
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                      ],
                    ],
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  flex: 5,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Column(
                      children: [
                        _buildPdfSummaryRow(
                          'Gross Subtotal',
                          Fmt.money(sale.subtotal, settings.currencySymbol),
                        ),
                        if (sale.discountAmount > 0)
                          _buildPdfSummaryRow(
                            'Discount (${sale.discountPercent.toStringAsFixed(2)}%)',
                            '-${Fmt.money(sale.discountAmount, settings.currencySymbol)}',
                          ),
                        if (sale.rewardDiscountAmount > 0)
                          _buildPdfSummaryRow(
                            'Reward Discount',
                            '-${Fmt.money(sale.rewardDiscountAmount, settings.currencySymbol)}',
                          ),
                        if (sale.taxableAmount > 0)
                          _buildPdfSummaryRow(
                            'Taxable Value',
                            Fmt.money(
                              sale.taxableAmount,
                              settings.currencySymbol,
                            ),
                          ),
                        if (sale.isInterState) ...[
                          if (sale.igstAmount > 0)
                            _buildPdfSummaryRow(
                              'IGST',
                              Fmt.money(
                                sale.igstAmount,
                                settings.currencySymbol,
                              ),
                            ),
                        ] else ...[
                          if (sale.cgstAmount > 0)
                            _buildPdfSummaryRow(
                              'CGST',
                              Fmt.money(
                                sale.cgstAmount,
                                settings.currencySymbol,
                              ),
                            ),
                          if (sale.utgstAmount > 0)
                            _buildPdfSummaryRow(
                              'UTGST',
                              Fmt.money(
                                sale.utgstAmount,
                                settings.currencySymbol,
                              ),
                            )
                          else if (sale.sgstAmount > 0)
                            _buildPdfSummaryRow(
                              'SGST',
                              Fmt.money(
                                sale.sgstAmount,
                                settings.currencySymbol,
                              ),
                            ),
                        ],
                        if (sale.cessAmount > 0)
                          _buildPdfSummaryRow(
                            'Cess',
                            Fmt.money(sale.cessAmount, settings.currencySymbol),
                          ),
                        if (sale.roundOff != 0.0)
                          _buildPdfSummaryRow(
                            'Round-Off',
                            '${sale.roundOff >= 0 ? "+" : ""}${Fmt.money(sale.roundOff, settings.currencySymbol)}',
                          ),
                        pw.Divider(thickness: 1, color: PdfColors.grey400),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'Total Payable',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            pw.Text(
                              Fmt.money(
                                sale.grandTotal,
                                settings.currencySymbol,
                              ),
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 12,
                                color: PdfColors.blue900,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // Optional HSN Summary Table
            if (settings.showHsnSummary && hsnMap.isNotEmpty) ...[
              pw.Text(
                'HSN / SAC Tax Summary',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.TableHelper.fromTextArray(
                context: context,
                border: const pw.TableBorder(
                  horizontalInside: pw.BorderSide(
                    color: PdfColors.grey300,
                    width: 0.5,
                  ),
                  bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                ),
                headerAlignment: pw.Alignment.centerLeft,
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 7,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellHeight: 16,
                cellStyle: const pw.TextStyle(fontSize: 7),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                },
                headers: [
                  'HSN',
                  'Taxable Value',
                  'CGST',
                  'SGST/UTGST',
                  'IGST',
                  'Total Tax',
                ],
                data: hsnMap.values.map((h) {
                  return [
                    h['hsn'] as String,
                    Fmt.money(h['taxable'] as double, settings.currencySymbol),
                    Fmt.money(h['cgst'] as double, settings.currencySymbol),
                    Fmt.money(
                      ((h['sgst'] as double) + (h['utgst'] as double)),
                      settings.currencySymbol,
                    ),
                    Fmt.money(h['igst'] as double, settings.currencySymbol),
                    Fmt.money(h['totalTax'] as double, settings.currencySymbol),
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 12),
            ],

            // Bottom Footer and UPI QR
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
                          fontSize: 8,
                        ),
                      ),
                      if (invoiceSettings.upiId.isNotEmpty)
                        pw.Text(
                          invoiceSettings.upiId,
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      pw.SizedBox(height: 2),
                      pw.Image(upiQrImage, width: 60, height: 60),
                    ],
                  )
                else
                  pw.SizedBox(),
                if (invoiceSettings.showSignature)
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'For $sellerLegal',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 28),
                      pw.Text(
                        'Authorized Signatory',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  )
                else
                  pw.SizedBox(),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                invoiceSettings.footerText.isNotEmpty
                    ? invoiceSettings.footerText
                    : 'Thank you for shopping with us!',
                style: pw.TextStyle(
                  fontStyle: pw.FontStyle.italic,
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ),
          ];
        },
      ),
    );
    return pdf;
  }

  static pw.Widget _buildPdfSummaryRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
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
    // Same switch as the sheet invoice. It used to be read only there, so a
    // shop that turned the logo on saw it on the A4 and never on the roll.
    final logoImage = invoiceSettings.showCompanyLogo
        ? await _getCompanyLogo(company)
        : null;

    final is58mm = settings.thermalReceiptSize == '58mm';
    final format = is58mm ? PdfPageFormat.roll57 : PdfPageFormat.roll80;

    final sellerLegal = sale.sellerLegalName.isNotEmpty
        ? sale.sellerLegalName
        : (company.name.isNotEmpty ? company.name : settings.companyName);
    final sellerGstin = sale.sellerGstin.isNotEmpty
        ? sale.sellerGstin
        : company.gstNumber;

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        theme: theme,
        margin: const pw.EdgeInsets.all(8),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              if (logoImage != null) ...[
                pw.Image(logoImage, height: is58mm ? 28 : 36),
                pw.SizedBox(height: 4),
              ],
              pw.Text(
                sellerLegal,
                style: pw.TextStyle(
                  fontSize: is58mm ? 12 : 14,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
              if (sellerGstin.isNotEmpty)
                pw.Text(
                  'GSTIN: $sellerGstin',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              if (sale.sellerAddress.isNotEmpty)
                pw.Text(
                  sale.sellerAddress,
                  style: const pw.TextStyle(fontSize: 7),
                  textAlign: pw.TextAlign.center,
                ),
              pw.SizedBox(height: 4),
              pw.Text(
                sale.documentType.isNotEmpty
                    ? sale.documentType
                    : 'TAX INVOICE',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Bill #: ${sale.invoiceNumber}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Date: ${sale.date.year}-${sale.date.month.toString().padLeft(2, '0')}-${sale.date.day.toString().padLeft(2, '0')} ${sale.date.hour.toString().padLeft(2, '0')}:${sale.date.minute.toString().padLeft(2, '0')}',
                style: const pw.TextStyle(fontSize: 7),
              ),
              if (sale.customerName.isNotEmpty &&
                  sale.customerName != 'Walk-In Customer')
                pw.Text(
                  'Customer: ${sale.customerName}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              if (sale.customerGstin.isNotEmpty)
                pw.Text(
                  'Customer GSTIN: ${sale.customerGstin}',
                  style: const pw.TextStyle(fontSize: 7),
                ),
              pw.SizedBox(height: 4),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              // Line Items
              ...sale.items.map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          '${item.productName} (${item.variantSize}) x${item.quantity}',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ),
                      pw.Text(
                        Fmt.money(item.total, settings.currencySymbol),
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                );
              }),

              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              // Totals
              _buildThermalRow(
                'Subtotal (Gross):',
                Fmt.money(sale.subtotal, settings.currencySymbol),
              ),
              if (sale.discountAmount > 0)
                _buildThermalRow(
                  'Discount (${sale.discountPercent.toStringAsFixed(1)}%):',
                  '-${Fmt.money(sale.discountAmount, settings.currencySymbol)}',
                ),
              if (sale.rewardDiscountAmount > 0)
                _buildThermalRow(
                  'Reward Discount:',
                  '-${Fmt.money(sale.rewardDiscountAmount, settings.currencySymbol)}',
                ),
              if (settings.showTaxOnThermalReceipt && sale.taxAmount > 0) ...[
                _buildThermalRow(
                  'Taxable Value:',
                  Fmt.money(sale.taxableAmount, settings.currencySymbol),
                ),
                if (sale.isInterState)
                  _buildThermalRow(
                    'IGST:',
                    Fmt.money(sale.igstAmount, settings.currencySymbol),
                  )
                else ...[
                  _buildThermalRow(
                    'CGST:',
                    Fmt.money(sale.cgstAmount, settings.currencySymbol),
                  ),
                  _buildThermalRow(
                    'SGST/UTGST:',
                    Fmt.money(
                      sale.sgstAmount + sale.utgstAmount,
                      settings.currencySymbol,
                    ),
                  ),
                ],
              ],
              if (sale.roundOff != 0.0)
                _buildThermalRow(
                  'Round-Off:',
                  '${sale.roundOff >= 0 ? "+" : ""}${Fmt.money(sale.roundOff, settings.currencySymbol)}',
                ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'NET PAYABLE:',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    Fmt.money(sale.grandTotal, settings.currencySymbol),
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),
              pw.Text(
                'Paid by ${sale.paymentMethod}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              if (upiQrImage != null) ...[
                pw.SizedBox(height: 4),
                pw.Image(upiQrImage, width: 60, height: 60),
                if (invoiceSettings.upiId.isNotEmpty)
                  pw.Text(
                    invoiceSettings.upiId,
                    style: const pw.TextStyle(fontSize: 7),
                  ),
              ],
              if (invoiceSettings.termsAndConditions.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Divider(borderStyle: pw.BorderStyle.dashed),
                pw.Text(
                  invoiceSettings.termsAndConditions,
                  style: const pw.TextStyle(fontSize: 6),
                  textAlign: pw.TextAlign.center,
                ),
              ],
              if (invoiceSettings.showSignature) ...[
                pw.SizedBox(height: 6),
                pw.Text(
                  'For $sellerLegal',
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 18),
                pw.Text(
                  'Authorized Signatory',
                  style: const pw.TextStyle(fontSize: 7),
                ),
              ],
              pw.SizedBox(height: 4),
              pw.Text(
                invoiceSettings.footerText.isNotEmpty
                    ? invoiceSettings.footerText
                    : 'Thank you for your visit!',
                style: const pw.TextStyle(
                  fontSize: 7,
                  fontStyle: pw.FontStyle.italic,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 12),
            ],
          );
        },
      ),
    );
    return pdf;
  }

  static pw.Widget _buildThermalRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
          pw.Text(value, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  static Future<pw.Document> generateSalesReportPdf(
    List<import_sale.Sale> sales,
    String timeframe,
    SettingsModel settings,
    CompanyModel company,
  ) async {
    await _ensureResourcesLoaded();
    final pdf = pw.Document();

    // Computed by DocumentTotals so the printed figure and the tested one
    // cannot drift apart; see test/unit/document_totals_test.dart.
    final double totalRevenue = DocumentTotals.salesRevenue(sales);
    final int totalItems = DocumentTotals.salesUnits(sales);

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

    final double totalCost = DocumentTotals.purchaseCost(purchases);
    final int totalItems = DocumentTotals.purchaseUnits(purchases);

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
