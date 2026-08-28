import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/domain/pricing.dart';
import 'package:atomid/presentation/features/billing/checkout_screen.dart';
import 'package:atomid/presentation/features/sync/sync_status_widget.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/providers/cart_notifier.dart';
import 'package:atomid/presentation/widgets/adaptive_dialog.dart';
import 'package:atomid/presentation/widgets/empty_state.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  MobileScannerController? _scannerController;
  bool _isScanning = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _toggleScanner() async {
    if (_isScanning) {
      setState(() => _isScanning = false);
      await _scannerController?.dispose();
      _scannerController = null;
      _searchFocus.requestFocus();
    } else {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
      setState(() => _isScanning = true);
    }
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (!_isScanning) return;
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null || barcode.isEmpty) return;

    _toggleScanner();
    _processSearch(barcode);
  }

  void _processSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final repo = ref.read(storageRepositoryProvider);

    final scanned = repo.getProductByBarcode(trimmed);
    if (scanned != null) {
      final variant = scanned.variants.firstWhere(
        (v) => v.barcode == trimmed,
        orElse: () => scanned.variants.first,
      );
      _addToCart(scanned, variant);
      _searchController.clear();
      _searchFocus.requestFocus();
      return;
    }

    final matches = repo.searchProducts(trimmed);
    if (matches.isEmpty) {
      _toast('Nothing matches "$trimmed".');
      return;
    }
    if (matches.length == 1) {
      _openVariantPicker(matches.first);
    } else {
      _openProductPicker(matches);
    }
    _searchController.clear();
  }

  void _addToCart(Product product, ProductVariant variant) {
    if (variant.quantity <= 0) {
      _toast(
        '${product.productName} (${variant.size}) is out of stock.',
        isError: true,
      );
      return;
    }

    final added = ref.read(cartProvider.notifier).addItem(product, variant);
    if (!added) {
      _toast(
        'Only ${variant.quantity} in stock — all of them are already in the basket.',
        isError: true,
      );
      return;
    }
    _toast('${product.productName} (${variant.size}) added.', isSuccess: true);
  }

  void _toast(String message, {bool isError = false, bool isSuccess = false}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(milliseconds: isError ? 3000 : 1200),
          backgroundColor: isError
              ? scheme.error
              : isSuccess
              ? Colors.green.shade700
              : null,
        ),
      );
  }

  void _openVariantPicker(Product product) {
    final symbol = ref.read(currencySymbolProvider);
    showDialog<void>(
      context: context,
      builder: (context) => AdaptiveDialog(
        title: Text(product.productName),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: product.variants.length,
            itemBuilder: (context, index) {
              final variant = product.variants[index];
              final outOfStock = variant.quantity <= 0;
              return ListTile(
                enabled: !outOfStock,
                title: Text(
                  'Size ${variant.size} · ${Fmt.money(variant.price, symbol)}',
                ),
                subtitle: Text('Barcode ${variant.barcode}'),
                trailing: _StockBadge(quantity: variant.quantity),
                onTap: outOfStock
                    ? null
                    : () {
                        Navigator.pop(context);
                        _addToCart(product, variant);
                      },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _openProductPicker(List<Product> products) {
    showDialog<void>(
      context: context,
      builder: (context) => AdaptiveDialog(
        title: Text('${products.length} matches'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              final inStock = product.variants.fold<int>(
                0,
                (sum, v) => sum + v.quantity,
              );
              return ListTile(
                title: Text(product.productName),
                subtitle: Text(
                  '${product.productCode} · ${product.variants.length} variants',
                ),
                trailing: _StockBadge(quantity: inStock),
                onTap: () {
                  Navigator.pop(context);
                  _openVariantPicker(product);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final settings = ref.watch(settingsProvider);
    final loyalty = ref.watch(loyaltySettingsProvider);
    final company = ref.watch(companyProvider);
    final products = ref.watch(productsProvider);

    final totals = SalePricing.computeCart(
      items: cartItems,
      settings: settings,
      loyalty: loyalty,
      company: company,
    );

    final cart = _CartPane(
      items: cartItems,
      settings: settings,
      totals: totals,
      onCheckout: cartItems.isEmpty ? null : _openCheckout,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing & POS'),
        actions: [
          const SyncStatusWidget(),
          if (cartItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.remove_shopping_cart_outlined),
              tooltip: 'Clear basket',
              onPressed: () => ref.read(cartProvider.notifier).clearCart(),
            ),
        ],
      ),
      body: ResponsiveBuilder(
        mobileBuilder: (context) => Column(
          children: [
            _SearchBar(
              controller: _searchController,
              focusNode: _searchFocus,
              isScanning: _isScanning,
              onSubmitted: _processSearch,
              onToggleScanner: _toggleScanner,
            ),
            if (_isScanning) _buildCameraPreview(),
            Expanded(child: cart),
          ],
        ),
        tabletBuilder: (context) => Row(
          children: [
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  _SearchBar(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    isScanning: _isScanning,
                    onSubmitted: _processSearch,
                    onToggleScanner: _toggleScanner,
                  ),
                  if (_isScanning) _buildCameraPreview(),
                  Expanded(
                    child: _CatalogueGrid(
                      products: products,
                      onPick: _openVariantPicker,
                    ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(flex: 4, child: cart),
          ],
        ),
        desktopBuilder: (context) => Row(
          children: [
            Expanded(
              flex: 6,
              child: Column(
                children: [
                  _SearchBar(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    isScanning: _isScanning,
                    onSubmitted: _processSearch,
                    onToggleScanner: _toggleScanner,
                  ),
                  if (_isScanning) _buildCameraPreview(),
                  Expanded(
                    child: _CatalogueGrid(
                      products: products,
                      onPick: _openVariantPicker,
                    ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            SizedBox(width: 440, child: cart),
          ],
        ),
      ),
      floatingActionButton:
          ResponsiveHelper.isMobile(context) && cartItems.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _openCheckout,
              icon: const Icon(Icons.shopping_cart_checkout),
              label: Text(
                '${cartItems.length} · ${Fmt.money(totals.grandTotal, settings.currencySymbol)}',
              ),
            )
          : null,
    );
  }

  Widget _buildCameraPreview() {
    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_scannerController != null)
            MobileScanner(
              controller: _scannerController!,
              onDetect: _onBarcodeDetected,
            ),
          Container(
            width: 220,
            height: 120,
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          Positioned(
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Point at barcode',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openCheckout() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CheckoutScreen()),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isScanning;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onToggleScanner;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.isScanning,
    required this.onSubmitted,
    required this.onToggleScanner,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: 'Scan barcode, type style code or product name…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (controller.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    controller.clear();
                    focusNode.requestFocus();
                  },
                ),
              IconButton(
                tooltip: isScanning ? 'Close scanner' : 'Scan with camera',
                icon: Icon(
                  isScanning ? Icons.camera_alt : Icons.camera_alt_outlined,
                  color: isScanning
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                onPressed: onToggleScanner,
              ),
            ],
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _CatalogueGrid extends StatelessWidget {
  final List<Product> products;
  final ValueChanged<Product> onPick;

  const _CatalogueGrid({required this.products, required this.onPick});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No products yet',
        message: 'Add products to your catalogue to start ringing up sales.',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        final inStock = product.variants.fold<int>(
          0,
          (sum, v) => sum + v.quantity,
        );
        final minPrice = product.variants.isEmpty
            ? 0.0
            : product.variants
                  .map((v) => v.price)
                  .reduce((a, b) => a < b ? a : b);

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: inStock > 0 ? () => onPick(product) : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'from ${Fmt.money(minPrice, '')}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      Text(
                        inStock > 0 ? '$inStock in stock' : 'Out of stock',
                        style: TextStyle(
                          fontSize: 12,
                          color: inStock > 0
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StockBadge extends StatelessWidget {
  final int quantity;

  const _StockBadge({required this.quantity});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOut = quantity <= 0;
    final isLow = !isOut && quantity <= 5;

    final bg = isOut
        ? theme.colorScheme.errorContainer
        : isLow
        ? Colors.amber.shade100
        : theme.colorScheme.surfaceContainerHighest;

    final fg = isOut
        ? theme.colorScheme.onErrorContainer
        : isLow
        ? Colors.amber.shade900
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isOut ? 'Out' : '$quantity in stock',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}

class _CartPane extends ConsumerWidget {
  final List<CartItem> items;
  final SettingsModel settings;
  final SaleTotals totals;
  final VoidCallback? onCheckout;

  const _CartPane({
    required this.items,
    required this.settings,
    required this.totals,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.shopping_basket_outlined,
        title: 'Basket is empty',
        message: 'Scan or search a dress to add it to the bill.',
      );
    }

    final symbol = settings.currencySymbol;
    final hasTaxIssues = totals.gstResult != null && !totals.gstResult!.isValid;

    return Column(
      children: [
        if (hasTaxIssues)
          Container(
            color: Colors.amber.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.amber.shade900,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    totals.gstResult!.errors.first,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              final atLimit = item.quantity >= item.variant.quantity;

              return Dismissible(
                key: ValueKey(item.variant.barcode),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Theme.of(context).colorScheme.error,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => ref
                    .read(cartProvider.notifier)
                    .removeItem(item.variant.barcode),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  title: Text(
                    item.product.productName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Size ${item.variant.size} · '
                    '${Fmt.money(item.variant.price, symbol)}'
                    '${item.product.hsn.isNotEmpty ? " · HSN: ${item.product.hsn}" : ""}',
                  ),
                  trailing: SizedBox(
                    width: 180,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Reduce quantity of ${item.displayName}',
                          icon: const Icon(Icons.remove_circle_outline),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => ref
                              .read(cartProvider.notifier)
                              .updateQuantity(
                                item.variant.barcode,
                                item.quantity - 1,
                              ),
                        ),
                        SizedBox(
                          width: 24,
                          child: Text(
                            '${item.quantity}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          visualDensity: VisualDensity.compact,
                          tooltip: atLimit ? 'No more in stock' : null,
                          onPressed: atLimit
                              ? null
                              : () => ref
                                    .read(cartProvider.notifier)
                                    .updateQuantity(
                                      item.variant.barcode,
                                      item.quantity + 1,
                                    ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 72,
                          child: Text(
                            Fmt.money(item.total, symbol),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _CartFooter(
          settings: settings,
          totals: totals,
          itemCount: items.fold(0, (sum, i) => sum + i.quantity),
          onCheckout: hasTaxIssues ? null : onCheckout,
        ),
      ],
    );
  }
}

class _CartFooter extends StatelessWidget {
  final SettingsModel settings;
  final SaleTotals totals;
  final int itemCount;
  final VoidCallback? onCheckout;

  const _CartFooter({
    required this.settings,
    required this.totals,
    required this.itemCount,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final symbol = settings.currencySymbol;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 8,
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            children: [
              _row(
                context,
                '$itemCount ${itemCount == 1 ? 'item' : 'items'} (Gross)',
                Fmt.money(totals.subtotal, symbol),
              ),
              if (totals.taxableAmount > 0)
                _row(
                  context,
                  'Taxable Value',
                  Fmt.money(totals.taxableAmount, symbol),
                ),
              if (totals.taxAmount > 0)
                _row(
                  context,
                  settings.taxMode == TaxMode.inclusive
                      ? 'GST Included (CGST+SGST/IGST)'
                      : 'GST Added (CGST+SGST/IGST)',
                  Fmt.money(totals.taxAmount, symbol),
                ),
              if (totals.roundOff != 0.0)
                _row(
                  context,
                  'Round-Off',
                  '${totals.roundOff >= 0 ? "+" : ""}${Fmt.money(totals.roundOff, symbol)}',
                ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payable Amount',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (totals.placeOfSupply.isNotEmpty)
                        Text(
                          'POS: ${totals.placeOfSupply}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                  Text(
                    Fmt.money(totals.grandTotal, symbol),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onCheckout,
                icon: const Icon(Icons.arrow_forward),
                label: const Text(
                  'Proceed to Checkout',
                  style: TextStyle(fontSize: 16),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
