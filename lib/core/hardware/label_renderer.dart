import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:atomid/data/models/settings_model.dart';
import 'label_printer_profile.dart';
import 'package:atomid/domain/price_tag_job.dart';
import 'package:atomid/core/utils/formatters.dart';

class LabelRenderer {
  final LabelPrinterProfile profile;
  final SettingsModel settings;
  final pw.Font defaultFont;
  final pw.MemoryImage? logoImage;

  LabelRenderer({
    required this.profile,
    required this.settings,
    required this.defaultFont,
    this.logoImage,
  });

  pw.Widget buildLabelContent(PriceTagLine tag) {
    final product = tag.product;
    final variant = tag.variant;

    // ── Guard: label dimensions too small ────────────────────────────
    if (profile.labelWidthMm < 20 || profile.labelHeightMm < 15) {
      throw Exception(
        'Label dimensions (${profile.labelWidthMm}×${profile.labelHeightMm} mm) '
        'are too small. Minimum is 20×15 mm.',
      );
    }

    final width = math.max(0.0, profile.labelWidthMm * PdfPageFormat.mm);
    final height = math.max(0.0, profile.labelHeightMm * PdfPageFormat.mm);

    // Generous safe margin to prevent elements from looking cramped
    final safeMargin = 2.5 * PdfPageFormat.mm;
    final safeWidth = math.max(0.0, width - (safeMargin * 2));
    final safeHeight = math.max(0.0, height - (safeMargin * 2));

    // ── Edge-case: product name ──────────────────────────────────────
    final displayName = product.productName.trim().isNotEmpty
        ? product.productName.trim()
        : 'Unnamed Product';

    // ── Edge-case: barcode ───────────────────────────────────────────
    // Code128 accepts ASCII 0–127. Replace anything outside that range
    // so the barcode widget never throws on unexpected input.
    final rawBarcode = variant.barcode.trim();
    final hasBarcode = rawBarcode.isNotEmpty;
    final safeBarcode = hasBarcode
        ? rawBarcode.replaceAll(RegExp(r'[^\x00-\x7F]'), '?')
        : '00000';
    final barcodeDisplayText = hasBarcode ? rawBarcode : '';

    // ── Proportional vertical budget ─────────────────────────────────
    // Allocate the available height to each section as a fraction so the
    // layout scales without clipping for any label height.
    //
    //   Product + Size   : 50 %
    //   Barcode + text   : 30 %
    //   Price            : 20 %
    //
    // The 0.5mm spacing between sections is taken from each section's
    // own budget, so the sum never exceeds safeHeight.

    final double nameFraction = 0.40;
    final double barcodeFraction = 0.35;
    final double priceFraction = 0.25;

    final spacing = 0.5 * PdfPageFormat.mm;

    final nameSectionH = safeHeight * nameFraction;
    final barcodeSectionH = safeHeight * barcodeFraction;
    final priceSectionH = safeHeight * priceFraction;

    // Barcode graphic gets most of its section, minus room for text below it.
    // Guard against sections so small they'd produce a zero/negative height.
    final barcodeTextH = math.min(3.0 * PdfPageFormat.mm, barcodeSectionH * 0.30);
    final barcodeGraphicH = math.max(1.0, barcodeSectionH - barcodeTextH - spacing);

    return pw.Container(
      width: width,
      height: height,
      padding: pw.EdgeInsets.all(safeMargin),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.start,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // ── 1. PRODUCT NAME + SIZE ──────────────────────────────────
          pw.Container(
            height: nameSectionH,
            width: safeWidth,
            alignment: pw.Alignment.center,
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  displayName,
                  maxLines: 2,
                  style: pw.TextStyle(
                    font: defaultFont,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                if (variant.size.trim().isNotEmpty) ...[
                  pw.SizedBox(height: spacing),
                  pw.Text(
                    'Size: ${variant.size.trim()}',
                    maxLines: 1,
                    style: pw.TextStyle(
                      font: defaultFont,
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ],
            ),
          ),

          // ── 3. BARCODE (graphic) ────────────────────────────────────
          pw.Container(
            height: barcodeGraphicH,
            width: safeWidth,
            alignment: pw.Alignment.center,
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: safeBarcode,
              drawText: false,
            ),
          ),

          // ── 4. BARCODE (human-readable text) ────────────────────────
          if (barcodeDisplayText.isNotEmpty)
            pw.Container(
              height: barcodeTextH,
              width: safeWidth,
              alignment: pw.Alignment.center,
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                child: pw.Text(
                  barcodeDisplayText,
                  style: pw.TextStyle(font: defaultFont, fontSize: 6),
                ),
              ),
            )
          else
            pw.SizedBox(height: barcodeTextH),

          // ── 5. PRICE ────────────────────────────────────────────────
          pw.Container(
            height: priceSectionH,
            width: safeWidth,
            alignment: pw.Alignment.center,
            child: pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                Fmt.money(variant.price, settings.currencySymbol),
                style: pw.TextStyle(
                  font: defaultFont,
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
