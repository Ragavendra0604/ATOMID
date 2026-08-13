import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/presentation/features/billing/pos_screen.dart';
import 'package:atomid/presentation/features/billing/sales_history_screen.dart';
import 'package:atomid/presentation/features/expenses/expense_list_screen.dart';
import 'package:atomid/presentation/features/history/history_screen.dart';
import 'package:atomid/presentation/features/inventory/stock_in_screen.dart';
import 'package:atomid/presentation/features/price_tag/bulk_generator_screen.dart';
import 'package:atomid/presentation/features/scanner/barcode_scanner_screen.dart';
import 'package:atomid/presentation/features/sync/sync_status_widget.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/widgets/empty_state.dart';
import 'package:atomid/presentation/widgets/brand_title.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final products = ref.watch(productsProvider);
    final lowStock = ref.watch(lowStockItemsProvider);
    final outOfStock = ref.watch(outOfStockItemsProvider);
    final todayRevenue = ref.watch(todayRevenueProvider);
    final todaySales = ref.watch(todaySalesProvider);
    final todayItems = ref.watch(todayItemsSoldProvider);
    final valuation = ref.watch(inventoryValuationProvider);

    final symbol = settings.currencySymbol;

    return Scaffold(
      appBar: AppBar(
        title: BrandTitle(name: settings.companyName),
        actions: [
          const SyncStatusWidget(),
        ],
      ),
      body: products.isEmpty && todaySales.isEmpty
          ? EmptyState(
              icon: Icons.rocket_launch_outlined,
              title: 'Welcome to ${settings.companyName}',
              message:
                  'Add your first product, then start billing. '
                  'Everything works offline and syncs when you connect.',
              actionLabel: 'Add stock',
              onAction: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StockInScreen()),
              ),
            )
          : ListView(
              padding: ResponsivePadding.getScreenPadding(context),
              children: [
                _SectionTitle('Today'),
                _TodayGrid(
                  revenue: todayRevenue,
                  invoices: todaySales.length,
                  itemsSold: todayItems,
                  averageSale: todaySales.isEmpty
                      ? 0
                      : todayRevenue / todaySales.length,
                  currencySymbol: symbol,
                ),

                if (outOfStock.isNotEmpty || lowStock.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _SectionTitle('Needs attention'),
                  _StockAlerts(outOfStock: outOfStock, lowStock: lowStock),
                ],

                const SizedBox(height: 28),
                _SectionTitle('Quick actions'),
                _QuickActions(),

                const SizedBox(height: 28),
                _SectionTitle('Your store'),
                _StoreSummary(
                  productCount: products.length,
                  stockValue: valuation['retailValue'] ?? 0,
                  costValue: valuation['costValue'] ?? 0,
                  currencySymbol: symbol,
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _TodayGrid extends StatelessWidget {
  final double revenue;
  final int invoices;
  final int itemsSold;
  final double averageSale;
  final String currencySymbol;

  const _TodayGrid({
    required this.revenue,
    required this.invoices,
    required this.itemsSold,
    required this.averageSale,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _Stat(
        label: 'Revenue',
        value: Fmt.moneyCompact(revenue, currencySymbol),
        icon: Icons.payments_outlined,
        emphasis: true,
      ),
      _Stat(
        label: 'Invoices',
        value: Fmt.count(invoices),
        icon: Icons.receipt_long_outlined,
      ),
      _Stat(
        label: 'Items sold',
        value: Fmt.count(itemsSold),
        icon: Icons.shopping_bag_outlined,
      ),
      _Stat(
        label: 'Average sale',
        value: Fmt.moneyCompact(averageSale, currencySymbol),
        icon: Icons.trending_up,
      ),
    ];

    final columns = ResponsiveHelper.isDesktop(context)
        ? 4
        : ResponsiveHelper.isTablet(context)
        ? 4
        : 2;

    // A fixed height rather than an aspect ratio. Deriving the tile's height
    // from its width meant the cell shrank with the screen while the icon,
    // figure and label inside did not, so the tiles overflowed on narrow
    // phones and again at the 600px tablet breakpoint.
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 104,
      ),
      itemBuilder: (context, index) => tiles[index],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool emphasis;

  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: emphasis ? scheme.primaryContainer.withValues(alpha: 0.4) : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Out-of-stock lines used to vanish from the dashboard entirely: the
/// low-stock query required `quantity > 0`, so the moment something ran out it
/// disappeared from the one place the owner was looking.
class _StockAlerts extends StatelessWidget {
  final List<Map<String, dynamic>> outOfStock;
  final List<Map<String, dynamic>> lowStock;

  const _StockAlerts({required this.outOfStock, required this.lowStock});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        if (outOfStock.isNotEmpty)
          _AlertCard(
            color: scheme.error,
            icon: Icons.remove_shopping_cart_outlined,
            title: '${outOfStock.length} out of stock',
            items: outOfStock,
          ),
        if (lowStock.isNotEmpty) ...[
          if (outOfStock.isNotEmpty) const SizedBox(height: 10),
          _AlertCard(
            color: Colors.orange.shade800,
            icon: Icons.warning_amber_rounded,
            title: '${lowStock.length} running low',
            items: lowStock,
          ),
        ],
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final List<Map<String, dynamic>> items;

  const _AlertCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final preview = items.take(6).toList();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in preview)
                  _VariantChip(
                    product: item['product'] as Product,
                    variant: item['variant'] as ProductVariant,
                    color: color,
                  ),
                if (items.length > preview.length)
                  Chip(
                    label: Text('+${items.length - preview.length} more'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VariantChip extends StatelessWidget {
  final Product product;
  final ProductVariant variant;
  final Color color;

  const _VariantChip({
    required this.product,
    required this.variant,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      visualDensity: VisualDensity.compact,
      avatar: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Text(
          '${variant.quantity}',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
      label: Text(
        '${product.productName} · ${variant.size}',
        style: const TextStyle(fontSize: 12),
      ),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StockInScreen(
            preselectedProduct: product,
            preselectedVariant: variant,
          ),
        ),
      ),
    );
  }
}

/// Only actions that are *not* already permanent navigation destinations.
///
/// The previous grid repeated Products, Inventory, Purchases, Suppliers,
/// Customers and Reports — all of which sit in the nav rail — so tapping one
/// pushed a second copy on top of the shell.
class _QuickActions extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = <_Action>[
        _Action(
          'New sale',
          Icons.point_of_sale,
          const PosScreen(),
          primary: true,
        ),
        _Action(
          'Sales history',
          Icons.receipt_long,
          const SalesHistoryScreen(),
        ),
        _Action('Stock in', Icons.add_box_outlined, const StockInScreen()),
      _Action('Scan', Icons.qr_code_scanner, const BarcodeScannerScreen()),
      _Action('Price tags', Icons.sell_outlined, const BulkGeneratorScreen()),
        _Action(
          'Expenses',
          Icons.account_balance_wallet_outlined,
          const ExpenseListScreen(),
        ),
      _Action('Activity', Icons.history, const HistoryScreen()),
    ];

    if (actions.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: actions
          .map((a) => _ActionButton(action: a))
          .toList(growable: false),
    );
  }
}

class _Action {
  final String label;
  final IconData icon;
  final Widget screen;
  final bool primary;

  const _Action(this.label, this.icon, this.screen, {this.primary = false});
}

class _ActionButton extends StatelessWidget {
  final _Action action;

  const _ActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    void open() => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => action.screen),
    );

    if (action.primary) {
      return FilledButton.icon(
        onPressed: open,
        icon: Icon(action.icon),
        label: Text(action.label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: open,
      icon: Icon(action.icon, size: 18),
      label: Text(action.label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

class _StoreSummary extends StatelessWidget {
  final int productCount;
  final double stockValue;
  final double costValue;
  final String currencySymbol;

  const _StoreSummary({
    required this.productCount,
    required this.stockValue,
    required this.costValue,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final margin = stockValue - costValue;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            _row(context, 'Products', Fmt.count(productCount)),
            const Divider(height: 22),
            _row(
              context,
              'Stock at retail',
              Fmt.money(stockValue, currencySymbol),
            ),
            _row(
              context,
              'Stock at cost',
              Fmt.money(costValue, currencySymbol),
            ),
            _row(
              context,
              'Potential margin',
              Fmt.money(margin, currencySymbol),
              color: margin >= 0 ? Colors.green.shade700 : scheme.error,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // Two bare Texts under spaceBetween have nothing to give when the
          // pair is wider than the row, so the label takes the slack and
          // ellipsises while the figure keeps its full width.
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
