import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

class InventoryMovementScreen extends ConsumerStatefulWidget {
  const InventoryMovementScreen({super.key});

  @override
  ConsumerState<InventoryMovementScreen> createState() =>
      _InventoryMovementScreenState();
}

class _InventoryMovementScreenState
    extends ConsumerState<InventoryMovementScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'All';

  final List<String> _filters = ['All', 'Stock In', 'Stock Out'];

  @override
  Widget build(BuildContext context) {
    final movements = ref.watch(inventoryMovementsProvider);

    final filteredList = movements.where((m) {
      bool matchesSearch =
          m.productName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          m.variantBarcode.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          m.variantSize.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          m.reason.toLowerCase().contains(_searchQuery.toLowerCase());
      bool matchesFilter =
          _selectedFilter == 'All' || m.type == _selectedFilter;
      return matchesSearch && matchesFilter;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Movements'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search product, barcode, or reason...',
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
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 4.0,
                ),
                child: Row(
                  children: _filters.map((f) {
                    final isSelected = _selectedFilter == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: FilterChip(
                        label: Text(f),
                        selected: isSelected,
                        onSelected: (_) => setState(() => _selectedFilter = f),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
      body: filteredList.isEmpty
          ? const Center(child: Text('No movements found.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredList.length,
              itemBuilder: (ctx, index) {
                final m = filteredList[index];
                final isStockIn = m.type == 'Stock In';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isStockIn
                          ? Colors.green.withAlpha(40)
                          : Colors.red.withAlpha(40),
                      child: Icon(
                        isStockIn
                            ? Icons.add_box_outlined
                            : Icons.outbox_outlined,
                        color: isStockIn ? Colors.green : Colors.red,
                      ),
                    ),
                    title: Text(
                      '${m.type} — ${m.productName}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Size: ${m.variantSize} | Qty: ${isStockIn ? "+" : "-"}${m.quantity}\n'
                      'Reason: ${m.reason} | Barcode: ${m.variantBarcode}',
                    ),
                    isThreeLine: true,
                    trailing: Text(
                      _formatDate(m.date),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}\n'
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
