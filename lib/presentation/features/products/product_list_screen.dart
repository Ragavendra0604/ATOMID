import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/providers/provider_refresh_helper.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:uuid/uuid.dart';
import 'package:atomid/data/models/action_history_model.dart';
import 'package:atomid/presentation/features/price_tag/price_tag_screen.dart';
import 'package:atomid/presentation/features/products/product_form_screen.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/presentation/widgets/adaptive_dialog.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Product? _selectedProduct;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(filteredProductsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search product or barcode...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchCtrl.clear();
                    ref.read(searchQueryProvider.notifier).setQuery('');
                  },
                ),
              ),
              onChanged: (val) {
                ref.read(searchQueryProvider.notifier).setQuery(val);
              },
            ),
          ),
        ),
      ),
      body: products.isEmpty
          ? const Center(child: Text('No products found.'))
          : ResponsiveBuilder(
              mobileBuilder: (context) => _buildMobile(products),
              tabletBuilder: (context) => _buildTablet(products),
              desktopBuilder: (context) => _buildDesktop(products),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateProductDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildMobile(List<Product> products) {
    return ListView.builder(
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return ExpansionTile(
          title: Text(
            product.productName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(product.productCode),
          leading: const CircleAvatar(child: Icon(Icons.inventory)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.blue),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ProductFormScreen(existingProduct: product),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteProduct(product),
              ),
            ],
          ),
          children: product.variants.map((variant) {
            return ListTile(
              title: Text('Size: ${variant.size} - Qty: ${variant.quantity}'),
              subtitle: Text('Barcode: ${variant.barcode}'),
              trailing: ElevatedButton(
                child: const Text('Price Tag'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PriceTagScreen(
                        product: product,
                        initialVariant: variant,
                      ),
                    ),
                  );
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildTablet(List<Product> products) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 1,
          child: ListView.builder(
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return ListTile(
                selected: _selectedProduct?.id == product.id,
                selectedTileColor: Theme.of(
                  context,
                ).colorScheme.primary.withAlpha(30),
                leading: const CircleAvatar(child: Icon(Icons.inventory)),
                title: Text(
                  product.productName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(product.productCode),
                onTap: () => setState(() => _selectedProduct = product),
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 2,
          child: _selectedProduct == null
              ? const Center(child: Text('Select a product to view details.'))
              : _buildDetailsPanel(_selectedProduct!, showActions: true),
        ),
      ],
    );
  }

  Widget _buildDesktop(List<Product> products) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: ListView.builder(
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return ListTile(
                selected: _selectedProduct?.id == product.id,
                selectedTileColor: Theme.of(
                  context,
                ).colorScheme.primary.withAlpha(30),
                leading: const CircleAvatar(child: Icon(Icons.inventory)),
                title: Text(
                  product.productName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(product.productCode),
                onTap: () => setState(() => _selectedProduct = product),
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 3,
          child: _selectedProduct == null
              ? const Center(child: Text('Select a product to view details.'))
              : _buildDetailsPanel(_selectedProduct!, showActions: false),
        ),
        if (_selectedProduct != null) const VerticalDivider(width: 1),
        if (_selectedProduct != null)
          Expanded(flex: 1, child: _buildActionsPanel(_selectedProduct!)),
      ],
    );
  }

  Widget _buildDetailsPanel(Product product, {required bool showActions}) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.productName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Code: ${product.productCode}',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (showActions)
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    tooltip: 'Edit Product',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ProductFormScreen(existingProduct: product),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Delete Product',
                    onPressed: () => _deleteProduct(product),
                  ),
                ],
              ),
          ],
        ),
        const Divider(height: 48),
        const Text(
          'Variants',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ...product.variants.map((variant) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text(
                'Size: ${variant.size}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Qty: ${variant.quantity}  |  Barcode: ${variant.barcode}',
              ),
              trailing: ElevatedButton.icon(
                icon: const Icon(Icons.sell, size: 16),
                label: const Text('Price Tag'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PriceTagScreen(
                        product: product,
                        initialVariant: variant,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildActionsPanel(Product product) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Actions',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.edit),
            label: const Text('Edit Product'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.centerLeft,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProductFormScreen(existingProduct: product),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete, color: Colors.red),
            label: const Text(
              'Delete Product',
              style: TextStyle(color: Colors.red),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.centerLeft,
            ),
            onPressed: () => _deleteProduct(product),
          ),
        ],
      ),
    );
  }

  void _showCreateProductDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProductFormScreen()),
    );
  }

  Future<void> _deleteProduct(Product product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AdaptiveDialog(
        title: const Text('Delete Product'),
        content: const Text('Are you sure you want to delete this product?'),
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
      final repo = ref.read(storageRepositoryProvider);

      if (product.variants.isNotEmpty) {
        await repo.saveHistory(
          ActionHistory(
            id: const Uuid().v4(),
            barcode: product.variants.first.barcode,
            productName: product.productName,
            action: 'Deleted',
            date: DateTime.now(),
          ),
        );
      }

      await repo.deleteProduct(product.id);
      ProviderRefreshHelper.invalidateProductProviders(ref);

      if (mounted && _selectedProduct?.id == product.id) {
        setState(() => _selectedProduct = null);
      }
    }
  }
}
