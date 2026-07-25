import 'package:flutter/material.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/presentation/features/dashboard/dashboard_screen.dart';
import 'package:atomid/presentation/features/products/product_list_screen.dart';
import 'package:atomid/presentation/features/inventory/inventory_dashboard_screen.dart';
import 'package:atomid/presentation/features/purchases/purchase_list_screen.dart';
import 'package:atomid/presentation/features/suppliers/supplier_list_screen.dart';
import 'package:atomid/presentation/features/customers/customer_list_screen.dart';
import 'package:atomid/presentation/features/reports/reports_dashboard_screen.dart';
import 'package:atomid/presentation/features/settings/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  // All screens for rail/sidebar (8 destinations)
  final List<Widget> _allScreens = const [
    DashboardScreen(),
    ProductListScreen(),
    InventoryDashboardScreen(),
    PurchaseListScreen(),
    SupplierListScreen(),
    CustomerListScreen(),
    ReportsDashboardScreen(),
    SettingsScreen(),
  ];

  // Mobile bottom nav: only 4 main + More
  // "More" opens a sheet with the remaining destinations
  final List<NavigationDestination> _mobileDestinations = const [
    NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.inventory_2_outlined),
      selectedIcon: Icon(Icons.inventory_2),
      label: 'Products',
    ),
    NavigationDestination(
      icon: Icon(Icons.storefront_outlined),
      selectedIcon: Icon(Icons.storefront),
      label: 'Inventory',
    ),
    NavigationDestination(
      icon: Icon(Icons.bar_chart_outlined),
      selectedIcon: Icon(Icons.bar_chart),
      label: 'Reports',
    ),
    NavigationDestination(
      icon: Icon(Icons.more_horiz),
      selectedIcon: Icon(Icons.more_horiz),
      label: 'More',
    ),
  ];

  // Rail destinations for tablet/desktop (all 7)
  final List<NavigationRailDestination> _railDestinations = const [
    NavigationRailDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: Text('Dashboard'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.inventory_2_outlined),
      selectedIcon: Icon(Icons.inventory_2),
      label: Text('Products'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.storefront_outlined),
      selectedIcon: Icon(Icons.storefront),
      label: Text('Inventory'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.shopping_cart_outlined),
      selectedIcon: Icon(Icons.shopping_cart),
      label: Text('Purchases'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.business_outlined),
      selectedIcon: Icon(Icons.business),
      label: Text('Suppliers'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.people_outline),
      selectedIcon: Icon(Icons.people),
      label: Text('Customers'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.bar_chart_outlined),
      selectedIcon: Icon(Icons.bar_chart),
      label: Text('Reports'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: Text('Settings'),
    ),
  ];

  // Maps mobile bottom nav index to _allScreens index
  // 0=Dashboard, 1=Products, 2=Inventory, 3=Reports, 4=More (sheet)
  static const List<int> _mobileIndexMap = [0, 1, 2, 6];

  void _onMobileDestinationSelected(int index) {
    if (index == 4) {
      // Show "More" bottom sheet
      _showMoreSheet();
    } else {
      setState(() => _selectedIndex = _mobileIndexMap[index]);
    }
  }

  void _showMoreSheet() {
    final moreItems = [
      _MoreItem('Purchases', Icons.shopping_cart, 3),
      _MoreItem('Suppliers', Icons.business, 4),
      _MoreItem('Customers', Icons.people, 5),
      _MoreItem('Settings', Icons.settings, 7),
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ...moreItems.map(
                  (item) => ListTile(
                    leading: Icon(
                      item.icon,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      item.label,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    selected: _selectedIndex == item.screenIndex,
                    selectedTileColor: Theme.of(
                      context,
                    ).colorScheme.primary.withAlpha(20),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _selectedIndex = item.screenIndex);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Which mobile bottom nav index corresponds to current _selectedIndex
  int get _mobileBottomIndex {
    final idx = _mobileIndexMap.indexOf(_selectedIndex);
    if (idx != -1) return idx;
    return 4; // "More" tab highlighted for Purchases/Suppliers/Settings
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      mobileBuilder: (context) => _buildMobile(context),
      tabletBuilder: (context) => _buildTablet(context),
      desktopBuilder: (context) => _buildDesktop(context),
    );
  }

  Widget _buildMobile(BuildContext context) {
    return Scaffold(
      body: _allScreens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _mobileBottomIndex,
        onDestinationSelected: _onMobileDestinationSelected,
        destinations: _mobileDestinations,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 65,
      ),
    );
  }

  Widget _buildTablet(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.all,
            destinations: _railDestinations,
            extended: false,
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _allScreens[_selectedIndex]),
        ],
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.none,
            destinations: _railDestinations,
            extended: true,
            minExtendedWidth: 250,
            leading: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(
                    Icons.store,
                    color: Theme.of(context).colorScheme.primary,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Atomid Store',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _allScreens[_selectedIndex]),
        ],
      ),
    );
  }
}

class _MoreItem {
  final String label;
  final IconData icon;
  final int screenIndex;
  const _MoreItem(this.label, this.icon, this.screenIndex);
}
