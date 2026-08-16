import 'package:flutter/material.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/features/suppliers/supplier_form_screen.dart';
import 'package:atomid/presentation/widgets/adaptive_dialog.dart';
import 'package:atomid/presentation/features/suppliers/supplier_details_screen.dart';
import 'package:atomid/presentation/widgets/responsive_data_table.dart';

class SupplierListScreen extends ConsumerStatefulWidget {
  const SupplierListScreen({super.key});

  @override
  ConsumerState<SupplierListScreen> createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends ConsumerState<SupplierListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(filteredSuppliersProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Exporting Suppliers...')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Import',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Import Suppliers...')),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search supplier...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        ref.read(supplierSearchProvider.notifier).setQuery('');
                      },
                    ),
                  ),
                  onChanged: (val) =>
                      ref.read(supplierSearchProvider.notifier).setQuery(val),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(
                        'Category: ',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: ref.watch(supplierCategoryFilterProvider),
                        dropdownColor: Theme.of(context).cardColor,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'All', child: Text('All')),
                          DropdownMenuItem(
                            value: 'General',
                            child: Text('General'),
                          ),
                          DropdownMenuItem(
                            value: 'Electronics',
                            child: Text('Electronics'),
                          ),
                          DropdownMenuItem(
                            value: 'Hardware',
                            child: Text('Hardware'),
                          ),
                          DropdownMenuItem(
                            value: 'Services',
                            child: Text('Services'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            ref
                                .read(supplierCategoryFilterProvider.notifier)
                                .setCategory(v);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: ResponsiveDataTable<Supplier>(
        headers: const [
          'Supplier Name',
          'Code',
          'Contact',
          'Status',
          'Balance',
          'Actions',
        ],
        items: suppliers,
        emptyWidget: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No suppliers found.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              SizedBox(height: 8),
              Text(
                'Tap + to add your first supplier.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
        mobileCardBuilder: (context, supplier) {
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: supplier.isActive
                    ? Theme.of(context).colorScheme.primary.withAlpha(40)
                    : Colors.grey.withAlpha(40),
                child: Icon(
                  Icons.business,
                  color: supplier.isActive
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
              ),
              title: Text(
                supplier.supplierName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: supplier.isActive ? null : Colors.grey,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    supplier.supplierCode,
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (!supplier.isActive)
                    const Text(
                      'Inactive',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Fmt.money(supplier.currentBalance, settings.currencySymbol),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: supplier.currentBalance > 0
                          ? Colors.red
                          : (supplier.currentBalance < 0
                                ? Colors.green
                                : Colors.grey),
                    ),
                  ),
                  Text(
                    supplier.currentBalance > 0
                        ? 'To Pay'
                        : (supplier.currentBalance < 0 ? 'Advance' : 'Settled'),
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SupplierDetailsScreen(supplier: supplier),
                  ),
                ).then((_) => setState(() {}));
              },
            ),
          );
        },
        dataRowBuilder: (supplier) {
          return DataRow(
            cells: [
              DataCell(
                Text(
                  supplier.supplierName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: supplier.isActive ? null : Colors.grey,
                  ),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SupplierDetailsScreen(supplier: supplier),
                    ),
                  ).then((_) => setState(() {}));
                },
              ),
              DataCell(Text(supplier.supplierCode)),
              DataCell(Text('${supplier.phone}\n${supplier.email}')),
              DataCell(
                supplier.isActive
                    ? Chip(
                        label: const Text(
                          'Active',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        backgroundColor: Colors.green,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      )
                    : const Chip(
                        label: Text('Inactive', style: TextStyle(fontSize: 12)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
              ),
              DataCell(
                Text(
                  Fmt.money(supplier.currentBalance, settings.currencySymbol),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: supplier.currentBalance > 0
                        ? Colors.red
                        : (supplier.currentBalance < 0 ? Colors.green : null),
                  ),
                ),
              ),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                SupplierFormScreen(existingSupplier: supplier),
                          ),
                        ).then((_) => setState(() {}));
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteSupplier(supplier),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SupplierFormScreen()),
          ).then((_) => setState(() {}));
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _deleteSupplier(Supplier supplier) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AdaptiveDialog(
        title: const Text('Delete Supplier'),
        content: Text(
          'Are you sure you want to delete "${supplier.supplierName}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final service = ref.read(supplierServiceProvider);
      await service.deleteSupplier(supplier);
    }
  }
}
