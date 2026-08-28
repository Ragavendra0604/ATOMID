import 'package:flutter/material.dart';
import 'package:atomid/domain/purchase_payment.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/domain/services/purchase_service.dart';
import 'package:atomid/presentation/features/purchases/purchase_form_screen.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
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

    // Payments are supplier-ledger rows filed under the purchase number.
    final paidSoFar =
        ref.watch(purchasePaymentsProvider)[freshPurchase.purchaseNumber] ?? 0;
    final outstanding = PurchasePayment.outstanding(
      grandTotal: freshPurchase.grandTotal,
      paidSoFar: paidSoFar,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(freshPurchase.purchaseNumber),
        actions: [
          // Shown disabled rather than removed on a settled order.
          //
          // A received order has moved stock and credited the supplier, so it
          // genuinely cannot be edited — but silently deleting the button
          // meant a shopkeeper saw the option simply vanish, which is
          // indistinguishable from a broken build. It was reported as one.
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: PurchaseStatus.isSettled(freshPurchase.status)
                ? 'Received orders cannot be edited'
                : 'Edit purchase',
            onPressed: PurchaseStatus.isSettled(freshPurchase.status)
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PurchaseFormScreen(existingPurchase: freshPurchase),
                    ),
                  ),
          ),
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
      bottomNavigationBar: _buildBottomActions(
        context,
        ref,
        freshPurchase,
        outstanding,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Says why the order is read-only, next to the status that made
            // it so. A disabled button explains that something is unavailable;
            // it does not explain what to do instead.
            if (PurchaseStatus.isSettled(freshPurchase.status))
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This order has been received. Its stock is already '
                          'on the shelf and the supplier account has been '
                          'credited, so it can no longer be edited.\n\n'
                          'To correct a quantity, adjust the stock from the '
                          'product. To correct what is owed, add a supplier '
                          'ledger entry.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

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
                    _infoRow(
                      context,
                      'Purchase #',
                      freshPurchase.purchaseNumber,
                    ),
                    _infoRow(context, 'Supplier', freshPurchase.supplierName),
                    _infoRow(
                      context,
                      'Date',
                      _formatDate(freshPurchase.purchaseDate),
                    ),
                    if (freshPurchase.expectedDeliveryDate != null)
                      _infoRow(
                        context,
                        'Due Date',
                        _formatDate(freshPurchase.expectedDeliveryDate!),
                      ),
                    _infoRow(context, 'Status', freshPurchase.status),
                    // Derived from the supplier ledger, not read from
                    // `paymentStatus` — that field was never written to and
                    // showed every order as unpaid forever.
                    _infoRow(
                      context,
                      'Payment',
                      PurchasePayment.status(
                        grandTotal: freshPurchase.grandTotal,
                        paidSoFar: paidSoFar,
                      ),
                    ),
                    if (paidSoFar > 0)
                      _infoRow(
                        context,
                        'Paid',
                        Fmt.money(paidSoFar, settings.currencySymbol),
                      ),
                    if (outstanding > 0)
                      _infoRow(
                        context,
                        'Outstanding',
                        Fmt.money(outstanding, settings.currencySymbol),
                      ),
                    _infoRow(
                      context,
                      'Items',
                      '${freshPurchase.items.length} line items',
                    ),
                    if (freshPurchase.notes.isNotEmpty)
                      _infoRow(context, 'Notes', freshPurchase.notes),
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
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    title: Text(item.productName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${item.variantSize} - ${item.variantBarcode}'),
                        if (freshPurchase.status == 'Received' ||
                            freshPurchase.status == 'Partially Received')
                          Text(
                            'Received: ${item.receivedQuantity} / ${item.quantity}',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${item.quantity} x ${Fmt.money(item.costPrice, settings.currencySymbol)}',
                        ),
                        Text(
                          Fmt.money(item.lineTotal, settings.currencySymbol),
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
                    _summaryRow(
                      context,
                      'Subtotal',
                      Fmt.money(
                        freshPurchase.subtotal,
                        settings.currencySymbol,
                      ),
                    ),
                    if (freshPurchase.discount > 0)
                      _summaryRow(
                        context,
                        'Discount',
                        '-${Fmt.money(freshPurchase.discount, settings.currencySymbol)}',
                      ),
                    if (freshPurchase.tax > 0)
                      _summaryRow(
                        context,
                        'Tax (${freshPurchase.tax}%)',
                        Fmt.money(
                          (freshPurchase.subtotal - freshPurchase.discount) *
                              freshPurchase.tax /
                              100,
                          settings.currencySymbol,
                        ),
                      ),
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
                            Fmt.money(
                              freshPurchase.grandTotal,
                              settings.currencySymbol,
                            ),
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

  Widget? _buildBottomActions(
    BuildContext context,
    WidgetRef ref,
    Purchase purchase,
    double outstanding,
  ) {
    final errorColor = Theme.of(context).colorScheme.error;

    Future<void> run(Future<void> Function() action, String success) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await action();
        messenger.showSnackBar(
          SnackBar(
            content: Text(success),
            backgroundColor: Colors.green.shade700,
          ),
        );
      } catch (error) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              describeError(
                error,
                fallback: 'That could not be completed. Please try again.',
              ),
            ),
            backgroundColor: errorColor,
          ),
        );
      }
    }

    final service = ref.read(purchaseServiceProvider);

    return switch (purchase.status) {
      PurchaseStatus.draft => _actionBar(
        label: 'Send to supplier',
        icon: Icons.send_outlined,
        onPressed: () => run(
          () => service.markAsIssued(purchase),
          'Order marked as issued.',
        ),
      ),
      PurchaseStatus.issued => _actionBar(
        label: 'Receive into stock',
        icon: Icons.inventory_outlined,
        emphasis: true,
        onPressed: () => run(
          () => service.markAsReceived(purchase),
          'Stock updated and supplier account credited.',
        ),
      ),
      // A received order is the only one that can owe anything: the supplier
      // is credited when it is received, not when it is raised.
      PurchaseStatus.received when outstanding > 0 => _actionBar(
        label: 'Record payment',
        icon: Icons.payments_outlined,
        onPressed: () => _recordPayment(context, ref, purchase, outstanding),
      ),
      _ => null,
    };
  }

  /// Files a payment against this order.
  ///
  /// The reference is the purchase number, which is what ties the debit back
  /// to this order — a payment recorded from the supplier screen carries its
  /// own reference and settles the account as a whole instead.
  Future<void> _recordPayment(
    BuildContext context,
    WidgetRef ref,
    Purchase purchase,
    double outstanding,
  ) async {
    final amountCtrl = TextEditingController(
      text: outstanding.toStringAsFixed(2),
    );
    final notesCtrl = TextEditingController();
    final symbol = ref.read(settingsProvider).currencySymbol;

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Payment for ${purchase.purchaseNumber}'),
          // Scrollable and width-bounded.
          //
          // On a phone the soft keyboard opens the moment this dialog does
          // (the amount field autofocuses) and takes roughly half the screen
          // with it. An AlertDialog shrinks to what is left, and a plain
          // Column has nowhere to go — it overflows, which is a render error
          // rather than a clipped field. A desktop has no soft keyboard, so
          // this never appeared while testing on Windows.
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${Fmt.money(outstanding, symbol)} outstanding',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText: symbol,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Record'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
      if (!context.mounted) return;

      final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
      final messenger = ScaffoldMessenger.of(context);
      if (amount <= 0) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Enter an amount greater than zero.')),
        );
        return;
      }

      try {
        await ref
            .read(storageRepositoryProvider)
            .addSupplierLedgerEntry(
              supplierId: purchase.supplierId,
              date: DateTime.now(),
              transactionType: 'Payment',
              referenceId: purchase.purchaseNumber,
              debit: amount,
              notes: notesCtrl.text.trim(),
            );
        messenger.showSnackBar(
          SnackBar(content: Text('${Fmt.money(amount, symbol)} recorded.')),
        );
      } catch (error) {
        messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
      }
    } finally {
      // Built per invocation: without this every payment leaks two
      // controllers for the life of the session.
      amountCtrl.dispose();
      notesCtrl.dispose();
    }
  }

  Widget _actionBar({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool emphasis = false,
  }) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: emphasis ? Colors.green.shade700 : null,
            foregroundColor: emphasis ? Colors.white : null,
          ),
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
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

  Widget _summaryRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) => Fmt.date(date);
}
