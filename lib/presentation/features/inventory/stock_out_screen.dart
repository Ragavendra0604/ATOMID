import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/providers/provider_refresh_helper.dart';
import 'package:atomid/core/utils/responsive.dart';

class StockOutScreen extends ConsumerStatefulWidget {
  final Product? preselectedProduct;
  final ProductVariant? preselectedVariant;

  const StockOutScreen({
    super.key,
    this.preselectedProduct,
    this.preselectedVariant,
  });

  @override
  ConsumerState<StockOutScreen> createState() => _StockOutScreenState();
}

class _StockOutScreenState extends ConsumerState<StockOutScreen> {
  Product? _selectedProduct;
  ProductVariant? _selectedVariant;
  final _qtyController = TextEditingController();
  String _selectedReason = 'Sale';
  bool _isLoading = false;

  final List<String> _reasons = ['Sale', 'Damage', 'Return', 'Adjustment'];

  @override
  void initState() {
    super.initState();
    if (widget.preselectedProduct != null) {
      _selectedProduct = widget.preselectedProduct;
      _selectedVariant = widget.preselectedVariant;
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  Future<void> _performStockOut() async {
    if (_selectedProduct == null || _selectedVariant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a product and variant')),
      );
      return;
    }

    final qty = int.tryParse(_qtyController.text.trim());
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid quantity greater than 0'),
        ),
      );
      return;
    }

    if (qty > _selectedVariant!.quantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot remove $qty units. Only ${_selectedVariant!.quantity} available.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(storageRepositoryProvider);
      await repo.performStockOut(
        productId: _selectedProduct!.id,
        variantBarcode: _selectedVariant!.barcode,
        quantity: qty,
        reason: _selectedReason,
      );

      ProviderRefreshHelper.invalidateProductProviders(ref);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Stock Out: -$qty for ${_selectedProduct!.productName} (${_selectedVariant!.size})',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context);
      }
      debugPrint('Stock out error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to update inventory. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Stock Out')),
      body: SingleChildScrollView(
        padding: ResponsivePadding.getScreenPadding(context),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ResponsiveBreakpoints.maxFormWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info banner
                Card(
                  color: Colors.red.withAlpha(30),
                  child: const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Icon(Icons.outbox_outlined, color: Colors.red),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Remove stock from your inventory. Select a product and variant, then enter the quantity to remove.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Product Selection
                const Text(
                  'Select Product',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<Product>(
                  initialValue: _selectedProduct,
                  isExpanded: true,
                  hint: const Text('Choose a product'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.inventory_2),
                    border: OutlineInputBorder(),
                  ),
                  items: products.map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text('${p.productName} (${p.productCode})'),
                    );
                  }).toList(),
                  onChanged: (p) {
                    setState(() {
                      _selectedProduct = p;
                      _selectedVariant = null;
                    });
                  },
                ),
                const SizedBox(height: 20),

                // Variant Selection
                if (_selectedProduct != null) ...[
                  const Text(
                    'Select Variant',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ProductVariant>(
                    initialValue: _selectedVariant,
                    isExpanded: true,
                    hint: const Text('Choose a variant'),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.straighten),
                      border: OutlineInputBorder(),
                    ),
                    items: _selectedProduct!.variants.map((v) {
                      return DropdownMenuItem(
                        value: v,
                        child: Text(
                          'Size: ${v.size} | Qty: ${v.quantity} | ${v.barcode}',
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedVariant = v),
                  ),
                  const SizedBox(height: 20),
                ],

                // Current Stock Info
                if (_selectedVariant != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Stock Info',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const Divider(),
                          _infoRow('Product', _selectedProduct!.productName),
                          _infoRow('Size', _selectedVariant!.size),
                          _infoRow(
                            'Available Qty',
                            _selectedVariant!.quantity.toString(),
                          ),
                          _infoRow(
                            'Total Stock Out',
                            _selectedVariant!.stockOut.toString(),
                          ),
                          _infoRow('Barcode', _selectedVariant!.barcode),
                          if (_selectedVariant!.quantity <=
                              _selectedVariant!.reorderLevel)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _selectedVariant!.quantity <= 0
                                        ? 'OUT OF STOCK'
                                        : 'LOW STOCK',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _selectedVariant!.quantity <= 0
                                          ? Colors.red
                                          : Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Quantity
                  const Text(
                    'Quantity to Remove',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _qtyController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.remove),
                      hintText: 'Max: ${_selectedVariant!.quantity}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Reason
                  const Text(
                    'Reason',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedReason,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.description),
                      border: OutlineInputBorder(),
                    ),
                    items: _reasons.map((r) {
                      return DropdownMenuItem(value: r, child: Text(r));
                    }).toList(),
                    onChanged: (r) {
                      if (r != null) setState(() => _selectedReason = r);
                    },
                  ),
                  const SizedBox(height: 32),

                  // Submit
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _selectedVariant!.quantity <= 0
                                ? null
                                : _performStockOut,
                            icon: const Icon(Icons.outbox),
                            label: const Text('Confirm Stock Out'),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
