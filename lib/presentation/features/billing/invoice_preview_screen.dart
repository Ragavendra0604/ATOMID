import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/core/services/export_service.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

class InvoicePreviewScreen extends ConsumerWidget {
  final Sale sale;

  const InvoicePreviewScreen({super.key, required this.sale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final invoiceSettings = ref.watch(invoiceSettingsProvider);
    final company = ref.watch(companyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
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
