import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/invoice_settings_model.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/core/services/export_service.dart';
import 'package:atomid/domain/invoice_template.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

/// Previews a completed sale and prints it.
///
/// The design is whatever the shop has set in Settings -> Invoice Template.
/// It is deliberately not selectable here: the counter should print the same
/// document on every bill, and one shop-wide choice is the only way that
/// stays true. Changing it is a settings decision, not a per-sale one.
class InvoicePreviewScreen extends ConsumerStatefulWidget {
  final Sale sale;

  const InvoicePreviewScreen({super.key, required this.sale});

  @override
  ConsumerState<InvoicePreviewScreen> createState() =>
      _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends ConsumerState<InvoicePreviewScreen> {
  Sale get sale => widget.sale;

  InvoiceTemplate get _template =>
      InvoiceTemplate.fromId(ref.read(settingsProvider).invoiceTemplate);

  /// Writes the invoice out under its own number and hands it to the OS
  /// share sheet.
  ///
  /// `PdfPreview` above already carries a share button, but it shares a
  /// temporary file under a generated name with no accompanying message. A
  /// shop sending a bill over WhatsApp needs the invoice number in the file
  /// name and the amount in the text — otherwise the customer receives
  /// `document.pdf` and cannot tell one bill from the next.
  Future<void> _shareInvoice(
    BuildContext context,
    SettingsModel settings,
    CompanyModel company,
    InvoiceSettingsModel invoiceSettings,
  ) async {
    // Captured before the first await: the screen can be popped while the
    // PDF is still rendering.
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pdf = await ExportService.generateInvoiceForTemplate(
        sale,
        settings,
        company,
        invoiceSettings,
        template: _template,
      );
      final file = await ExportService.exportPdf(
        pdf,
        'Invoice_${sale.invoiceNumber}',
      );
      final from = company.name.trim().isEmpty ? '' : ' from ${company.name}';
      if (!context.mounted) return;
      await ExportService.shareFile(
        context,
        file,
        'Invoice ${sale.invoiceNumber}$from — '
        '${Fmt.money(sale.grandTotal, settings.currencySymbol)}',
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not share the invoice: $error')),
      );
    }
  }

  Future<void> _downloadInvoice(
    SettingsModel settings,
    CompanyModel company,
    InvoiceSettingsModel invoiceSettings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pdf = await ExportService.generateInvoiceForTemplate(
        sale,
        settings,
        company,
        invoiceSettings,
        template: _template,
      );
      final file = await ExportService.exportPdf(
        pdf,
        'Invoice_${sale.invoiceNumber}',
      );
      messenger.showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not download the invoice: $error')),
      );
    }
  }

  Future<void> _print(
    SettingsModel settings,
    CompanyModel company,
    InvoiceSettingsModel invoiceSettings,
  ) async {
    final template = _template;
    // Built inside onLayout so a sheet invoice is laid out for the paper the
    // print dialog actually reports. A till roll has its own fixed width and
    // ignores that format.
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        final pdf = await ExportService.generateInvoiceForTemplate(
          sale,
          settings,
          company,
          invoiceSettings,
          template: template,
          pageFormat: format,
        );
        return pdf.save();
      },
      name: template.isThermal
          ? 'Receipt_${sale.invoiceNumber}'
          : 'Invoice_${sale.invoiceNumber}',
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final invoiceSettings = ref.watch(invoiceSettingsProvider);
    final company = ref.watch(companyProvider);
    // Watched rather than read here, so changing the shop default in
    // Settings is reflected in an already-open preview.
    final template = InvoiceTemplate.fromId(settings.invoiceTemplate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Details'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Share invoice',
              icon: const Icon(Icons.share),
              onPressed: () =>
                  _shareInvoice(ctx, settings, company, invoiceSettings),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PdfPreview(
              // Rebuilt when the template changes: PdfPreview caches by key.
              key: ValueKey(template),
              build: (format) => ExportService.generateInvoiceForTemplate(
                sale,
                settings,
                company,
                invoiceSettings,
                template: template,
                pageFormat: format,
              ).then((pdf) => pdf.save()),
              allowPrinting: true,
              allowSharing: true,
              canChangeOrientation: false,
              canChangePageFormat: false,
              // A sheet invoice is a sheet, never an 80mm till roll. The old
              // fallback sent every non-A4 shop (Letter) to roll80.
              initialPageFormat: template.isThermal
                  ? (settings.thermalReceiptSize == '58mm'
                        ? PdfPageFormat.roll57
                        : PdfPageFormat.roll80)
                  : (settings.pdfPageSize == 'Letter'
                        ? PdfPageFormat.letter
                        : PdfPageFormat.a4),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).cardColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _print(settings, company, invoiceSettings),
                  icon: Icon(
                    template.isThermal
                        ? Icons.receipt_long
                        : Icons.picture_as_pdf,
                  ),
                  label: Text('Print ${template.label}'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _downloadInvoice(settings, company, invoiceSettings),
                  icon: const Icon(Icons.download),
                  label: const Text('Download PDF'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
