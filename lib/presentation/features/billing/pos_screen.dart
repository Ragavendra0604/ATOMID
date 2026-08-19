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

  /// The camera is only held while the scanner is on screen — keeping a
  /// controller alive for the whole session drains battery and blocks other
  /// apps from the camera.
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

    // An exact barcode goes straight into the basket — the fast path a
    // cashier uses hundreds of times a day.
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
    final products = ref.watch(productsProvider);

    final totals = SalePricing.compute(
      lineItemTotal: cartItems.fold(0.0, (sum, item) => sum + item.total),
      settings: settings,
      loyalty: loyalty,
    );

    final cart = _CartPane(
      items: cartItems,
      settings: settings,
      totals: totals,
      onCheckout: cartItems.isEmpty ? null : _openCheckout,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing'),
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
            _buildSearchBar(),
            if (_isScanning) _buildScanner(),
            Expanded(child: cart),
          ],
        ),
        tabletBuilder: (context) =>
            _splitLayout(products, cart, catalogFlex: 5),
        desktopBuilder: (context) =>
            _splitLayout(products, cart, catalogFlex: 6),
      ),
    );
  }

  Widget _splitLayout(
    List<Product> products,
    Widget cart, {
    required int catalogFlex,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: catalogFlex,
          child: Column(
            children: [
              _buildSearchBar(),
              if (_isScanning) _buildScanner(),
              Expanded(child: _buildCatalog(products)),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(flex: 4, child: cart),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Scan a barcode or search by name',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: _processSearch,
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filled(
            onPressed: _toggleScanner,
            tooltip: _isScanning ? 'Stop scanning' : 'Scan barcode',
            icon: Icon(_isScanning ? Icons.stop : Icons.qr_code_scanner),
            style: IconButton.styleFrom(
              backgroundColor: _isScanning
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    final controller = _scannerController;
    if (controller == null) return const SizedBox.shrink();
    return SizedBox(
      height: 220,
      child: MobileScanner(
        controller: controller,
        onDetect: _onBarcodeDetected,
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Camera unavailable. Type or paste the barcode instead.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCatalog(List<Product> products) {
    if (products.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No products yet',
        message: 'Add your first product to start billing.',
      );
    }

    final symbol = ref.watch(currencySymbolProvider);

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.95,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        final stock = product.variants.fold<int>(
          0,
          (sum, v) => sum + v.quantity,
        );
        final lowest = product.variants.isEmpty
            ? 0.0
            : product.variants
                  .map((v) => v.price)
                  .reduce((a, b) => a < b ? a : b);

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: stock <= 0
                ? null
                : () {
                    if (product.variants.length == 1) {
                      _addToCart(product, product.variants.first);
                    } else {
                      _openVariantPicker(product);
                    }
                  },
            child: Opacity(
              opacity: stock <= 0 ? 0.45 : 1,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: _StockBadge(quantity: stock),
                    ),
                    const Spacer(),
                    Text(
                      product.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product.variants.length > 1
                          ? 'from ${Fmt.money(lowest, symbol)}'
                          : Fmt.money(lowest, symbol),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openCheckout() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CheckoutScreen()),
    );
  }
}

class _StockBadge extends StatelessWidget {
  final int quantity;

  const _StockBadge({required this.quantity});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (quantity) {
      <= 0 => ('Out of stock', scheme.error),
      < 5 => ('$quantity left', Colors.orange.shade800),
      _ => ('$quantity in stock', Colors.green.shade700),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
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
        icon: Icons.shopping_cart_outlined,
        title: 'Basket is empty',
        message: 'Scan a barcode or tap a product to begin.',
      );
    }

    final symbol = settings.currencySymbol;

    return Column(
      children: [
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
                    '${Fmt.money(item.variant.price, symbol)}',
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
          onCheckout: onCheckout,
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
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            children: [
              _row(
                context,
                '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                Fmt.money(totals.subtotal, symbol),
              ),
              if (totals.taxAmount > 0)
                _row(
                  context,
                  settings.taxMode == TaxMode.inclusive
                      ? 'Includes tax (${settings.taxRate}%)'
                      : 'Tax (${settings.taxRate}%)',
                  Fmt.money(totals.taxAmount, symbol),
                ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    Fmt.money(totals.grandTotal, symbol),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onCheckout,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Checkout', style: TextStyle(fontSize: 17)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
