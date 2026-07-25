import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/domain/services/customer_service.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/action_history_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/data/models/invoice_settings_model.dart';
import 'package:atomid/data/models/inventory_movement_model.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/data/models/supplier_ledger_model.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/customer_ledger_model.dart';
import 'package:atomid/data/models/loyalty_transaction_model.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/data/repositories/firebase_repository.dart';
import 'package:atomid/domain/services/auth_service.dart';
import 'package:atomid/domain/services/session_service.dart';
import 'package:atomid/domain/services/sync_service.dart';
import 'package:atomid/domain/services/supplier_service.dart';
import 'package:atomid/domain/services/purchase_service.dart';
import 'package:atomid/domain/services/expense_service.dart';
import 'package:atomid/data/models/expense_model.dart';
import 'package:atomid/data/models/employee_model.dart';
import 'package:atomid/data/models/login_history_model.dart';
import 'package:atomid/data/models/activity_log_model.dart';
import 'package:atomid/data/models/role_model.dart';
import 'package:firebase_auth/firebase_auth.dart';

final storageRepositoryProvider = Provider<StorageRepository>((ref) {
  throw UnimplementedError('StorageRepository is not initialized');
});

final sessionServiceProvider = Provider<SessionService>((ref) {
  throw UnimplementedError('SessionService is not initialized');
});

final productsProvider = Provider<List<Product>>((ref) {
  return ref.watch(storageRepositoryProvider).getAllProducts();
});

final historyListProvider = Provider<List<ActionHistory>>((ref) {
  return ref.watch(storageRepositoryProvider).getHistory();
});

final settingsProvider = Provider<SettingsModel>((ref) {
  return ref.watch(storageRepositoryProvider).getSettings();
});

final invoiceSettingsProvider = Provider<InvoiceSettingsModel>((ref) {
  return ref.watch(storageRepositoryProvider).getInvoiceSettings();
});

final companyProvider = Provider<CompanyModel>((ref) {
  return ref.watch(storageRepositoryProvider).getCompany();
});

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(() {
  return SearchQueryNotifier();
});

final filteredProductsProvider = Provider<List<Product>>((ref) {
  final repo = ref.watch(storageRepositoryProvider);
  final query = ref.watch(searchQueryProvider);
  return repo.searchProducts(query);
});

// --- INVENTORY PROVIDERS ---

final lowStockItemsProvider = Provider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(storageRepositoryProvider).getLowStockItems();
});

final outOfStockItemsProvider = Provider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(storageRepositoryProvider).getOutOfStockItems();
});

final totalStockUnitsProvider = Provider<int>((ref) {
  return ref.watch(storageRepositoryProvider).getTotalStockUnits();
});

final inventoryMovementsProvider = Provider<List<InventoryMovement>>((ref) {
  return ref.watch(storageRepositoryProvider).getAllMovements();
});

// --- SALES PROVIDERS ---

final salesProvider = Provider<List<Sale>>((ref) {
  return ref.watch(storageRepositoryProvider).getAllSales();
});

final todaySalesProvider = Provider<List<Sale>>((ref) {
  return ref.watch(storageRepositoryProvider).getTodaySales();
});

final todayRevenueProvider = Provider<double>((ref) {
  return ref.watch(storageRepositoryProvider).getTodayRevenue();
});

final todayItemsSoldProvider = Provider<int>((ref) {
  return ref.watch(storageRepositoryProvider).getTodayItemsSold();
});

// --- SUPPLIER PROVIDERS ---

final supplierServiceProvider = Provider<SupplierService>((ref) {
  return SupplierService(ref.watch(storageRepositoryProvider));
});

final suppliersProvider = Provider<List<Supplier>>((ref) {
  return ref.watch(storageRepositoryProvider).getSuppliers();
});

final activeSuppliersProvider = Provider<List<Supplier>>((ref) {
  return ref.watch(storageRepositoryProvider).getActiveSuppliers();
});

class SupplierSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }
}

