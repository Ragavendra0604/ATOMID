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
import 'package:atomid/presentation/providers/app_providers.dart';

class InvoicePreviewScreen extends ConsumerWidget {
  final Sale sale;

  const InvoicePreviewScreen({super.key, required this.sale});

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
      final pdf = await ExportService.generateInvoicePdf(
        sale,
        settings,
        company,
        invoiceSettings,
      );
      final file = await ExportService.exportPdf(
        pdf,
        'Invoice_${sale.invoiceNumber}',
      );
      final from = company.name.trim().isEmpty ? '' : ' from ${company.name}';
      await ExportService.shareFile(
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final invoiceSettings = ref.watch(invoiceSettingsProvider);
    final company = ref.watch(companyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Details'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Share invoice',
            icon: const Icon(Icons.share),
            onPressed: () =>
                _shareInvoice(context, settings, company, invoiceSettings),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PdfPreview(
              build: (format) => ExportService.generateInvoicePdf(
                sale,
                settings,
                company,
                invoiceSettings,
              ).then((pdf) => pdf.save()),
              allowPrinting: true,
              allowSharing: true,
              canChangeOrientation: false,
              canChangePageFormat: false,
              initialPageFormat: settings.pdfPageSize == 'A4'
                  ? PdfPageFormat.a4
                  : PdfPageFormat.roll80,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).cardColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    final pdf = await ExportService.generateThermalReceiptPdf(
                      sale,
                      settings,
                      company,
                      invoiceSettings,
                    );
                    await Printing.layoutPdf(
                      onLayout: (PdfPageFormat format) async => pdf.save(),
                      name: 'Receipt_${sale.invoiceNumber}',
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Thermal Receipt'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final pdf = await ExportService.generateInvoicePdf(
                      sale,
                      settings,
                      company,
                      invoiceSettings,
                    );
                    await Printing.layoutPdf(
                      onLayout: (PdfPageFormat format) async => pdf.save(),
                      name: 'Invoice_${sale.invoiceNumber}',
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('A4 Invoice'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
