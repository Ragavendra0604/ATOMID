import 'package:flutter/material.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/data/models/action_history_model.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/features/suppliers/supplier_form_screen.dart';
import 'package:atomid/presentation/features/purchases/purchase_details_screen.dart';
import 'package:uuid/uuid.dart';

class SupplierDetailsScreen extends ConsumerStatefulWidget {
  final Supplier supplier;

  const SupplierDetailsScreen({super.key, required this.supplier});

  @override
  ConsumerState<SupplierDetailsScreen> createState() =>
      _SupplierDetailsScreenState();
}

class _SupplierDetailsScreenState extends ConsumerState<SupplierDetailsScreen> {
  @override
  Widget build(BuildContext context) {
    // Re-read supplier from providers for freshness
    final allSuppliers = ref.watch(suppliersProvider);
    final freshSupplier = allSuppliers.firstWhere(
      (s) => s.id == widget.supplier.id,
      orElse: () => widget.supplier,
    );
    final allPurchases = ref.watch(purchasesProvider);
    final purchases = allPurchases
        .where((p) => p.supplierId == freshSupplier.id)
        .toList();
    final ledgers = ref.watch(supplierLedgerProvider(freshSupplier.id));
    final settings = ref.watch(settingsProvider);

    final totalPurchaseValue = purchases.fold(
      0.0,
      (sum, p) => sum + p.grandTotal,
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(freshSupplier.supplierName),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Details', icon: Icon(Icons.info)),
              Tab(text: 'Ledger', icon: Icon(Icons.account_balance_wallet)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SupplierFormScreen(existingSupplier: freshSupplier),
                  ),
                );
              },
            ),
            IconButton(
              icon: Icon(
                freshSupplier.isActive
                    ? Icons.block
                    : Icons.check_circle_outline,
              ),
              tooltip: freshSupplier.isActive
                  ? 'Disable Supplier'
                  : 'Enable Supplier',
              onPressed: () async {
                final repo = ref.read(storageRepositoryProvider);
                final updated = Supplier(
                  id: freshSupplier.id,
                  supplierCode: freshSupplier.supplierCode,
                  supplierName: freshSupplier.supplierName,
                  phone: freshSupplier.phone,
                  email: freshSupplier.email,
                  address: freshSupplier.address,
                  gstNumber: freshSupplier.gstNumber,
                  contactPerson: freshSupplier.contactPerson,
                  notes: freshSupplier.notes,
                  createdDate: freshSupplier.createdDate,
                  updatedDate: DateTime.now(),
                  isActive: !freshSupplier.isActive,
                );
                await repo.saveSupplier(updated);
                await repo.saveHistory(
                  ActionHistory(
                    id: const Uuid().v4(),
                    barcode: updated.supplierCode,
                    productName: updated.supplierName,
                    action: updated.isActive
                        ? 'Supplier Enabled'
                        : 'Supplier Disabled',
                    date: DateTime.now(),
                  ),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        updated.isActive
                            ? 'Supplier enabled'
                            : 'Supplier disabled',
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        ),
        body: TabBarView(
          children: [
            // TAB 1: DETAILS
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status Badge
                  if (!freshSupplier.isActive)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.block, color: Colors.red),
                          SizedBox(width: 8),
                          Text(
                            'This supplier is currently inactive',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),

                  // Info Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Supplier Details',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Divider(),
                          _infoRow('Code', freshSupplier.supplierCode),
                          _infoRow('Name', freshSupplier.supplierName),
                          _infoRow('Category', freshSupplier.supplierCategory),
                          if (freshSupplier.contactPerson.isNotEmpty)
                            _infoRow(
                              'Contact Person',
                              freshSupplier.contactPerson,
                            ),
                          if (freshSupplier.phone.isNotEmpty)
                            _infoRow('Phone', freshSupplier.phone),
                          if (freshSupplier.email.isNotEmpty)
                            _infoRow('Email', freshSupplier.email),
                          if (freshSupplier.address.isNotEmpty)
                            _infoRow('Address', freshSupplier.address),
                          if (freshSupplier.gstNumber.isNotEmpty)
                            _infoRow('GST Number', freshSupplier.gstNumber),
                          _infoRow('Payment Terms', freshSupplier.paymentTerms),
                          _infoRow(
                            'Rating',
                            freshSupplier.rating.toStringAsFixed(1),
                          ),
                          if (freshSupplier.notes.isNotEmpty)
                            _infoRow('Notes', freshSupplier.notes),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Stats Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Purchase Statistics',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Divider(),
                          _infoRow(
                            'Total Purchases',
                            purchases.length.toString(),
                          ),
                          _infoRow(
                            'Total Value',
                            Fmt.money(
                              totalPurchaseValue,
                              settings.currencySymbol,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Purchase History
                  Row(
                    children: [
                      const Icon(Icons.receipt_long, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Purchase History (${purchases.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (purchases.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text('No purchases from this supplier yet.'),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: purchases.length,
                      itemBuilder: (context, index) {
                        final purchase = purchases[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary.withAlpha(40),
                              child: const Icon(Icons.receipt),
                            ),
                            title: Text(
                              purchase.purchaseNumber,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${_formatDate(purchase.purchaseDate)} • ${purchase.items.length} items',
                            ),
                            trailing: Text(
                              Fmt.money(
                                purchase.grandTotal,
                                settings.currencySymbol,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PurchaseDetailsScreen(purchase: purchase),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),

            // TAB 2: LEDGER
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).cardColor,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Balance (Owed)',
                            style: TextStyle(color: Colors.grey),
                          ),
                          Text(
                            Fmt.money(
                              freshSupplier.currentBalance,
                              settings.currencySymbol,
                            ),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: freshSupplier.currentBalance > 0
                                  ? Colors.red
                                  : (freshSupplier.currentBalance < 0
                                        ? Colors.green
                                        : Colors.grey),
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.payment),
                        label: const Text('Record Payment'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () =>
                            _showRecordPaymentDialog(context, freshSupplier),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ledgers.isEmpty
                      ? const Center(child: Text('No ledger entries yet.'))
                      : ListView.builder(
                          itemCount: ledgers.length,
                          itemBuilder: (context, index) {
                            // Display descending order (newest first)
                            final l = ledgers[ledgers.length - 1 - index];
                            final isDebit = l.debit > 0; // Payment to supplier
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isDebit
                                      ? Colors.green.withAlpha(40)
                                      : Colors.red.withAlpha(40),
                                  child: Icon(
                                    isDebit
                                        ? Icons.arrow_upward
                                        : Icons.arrow_downward,
                                    color: isDebit ? Colors.green : Colors.red,
                                  ),
                                ),
                                title: Text(l.transactionType),
                                subtitle: Text(
                                  '${_formatDate(l.date)} • Ref: ${l.referenceId}\n${l.notes}',
                                ),
                                isThreeLine: true,
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${isDebit ? '-' : '+'}${Fmt.money(isDebit ? l.debit : l.credit, settings.currencySymbol)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isDebit
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                    ),
                                    Text(
                                      'Balance ${Fmt.money(l.balance, settings.currencySymbol)}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
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

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _showRecordPaymentDialog(BuildContext context, Supplier supplier) {
    final amountCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Payment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount Paid',
                  prefixIcon: Icon(Icons.attach_money),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: refCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reference ID (e.g. Check #, Transaction ID)',
                  prefixIcon: Icon(Icons.receipt),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text) ?? 0.0;
              if (amount <= 0) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Invalid amount')));
                return;
              }
              Navigator.pop(ctx);

              final repo = ref.read(storageRepositoryProvider);
              await repo.addSupplierLedgerEntry(
                supplierId: supplier.id,
                date: DateTime.now(),
                transactionType: 'Payment',
                referenceId: refCtrl.text.isEmpty
                    ? 'PAY-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}'
                    : refCtrl.text,
                debit: amount, // Payment decreases owed amount
                notes: notesCtrl.text,
              );

              // Refresh

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Payment recorded successfully'),
                  ),
                );
              }
            },
            child: const Text('Record'),
          ),
        ],
      ),
      // Built per invocation, so without this every payment recorded leaks
      // three controllers for the life of the session.
    ).whenComplete(() {
      amountCtrl.dispose();
      refCtrl.dispose();
      notesCtrl.dispose();
    });
  }
}