final supplierSearchProvider = NotifierProvider<SupplierSearchNotifier, String>(
  () {
    return SupplierSearchNotifier();
  },
);

class SupplierCategoryFilterNotifier extends Notifier<String> {
  @override
  String build() => 'All';

  void setCategory(String category) {
    state = category;
  }
}

final supplierCategoryFilterProvider =
    NotifierProvider<SupplierCategoryFilterNotifier, String>(() {
      return SupplierCategoryFilterNotifier();
    });

final filteredSuppliersProvider = Provider<List<Supplier>>((ref) {
  final repo = ref.watch(storageRepositoryProvider);
  final query = ref.watch(supplierSearchProvider);
  final category = ref.watch(supplierCategoryFilterProvider);

  List<Supplier> list;
  if (query.isNotEmpty) {
    list = repo.searchSuppliers(query);
    if (category != 'All') {
      list = list.where((s) => s.supplierCategory == category).toList();
    }
  } else {
    list = repo.getSuppliersByCategory(category);
  }

  return list;
});

final supplierLedgerProvider = Provider.family<List<SupplierLedger>, String>((
  ref,
  supplierId,
) {
  return ref.watch(storageRepositoryProvider).getLedgerForSupplier(supplierId);
});

// --- PURCHASE PROVIDERS ---

final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  return PurchaseService(ref.watch(storageRepositoryProvider));
});

// --- EXPENSES PROVIDERS ---
final expenseServiceProvider = Provider<ExpenseService>((ref) {
  return ExpenseService(ref.watch(storageRepositoryProvider));
});

final expensesProvider = Provider<List<Expense>>((ref) {
  return ref.watch(expenseServiceProvider).getAllExpenses();
});

final expenseCategoriesProvider = Provider<List<ExpenseCategory>>((ref) {
  return ref.watch(expenseServiceProvider).getExpenseCategories();
});

final purchasesProvider = Provider<List<Purchase>>((ref) {
  return ref.watch(storageRepositoryProvider).getPurchases();
});

class PurchaseSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }
}

final purchaseSearchProvider = NotifierProvider<PurchaseSearchNotifier, String>(
  () {
    return PurchaseSearchNotifier();
  },
);

class PurchaseStatusFilterNotifier extends Notifier<String> {
  @override
  String build() => 'All';

  void setStatus(String status) {
    state = status;
  }
}

final purchaseStatusFilterProvider =
    NotifierProvider<PurchaseStatusFilterNotifier, String>(() {
      return PurchaseStatusFilterNotifier();
    });

final filteredPurchasesProvider = Provider<List<Purchase>>((ref) {
  final repo = ref.watch(storageRepositoryProvider);
  final query = ref.watch(purchaseSearchProvider);
  final status = ref.watch(purchaseStatusFilterProvider);

  List<Purchase> list;
  if (query.isNotEmpty) {
    list = repo.searchPurchases(query);
  } else {
    list = repo.getPurchases();
  }

  if (status != 'All') {
    list = list.where((p) => p.status == status).toList();
  }

  return list;
});

final todayPurchasesProvider = Provider<List<Purchase>>((ref) {
  return ref.watch(storageRepositoryProvider).getTodayPurchases();
});

// --- VALUATION PROVIDERS ---

final inventoryValuationProvider = Provider<Map<String, double>>((ref) {
  return ref.watch(storageRepositoryProvider).calculateInventoryValue();
});

// --- CUSTOMER PROVIDERS ---

final customerServiceProvider = Provider<CustomerService>((ref) {
  return CustomerService(
    ref.watch(storageRepositoryProvider),
    ref.watch(sessionServiceProvider),
  );
});

final customersProvider = Provider<List<Customer>>((ref) {
  return ref.watch(customerServiceProvider).getAllCustomers();
});

class CustomerSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }
}

final customerSearchProvider = NotifierProvider<CustomerSearchNotifier, String>(
  () {
    return CustomerSearchNotifier();
  },
);

class CustomerGroupFilterNotifier extends Notifier<String> {
  @override
  String build() => 'All';

