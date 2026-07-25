import 'dart:io';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/action_history_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/data/models/invoice_settings_model.dart';
import 'package:atomid/data/models/inventory_movement_model.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/customer_ledger_model.dart';
import 'package:atomid/data/models/supplier_ledger_model.dart';
import 'package:atomid/data/models/loyalty_transaction_model.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/models/sync_queue_model.dart';
import 'package:atomid/data/models/sync_log_model.dart';
import 'package:atomid/data/models/expense_model.dart';
import 'package:atomid/data/models/employee_model.dart';
import 'package:atomid/data/models/login_history_model.dart';
import 'package:atomid/data/models/activity_log_model.dart';
import 'package:atomid/hive_registrar.g.dart';
class StorageRepository {
  static const String productsBoxName = 'products';
  static const String historyBoxName = 'history';
  static const String settingsBoxName = 'settings';
  static const String invoiceSettingsBoxName = 'invoice_settings';
  static const String movementsBoxName = 'inventory_movements';
  static const String salesBoxName = 'sales';
  static const String suppliersBoxName = 'suppliers';
  static const String purchasesBoxName = 'purchases';
  static const String customersBoxName = 'customers';
  static const String customerLedgersBoxName = 'customer_ledgers';
  static const String supplierLedgersBoxName = 'supplier_ledgers';
  static const String loyaltyTransactionsBoxName = 'loyalty_transactions';
  static const String loyaltySettingsBoxName = 'loyalty_settings';
  static const String syncQueueBoxName = 'sync_queue';
  static const String syncLogBoxName = 'sync_logs';
  static const String expensesBoxName = 'expenses';
  static const String expenseCategoriesBoxName = 'expense_categories';
  static const String employeesBoxName = 'employees';
  static const String loginHistoryBoxName = 'login_history';
  static const String activityLogBoxName = 'activity_logs';
  late Box<Product> _productsBox;
  late Box<ActionHistory> _historyBox;
  late Box<SettingsModel> _settingsBox;
  late Box<InvoiceSettingsModel> _invoiceSettingsBox;
  late Box<InventoryMovement> _movementsBox;
  late Box<Sale> _salesBox;
  late Box<Supplier> _suppliersBox;
  late Box<Purchase> _purchasesBox;
  late Box<CompanyModel> _companyBox;
  late Box<Customer> _customersBox;
  late Box<CustomerLedger> _customerLedgersBox;
  late Box<SupplierLedger> _supplierLedgersBox;
  late Box<LoyaltyTransaction> _loyaltyTransactionsBox;
  late Box<LoyaltySettingsModel> _loyaltySettingsBox;
  late Box<SyncQueueItem> _syncQueueBox;
  late Box<SyncLogModel> _syncLogBox;
  late Box<Expense> _expensesBox;
  late Box<ExpenseCategory> _expenseCategoriesBox;
  late Box<EmployeeModel> _employeesBox;
  late Box<LoginHistoryModel> _loginHistoryBox;
  late Box<ActivityLogModel> _activityLogBox;

  // Fast index for barcode -> Product
  final Map<String, Product> _barcodeIndex = {};

