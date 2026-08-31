import 'package:flutter/material.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/features/billing/invoice_preview_screen.dart';
import 'package:atomid/core/services/export_service.dart';
import 'package:atomid/domain/invoice_template.dart';
import 'package:atomid/data/models/sale_model.dart';

class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  ConsumerState<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  String _searchQuery = '';

  Future<void> _shareSale(BuildContext context, Sale sale) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final settings = ref.read(settingsProvider);
      final company = ref.read(companyProvider);
      final invoiceSettings = ref.read(invoiceSettingsProvider);
      final template = InvoiceTemplate.fromId(settings.invoiceTemplate);

      final pdf = await ExportService.generateInvoiceForTemplate(
        sale,
        settings,
        company,
        invoiceSettings,
        template: template,
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

  @override
  Widget build(BuildContext context) {
    final sales = ref.watch(salesProvider);
    final settings = ref.watch(settingsProvider);

    final filteredSales = sales.where((s) {
      final matchesSearch =
          s.invoiceNumber.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.customerName.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesSearch;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales History'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by invoice number or customer...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
        ),
      ),
      body: filteredSales.isEmpty
          ? const Center(child: Text('No sales found.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredSales.length,
              itemBuilder: (context, index) {
                final sale = filteredSales[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primary.withAlpha(40),
                      child: Icon(
                        Icons.receipt,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      sale.invoiceNumber,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${sale.date.year}-${sale.date.month.toString().padLeft(2, '0')}-${sale.date.day.toString().padLeft(2, '0')} | Items: ${sale.items.length}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          Fmt.money(sale.grandTotal, settings.currencySymbol),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Builder(
                          builder: (ctx) => IconButton(
                            icon: const Icon(Icons.share),
                            tooltip: 'Share',
                            onPressed: () => _shareSale(ctx, sale),
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InvoicePreviewScreen(sale: sale),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