  void setGroup(String group) {
    state = group;
  }
}

final customerGroupFilterProvider =
    NotifierProvider<CustomerGroupFilterNotifier, String>(() {
      return CustomerGroupFilterNotifier();
    });

final filteredCustomersProvider = Provider<List<Customer>>((ref) {
  final service = ref.watch(customerServiceProvider);
  final query = ref.watch(customerSearchProvider);
  final group = ref.watch(customerGroupFilterProvider);

  List<Customer> list;
  if (query.isNotEmpty) {
    list = service.searchCustomers(query);
    if (group != 'All') {
      list = list.where((c) => c.customerGroup == group).toList();
    }
  } else {
    list = service.getCustomersByGroup(group);
  }

  return list;
});

final customerLedgerProvider = Provider.family<List<CustomerLedger>, String>((
  ref,
  customerId,
) {
  return ref.watch(storageRepositoryProvider).getLedgerForCustomer(customerId);
});

// --- LOYALTY PROVIDERS ---

final loyaltySettingsProvider = Provider<LoyaltySettingsModel>((ref) {
  return ref.watch(storageRepositoryProvider).getLoyaltySettings();
});

final loyaltyTransactionsProvider =
    Provider.family<List<LoyaltyTransaction>, String>((ref, customerId) {
      return ref
          .watch(storageRepositoryProvider)
          .getLoyaltyTransactions(customerId);
    });

// --- FIREBASE & SYNC PROVIDERS ---

final firebaseRepositoryProvider = Provider<FirebaseRepository>((ref) {
  return FirebaseRepository();
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(firebaseRepositoryProvider));
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(
    ref.watch(storageRepositoryProvider),
    ref.watch(firebaseRepositoryProvider),
    ref.watch(authServiceProvider),
    ref.watch(sessionServiceProvider),
  );
  return service;
});

class SyncStatusNotifier extends Notifier<String> {
  @override
  String build() => 'Synced';

  void setStatus(String status) {
    state = status;
  }
}

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, String>(() {
  return SyncStatusNotifier();
});

// --- Admin Panel & Employee Providers ---

final employeesProvider = Provider<List<EmployeeModel>>((ref) {
  return ref.watch(storageRepositoryProvider).getEmployees();
});

final loginHistoryProvider = Provider<List<LoginHistoryModel>>((ref) {
  return ref.watch(storageRepositoryProvider).getLoginHistory();
});

final activityLogProvider = Provider<List<ActivityLogModel>>((ref) {
  return ref.watch(storageRepositoryProvider).getActivityLogs();
});

class CurrentEmployeeNotifier extends Notifier<EmployeeModel?> {
  @override
  EmployeeModel? build() {
    final user = ref.watch(authStateProvider).value;
    if (user != null && user.email != null) {
      final employees = ref.read(storageRepositoryProvider).getEmployees();
      try {
        return employees.firstWhere((e) => e.email == user.email);
      } catch (_) {
        // Not found locally. Try fetching from Firestore users collection
        _fetchFirebaseProfile(user.uid, user.email!);
        return null;
      }
    }
    return null;
  }

  Future<void> _fetchFirebaseProfile(String uid, String email) async {
    try {
      final fbRepo = ref.read(firebaseRepositoryProvider);
      final doc = await fbRepo.getUserProfile(uid);
      if (doc != null && doc['role'] == 'Owner') {
        final implicitOwner = EmployeeModel(
          id: uid,
          fullName: doc['displayName'] ?? 'Owner',
          email: email,
          phoneNumber: '',
          role: Role.owner,
          permissions: [], // Owners have omnipotent access
        );
        state = implicitOwner;
      }
    } catch (e) {
      // Ignore
    }
  }

  void setEmployee(EmployeeModel employee) {
    state = employee;
  }
}

final currentEmployeeProvider =
    NotifierProvider<CurrentEmployeeNotifier, EmployeeModel?>(() {
      return CurrentEmployeeNotifier();
    });
