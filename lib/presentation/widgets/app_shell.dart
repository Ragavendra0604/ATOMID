import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/bootstrap.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/presentation/features/customers/customer_list_screen.dart';
import 'package:atomid/presentation/features/dashboard/dashboard_screen.dart';
import 'package:atomid/presentation/features/inventory/inventory_dashboard_screen.dart';
import 'package:atomid/presentation/features/products/product_list_screen.dart';
import 'package:atomid/presentation/features/purchases/purchase_list_screen.dart';
import 'package:atomid/presentation/features/reports/reports_dashboard_screen.dart';
import 'package:atomid/presentation/features/settings/settings_screen.dart';
import 'package:atomid/presentation/features/suppliers/supplier_list_screen.dart';
import 'package:atomid/presentation/features/system/system_console_screen.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/widgets/brand_title.dart';

/// One navigation destination.
class _Destination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;

  /// Sits on the phone bottom bar rather than behind "More".
  final bool primaryOnMobile;

  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
    this.primaryOnMobile = false,
  });
}

class AppShell extends ConsumerStatefulWidget {
  final BootstrapResult? startup;

  const AppShell({super.key, this.startup});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;
  bool _noticesShown = false;

  /// Destinations the user has opened, keyed by label rather than position so
  /// reordering cannot make an entry point at a different screen.
  final _visited = <String>{};

  /// Switches tab and records the destination as built.
  void _select(int index, List<_Destination> visible) {
    setState(() {
      _selectedIndex = index;
      _visited.add(visible[index].label);
    });
  }

  static const _destinations = <_Destination>[
    _Destination(
      label: 'Home',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      screen: DashboardScreen(),
      primaryOnMobile: true,
    ),
    _Destination(
      label: 'Products',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
      screen: ProductListScreen(),
      primaryOnMobile: true,
    ),
    _Destination(
      label: 'Stock',
      icon: Icons.storefront_outlined,
      selectedIcon: Icons.storefront,
      screen: InventoryDashboardScreen(),
      primaryOnMobile: true,
    ),
    _Destination(
      label: 'Purchases',
      icon: Icons.shopping_cart_outlined,
      selectedIcon: Icons.shopping_cart,
      screen: PurchaseListScreen(),
    ),
    _Destination(
      label: 'Suppliers',
      icon: Icons.business_outlined,
      selectedIcon: Icons.business,
      screen: SupplierListScreen(),
    ),
    _Destination(
      label: 'Customers',
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      screen: CustomerListScreen(),
    ),
    _Destination(
      label: 'Reports',
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
      screen: ReportsDashboardScreen(),
      primaryOnMobile: true,
    ),
    _Destination(
      label: 'System',
      icon: Icons.monitor_heart_outlined,
      selectedIcon: Icons.monitor_heart,
      screen: SystemConsoleScreen(),
      primaryOnMobile: true,
    ),
    _Destination(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      screen: SettingsScreen(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showStartupNotices());
  }

  /// Surfaces anything startup wants the user to know — recovered data or a
  /// cloud that could not be reached — instead of failing silently.
  void _showStartupNotices() {
    if (_noticesShown || !mounted) return;
    _noticesShown = true;

    final startup = widget.startup;
    if (startup == null) return;

    final messenger = ScaffoldMessenger.of(context);

    if (startup.recoveredBoxes.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text(
            'Some data could not be read and was reset: '
            '${startup.recoveredBoxes.join(', ')}. '
            'Sign in and fetch from the cloud to restore it.',
          ),
        ),
      );
      return;
    }

    if (startup.cloudMessage != null) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(startup.cloudMessage!),
        ),
      );
    }
  }

  /// Every destination. One user, so there is nothing to filter on.
  List<_Destination> _visibleDestinations() => _destinations;

  @override
  Widget build(BuildContext context) {
    final visible = _visibleDestinations();
    final safeIndex = _selectedIndex.clamp(0, visible.length - 1);

    // IndexedStack keeps each screen alive, so scroll position, search text
    // and filters survive a tab switch instead of being rebuilt from scratch.
    //
    // Only screens that have actually been opened are built. Handing it every
    // destination meant the first frame after startup constructed all eight at
    // once — every list, dashboard and report querying storage before the user
    // had looked at any of them. Visited screens stay in the stack, so the
    // state that survives a tab switch still survives.
    final body = IndexedStack(
      index: safeIndex,
      children: [
        for (var i = 0; i < visible.length; i++)
          if (i == safeIndex || _visited.contains(visible[i].label))
            visible[i].screen
          else
            const SizedBox.shrink(),
      ],
    );

    return ResponsiveBuilder(
      mobileBuilder: (context) => _mobile(visible, safeIndex, body),
      tabletBuilder: (context) =>
          _rail(visible, safeIndex, body, extended: false),
      desktopBuilder: (context) =>
          _rail(visible, safeIndex, body, extended: true),
    );
  }

  Widget _mobile(List<_Destination> visible, int index, Widget body) {
    final all = List<int>.generate(visible.length, (i) => i);
    final primary = all.where((i) => visible[i].primaryOnMobile).toList();
    final overflow = all.where((i) => !visible[i].primaryOnMobile).toList();

    final barIndex = primary.indexOf(index);

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: barIndex >= 0 ? barIndex : primary.length,
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) {
          if (i < primary.length) {
            _select(primary[i], visible);
          } else {
            _showMoreSheet(visible, overflow);
          }
        },
        destinations: [
          for (final i in primary)
            NavigationDestination(
              icon: Icon(visible[i].icon),
              selectedIcon: Icon(visible[i].selectedIcon),
              label: visible[i].label,
            ),
          if (overflow.isNotEmpty)
            const NavigationDestination(
              icon: Icon(Icons.more_horiz),
              label: 'More',
            ),
        ],
      ),
    );
  }

  void _showMoreSheet(List<_Destination> visible, List<int> overflow) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final i in overflow)
              ListTile(
                leading: Icon(visible[i].icon),
                title: Text(visible[i].label),
                selected: _selectedIndex == i,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _select(i, visible);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _rail(
    List<_Destination> visible,
    int index,
    Widget body, {
    required bool extended,
  }) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) => _select(i, visible),
            extended: extended,
            minExtendedWidth: 230,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            leading: extended
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: BrandTitle(
                      name: ref.watch(
                        settingsProvider.select((s) => s.companyName),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      logoSize: 28,
                    ),
                  )
                : null,
            destinations: visible
                .map(
                  (d) => NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}
