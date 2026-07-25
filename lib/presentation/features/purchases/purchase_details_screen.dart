import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/providers/provider_refresh_helper.dart';
import 'package:atomid/core/services/export_service.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

class PurchaseDetailsScreen extends ConsumerWidget {
  final Purchase purchase;

  const PurchaseDetailsScreen({super.key, required this.purchase});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final company = ref.watch(companyProvider);
    final allPurchases = ref.watch(purchasesProvider);
    final freshPurchase = allPurchases.firstWhere(
      (p) => p.id == purchase.id,
      orElse: () => purchase,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(freshPurchase.purchaseNumber),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print Purchase',
            onPressed: () async {
              final pdf = await ExportService.generatePurchaseReportPdf(
                [purchase],
                'Single Purchase',
                settings,
                company,
              );
              await Printing.layoutPdf(
                onLayout: (PdfPageFormat format) async => pdf.save(),
                name: purchase.purchaseNumber,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share Purchase',
            onPressed: () async {
              final pdf = await ExportService.generatePurchaseReportPdf(
                [purchase],
                'Single Purchase',
                settings,
                company,
              );
              final file = await ExportService.exportPdf(
                pdf,
                freshPurchase.purchaseNumber,
              );
              await ExportService.shareFile(
                file,
                'Purchase ${freshPurchase.purchaseNumber} from ${freshPurchase.supplierName}',
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomActions(context, ref, freshPurchase),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Purchase Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Purchase Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(),
                    _infoRow('Purchase #', freshPurchase.purchaseNumber),
                    _infoRow('Supplier', freshPurchase.supplierName),
                    _infoRow('Date', _formatDate(freshPurchase.purchaseDate)),
                    if (freshPurchase.expectedDeliveryDate != null)
                      _infoRow('Due Date', _formatDate(freshPurchase.expectedDeliveryDate!)),
                    _infoRow('Status', freshPurchase.status),
                    _infoRow('Payment', freshPurchase.paymentStatus),
                    _infoRow('Items', '${freshPurchase.items.length} line items'),
                    if (freshPurchase.notes.isNotEmpty)
                      _infoRow('Notes', freshPurchase.notes),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Items Table
            const Text(
              'Items',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: freshPurchase.items.length,
              itemBuilder: (context, index) {
                final item = freshPurchase.items[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: Text(item.productName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${item.variantSize} - ${item.variantBarcode}'),
                        if (freshPurchase.status == 'Received' || freshPurchase.status == 'Partially Received')
                          Text('Received: ${item.receivedQuantity} / ${item.quantity}', style: const TextStyle(color: Colors.green, fontSize: 12)),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${item.quantity} x ${settings.currencySymbol}${item.costPrice.toStringAsFixed(2)}'),
                        Text(
                          '${settings.currencySymbol}${item.lineTotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            // Totals
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _summaryRow('Subtotal', '${settings.currencySymbol}${freshPurchase.subtotal.toStringAsFixed(2)}'),
                    if (freshPurchase.discount > 0)
                      _summaryRow('Discount', '-${settings.currencySymbol}${freshPurchase.discount.toStringAsFixed(2)}'),
                    if (freshPurchase.tax > 0)
                      _summaryRow('Tax', '${settings.currencySymbol}${freshPurchase.tax.toStringAsFixed(2)}'),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Grand Total',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${settings.currencySymbol}${freshPurchase.grandTotal.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildBottomActions(BuildContext context, WidgetRef ref, Purchase purchase) {
    if (purchase.status == 'Draft') {
      return Container(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: () async {
            await ref.read(purchaseServiceProvider).markAsIssued(purchase);
            ProviderRefreshHelper.invalidatePurchaseProviders(ref);
          },
          child: const Text('Mark as Issued'),
        ),
      );
    } else if (purchase.status == 'Issued') {
      return Container(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
          onPressed: () async {
            await ref.read(purchaseServiceProvider).markAsReceived(purchase);
            ProviderRefreshHelper.invalidatePurchaseProviders(ref);
            ProviderRefreshHelper.invalidateInventoryProviders(ref);
            ProviderRefreshHelper.invalidateSupplierProviders(ref);
          },
          child: const Text('Receive Order'),
        ),
      );
    }
    return null;
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16, color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
