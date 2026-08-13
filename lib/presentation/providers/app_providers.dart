import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/data/models/action_history_model.dart';
import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/customer_ledger_model.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/expense_model.dart';
import 'package:atomid/data/models/inventory_movement_model.dart';
import 'package:atomid/data/models/invoice_settings_model.dart';
import 'package:atomid/data/models/sync_log_model.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/models/loyalty_transaction_model.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/data/models/supplier_ledger_model.dart';
import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/data/models/sync_queue_model.dart';
import 'package:atomid/data/repositories/firebase_repository.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/domain/services/auth_service.dart';
import 'package:atomid/domain/services/backup_service.dart';
import 'package:atomid/domain/services/customer_service.dart';
import 'package:atomid/domain/services/expense_service.dart';
import 'package:atomid/domain/services/purchase_service.dart';
import 'package:atomid/domain/services/sale_service.dart';
import 'package:atomid/domain/services/session_service.dart';
import 'package:atomid/domain/services/supplier_service.dart';
import 'package:atomid/domain/services/sync_service.dart';

// ---------------------------------------------------------------------------
// Composition root
//
// Every long-lived service is created once in `bootstrap()` and injected here.
// These providers deliberately throw when unoverridden: a second construction
// path would give tests and entry points a different object graph than the app.
// ---------------------------------------------------------------------------

final storageRepositoryProvider = Provider<StorageRepository>(
  (ref) => throw UnimplementedError('StorageRepository was not injected'),
);

final firebaseRepositoryProvider = Provider<FirebaseRepository>(
  (ref) => throw UnimplementedError('FirebaseRepository was not injected'),
);

final authServiceProvider = Provider<AuthService>(
  (ref) => throw UnimplementedError('AuthService was not injected'),
);

final sessionServiceProvider = Provider<SessionService>(
  (ref) => throw UnimplementedError('SessionService was not injected'),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(storageRepositoryProvider)),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => throw UnimplementedError('SyncService was not injected'),
);

// ---------------------------------------------------------------------------
// Change tracking
//
// Read providers below watch a topic rather than depending on each screen
// calling the right invalidator after a write.
// ---------------------------------------------------------------------------

class DataVersionNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    final repo = ref.watch(storageRepositoryProvider);
    final subscription = repo.changes.listen((topic) {
      state = {...state, topic: (state[topic] ?? 0) + 1};
    });
    ref.onDispose(subscription.cancel);
    return {for (final topic in DataTopic.all) topic: 0};
  }
}

final dataVersionProvider =
    NotifierProvider<DataVersionNotifier, Map<String, int>>(
      DataVersionNotifier.new,
    );

