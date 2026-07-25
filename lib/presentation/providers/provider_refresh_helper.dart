import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

class ProviderRefreshHelper {
  static void invalidateInventoryProviders(WidgetRef ref) {
    ref.invalidate(totalStockUnitsProvider);
    ref.invalidate(lowStockItemsProvider);
    ref.invalidate(outOfStockItemsProvider);
    ref.invalidate(inventoryMovementsProvider);
    ref.invalidate(inventoryValuationProvider);
  }

  static void invalidateProductProviders(WidgetRef ref) {
    ref.invalidate(productsProvider);
    ref.invalidate(filteredProductsProvider);
    ref.invalidate(historyListProvider);
    invalidateInventoryProviders(ref);
  }

  static void invalidateSalesProviders(WidgetRef ref) {
    ref.invalidate(salesProvider);
    ref.invalidate(todaySalesProvider);
    ref.invalidate(todayRevenueProvider);
    ref.invalidate(todayItemsSoldProvider);
    invalidateProductProviders(ref); // Sales affect inventory and products
    invalidateCustomerProviders(ref); // Sales affect customer balances
  }

  static void invalidateCustomerProviders(WidgetRef ref) {
    ref.invalidate(customersProvider);
    ref.invalidate(filteredCustomersProvider);
    // Note: family providers like customerLedgerProvider are trickier to invalidate directly without knowing the ID, 
    // but invalidating customersProvider will update the main list.
  }

  static void invalidatePurchaseProviders(WidgetRef ref) {
    ref.invalidate(purchasesProvider);
    ref.invalidate(filteredPurchasesProvider);
    ref.invalidate(todayPurchasesProvider);
    invalidateProductProviders(ref); // Purchases affect inventory and products
  }

  static void invalidateSupplierProviders(WidgetRef ref) {
    ref.invalidate(suppliersProvider);
    ref.invalidate(filteredSuppliersProvider);
    ref.invalidate(activeSuppliersProvider);
    ref.invalidate(supplierLedgerProvider);
    ref.invalidate(historyListProvider);
  }

  static void invalidateExpenseProviders(WidgetRef ref) {
    ref.invalidate(expensesProvider);
    ref.invalidate(expenseCategoriesProvider);
  }
}
