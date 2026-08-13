import 'package:flutter/material.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/customer_ledger_model.dart';
import 'package:intl/intl.dart';
import 'package:atomid/presentation/features/customers/customer_form_screen.dart';

class CustomerDetailsScreen extends ConsumerStatefulWidget {
  final String customerId;

  const CustomerDetailsScreen({super.key, required this.customerId});

  @override
  ConsumerState<CustomerDetailsScreen> createState() =>
      _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends ConsumerState<CustomerDetailsScreen> {
  void _showPaymentDialog(
    BuildContext context,
    Customer customer,
    WidgetRef ref,
  ) {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    String paymentMode = 'Cash';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Record Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Outstanding: ${Fmt.money(customer.currentBalance, ref.read(settingsProvider).currencySymbol)}',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount Received',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: paymentMode,
                decoration: const InputDecoration(
                  labelText: 'Payment Mode',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                  DropdownMenuItem(value: 'Card', child: Text('Card')),
                  DropdownMenuItem(value: 'Bank', child: Text('Bank Transfer')),
                ],
                onChanged: (v) => paymentMode = v!,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes / Ref No.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text) ?? 0;
                if (amount <= 0) return;

                final repo = ref.read(storageRepositoryProvider);
                await repo.addLedgerEntry(
                  customerId: customer.id,
                  date: DateTime.now(),
                  transactionType: 'Payment',
                  referenceId:
                      'PAY-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}',
                  credit: amount, // Payment reduces balance
                  notes: 'Via $paymentMode - ${notesController.text}',
                );

                ref.invalidate(customersProvider);
                ref.invalidate(customerLedgerProvider(customer.id));

                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save Payment'),
            ),
          ],
        );
      },
      // Built per invocation, so without this every payment recorded leaks a
      // pair of controllers for the life of the session.
    ).whenComplete(() {
      amountController.dispose();
      notesController.dispose();
    });
  }

  void _showMergeDialog(
    BuildContext context,
    Customer currentCustomer,
    WidgetRef ref,
  ) {
    final allCustomers = ref
        .read(customersProvider)
        .where((c) => c.id != currentCustomer.id)
        .toList();
    Customer? selectedCustomer;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Merge Customer'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select a customer to merge into the current one. The selected customer will be soft-deleted.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Customer>(
                    decoration: const InputDecoration(
                      labelText: 'Secondary Customer',
                      border: OutlineInputBorder(),
                    ),
                    items: allCustomers
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text('${c.name} (${c.mobile})'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => selectedCustomer = v),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: selectedCustomer == null
                      ? null
                      : () async {
                          final service = ref.read(customerServiceProvider);
                          await service.mergeCustomers(
                            currentCustomer.id,
                            selectedCustomer!.id,
                          );
                          ref.invalidate(customersProvider);
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Customers merged successfully'),
                              ),
                            );
                          }
                        },
                  child: const Text('Merge'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch customersProvider to get updates when balance changes
    final customers = ref.watch(customersProvider);
    final customerIndex = customers.indexWhere(
      (c) => c.id == widget.customerId,
    );

    if (customerIndex == -1) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer Not Found')),
        body: const Center(
          child: Text('Customer has been deleted or not found.'),
        ),
      );
    }

    final customer = customers[customerIndex];
    final ledger = ref.watch(customerLedgerProvider(widget.customerId));
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(customer.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CustomerFormScreen(customer: customer),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'merge') _showMergeDialog(context, customer, ref);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'merge',
                child: Text('Merge Customer'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Dashboard Header
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).cardColor,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.mobile,
                        style: const TextStyle(fontSize: 16),
                      ),
                      if (customer.email.isNotEmpty)
                        Text(
                          customer.email,
                          style: const TextStyle(fontSize: 14),
                        ),
                      if (customer.gstNumber.isNotEmpty)
                        Text(
                          'GST: ${customer.gstNumber}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Group: ${customer.customerGroup}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (customer.tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Wrap(
                            spacing: 4,
                            children: customer.tags
                                .map(
                                  (t) => Chip(
                                    label: Text(
                                      t,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Credit limit: ${Fmt.money(customer.creditLimit, settings.currencySymbol)}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Reward points: ${Fmt.points(customer.totalRewardPoints)}',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Lifetime spend: ${Fmt.money(customer.lifetimeSpend, settings.currencySymbol)}',
                      ),
                    ],
                  ),
                ),
                Card(
                  color: customer.currentBalance > 0
                      ? Colors.red.withAlpha(26)
                      : Colors.green.withAlpha(26),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      children: [
                        Text(
                          customer.currentBalance > 0
                              ? 'Outstanding'
                              : (customer.currentBalance < 0
                                    ? 'Advance'
                                    : 'Settled'),
                          style: TextStyle(
                            color: customer.currentBalance > 0
                                ? Colors.red
                                : Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          Fmt.money(
                            customer.currentBalance.abs(),
                            settings.currencySymbol,
                          ),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: customer.currentBalance > 0
                                ? Colors.red
                                : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.payments),
                    label: const Text('Record Payment'),
                    onPressed: () => _showPaymentDialog(context, customer, ref),
                  ),
                ),
              ],
            ),
          ),

          // Tabs for Ledger & Loyalty
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    labelColor: Theme.of(context).colorScheme.primary,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Theme.of(context).colorScheme.primary,
                    tabs: const [
                      Tab(text: 'Financial Ledger'),
                      Tab(text: 'Loyalty Rewards'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildLedgerList(ledger, settings),
                        _buildLoyaltyList(ref, customer),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerList(List<CustomerLedger> ledger, dynamic settings) {
    if (ledger.isEmpty) {
      return const Center(child: Text('No transactions yet.'));
    }
    return ListView.builder(
      itemCount: ledger.length,
      itemBuilder: (context, index) {
        final entry = ledger[ledger.length - 1 - index];
        final isDebit = entry.debit > 0;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            title: Text(
              entry.transactionType,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('MMM dd, yyyy - hh:mm a').format(entry.date)),
                if (entry.notes.isNotEmpty)
                  Text(entry.notes, style: const TextStyle(fontSize: 12)),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isDebit ? "+" : "-"}${Fmt.money(isDebit ? entry.debit : entry.credit, settings.currencySymbol)}',
                  style: TextStyle(
                    color: isDebit ? Colors.red : Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Balance ${Fmt.money(entry.balance, settings.currencySymbol)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoyaltyList(WidgetRef ref, Customer customer) {
    final loyaltyTxs = ref.watch(loyaltyTransactionsProvider(customer.id));
    if (loyaltyTxs.isEmpty) {
      return const Center(child: Text('No reward transactions yet.'));
    }
    return ListView.builder(
      itemCount: loyaltyTxs.length,
      itemBuilder: (context, index) {
        final entry = loyaltyTxs[loyaltyTxs.length - 1 - index];
        final isEarn = entry.points > 0;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: Icon(
              isEarn ? Icons.add_circle : Icons.remove_circle,
              color: isEarn ? Colors.green : Colors.red,
            ),
            title: Text(
              entry.transactionType,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat(
                    'MMM dd, yyyy - hh:mm a',
                  ).format(entry.createdDate),
                ),
                if (entry.reference.isNotEmpty)
                  Text(
                    'Ref: ${entry.reference}',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
            trailing: Text(
              '${isEarn ? "+" : ""}${Fmt.points(entry.points)}',
              style: TextStyle(
                color: isEarn ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        );
      },
    );
  }
}