  Future<void> init() async {
    Directory dir;
    try {
      dir = await getApplicationSupportDirectory();
    } catch (_) {
      dir = await getApplicationDocumentsDirectory();
    }

    // If the support directory somehow maps to OneDrive, force a local path
    String dbPath = dir.path;
    if (dbPath.contains('OneDrive')) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        dbPath = '$userProfile\\AppData\\Local\\atomid\\db';
      }
    } else {
      dbPath = '$dbPath\\db';
    }

    final dbDir = Directory(dbPath);
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }

    Hive.init(dbPath);

    // Register Adapters
    // In hive_ce we can use the generated adapters via extension
    Hive.registerAdapters();

    // Open boxes
    _productsBox = await Hive.openBox<Product>(productsBoxName);
    _historyBox = await Hive.openBox<ActionHistory>(historyBoxName);
    _settingsBox = await Hive.openBox<SettingsModel>(settingsBoxName);
    _invoiceSettingsBox = await Hive.openBox<InvoiceSettingsModel>(invoiceSettingsBoxName);
    _movementsBox = await Hive.openBox<InventoryMovement>(movementsBoxName);
    _salesBox = await Hive.openBox<Sale>(salesBoxName);
    _suppliersBox = await Hive.openBox<Supplier>(suppliersBoxName);
    _purchasesBox = await Hive.openBox<Purchase>(purchasesBoxName);
    _companyBox = await Hive.openBox<CompanyModel>('company');
    _customersBox = await Hive.openBox<Customer>(customersBoxName);
    _customerLedgersBox = await Hive.openBox<CustomerLedger>(customerLedgersBoxName);
    _supplierLedgersBox = await Hive.openBox<SupplierLedger>(supplierLedgersBoxName);
    _loyaltyTransactionsBox = await Hive.openBox<LoyaltyTransaction>(loyaltyTransactionsBoxName);
    _loyaltySettingsBox = await Hive.openBox<LoyaltySettingsModel>(loyaltySettingsBoxName);
    _syncQueueBox = await Hive.openBox<SyncQueueItem>(syncQueueBoxName);
    _syncLogBox = await Hive.openBox<SyncLogModel>(syncLogBoxName);
    _expensesBox = await Hive.openBox<Expense>(expensesBoxName);
    _expenseCategoriesBox = await Hive.openBox<ExpenseCategory>(expenseCategoriesBoxName);
    _employeesBox = await Hive.openBox<EmployeeModel>(employeesBoxName);
    _loginHistoryBox = await Hive.openBox<LoginHistoryModel>(loginHistoryBoxName);
    _activityLogBox = await Hive.openBox<ActivityLogModel>(activityLogBoxName);
    _rebuildBarcodeIndex();
  }

  void _rebuildBarcodeIndex() {
    _barcodeIndex.clear();
    for (var product in _productsBox.values) {
      for (var variant in product.variants) {
        if (variant.barcode.isNotEmpty) {
          _barcodeIndex[variant.barcode] = product;
        }
      }
    }
  }

  // --- SYNC QUEUE ---
  Future<void> enqueueSync({
    required String entityType,
    required String entityId,
    required String action,
    int priority = 10,
  }) async {
    final item = SyncQueueItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // Alternatively use UUID
      entityType: entityType,
      entityId: entityId,
      action: action,
      status: 'PENDING',
      retryCount: 0,
      createdAt: DateTime.now(),
      priority: priority,
    );
    await _syncQueueBox.put(item.id, item);
  }

  Future<void> enqueueAllExistingDataForSync() async {
    // Enqueue all products
    for (var p in _productsBox.values) {
      await enqueueSync(entityType: 'Product', entityId: p.id, action: 'UPDATE');
    }
    // Enqueue all customers
    for (var c in _customersBox.values) {
      if (!c.isDeleted) await enqueueSync(entityType: 'Customer', entityId: c.id, action: 'UPDATE');
    }
    // Enqueue all sales
    for (var s in _salesBox.values) {
      await enqueueSync(entityType: 'Sale', entityId: s.id, action: 'UPDATE');
    }
    // Enqueue all suppliers
    for (var s in _suppliersBox.values) {
      if (!s.isDeleted) await enqueueSync(entityType: 'Supplier', entityId: s.id, action: 'UPDATE');
    }
    // Enqueue all purchases
    for (var p in _purchasesBox.values) {
      await enqueueSync(entityType: 'Purchase', entityId: p.id, action: 'UPDATE');
    }
    // Enqueue all expenses
    for (var e in _expensesBox.values) {
      await enqueueSync(entityType: 'Expense', entityId: e.id, action: 'UPDATE');
    }
    // Enqueue all movements
    for (var m in _movementsBox.values) {
      await enqueueSync(entityType: 'InventoryMovement', entityId: m.id, action: 'UPDATE');
    }
    
    // Settings and Company
    await enqueueSync(entityType: 'SettingsModel', entityId: 'app_settings', action: 'UPDATE');
    await enqueueSync(entityType: 'CompanyModel', entityId: 'profile', action: 'UPDATE');
  }

  List<SyncQueueItem> getPendingSyncItems() {
    final items = _syncQueueBox.values
        .where((item) => item.status == 'PENDING' || item.status == 'FAILED')
        .toList();
    // Sort by priority (lower number = higher priority), then by creation date
    items.sort((a, b) {
      int cmp = a.priority.compareTo(b.priority);
      if (cmp == 0) {
        return a.createdAt.compareTo(b.createdAt);
      }
      return cmp;
    });
    return items;
  }

  Future<void> updateSyncItemStatus(String id, String status, {int? retryCount, DateTime? lastAttempt}) async {
    final item = _syncQueueBox.get(id);
    if (item != null) {
      item.status = status;
      if (retryCount != null) item.retryCount = retryCount;
      if (lastAttempt != null) item.lastAttempt = lastAttempt;
      await _syncQueueBox.put(id, item);
    }
  }
  
  Future<void> deleteSyncItem(String id) async {
    await _syncQueueBox.delete(id);
  }

  // --- SYNC LOGS ---
  Future<void> addSyncLog(SyncLogModel log) async {
    await _syncLogBox.put(log.id, log);
    
    // Optional: Keep only the latest 1000 logs to prevent unbounded growth
    if (_syncLogBox.length > 1000) {
      final keysToDelete = _syncLogBox.keys.take(_syncLogBox.length - 1000).toList();
      await _syncLogBox.deleteAll(keysToDelete);
    }
  }

  Map<String, dynamic>? getEntityJson(String entityType, String entityId) {
    if (entityType == 'Customer') {
      final c = getCustomerById(entityId);
      if (c == null) return null;
      return {
        'id': c.id, 'code': c.code, 'name': c.name, 'mobile': c.mobile,
        'gstNumber': c.gstNumber, 'address': c.address, 'creditLimit': c.creditLimit,
        'creditDays': c.creditDays, 'openingBalance': c.openingBalance,
        'currentBalance': c.currentBalance, 'status': c.status,
        'createdDate': c.createdDate.toIso8601String(),
        'totalRewardPoints': c.totalRewardPoints,
        'lifetimeSpend': c.lifetimeSpend,
        'isSynced': true,
        'updatedAt': c.updatedAt?.toIso8601String(),
        'email': c.email,
        'customerGroup': c.customerGroup,
        'notes': c.notes,
        'tags': c.tags,
        'attachments': c.attachments,
        'isDeleted': c.isDeleted,
      };
    }
    if (entityType == 'Sale') {
      final s = getSaleById(entityId);
      if (s == null) return null;
      return {
        'id': s.id, 'invoiceNumber': s.invoiceNumber, 'date': s.date.toIso8601String(),
        'customerId': s.customerId, 'customerName': s.customerName,
        'subtotal': s.subtotal, 'discountPercent': s.discountPercent,
        'discountAmount': s.discountAmount, 'taxAmount': s.taxAmount,
        'grandTotal': s.grandTotal, 'paymentMethod': s.paymentMethod,
        'notes': s.notes, 'rewardDiscountAmount': s.rewardDiscountAmount,
        'rewardPointsEarned': s.rewardPointsEarned,
        'isSynced': true,
        'updatedAt': s.updatedAt?.toIso8601String(),
        'items': s.items.map((i) => {
          'productId': i.productId, 'productName': i.productName,
          'productCode': i.productCode, 'variantBarcode': i.variantBarcode,
          'variantSize': i.variantSize, 'price': i.price, 'quantity': i.quantity,
          'total': i.total,
        }).toList(),
      };
    }
    if (entityType == 'Supplier') {
      final s = getSupplierById(entityId);
      if (s == null) return null;
      return {
        'id': s.id, 'code': s.supplierCode, 'name': s.supplierName,
        'phone': s.phone, 'email': s.email, 'address': s.address,
        'gstNumber': s.gstNumber, 'contactPerson': s.contactPerson,
        'notes': s.notes, 'isActive': s.isActive, 'isSynced': true,
        'createdDate': s.createdDate.toIso8601String(),
        'updatedDate': s.updatedDate.toIso8601String(),
        'paymentTerms': s.paymentTerms,
        'currentBalance': s.currentBalance,
        'rating': s.rating,
        'supplierCategory': s.supplierCategory,
        'attachments': s.attachments,
        'isDeleted': s.isDeleted,
      };
    }
    if (entityType == 'LoyaltyTransaction') {
      final l = getLoyaltyTransactionById(entityId);
      if (l == null) return null;
      return {
        'id': l.id, 'customerId': l.customerId, 'saleId': l.saleId,
        'transactionType': l.transactionType, 'points': l.points,
        'monetaryValue': l.monetaryValue, 'reference': l.reference,
        'remarks': l.remarks, 'createdDate': l.createdDate.toIso8601String(),
        'createdBy': l.createdBy, 'isSynced': true,
        'updatedAt': l.updatedAt?.toIso8601String(),
      };
    }
    if (entityType == 'Product') {
      final p = getProductById(entityId);
      if (p == null) return null;
      return {
        'id': p.id, 'productName': p.productName, 'productCode': p.productCode,
        'category': p.category, 'brand': p.brand, 'color': p.color,
        'createdDate': p.createdDate.toIso8601String(),
        'isSynced': true,
        'variants': p.variants.map((v) => {
          'size': v.size, 'barcode': v.barcode, 'sku': v.sku,
          'price': v.price,
          'quantity': v.quantity, 'reorderLevel': v.reorderLevel,
          'stockIn': v.stockIn, 'stockOut': v.stockOut,
          'lastStockUpdated': v.lastStockUpdated?.toIso8601String(),
        }).toList(),
      };
    }
    if (entityType == 'Purchase') {
      final p = getPurchaseById(entityId);
      if (p == null) return null;
      return {
        'id': p.id, 'purchaseNumber': p.purchaseNumber, 'purchaseDate': p.purchaseDate.toIso8601String(),
        'supplierId': p.supplierId, 'supplierName': p.supplierName,
        'subtotal': p.subtotal, 'discount': p.discount,
        'tax': p.tax, 'grandTotal': p.grandTotal, 'paymentStatus': p.paymentStatus,
        'notes': p.notes, 'isSynced': true, 'updatedAt': p.updatedAt?.toIso8601String(),
        'items': p.items.map((i) => {
          'productId': i.productId, 'productName': i.productName,
          'variantBarcode': i.variantBarcode, 'variantSize': i.variantSize,
          'costPrice': i.costPrice, 'quantity': i.quantity, 'lineTotal': i.lineTotal,
        }).toList(),
      };
    }
    if (entityType == 'Expense') {
      final e = _expensesBox.get(entityId);
      if (e == null) return null;
      return {
        'id': e.id, 'categoryId': e.categoryId, 'categoryName': e.categoryName,
        'amount': e.amount, 'date': e.date.toIso8601String(), 'notes': e.notes,
        'createdBy': e.createdBy, 'isSynced': true,
      };
    }
    if (entityType == 'InventoryMovement') {
      final m = _movementsBox.get(entityId);
      if (m == null) return null;
      return {
        'id': m.id, 'productId': m.productId, 'productName': m.productName,
        'variantBarcode': m.variantBarcode, 'variantSize': m.variantSize,
        'quantity': m.quantity, 'type': m.type, 'reason': m.reason,
        'date': m.date.toIso8601String(), 'movementReferenceId': m.movementReferenceId,
        'performedAt': m.performedAt,
      };
    }
    if (entityType == 'SettingsModel') {
      final s = _settingsBox.get('app_settings');
      if (s == null) return null;
      return {
        'isDarkMode': s.isDarkMode, 'companyName': s.companyName,
        'currencySymbol': s.currencySymbol, 'pdfPageSize': s.pdfPageSize,
      };
    }
    return null;
  }

  // --- PRODUCTS ---
  Future<void> saveProduct(Product product) async {
    final existing = _productsBox.get(product.id);
    if (existing != null) {
      for (var variant in existing.variants) {
        if (variant.barcode.isNotEmpty) {
          _barcodeIndex.remove(variant.barcode);
        }
      }
    }

    await _productsBox.put(product.id, product);

    // Update index locally
    for (var variant in product.variants) {
      if (variant.barcode.isNotEmpty) {
        _barcodeIndex[variant.barcode] = product;
      }
    }
    
    await enqueueSync(
      entityType: 'Product',
      entityId: product.id,
      action: 'UPDATE',
    );
  }

  Future<void> deleteProduct(String id) async {
    final product = _productsBox.get(id);
    if (product != null) {
      for (var variant in product.variants) {
        if (variant.barcode.isNotEmpty) {
          _barcodeIndex.remove(variant.barcode);
        }
      }
    }
    await _productsBox.delete(id);
    await enqueueSync(
      entityType: 'Product',
      entityId: id,
      action: 'DELETE',
    );
  }

  List<Product> getAllProducts() {
    return _productsBox.values.toList()
      ..sort((a, b) => b.createdDate.compareTo(a.createdDate));
  }

  List<Product> searchProducts(String query) {
    if (query.isEmpty) return getAllProducts();

    // Optimization: Exact barcode match first (O(1))
    final exactMatch = _barcodeIndex[query];
    if (exactMatch != null) return [exactMatch];

    final lowerQuery = query.toLowerCase();
    return _productsBox.values.where((p) {
      return p.productName.toLowerCase().contains(lowerQuery) ||
          p.productCode.toLowerCase().contains(lowerQuery) ||
          p.category.toLowerCase().contains(lowerQuery) ||
          p.brand.toLowerCase().contains(lowerQuery) ||
          p.variants.any((v) => v.barcode.toLowerCase().contains(lowerQuery));
    }).toList()..sort((a, b) => b.createdDate.compareTo(a.createdDate));
  }

  Product? getProductByBarcode(String barcode) {
    return _barcodeIndex[barcode];
  }

  Product? getProductById(String id) {
    return _productsBox.get(id);
  }

  // --- INVENTORY ---
  Future<void> performStockIn({
    required String productId,
    required String variantBarcode,
    required int quantity,
    required String reason,
    String movementReferenceId = '',
    String performedAt = '',
  }) async {
    if (quantity <= 0) throw Exception('Quantity must be greater than 0');

    final product = _productsBox.get(productId);
    if (product == null) throw Exception('Product not found');

    final variantIndex = product.variants.indexWhere(
      (v) => v.barcode == variantBarcode,
    );
    if (variantIndex == -1) throw Exception('Variant not found');

    final variant = product.variants[variantIndex];
    variant.quantity += quantity;
    variant.stockIn += quantity;
    variant.lastStockUpdated = DateTime.now();

    await saveProduct(product);

    // Record movement
    final movement = InventoryMovement(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      productId: productId,
      productName: product.productName,
      variantBarcode: variantBarcode,
      variantSize: variant.size,
      quantity: quantity,
      type: 'Stock In',
      reason: reason,
      date: DateTime.now(),
      movementReferenceId: movementReferenceId,
      performedAt: performedAt,
    );
    await _movementsBox.put(movement.id, movement);
    await enqueueSync(
      entityType: 'InventoryMovement',
      entityId: movement.id,
      action: 'CREATE',
    );

    // Record action history
    await saveHistory(
      ActionHistory(
        id: movement.id,
        barcode: variantBarcode,
        productName: product.productName,
        action: 'Stock In (+$quantity) - $reason',
        date: DateTime.now(),
      ),
    );
  }

  Future<void> performStockOut({
    required String productId,
    required String variantBarcode,
    required int quantity,
    required String reason,
    String movementReferenceId = '',
    String performedAt = '',
  }) async {
    if (quantity <= 0) throw Exception('Quantity must be greater than 0');

    final product = _productsBox.get(productId);
    if (product == null) throw Exception('Product not found');

    final variantIndex = product.variants.indexWhere(
      (v) => v.barcode == variantBarcode,
    );
    if (variantIndex == -1) throw Exception('Variant not found');

    final variant = product.variants[variantIndex];
    if (variant.quantity < quantity) {
      throw Exception(
        'Insufficient stock. Available: ${variant.quantity}, Requested: $quantity',
      );
    }

    variant.quantity -= quantity;
    variant.stockOut += quantity;
    variant.lastStockUpdated = DateTime.now();

    await saveProduct(product);

    // Record movement
    final movement = InventoryMovement(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      productId: productId,
      productName: product.productName,
      variantBarcode: variantBarcode,
      variantSize: variant.size,
      quantity: quantity,
      type: 'Stock Out',
      reason: reason,
      date: DateTime.now(),
      movementReferenceId: movementReferenceId,
      performedAt: performedAt,
    );
    await _movementsBox.put(movement.id, movement);
    await enqueueSync(
      entityType: 'InventoryMovement',
      entityId: movement.id,
      action: 'CREATE',
    );

    // Record action history
    await saveHistory(
      ActionHistory(
        id: movement.id,
        barcode: variantBarcode,
        productName: product.productName,
        action: 'Stock Out (-$quantity) - $reason',
        date: DateTime.now(),
      ),
    );
  }

  List<InventoryMovement> getAllMovements() {
    return _movementsBox.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<InventoryMovement> getMovementsForProduct(String productId) {
    return _movementsBox.values.where((m) => m.productId == productId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Returns products that have at least one variant with qty <= reorderLevel and qty > 0
  List<Map<String, dynamic>> getLowStockItems() {
    final result = <Map<String, dynamic>>[];
    for (var product in _productsBox.values) {
      for (var variant in product.variants) {
        if (variant.quantity > 0 && variant.quantity <= variant.reorderLevel) {
          result.add({'product': product, 'variant': variant});
        }
      }
    }
    return result;
  }

  /// Returns products that have at least one variant with qty == 0
  List<Map<String, dynamic>> getOutOfStockItems() {
    final result = <Map<String, dynamic>>[];
    for (var product in _productsBox.values) {
      for (var variant in product.variants) {
        if (variant.quantity <= 0) {
          result.add({'product': product, 'variant': variant});
        }
      }
    }
    return result;
  }

  int getTotalStockUnits() {
    int total = 0;
    for (var product in _productsBox.values) {
      for (var variant in product.variants) {
        total += variant.quantity;
      }
    }
    return total;
  }

  // --- HISTORY ---
  Future<void> saveHistory(ActionHistory history) async {
    await _historyBox.put(history.id, history);
  }

  List<ActionHistory> getHistory() {
    return _historyBox.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> clearHistory() async {
    await _historyBox.clear();
  }

  // --- SETTINGS ---
  SettingsModel getSettings() {
    return _settingsBox.get('app_settings') ??
        SettingsModel(
          isDarkMode: true, // Default to dark premium
          companyName: 'ATOMID STORE',
          currencySymbol: '₹',
          pdfPageSize: 'A4',
          taxMode: 'inclusive',
          taxRate: 0,
        );
  }

  Future<void> saveSettings(SettingsModel settings) async {
    await _settingsBox.put('app_settings', settings);
    await enqueueSync(
      entityType: 'SettingsModel',
      entityId: 'app_settings',
      action: 'UPDATE',
    );
  }

  // --- INVOICE SETTINGS ---
  InvoiceSettingsModel getInvoiceSettings() {
    return _invoiceSettingsBox.get('invoice_settings') ?? InvoiceSettingsModel();
  }

  Future<void> saveInvoiceSettings(InvoiceSettingsModel settings) async {
    await _invoiceSettingsBox.put('invoice_settings', settings);
  }

  // --- SALES ---
  String getNextInvoiceNumber() {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final prefix = 'INV-$dateStr-';

    int maxCounter = 0;
    for (var sale in _salesBox.values) {
      if (sale.invoiceNumber.startsWith(prefix)) {
        final counterStr = sale.invoiceNumber.substring(prefix.length);
        final counter = int.tryParse(counterStr) ?? 0;
        if (counter > maxCounter) maxCounter = counter;
      }
    }

    return '$prefix${(maxCounter + 1).toString().padLeft(4, '0')}';
  }

  Future<void> saveSale(Sale sale) async {
    final isNew = _salesBox.get(sale.id) == null;
    await _salesBox.put(sale.id, sale);
    await enqueueSync(
      entityType: 'Sale',
      entityId: sale.id,
      action: isNew ? 'CREATE' : 'UPDATE',
    );

    // Update Customer Ledger if sale is linked to a customer
    if (sale.customerId.isNotEmpty) {
      // Debit the customer account for the grand total
      await addLedgerEntry(
        customerId: sale.customerId,
        date: sale.date,
        transactionType: 'Sale',
        referenceId: sale.invoiceNumber,
        debit: sale.grandTotal,
        notes: 'Invoice #${sale.invoiceNumber}',
      );

      // If the sale was immediately paid (not Credit), record the payment
      if (sale.paymentMethod.toLowerCase() != 'credit') {
        await addLedgerEntry(
          customerId: sale.customerId,
          date: sale.date,
          transactionType: 'Payment',
          referenceId: sale.invoiceNumber,
          credit: sale.grandTotal,
          notes: 'Paid via ${sale.paymentMethod}',
        );
      }
    }
  }

  List<Sale> getAllSales() {
    return _salesBox.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  Sale? getSaleById(String id) {
    return _salesBox.get(id);
  }

  List<Sale> getTodaySales() {
    final now = DateTime.now();
    return _salesBox.values.where((s) {
      return s.date.year == now.year &&
          s.date.month == now.month &&
          s.date.day == now.day;
    }).toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  double getTodayRevenue() {
    return getTodaySales().fold(0.0, (sum, s) => sum + s.grandTotal);
  }

  int getTodayItemsSold() {
    return getTodaySales().fold(
      0,
      (sum, s) => sum + s.items.fold(0, (iSum, item) => iSum + item.quantity),
    );
  }

  List<Sale> getSalesByDateRange(DateTime start, DateTime end) {
    return _salesBox.values.where((s) {
      return s.date.isAfter(start.subtract(const Duration(days: 1))) &&
          s.date.isBefore(end.add(const Duration(days: 1)));
    }).toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  // --- SUPPLIERS ---
  Future<void> saveSupplier(Supplier supplier) async {
    final isNew = _suppliersBox.get(supplier.id) == null;
    await _suppliersBox.put(supplier.id, supplier);
    await enqueueSync(
      entityType: 'Supplier',
      entityId: supplier.id,
      action: isNew ? 'CREATE' : 'UPDATE',
    );
  }

  Future<void> deleteSupplier(String id) async {
    await _suppliersBox.delete(id);
  }

  List<Supplier> getSuppliers() {
    return _suppliersBox.values.toList()
      ..sort((a, b) => b.createdDate.compareTo(a.createdDate));
  }

  List<Supplier> getActiveSuppliers() {
    return _suppliersBox.values.where((s) => s.isActive).toList()
      ..sort((a, b) => a.supplierName.compareTo(b.supplierName));
  }

  Supplier? getSupplierById(String id) {
    return _suppliersBox.get(id);
  }

  List<Supplier> searchSuppliers(String query) {
    if (query.isEmpty) return getSuppliers();
    final lowerQuery = query.toLowerCase();
    return _suppliersBox.values.where((s) {
      if (s.isDeleted) return false;
      return s.supplierName.toLowerCase().contains(lowerQuery) ||
          s.supplierCode.toLowerCase().contains(lowerQuery) ||
          s.phone.toLowerCase().contains(lowerQuery) ||
          s.contactPerson.toLowerCase().contains(lowerQuery) ||
          s.email.toLowerCase().contains(lowerQuery) ||
          s.supplierCategory.toLowerCase().contains(lowerQuery);
    }).toList()..sort((a, b) => b.createdDate.compareTo(a.createdDate));
  }

  List<Supplier> getSuppliersByCategory(String category) {
    if (category.isEmpty || category == 'All') return getSuppliers();
    return _suppliersBox.values.where((s) => !s.isDeleted && s.supplierCategory == category).toList()
      ..sort((a, b) => b.createdDate.compareTo(a.createdDate));
  }

  bool isSupplierCodeDuplicate(String code, {String? excludeId}) {
    return _suppliersBox.values.any(
      (s) => s.supplierCode == code && s.id != excludeId,
    );
  }

  // --- PURCHASES ---
  String getNextPurchaseNumber() {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final prefix = 'PUR-$dateStr-';

    int maxCounter = 0;
    for (var purchase in _purchasesBox.values) {
      if (purchase.purchaseNumber.startsWith(prefix)) {
        final counterStr = purchase.purchaseNumber.substring(prefix.length);
        final counter = int.tryParse(counterStr) ?? 0;
        if (counter > maxCounter) maxCounter = counter;
      }
    }

    return '$prefix${(maxCounter + 1).toString().padLeft(4, '0')}';
  }

  /// Saves a purchase to the local database.
  /// Note: Stock updates and supplier ledger entries are now handled by PurchaseService.
  Future<void> savePurchase(Purchase purchase) async {
    final isNew = _purchasesBox.get(purchase.id) == null;
    await _purchasesBox.put(purchase.id, purchase);
    await enqueueSync(
      entityType: 'Purchase',
      entityId: purchase.id,
      action: isNew ? 'CREATE' : 'UPDATE',
    );
  }

  List<Purchase> getPurchases() {
    return _purchasesBox.values.toList()
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
  }

  Purchase? getPurchaseById(String id) {
    return _purchasesBox.get(id);
  }

  List<Purchase> getPurchasesBySupplier(String supplierId) {
    return _purchasesBox.values
        .where((p) => p.supplierId == supplierId)
        .toList()
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
  }

  List<Purchase> searchPurchases(String query) {
    if (query.isEmpty) return getPurchases();
    final lowerQuery = query.toLowerCase();
    return _purchasesBox.values.where((p) {
      return p.purchaseNumber.toLowerCase().contains(lowerQuery) ||
          p.supplierName.toLowerCase().contains(lowerQuery) ||
          p.items.any(
            (item) => item.productName.toLowerCase().contains(lowerQuery),
          );
    }).toList()..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
  }

  List<Purchase> getTodayPurchases() {
    final now = DateTime.now();
    return _purchasesBox.values.where((p) {
      return p.purchaseDate.year == now.year &&
          p.purchaseDate.month == now.month &&
          p.purchaseDate.day == now.day;
    }).toList()..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
  }

  List<Purchase> getPurchasesByDateRange(DateTime start, DateTime end) {
    return _purchasesBox.values.where((p) {
      return p.purchaseDate.isAfter(start.subtract(const Duration(days: 1))) &&
          p.purchaseDate.isBefore(end.add(const Duration(days: 1)));
    }).toList()..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
  }

  // --- INVENTORY VALUATION ---
  /// Returns {costValue, retailValue, potentialProfit}
  /// costValue uses a simple average: for each variant, uses the latest
  /// purchase cost price if available, otherwise falls back to selling price.
  Map<String, double> calculateInventoryValue() {
    double retailValue = 0;
    double costValue = 0;

    // Build a map of variant barcode -> latest cost price from purchases
    final Map<String, double> latestCostPrices = {};
    final sortedPurchases = _purchasesBox.values.toList()
      ..sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));
    for (var purchase in sortedPurchases) {
      for (var item in purchase.items) {
        latestCostPrices[item.variantBarcode] = item.costPrice;
      }
    }

    for (var product in _productsBox.values) {
      for (var variant in product.variants) {
        retailValue += variant.price * variant.quantity;
        final cost = latestCostPrices[variant.barcode] ?? variant.price;
        costValue += cost * variant.quantity;
      }
    }

    return {
      'costValue': costValue,
      'retailValue': retailValue,
      'potentialProfit': retailValue - costValue,
    };
  }

  // --- COMPANY ---
  CompanyModel getCompany() {
    return _companyBox.get('profile') ?? CompanyModel();
  }

  Future<void> saveCompany(CompanyModel company) async {
    await _companyBox.put('profile', company);
    await enqueueSync(
      entityType: 'CompanyModel',
      entityId: 'profile',
      action: 'UPDATE',
    );
  }

  // --- CUSTOMERS ---
  Future<void> saveCustomer(Customer customer) async {
    final isNew = _customersBox.get(customer.id) == null;
    await _customersBox.put(customer.id, customer);
    await enqueueSync(
      entityType: 'Customer',
      entityId: customer.id,
      action: isNew ? 'CREATE' : 'UPDATE',
    );
  }

  List<Customer> getAllCustomers() {
    return _customersBox.values.where((c) => !c.isDeleted).toList()
      ..sort((a, b) => b.createdDate.compareTo(a.createdDate));
  }

  Customer? getCustomerById(String id) {
    return _customersBox.get(id);
  }

  List<Customer> searchCustomers(String query) {
    if (query.isEmpty) return getAllCustomers();
    final lowerQuery = query.toLowerCase();
    return _customersBox.values.where((c) {
      if (c.isDeleted) return false;
      return c.name.toLowerCase().contains(lowerQuery) ||
          c.mobile.toLowerCase().contains(lowerQuery) ||
          c.code.toLowerCase().contains(lowerQuery) ||
          c.email.toLowerCase().contains(lowerQuery) ||
          c.tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
    }).toList()..sort((a, b) => b.createdDate.compareTo(a.createdDate));
  }
  
  List<Customer> getCustomersByGroup(String group) {
    if (group.isEmpty || group == 'All') return getAllCustomers();
    return _customersBox.values.where((c) => !c.isDeleted && c.customerGroup == group).toList()
      ..sort((a, b) => b.createdDate.compareTo(a.createdDate));
  }

  List<CustomerLedger> getLedgerForCustomer(String customerId) {
    return _customerLedgersBox.values
        .where((l) => l.customerId == customerId)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date)); // Chronological for balance logic
  }

  Future<void> addLedgerEntry({
    required String customerId,
    required DateTime date,
    required String transactionType,
    required String referenceId,
    double debit = 0,
    double credit = 0,
    String notes = '',
  }) async {
    final customer = getCustomerById(customerId);
    if (customer == null) throw Exception('Customer not found');

    // Create entry
    final entry = CustomerLedger(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      customerId: customerId,
      date: date,
      transactionType: transactionType,
      referenceId: referenceId,
      debit: debit,
      credit: credit,
      notes: notes,
    );

    await _customerLedgersBox.put(entry.id, entry);

    // Recalculate customer currentBalance
    // Balance = OpeningBalance + Sum(Debits) - Sum(Credits)
    final ledgers = getLedgerForCustomer(customerId);
    double runningBalance = customer.openingBalance;
    for (var l in ledgers) {
      runningBalance += l.debit;
      runningBalance -= l.credit;
      // Update running balance on the ledger entry itself
      l.balance = runningBalance;
      await _customerLedgersBox.put(l.id, l);
    }

    customer.currentBalance = runningBalance;
    await saveCustomer(customer);
  }

  // --- SUPPLIER LEDGER ---
  List<SupplierLedger> getLedgerForSupplier(String supplierId) {
    return _supplierLedgersBox.values
        .where((l) => l.supplierId == supplierId)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date)); // Chronological for balance logic
  }

  Future<void> addSupplierLedgerEntry({
    required String supplierId,
    required DateTime date,
    required String transactionType,
    required String referenceId,
    double credit = 0,
    double debit = 0,
    String notes = '',
  }) async {
    final supplier = getSupplierById(supplierId);
    if (supplier == null) throw Exception('Supplier not found');

    // Create entry
    final entry = SupplierLedger(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      supplierId: supplierId,
      date: date,
      transactionType: transactionType,
      referenceId: referenceId,
      credit: credit,
      debit: debit,
      notes: notes,
    );

    await _supplierLedgersBox.put(entry.id, entry);

    // Recalculate supplier currentBalance
    // Balance = Sum(Credits) - Sum(Debits)  -> Since Supplier balance means "How much we owe them"
    // So Credit (Purchase) increases balance, Debit (Payment) decreases balance
    final ledgers = getLedgerForSupplier(supplierId);
    double runningBalance = 0; // We will add an Opening Balance logic in future if needed
    for (var l in ledgers) {
      runningBalance += l.credit;
      runningBalance -= l.debit;
      // Update running balance on the ledger entry itself
      l.balance = runningBalance;
      await _supplierLedgersBox.put(l.id, l);
    }

    supplier.currentBalance = runningBalance;
    await saveSupplier(supplier);
  }

  // --- LOYALTY ---
  LoyaltySettingsModel getLoyaltySettings() {
    return _loyaltySettingsBox.get('loyalty_settings') ?? LoyaltySettingsModel();
  }

  Future<void> saveLoyaltySettings(LoyaltySettingsModel settings) async {
    await _loyaltySettingsBox.put('loyalty_settings', settings);
  }

  List<LoyaltyTransaction> getLoyaltyTransactions(String customerId) {
    return _loyaltyTransactionsBox.values
        .where((t) => t.customerId == customerId)
        .toList()
      ..sort((a, b) => a.createdDate.compareTo(b.createdDate));
  }

  LoyaltyTransaction? getLoyaltyTransactionById(String id) {
    return _loyaltyTransactionsBox.get(id);
  }

  Future<void> addLoyaltyTransaction({
    required String customerId,
    String? saleId,
    required String transactionType, // Earn, Redeem, Refund, Expire, ManualAdjustment
    required double points,
    required double monetaryValue,
    String reference = '',
    String remarks = '',
    required String createdBy,
  }) async {
    final customer = getCustomerById(customerId);
    if (customer == null) throw Exception('Customer not found');

    final tx = LoyaltyTransaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // or UUIDv4
      customerId: customerId,
      saleId: saleId,
      transactionType: transactionType,
      points: points,
      monetaryValue: monetaryValue,
      reference: reference,
      remarks: remarks,
      createdDate: DateTime.now(),
      createdBy: createdBy,
    );

    await _loyaltyTransactionsBox.put(tx.id, tx);
    await enqueueSync(
      entityType: 'LoyaltyTransaction',
      entityId: tx.id,
      action: 'CREATE',
    );

    // Recalculate customer total points
    final allTxs = getLoyaltyTransactions(customerId);
    double totalPoints = 0;
    for (var t in allTxs) {
      totalPoints += t.points;
    }
    
    // Prevent negative balance logically, though not throwing here allows corrections
    if (totalPoints < 0) totalPoints = 0;

    customer.totalRewardPoints = totalPoints;
    await saveCustomer(customer);
  }

  // Reward Engine Core Logic
  double calculateEarnedPoints(double subtotal) {
    final settings = getLoyaltySettings();
    if (!settings.isLoyaltyEnabled) return 0;
    if (settings.spendAmountForPoint <= 0) return 0;

    // Floor(subtotal / spendAmountForPoint) * pointsEarnedPerSpend
    final multiples = (subtotal / settings.spendAmountForPoint).floorToDouble();
    return multiples * settings.pointsEarnedPerSpend;
  }

  double calculateMaxRedemptionValue(double availablePoints, double subtotal) {
    final settings = getLoyaltySettings();
    if (!settings.isLoyaltyEnabled) return 0;
    if (subtotal < settings.minBillAmountForRedemption) return 0;

    final potentialValue = availablePoints * settings.pointRedemptionValue;
    final maxAllowedValue = subtotal * (settings.maxRedemptionPercentage / 100.0);

    return potentialValue > maxAllowedValue ? maxAllowedValue : potentialValue;
  }
  // --- EXPENSES ---
  List<Expense> getExpenses() {
    return _expensesBox.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> saveExpense(Expense expense, {bool isNew = false}) async {
    await _expensesBox.put(expense.id, expense);
    await enqueueSync(
      entityType: 'Expense',
      entityId: expense.id,
      action: isNew ? 'CREATE' : 'UPDATE',
    );
  }

  Future<void> deleteExpense(String expenseId) async {
    await _expensesBox.delete(expenseId);
    await enqueueSync(
      entityType: 'Expense',
      entityId: expenseId,
      action: 'DELETE',
    );
  }

  List<ExpenseCategory> getExpenseCategories() {
    return _expenseCategoriesBox.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> saveExpenseCategory(ExpenseCategory category) async {
    await _expenseCategoriesBox.put(category.id, category);
  }

  Future<void> deleteExpenseCategory(String categoryId) async {
    await _expenseCategoriesBox.delete(categoryId);
  }

  // --- Employee Management ---

  List<EmployeeModel> getEmployees() {
    return _employeesBox.values.toList()..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  EmployeeModel? getEmployee(String id) {
    return _employeesBox.get(id);
  }

  Future<void> saveEmployee(EmployeeModel employee, {String? actionBy}) async {
    final isNew = !_employeesBox.containsKey(employee.id);
    await _employeesBox.put(employee.id, employee);
    await enqueueSync(
      entityType: 'Employee',
      entityId: employee.id,
      action: isNew ? 'CREATE' : 'UPDATE',
    );
    if (actionBy != null) {
      await logActivity(
        action: isNew ? 'Created Employee' : 'Updated Employee',
        ownerId: actionBy,
        targetEmployeeId: employee.id,
      );
    }
  }

  Future<void> deleteEmployee(String id, {String? actionBy}) async {
    final employee = _employeesBox.get(id);
    if (employee != null) {
      final updated = employee.copyWith(isDeleted: true);
      await _employeesBox.put(id, updated);
      await enqueueSync(
        entityType: 'Employee',
        entityId: id,
        action: 'UPDATE', // Soft delete is an update
      );
      if (actionBy != null) {
        await logActivity(
          action: 'Deleted Employee',
          ownerId: actionBy,
          targetEmployeeId: id,
        );
      }
    }
  }

  // --- Audit & Login Logging ---

  Future<void> logActivity({
    required String action,
    required String ownerId,
    required String targetEmployeeId,
  }) async {
    final log = ActivityLogModel(
      timestamp: DateTime.now(),
      action: action,
      ownerId: ownerId,
      targetEmployeeId: targetEmployeeId,
    );
    await _activityLogBox.put(log.id, log);
    await enqueueSync(
      entityType: 'ActivityLog',
      entityId: log.id,
      action: 'CREATE',
    );
  }

  List<ActivityLogModel> getActivityLogs() {
    return _activityLogBox.values.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<void> logLogin({
    required String employeeId,
    required String deviceInfo,
    required String ipAddress,
  }) async {
    final log = LoginHistoryModel(
      employeeId: employeeId,
      loginTime: DateTime.now(),
      deviceInfo: deviceInfo,
      ipAddress: ipAddress,
    );
    await _loginHistoryBox.put(log.id, log);
    await enqueueSync(
      entityType: 'LoginHistory',
      entityId: log.id,
      action: 'CREATE',
    );
  }

  List<LoginHistoryModel> getLoginHistory() {
    return _loginHistoryBox.values.toList()..sort((a, b) => b.loginTime.compareTo(a.loginTime));
  }
}
