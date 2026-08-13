import 'package:flutter/material.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/features/billing/invoice_preview_screen.dart';

class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  ConsumerState<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  String _searchQuery = '';

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
                  trailing: Text(
                    Fmt.money(sale.grandTotal, settings.currencySymbol),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
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