/// Subscribes the calling provider to one area of the store.
void _watch(Ref ref, String topic) {
  ref.watch(dataVersionProvider.select((versions) => versions[topic]));
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

final settingsProvider = Provider<SettingsModel>((ref) {
  _watch(ref, DataTopic.settings);
  return ref.watch(storageRepositoryProvider).getSettings();
});

final invoiceSettingsProvider = Provider<InvoiceSettingsModel>((ref) {
  _watch(ref, DataTopic.settings);
  return ref.watch(storageRepositoryProvider).getInvoiceSettings();
});

final companyProvider = Provider<CompanyModel>((ref) {
  _watch(ref, DataTopic.settings);
  return ref.watch(storageRepositoryProvider).getCompany();
});

final loyaltySettingsProvider = Provider<LoyaltySettingsModel>((ref) {
  _watch(ref, DataTopic.loyalty);
  return ref.watch(storageRepositoryProvider).getLoyaltySettings();
});

/// Convenience: the currency symbol alone, so widgets that only need it do not
/// rebuild when an unrelated setting changes.
final currencySymbolProvider = Provider<String>(
  (ref) => ref.watch(settingsProvider.select((s) => s.currencySymbol)),
);

// ---------------------------------------------------------------------------
// Products & inventory
// ---------------------------------------------------------------------------

final productsProvider = Provider<List<Product>>((ref) {
  _watch(ref, DataTopic.products);
  return ref.watch(storageRepositoryProvider).getAllProducts();
});

final historyListProvider = Provider<List<ActionHistory>>((ref) {
  _watch(ref, DataTopic.history);
  return ref.watch(storageRepositoryProvider).getHistory();
});

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void setQuery(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

final filteredProductsProvider = Provider<List<Product>>((ref) {
  _watch(ref, DataTopic.products);
  final repo = ref.watch(storageRepositoryProvider);
  return repo.searchProducts(ref.watch(searchQueryProvider));
});

final lowStockItemsProvider = Provider<List<Map<String, dynamic>>>((ref) {
  _watch(ref, DataTopic.inventory);
  return ref.watch(storageRepositoryProvider).getLowStockItems();
});

final outOfStockItemsProvider = Provider<List<Map<String, dynamic>>>((ref) {
  _watch(ref, DataTopic.inventory);
  return ref.watch(storageRepositoryProvider).getOutOfStockItems();
});

final totalStockUnitsProvider = Provider<int>((ref) {
  _watch(ref, DataTopic.inventory);
  return ref.watch(storageRepositoryProvider).getTotalStockUnits();
});

final inventoryMovementsProvider = Provider<List<InventoryMovement>>((ref) {
  _watch(ref, DataTopic.inventory);
  return ref.watch(storageRepositoryProvider).getAllMovements();
});

final inventoryValuationProvider = Provider<Map<String, double>>((ref) {
  _watch(ref, DataTopic.inventory);
  return ref.watch(storageRepositoryProvider).calculateInventoryValue();
});

// ---------------------------------------------------------------------------
// Sales
// ---------------------------------------------------------------------------

final saleServiceProvider = Provider<SaleService>(
  (ref) => SaleService(
    ref.watch(storageRepositoryProvider),
    ref.watch(sessionServiceProvider),
  ),
);

final salesProvider = Provider<List<Sale>>((ref) {
  _watch(ref, DataTopic.sales);
  return ref.watch(storageRepositoryProvider).getAllSales();
});

final todaySalesProvider = Provider<List<Sale>>((ref) {
  _watch(ref, DataTopic.sales);
  return ref.watch(storageRepositoryProvider).getTodaySales();
});

final todayRevenueProvider = Provider<double>((ref) {
  _watch(ref, DataTopic.sales);
  return ref.watch(storageRepositoryProvider).getTodayRevenue();
});

final todayItemsSoldProvider = Provider<int>((ref) {
  _watch(ref, DataTopic.sales);
  return ref.watch(storageRepositoryProvider).getTodayItemsSold();
});

// ---------------------------------------------------------------------------
// Suppliers
// ---------------------------------------------------------------------------

final supplierServiceProvider = Provider<SupplierService>(
  (ref) => SupplierService(ref.watch(storageRepositoryProvider)),
);

final suppliersProvider = Provider<List<Supplier>>((ref) {
  _watch(ref, DataTopic.suppliers);
  return ref.watch(storageRepositoryProvider).getSuppliers();
});

final activeSuppliersProvider = Provider<List<Supplier>>((ref) {
  _watch(ref, DataTopic.suppliers);
  return ref.watch(storageRepositoryProvider).getActiveSuppliers();
});

class SupplierSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void setQuery(String query) => state = query;
}

final supplierSearchProvider = NotifierProvider<SupplierSearchNotifier, String>(
  SupplierSearchNotifier.new,
);

class SupplierCategoryFilterNotifier extends Notifier<String> {
  @override
  String build() => 'All';
  void setCategory(String category) => state = category;
}

final supplierCategoryFilterProvider =
    NotifierProvider<SupplierCategoryFilterNotifier, String>(
      SupplierCategoryFilterNotifier.new,
    );

final filteredSuppliersProvider = Provider<List<Supplier>>((ref) {
  _watch(ref, DataTopic.suppliers);
  final repo = ref.watch(storageRepositoryProvider);
  final query = ref.watch(supplierSearchProvider);
  final category = ref.watch(supplierCategoryFilterProvider);

  if (query.isEmpty) return repo.getSuppliersByCategory(category);

  final matches = repo.searchSuppliers(query);
  if (category == 'All') return matches;
  return matches.where((s) => s.supplierCategory == category).toList();
});

final supplierLedgerProvider = Provider.family<List<SupplierLedger>, String>((
  ref,
  supplierId,
) {
  _watch(ref, DataTopic.suppliers);
  return ref.watch(storageRepositoryProvider).getLedgerForSupplier(supplierId);
});

// ---------------------------------------------------------------------------
// Purchases
// ---------------------------------------------------------------------------

final purchaseServiceProvider = Provider<PurchaseService>(
  (ref) => PurchaseService(ref.watch(storageRepositoryProvider)),
);

final purchasesProvider = Provider<List<Purchase>>((ref) {
  _watch(ref, DataTopic.purchases);
  return ref.watch(storageRepositoryProvider).getPurchases();
});

class PurchaseSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void setQuery(String query) => state = query;
}

final purchaseSearchProvider = NotifierProvider<PurchaseSearchNotifier, String>(
  PurchaseSearchNotifier.new,
);

class PurchaseStatusFilterNotifier extends Notifier<String> {
  @override
  String build() => 'All';
  void setStatus(String status) => state = status;
}

final purchaseStatusFilterProvider =
    NotifierProvider<PurchaseStatusFilterNotifier, String>(
      PurchaseStatusFilterNotifier.new,
    );

