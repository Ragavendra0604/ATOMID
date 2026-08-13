import 'package:flutter/material.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/features/purchases/purchase_form_screen.dart';
import 'package:atomid/presentation/features/purchases/purchase_details_screen.dart';

class PurchaseListScreen extends ConsumerStatefulWidget {
  const PurchaseListScreen({super.key});

  @override
  ConsumerState<PurchaseListScreen> createState() => _PurchaseListScreenState();
}

class _PurchaseListScreenState extends ConsumerState<PurchaseListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final List<String> _tabs = [
    'All',
    'Draft',
    'Issued',
    'Partially Received',
    'Received',
    'Cancelled',
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final purchases = ref.watch(filteredPurchasesProvider);
    final settings = ref.watch(settingsProvider);
    final currentStatus = ref.watch(purchaseStatusFilterProvider);

    return DefaultTabController(
      length: _tabs.length,
      initialIndex: _tabs.indexOf(currentStatus).clamp(0, _tabs.length - 1),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Purchase Orders'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(110),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search purchase or supplier...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref
                              .read(purchaseSearchProvider.notifier)
                              .setQuery('');
                        },
                      ),
                    ),
                    onChanged: (val) {
                      ref.read(purchaseSearchProvider.notifier).setQuery(val);
                    },
                  ),
                ),
                TabBar(
                  isScrollable: true,
                  onTap: (index) {
                    ref
                        .read(purchaseStatusFilterProvider.notifier)
                        .setStatus(_tabs[index]);
                  },
                  tabs: _tabs.map((t) => Tab(text: t)).toList(),
                ),
              ],
            ),
          ),
        ),
        body: purchases.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.shopping_cart_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No purchases found.',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Tap + to create a new purchase.',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: purchases.length,
                itemBuilder: (context, index) {
                  final purchase = purchases[index];
                  final totalItems = purchase.items.fold(
                    0,
                    (sum, item) => sum + item.quantity,
                  );
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
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
                        purchase.purchaseNumber,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            '${purchase.supplierName} • ${_formatDate(purchase.purchaseDate)} • $totalItems items',
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _buildStatusBadge(purchase.status),
                              const SizedBox(width: 8),
                              _buildPaymentBadge(purchase.paymentStatus),
                            ],
                          ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Fmt.money(
                              purchase.grandTotal,
                              settings.currencySymbol,
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (purchase.expectedDeliveryDate != null)
                            Text(
                              'Due: ${_formatDate(purchase.expectedDeliveryDate!)}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                        ],
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
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PurchaseFormScreen()),
            );
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status) {
      case 'Draft':
        color = Colors.grey;
        break;
      case 'Issued':
        color = Colors.blue;
        break;
      case 'Partially Received':
        color = Colors.orange;
        break;
      case 'Received':
        color = Colors.green;
        break;
      case 'Cancelled':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildPaymentBadge(String status) {
    Color color;
    switch (status) {
      case 'Unpaid':
        color = Colors.red;
        break;
      case 'Partial':
        color = Colors.orange;
        break;
      case 'Paid':
        color = Colors.green;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