final filteredPurchasesProvider = Provider<List<Purchase>>((ref) {
  _watch(ref, DataTopic.purchases);
  final repo = ref.watch(storageRepositoryProvider);
  final query = ref.watch(purchaseSearchProvider);
  final status = ref.watch(purchaseStatusFilterProvider);

  final list = query.isEmpty
      ? repo.getPurchases()
      : repo.searchPurchases(query);
  if (status == 'All') return list;
  return list.where((p) => p.status == status).toList();
});

final todayPurchasesProvider = Provider<List<Purchase>>((ref) {
  _watch(ref, DataTopic.purchases);
  return ref.watch(storageRepositoryProvider).getTodayPurchases();
});

// ---------------------------------------------------------------------------
// Expenses
// ---------------------------------------------------------------------------

final expenseServiceProvider = Provider<ExpenseService>(
  (ref) => ExpenseService(ref.watch(storageRepositoryProvider)),
);

final expensesProvider = Provider<List<Expense>>((ref) {
  _watch(ref, DataTopic.expenses);
  return ref.watch(expenseServiceProvider).getAllExpenses();
});

final expenseCategoriesProvider = Provider<List<ExpenseCategory>>((ref) {
  _watch(ref, DataTopic.expenses);
  return ref.watch(expenseServiceProvider).getExpenseCategories();
});

// ---------------------------------------------------------------------------
// Customers & loyalty
// ---------------------------------------------------------------------------

final customerServiceProvider = Provider<CustomerService>(
  (ref) => CustomerService(
    ref.watch(storageRepositoryProvider),
    ref.watch(sessionServiceProvider),
  ),
);

final customersProvider = Provider<List<Customer>>((ref) {
  _watch(ref, DataTopic.customers);
  return ref.watch(customerServiceProvider).getAllCustomers();
});

class CustomerSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void setQuery(String query) => state = query;
}

final customerSearchProvider = NotifierProvider<CustomerSearchNotifier, String>(
  CustomerSearchNotifier.new,
);

class CustomerGroupFilterNotifier extends Notifier<String> {
  @override
  String build() => 'All';
  void setGroup(String group) => state = group;
}

final customerGroupFilterProvider =
    NotifierProvider<CustomerGroupFilterNotifier, String>(
      CustomerGroupFilterNotifier.new,
    );

final filteredCustomersProvider = Provider<List<Customer>>((ref) {
  _watch(ref, DataTopic.customers);
  final service = ref.watch(customerServiceProvider);
  final query = ref.watch(customerSearchProvider);
  final group = ref.watch(customerGroupFilterProvider);

  if (query.isEmpty) return service.getCustomersByGroup(group);

  final matches = service.searchCustomers(query);
  if (group == 'All') return matches;
  return matches.where((c) => c.customerGroup == group).toList();
});

final customerLedgerProvider = Provider.family<List<CustomerLedger>, String>((
  ref,
  customerId,
) {
  _watch(ref, DataTopic.customers);
  return ref.watch(storageRepositoryProvider).getLedgerForCustomer(customerId);
});

final loyaltyTransactionsProvider =
    Provider.family<List<LoyaltyTransaction>, String>((ref, customerId) {
      _watch(ref, DataTopic.loyalty);
      return ref
          .watch(storageRepositoryProvider)
          .getLoyaltyTransactions(customerId);
    });

// ---------------------------------------------------------------------------
// Authentication & sync status
// ---------------------------------------------------------------------------

final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges,
);

/// Live sync state, driven by the service itself.
///
/// This used to be a string that nothing ever wrote, so the cloud icon showed
/// a green "Synced" no matter how deep or broken the queue was.
class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() {
    final service = ref.watch(syncServiceProvider);
    final subscription = service.statusStream.listen((status) {
      state = status;
    });
    ref.onDispose(subscription.cancel);
    return service.status;
  }
}

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(
  SyncStatusNotifier.new,
);

final pendingSyncItemsProvider = Provider<List<SyncQueueItem>>((ref) {
  _watch(ref, DataTopic.sync);
  return ref.watch(storageRepositoryProvider).getPendingSyncItems();
});

final deadSyncItemsProvider = Provider<List<SyncQueueItem>>((ref) {
  _watch(ref, DataTopic.sync);
  return ref.watch(storageRepositoryProvider).getDeadSyncItems();
});

/// Recent sync outcomes for the system console.
final syncLogProvider = Provider<List<SyncLogModel>>((ref) {
  _watch(ref, DataTopic.sync);
  return ref.watch(storageRepositoryProvider).getSyncLogs();
});

/// Only the failures — what a technician opens first.
final syncFailureLogProvider = Provider<List<SyncLogModel>>((ref) {
  _watch(ref, DataTopic.sync);
  return ref.watch(storageRepositoryProvider).getSyncLogs(failuresOnly: true);
});

/// Whether this device is backed up to the cloud right now.
///
/// Signing in is the only thing it controls: every screen works either way,
/// on-device. This is what the settings entry and the sync indicator read.
final isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(authStateProvider).value != null,
);
