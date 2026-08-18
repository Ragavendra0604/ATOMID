import 'dart:async';

import 'package:atomid/core/utils/platform_io.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:hive_ce_flutter/hive_flutter.dart';
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
import 'package:atomid/data/models/customer_stats.dart';
import 'package:atomid/data/models/customer_ledger_model.dart';
import 'package:atomid/data/models/supplier_ledger_model.dart';
import 'package:atomid/data/models/loyalty_transaction_model.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/models/sync_queue_model.dart';
import 'package:atomid/data/models/sync_log_model.dart';
import 'package:atomid/data/models/expense_model.dart';
import 'package:atomid/hive_registrar.g.dart';
import 'package:atomid/data/sync/entity_codec.dart';
import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/ids.dart';

/// Areas of the store that the UI subscribes to.
///
/// Read providers watch a topic instead of relying on each screen remembering
/// to invalidate after a write — the previous arrangement, where a missed
/// invalidation silently showed stale numbers.
class DataTopic {
  static const products = 'products';
  static const inventory = 'inventory';
  static const sales = 'sales';
  static const customers = 'customers';
  static const suppliers = 'suppliers';
  static const purchases = 'purchases';
  static const expenses = 'expenses';
  static const settings = 'settings';
  static const history = 'history';
  static const loyalty = 'loyalty';
  static const sync = 'sync';

  static const all = [
    products,
    inventory,
    sales,
    customers,
    suppliers,
    purchases,
    expenses,
    settings,
    history,
    loyalty,
    sync,
  ];
}

/// Lifecycle states for a queued sync item.
class SyncState {
  static const pending = 'PENDING';
  static const syncing = 'SYNCING';
  static const failed = 'FAILED';

  /// Terminal state: retries exhausted. Kept for reporting, never retried.
  static const dead = 'DEAD';

  static const maxRetries = 5;
}

/// Today's sales figures, derived together and held until a sale changes.
class _TodayTotals {
  final DateTime day;
  final List<Sale> sales;
  final double revenue;
  final int units;

  const _TodayTotals({
    required this.day,
    required this.sales,
    required this.revenue,
    required this.units,
  });

  /// Guards against a till left open across midnight still reporting
  /// yesterday's takings as today's.
  bool isFor(DateTime now) =>
      day.year == now.year && day.month == now.month && day.day == now.day;
}

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

  // Fast index for barcode -> Product
  final Map<String, Product> _barcodeIndex = {};

  // Mobile number -> Customer. The till identifies people by phone, so this
  // has to be O(1) rather than a scan on every keystroke.
  final Map<String, Customer> _mobileIndex = {};

  // Customer id -> the number they are currently indexed under.
  //
  // Needed because Hive hands back the same instance the caller just mutated,
  // so re-reading the box cannot tell us what the number used to be.
  final Map<String, String> _indexedMobile = {};

  // Customer -> their sales, so visit counts do not rescan the sales box.
  final Map<String, List<Sale>> _salesByCustomer = {};

  // Ledger running balances, kept in memory so appending an entry does not
  // require rewriting every historical row for that party.
  final Map<String, double> _customerBalances = {};
  final Map<String, double> _supplierBalances = {};

  static bool _adaptersRegistered = false;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Boxes that could not be opened and had to be rebuilt during [init].
  /// Surfaced on the splash screen so data loss is never silent.
  final List<String> recoveredBoxes = [];

  final StreamController<String> _changes = StreamController.broadcast();

  /// Emits a [DataTopic] whenever stored data changes.
  Stream<String> get changes => _changes.stream;

  void _notify(String topic) {
    // Derived totals are dropped here rather than at each write site. Every
    // path that changes sales has to announce it or the UI would not refresh
    // either, so hanging invalidation off the same signal means the cache
    // cannot outlive the data it summarises.
    if (topic == DataTopic.sales) _todayCache = null;
    if (!_changes.isClosed) _changes.add(topic);
  }

  Future<void> dispose() async {
    await _changes.close();
  }

  /// Opens every box.
  ///
  /// [storagePath] bypasses platform directory lookup — tests supply a
  /// temporary folder so the repository can be exercised for real without a
  /// path_provider plugin implementation.
  Future<void> init({String? storagePath}) async {
    if (storagePath != null) {
      Hive.init(storagePath);
    } else if (kIsWeb) {
      await Hive.initFlutter();
    } else {
      PlatformDirectory dir;
      try {
        final path = await PlatformIo.getApplicationSupportDirectoryPath();
        dir = PlatformDirectory(path);
      } catch (_) {
        final path = await PlatformIo.getApplicationDocumentsDirectoryPath();
        dir = PlatformDirectory(path);
      }

      // If the support directory somehow maps to OneDrive, force a local path
      String dbPath = dir.path;
      if (dbPath.contains('OneDrive')) {
        final userProfile = PlatformIo.userProfile;
        if (userProfile != null) {
          dbPath = '$userProfile\\AppData\\Local\\atomid\\db';
        }
      } else {
        dbPath = '$dbPath\\db';
      }

      final dbDir = PlatformDirectory(dbPath);
      if (!dbDir.existsSync()) {
        dbDir.createSync(recursive: true);
      }

      Hive.init(dbPath);
    }

    // Type adapters are registered per isolate, not per repository, and
    // registering twice throws. Guarding here keeps a second init — a startup
    // retry, or a fresh store in a test — from failing.
    if (!_adaptersRegistered) {
      Hive.registerAdapters();
      _adaptersRegistered = true;
    }

    // Open boxes with safe auto-recovery.
    //
    // Every open is started before anything is awaited, so twenty-one disk
    // reads overlap instead of running end to end. Awaited sequentially they
    // held the first frame for seconds on a cold start — the splash was up but
    // the isolate was too busy to draw it. The boxes are independent and
    // [_safeOpenBox] recovers each one on its own, so there is no ordering
    // between them to preserve.
    final productsOpen = _safeOpenBox<Product>(productsBoxName);
    final historyOpen = _safeOpenBox<ActionHistory>(historyBoxName);
    final settingsOpen = _safeOpenBox<SettingsModel>(settingsBoxName);
    final invoiceSettingsOpen = _safeOpenBox<InvoiceSettingsModel>(
      invoiceSettingsBoxName,
    );
    final movementsOpen = _safeOpenBox<InventoryMovement>(movementsBoxName);
    final salesOpen = _safeOpenBox<Sale>(salesBoxName);
    final suppliersOpen = _safeOpenBox<Supplier>(suppliersBoxName);
    final purchasesOpen = _safeOpenBox<Purchase>(purchasesBoxName);
    final companyOpen = _safeOpenBox<CompanyModel>('company');
    final customersOpen = _safeOpenBox<Customer>(customersBoxName);
    final customerLedgersOpen = _safeOpenBox<CustomerLedger>(
      customerLedgersBoxName,
    );
    final supplierLedgersOpen = _safeOpenBox<SupplierLedger>(
      supplierLedgersBoxName,
    );
    final loyaltyTransactionsOpen = _safeOpenBox<LoyaltyTransaction>(
      loyaltyTransactionsBoxName,
    );
    final loyaltySettingsOpen = _safeOpenBox<LoyaltySettingsModel>(
      loyaltySettingsBoxName,
    );
    final syncQueueOpen = _safeOpenBox<SyncQueueItem>(syncQueueBoxName);
    final syncLogOpen = _safeOpenBox<SyncLogModel>(syncLogBoxName);
    final expensesOpen = _safeOpenBox<Expense>(expensesBoxName);
    final expenseCategoriesOpen = _safeOpenBox<ExpenseCategory>(
      expenseCategoriesBoxName,
    );

    _productsBox = await productsOpen;
    _historyBox = await historyOpen;
    _settingsBox = await settingsOpen;
    _invoiceSettingsBox = await invoiceSettingsOpen;
    _movementsBox = await movementsOpen;
    _salesBox = await salesOpen;
    _suppliersBox = await suppliersOpen;
    _purchasesBox = await purchasesOpen;
    _companyBox = await companyOpen;
    _customersBox = await customersOpen;
    _customerLedgersBox = await customerLedgersOpen;
    _supplierLedgersBox = await supplierLedgersOpen;
    _loyaltyTransactionsBox = await loyaltyTransactionsOpen;
    _loyaltySettingsBox = await loyaltySettingsOpen;
    _syncQueueBox = await syncQueueOpen;
    _syncLogBox = await syncLogOpen;
    _expensesBox = await expensesOpen;
    _expenseCategoriesBox = await expenseCategoriesOpen;

    _rebuildBarcodeIndex();
    _rebuildCustomerIndexes();
    _rebuildLedgerBalances();
    await resetStuckSyncItems();
    _isInitialized = true;
  }

  /// Opens a box, escalating through recovery steps rather than destroying
  /// data on the first error.
  ///
  /// A locked file or a transient IO error is retried; only a box that still
  /// refuses to open after crash recovery is rebuilt, and the loss is recorded
  /// in [recoveredBoxes] so the user is told.
  /// Reclaims disk once a box is more deleted-and-overwritten than live.
  ///
  /// Hive appends: every save of a record leaves the previous copy on disk as
  /// a dead frame, and nothing removes them on its own. A till that edits
  /// stock all day grows its file without its data growing at all — the frames
  /// are read and skipped on every open, so it costs startup time as well as
  /// space. Compacting at "half the frames are dead, and there are at least
  /// 60 of them" keeps small boxes from churning while stopping a busy one
  /// from running away.
  static bool _shouldCompact(int deletedEntries, int totalEntries) =>
      totalEntries > 60 && deletedEntries > totalEntries * 0.5;

  Future<Box<T>> _safeOpenBox<T>(String boxName) async {
    try {
      return await Hive.openBox<T>(boxName, compactionStrategy: _shouldCompact);
    } catch (e) {
      debugPrint('Box $boxName failed to open ($e). Attempting recovery...');
    }

    // Step 1: retry once — most failures here are a transient file lock.
    try {
      await Future.delayed(const Duration(milliseconds: 250));
      return await Hive.openBox<T>(boxName, compactionStrategy: _shouldCompact);
    } catch (e) {
      debugPrint(
        'Box $boxName retry failed ($e). Attempting crash recovery...',
      );
    }

    // Step 2: crash recovery salvages everything up to the corrupt frame.
    try {
      return await Hive.openBox<T>(
        boxName,
        crashRecovery: true,
        compactionStrategy: _shouldCompact,
      );
    } catch (e) {
      debugPrint('Box $boxName crash recovery failed ($e). Rebuilding...');
    }

    // Step 3: unrecoverable. Rebuild, and record that data was lost.
    recoveredBoxes.add(boxName);
    try {
      await Hive.deleteBoxFromDisk(boxName);
    } catch (_) {
      // Filesystem is locked, or we are on Web where the box is in IndexedDB.
    }
    return await Hive.openBox<T>(boxName);
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

  void _rebuildCustomerIndexes() {
    _mobileIndex.clear();
    _indexedMobile.clear();
    for (final customer in _customersBox.values) {
      if (customer.isDeleted) continue;
      _indexCustomerMobile(customer);
    }

    _salesByCustomer.clear();
    for (final sale in _salesBox.values) {
      if (sale.customerId.isEmpty || sale.isDeleted) continue;
      _salesByCustomer.putIfAbsent(sale.customerId, () => []).add(sale);
    }
  }

  void _indexCustomerMobile(Customer customer) {
    final previousKey = _indexedMobile[customer.id];
    if (previousKey != null && _mobileIndex[previousKey]?.id == customer.id) {
      _mobileIndex.remove(previousKey);
      _indexedMobile.remove(customer.id);
    }

    if (customer.isDeleted) return;

    final key = normaliseMobile(customer.mobile);
    if (key.isEmpty) return;
    _mobileIndex[key] = customer;
    _indexedMobile[customer.id] = key;
  }

  /// Strips spacing, punctuation and a country code so `+91 98765 43210`,
  /// `098765 43210` and `9876543210` all find the same person.
  static String normaliseMobile(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10) {
      digits = digits.substring(digits.length - 10);
    }
    return digits;
  }

  /// Finds a customer by phone number. The till's primary lookup.
  Customer? getCustomerByMobile(String mobile) {
    final key = normaliseMobile(mobile);
    if (key.length < 10) return null;
    return _mobileIndex[key];
  }

  /// Purchase history summary, for deciding what to offer a returning face.
  CustomerVisitStats getCustomerStats(String customerId) {
    final sales = _salesByCustomer[customerId];
    if (sales == null || sales.isEmpty) return CustomerVisitStats.none;

    var total = 0.0;
    DateTime? first;
    DateTime? last;

    for (final sale in sales) {
      total += sale.grandTotal;
      if (first == null || sale.date.isBefore(first)) first = sale.date;
      if (last == null || sale.date.isAfter(last)) last = sale.date;
    }

    return CustomerVisitStats(
      visits: sales.length,
      totalSpend: Fmt.round2(total),
      firstVisit: first,
      lastVisit: last,
    );
  }

  /// Sales for one customer, newest first.
  List<Sale> getSalesForCustomer(String customerId) {
    final sales = [...?_salesByCustomer[customerId]];
    sales.sort((a, b) => b.date.compareTo(a.date));
    return sales;
  }

  void _rebuildLedgerBalances() {
    _customerBalances.clear();
    for (final customer in _customersBox.values) {
      _customerBalances[customer.id] = customer.currentBalance;
    }
    _supplierBalances.clear();
    for (final supplier in _suppliersBox.values) {
      _supplierBalances[supplier.id] = supplier.currentBalance;
    }
  }

  // --- SYNC QUEUE ---

  /// Entity types the sync engine knows how to serialise.
  ///
  /// Enqueuing anything outside this set produces an item that can never be
  /// sent and never be removed, so the queue is guarded at the entry point.
  static const Set<String> syncableEntities = {
    'Product',
    'Customer',
    'Sale',
    'Supplier',
    'Purchase',
    'Expense',
    'ExpenseCategory',
    'InventoryMovement',
    'LoyaltyTransaction',
    'CustomerLedger',
    'SupplierLedger',
    'SettingsModel',
    'CompanyModel',
    'InvoiceSettingsModel',
    'LoyaltySettingsModel',
  };

  Future<void> enqueueSync({
    required String entityType,
    required String entityId,
    required String action,
    int priority = 10,
  }) async {
    assert(
      syncableEntities.contains(entityType),
      'No sync serialiser exists for "$entityType" — add one to '
      'getEntityJson and syncableEntities, or do not enqueue it.',
    );
    if (!syncableEntities.contains(entityType)) return;

    // Every meaningful mutation funnels through here, so this is the single
    // place that tells the UI something changed.
    for (final topic in _topicsFor(entityType)) {
      _notify(topic);
    }
    _notify(DataTopic.sync);

    // Collapse duplicates: a pending write for the same record is replaced
    // rather than stacked, so rapid edits produce one upload, not twenty.
    final existing = _syncQueueBox.values.firstWhere(
      (item) =>
          item.entityType == entityType &&
          item.entityId == entityId &&
          (item.status == SyncState.pending || item.status == SyncState.failed),
      orElse: () => _noSyncItem,
    );

    if (!identical(existing, _noSyncItem)) {
      // A delete always wins over a pending create/update.
      existing.action = action == 'DELETE' ? 'DELETE' : existing.action;
      existing.status = SyncState.pending;
      existing.createdAt = DateTime.now();
      await _syncQueueBox.put(existing.id, existing);
      return;
    }

    final item = SyncQueueItem(
      id: Ids.generate(),
      entityType: entityType,
      entityId: entityId,
      action: action,
      status: SyncState.pending,
      retryCount: 0,
      createdAt: DateTime.now(),
      priority: priority,
    );
    await _syncQueueBox.put(item.id, item);
  }

  static List<String> _topicsFor(String entityType) {
    switch (entityType) {
      case 'Product':
        return const [DataTopic.products, DataTopic.inventory];
      case 'InventoryMovement':
        return const [DataTopic.inventory, DataTopic.history];
      case 'Sale':
        return const [DataTopic.sales, DataTopic.inventory, DataTopic.products];
      case 'Customer':
        return const [DataTopic.customers];
      case 'LoyaltyTransaction':
        return const [DataTopic.loyalty, DataTopic.customers];
      case 'Supplier':
        return const [DataTopic.suppliers];
      case 'Purchase':
        return const [
          DataTopic.purchases,
          DataTopic.inventory,
          DataTopic.suppliers,
        ];
      case 'Expense':
      case 'ExpenseCategory':
        return const [DataTopic.expenses];
      case 'LoyaltySettingsModel':
        return const [DataTopic.loyalty, DataTopic.settings];
      default:
        return const [DataTopic.settings];
    }
  }

  static final SyncQueueItem _noSyncItem = SyncQueueItem(
    id: '',
    entityType: '',
    entityId: '',
    action: '',
    status: '',
    retryCount: 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// Returns items to `PENDING` if the app was killed mid-upload.
  ///
  /// `SYNCING` is not a queryable state, so without this sweep an item left in
  /// it by a crash would never be retried again.
  // --- Backup ---------------------------------------------------------------

  /// Local keys for the records that are one-of-a-kind rather than a list.
  static const Map<String, String> _singletonKeys = {
    'SettingsModel': 'app_settings',
    'CompanyModel': 'profile',
    'InvoiceSettingsModel': 'invoice_settings',
    'LoyaltySettingsModel': 'loyalty_settings',
  };

  /// Every record on this device, grouped by entity type.
  ///
  /// Built from [getEntityJson] rather than a second serialiser of its own.
  /// A backup written by different code than the one sync uses would drift
  /// from it silently — and a backup that quietly omits a field is worse than
  /// no backup, because it is only discovered when someone restores it.
  Map<String, List<Map<String, dynamic>>> exportSnapshot() {
    final snapshot = <String, List<Map<String, dynamic>>>{};

    for (final entityType in syncableEntities) {
      final singleton = _singletonKeys[entityType];
      final ids = singleton != null ? [singleton] : _idsFor(entityType);

      final records = <Map<String, dynamic>>[];
      for (final id in ids) {
        final json = getEntityJson(entityType, id);
        if (json == null) continue;
        // The local key travels alongside, because a singleton's payload id
        // ('settings') is not the box key it has to be restored under.
        records.add({...json, '_localId': id});
      }
      if (records.isNotEmpty) snapshot[entityType] = records;
    }

    return snapshot;
  }

  List<String> _idsFor(String entityType) => switch (entityType) {
    'Product' => _productsBox.keys.cast<String>().toList(),
    'Customer' => _customersBox.keys.cast<String>().toList(),
    'Supplier' => _suppliersBox.keys.cast<String>().toList(),
    'Sale' => _salesBox.keys.cast<String>().toList(),
    'Purchase' => _purchasesBox.keys.cast<String>().toList(),
    'Expense' => _expensesBox.keys.cast<String>().toList(),
    'ExpenseCategory' => _expenseCategoriesBox.keys.cast<String>().toList(),
    'InventoryMovement' => _movementsBox.keys.cast<String>().toList(),
    'LoyaltyTransaction' =>
      _loyaltyTransactionsBox.keys.cast<String>().toList(),
    'CustomerLedger' => _customerLedgersBox.keys.cast<String>().toList(),
    'SupplierLedger' => _supplierLedgersBox.keys.cast<String>().toList(),
    _ => const <String>[],
  };

  /// Writes a snapshot back, returning how many records of each type landed.
  ///
  /// Restoring is additive by id: a record already present is overwritten, one
  /// that is absent is created, and nothing local is deleted for being absent
  /// from the backup. Restoring an older backup therefore cannot destroy work
  /// done since it was taken, which is the failure people actually fear.
  Future<Map<String, int>> importSnapshot(
    Map<String, List<Map<String, dynamic>>> snapshot,
  ) async {
    final restored = <String, int>{};

    // Dependency order matters: a sale references products and customers.
    final order = [
      ...EntityCodec.pullOrder.where(snapshot.containsKey),
      ...snapshot.keys.where((k) => !EntityCodec.pullOrder.contains(k)),
    ];

    for (final entityType in order) {
      var count = 0;
      for (final record in snapshot[entityType] ?? const []) {
        final id = record['_localId'] as String? ?? record['id'] as String?;
        if (id == null || id.isEmpty) continue;
        if (await _writeRestored(entityType, id, record)) count++;
      }
      if (count > 0) restored[entityType] = count;
    }

    await reconcileAfterPull();
    return restored;
  }

  /// Puts one restored record straight into its box.
  ///
  /// Deliberately not [applyRemote]: that refuses a record with unsent local
  /// changes and skips anything older than what is stored, which are the right
  /// rules for a peer device and the wrong ones for an operator who has asked
  /// for this file to be put back.
  Future<bool> _writeRestored(
    String entityType,
    String id,
    Map<String, dynamic> json,
  ) async {
    switch (entityType) {
      case 'Product':
        await _productsBox.put(id, EntityCodec.product(json));
      case 'Customer':
        await _customersBox.put(id, EntityCodec.customer(json));
      case 'Supplier':
        await _suppliersBox.put(id, EntityCodec.supplier(json));
      case 'Sale':
        await _salesBox.put(id, EntityCodec.sale(json));
      case 'Purchase':
        await _purchasesBox.put(id, EntityCodec.purchase(json));
      case 'Expense':
        await _expensesBox.put(id, EntityCodec.expense(json));
      case 'ExpenseCategory':
        await _expenseCategoriesBox.put(id, EntityCodec.expenseCategory(json));
      case 'InventoryMovement':
        await _movementsBox.put(id, EntityCodec.movement(json));
      case 'LoyaltyTransaction':
        await _loyaltyTransactionsBox.put(
          id,
          EntityCodec.loyaltyTransaction(json),
        );
      case 'CustomerLedger':
        await _customerLedgersBox.put(id, EntityCodec.customerLedger(json));
      case 'SupplierLedger':
        await _supplierLedgersBox.put(id, EntityCodec.supplierLedger(json));
      case 'SettingsModel':
        // Biometric enrolment is per-device and is not in the payload, so it
        // is carried over rather than reset by a restore.
        final incoming = EntityCodec.settings(json);
        final local = _settingsBox.get('app_settings');
        if (local != null) {
          incoming.isBiometricEnabled = local.isBiometricEnabled;
        }
        await _settingsBox.put('app_settings', incoming);
      case 'CompanyModel':
        await _companyBox.put('profile', EntityCodec.company(json));
      case 'InvoiceSettingsModel':
        await _invoiceSettingsBox.put(
          'invoice_settings',
          EntityCodec.invoiceSettings(json),
        );
      case 'LoyaltySettingsModel':
        await _loyaltySettingsBox.put(
          'loyalty_settings',
          EntityCodec.loyaltySettings(json),
        );
      default:
        return false;
    }

    await enqueueSync(entityType: entityType, entityId: id, action: 'UPDATE');
    return true;
  }

  Future<void> resetStuckSyncItems() async {
    for (final item in _syncQueueBox.values.toList()) {
      if (item.status == SyncState.syncing) {
        item.status = SyncState.pending;
        await _syncQueueBox.put(item.id, item);
      }
    }
  }

  /// Items that exhausted their retries. Surfaced in the sync sheet so the
  /// user knows some records are not reaching the cloud.
  List<SyncQueueItem> getDeadSyncItems() =>
      _syncQueueBox.values.where((i) => i.status == SyncState.dead).toList();

  int get pendingSyncCount =>
      _syncQueueBox.values.where((i) => i.status != SyncState.dead).length;

  /// Moves dead items back to the queue for a manual retry.
  Future<void> retryDeadSyncItems() async {
    for (final item in _syncQueueBox.values.toList()) {
      if (item.status == SyncState.dead) {
        item.status = SyncState.pending;
        item.retryCount = 0;
        item.lastAttempt = null;
        await _syncQueueBox.put(item.id, item);
      }
    }
  }

  Future<void> enqueueAllExistingDataForSync() async {
    // Enqueue all products
    for (var p in _productsBox.values) {
      await enqueueSync(
        entityType: 'Product',
        entityId: p.id,
        action: 'UPDATE',
      );
    }
    // Enqueue all customers
    for (var c in _customersBox.values) {
      if (!c.isDeleted) {
        await enqueueSync(
          entityType: 'Customer',
          entityId: c.id,
          action: 'UPDATE',
        );
      }
    }
    // Enqueue all sales
    for (var s in _salesBox.values) {
      await enqueueSync(entityType: 'Sale', entityId: s.id, action: 'UPDATE');
    }
    // Enqueue all suppliers
    for (var s in _suppliersBox.values) {
      if (!s.isDeleted) {
        await enqueueSync(
          entityType: 'Supplier',
          entityId: s.id,
          action: 'UPDATE',
        );
      }
    }
    // Enqueue all purchases
    for (var p in _purchasesBox.values) {
      await enqueueSync(
        entityType: 'Purchase',
        entityId: p.id,
        action: 'UPDATE',
      );
    }
    // Enqueue all expenses
    for (var e in _expensesBox.values) {
      await enqueueSync(
        entityType: 'Expense',
        entityId: e.id,
        action: 'UPDATE',
      );
    }
    // Enqueue all movements
    for (var m in _movementsBox.values) {
      await enqueueSync(
        entityType: 'InventoryMovement',
        entityId: m.id,
        action: 'UPDATE',
      );
    }
    // Expense categories
    for (var c in _expenseCategoriesBox.values) {
      await enqueueSync(
        entityType: 'ExpenseCategory',
        entityId: c.id,
        action: 'UPDATE',
      );
    }
    // Loyalty transactions
    for (var t in _loyaltyTransactionsBox.values) {
      await enqueueSync(
        entityType: 'LoyaltyTransaction',
        entityId: t.id,
        action: 'UPDATE',
      );
    }
    // Singleton documents
    await enqueueSync(
      entityType: 'SettingsModel',
      entityId: 'app_settings',
      action: 'UPDATE',
    );
    await enqueueSync(
      entityType: 'CompanyModel',
      entityId: 'profile',
      action: 'UPDATE',
    );
    await enqueueSync(
      entityType: 'InvoiceSettingsModel',
      entityId: 'invoice_settings',
      action: 'UPDATE',
    );
    await enqueueSync(
      entityType: 'LoyaltySettingsModel',
      entityId: 'loyalty_settings',
      action: 'UPDATE',
    );
  }

  List<SyncQueueItem> getPendingSyncItems() {
    final items = _syncQueueBox.values
        .where(
          (item) =>
              item.status == SyncState.pending ||
              item.status == SyncState.failed,
        )
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

  Future<void> updateSyncItemStatus(
    String id,
    String status, {
    int? retryCount,
    DateTime? lastAttempt,
  }) async {
    final item = _syncQueueBox.get(id);
    if (item != null) {
      // Retries exhausted: park it rather than re-scanning it forever.
      final resolved =
          status == SyncState.failed &&
              (retryCount ?? item.retryCount) >= SyncState.maxRetries
          ? SyncState.dead
          : status;
      item.status = resolved;
      if (retryCount != null) item.retryCount = retryCount;
      if (lastAttempt != null) item.lastAttempt = lastAttempt;
      await _syncQueueBox.put(id, item);
      _notify(DataTopic.sync);
    }
  }

  Future<void> deleteSyncItem(String id) async {
    await _syncQueueBox.delete(id);
    _notify(DataTopic.sync);
  }

  // --- SYNC LOGS ---
  Future<void> addSyncLog(SyncLogModel log) async {
    await _syncLogBox.put(log.id, log);

    // Optional: Keep only the latest 1000 logs to prevent unbounded growth
    if (_syncLogBox.length > 1000) {
      final keysToDelete = _syncLogBox.keys
          .take(_syncLogBox.length - 1000)
          .toList();
      await _syncLogBox.deleteAll(keysToDelete);
    }
  }

  /// Sync outcomes, newest first.
  ///
  /// Every batch has been recorded here since sync was written, but nothing
  /// ever read them back — the failures a technician needs to diagnose were
  /// being captured and discarded.
  List<SyncLogModel> getSyncLogs({int limit = 200, bool failuresOnly = false}) {
    final logs =
        _syncLogBox.values
            .where((log) => !failuresOnly || log.status != 'SUCCESS')
            .toList()
          ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return logs.length > limit ? logs.sublist(0, limit) : logs;
  }

  /// Clears the sync log. The queue itself is untouched — this only discards
  /// history, never pending work.
  Future<void> clearSyncLogs() async {
    await _syncLogBox.clear();
    _notify(DataTopic.sync);
  }

  /// Builds the Firestore payload for a queued entity.
  ///
  /// Every branch mirrors the full model. A missing field here is silent data
  /// loss on sync, so anything added to a model must be added below and the
  /// round-trip covered by a test in `test/unit/sync_payload_test.dart`.
  Map<String, dynamic>? getEntityJson(String entityType, String entityId) {
    if (entityType == 'CompanyModel') {
      final c = getCompany();
      return {
        'name': c.name,
        'logoPath': c.logoPath,
        'ownerName': c.ownerName,
        'gstNumber': c.gstNumber,
        'panNumber': c.panNumber,
        'phone1': c.phone1,
        'phone2': c.phone2,
        'email': c.email,
        'website': c.website,
        'address': c.address,
        'city': c.city,
        'state': c.state,
        'country': c.country,
        'pincode': c.pincode,
        'invoicePrefix': c.invoicePrefix,
        'barcodePrefix': c.barcodePrefix,
        'currency': c.currency,
        'financialYear': c.financialYear,
      };
    }
    if (entityType == 'InvoiceSettingsModel') {
      final s = getInvoiceSettings();
      return {
        'footerText': s.footerText,
        'showUpiQr': s.showUpiQr,
        'upiId': s.upiId,
        'upiQrImagePath': s.upiQrImagePath,
        'showCompanyLogo': s.showCompanyLogo,
        'termsAndConditions': s.termsAndConditions,
        'fontName': s.fontName,
      };
    }
    if (entityType == 'LoyaltySettingsModel') {
      final s = getLoyaltySettings();
      return {
        'isLoyaltyEnabled': s.isLoyaltyEnabled,
        'spendAmountForPoint': s.spendAmountForPoint,
        'pointsEarnedPerSpend': s.pointsEarnedPerSpend,
        'pointRedemptionValue': s.pointRedemptionValue,
        'maxRedemptionPercentage': s.maxRedemptionPercentage,
        'minBillAmountForRedemption': s.minBillAmountForRedemption,
      };
    }
    if (entityType == 'ExpenseCategory') {
      final c = _expenseCategoriesBox.get(entityId);
      if (c == null) return null;
      return {'id': c.id, 'name': c.name, 'iconName': c.iconName};
    }
    if (entityType == 'Customer') {
      final c = getCustomerById(entityId);
      if (c == null) return null;
      return {
        'id': c.id,
        'code': c.code,
        'name': c.name,
        'mobile': c.mobile,
        'gstNumber': c.gstNumber,
        'address': c.address,
        'creditLimit': c.creditLimit,
        'creditDays': c.creditDays,
        'openingBalance': c.openingBalance,
        'currentBalance': c.currentBalance,
        'status': c.status,
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
        'id': s.id,
        'invoiceNumber': s.invoiceNumber,
        'date': s.date.toIso8601String(),
        'customerId': s.customerId,
        'customerName': s.customerName,
        'subtotal': s.subtotal,
        'discountPercent': s.discountPercent,
        'discountAmount': s.discountAmount,
        'taxAmount': s.taxAmount,
        'grandTotal': s.grandTotal,
        'paymentMethod': s.paymentMethod,
        'notes': s.notes,
        'rewardDiscountAmount': s.rewardDiscountAmount,
        'rewardPointsEarned': s.rewardPointsEarned,
        'isSynced': true,
        'updatedAt': s.updatedAt?.toIso8601String(),
        'items': s.items
            .map(
              (i) => {
                'productId': i.productId,
                'productName': i.productName,
                'productCode': i.productCode,
                'variantBarcode': i.variantBarcode,
                'variantSize': i.variantSize,
                'price': i.price,
                'quantity': i.quantity,
                'total': i.total,
              },
            )
            .toList(),
      };
    }
    if (entityType == 'Supplier') {
      final s = getSupplierById(entityId);
      if (s == null) return null;
      return {
        'id': s.id,
        'code': s.supplierCode,
        'name': s.supplierName,
        'phone': s.phone,
        'email': s.email,
        'address': s.address,
        'gstNumber': s.gstNumber,
        'contactPerson': s.contactPerson,
        'notes': s.notes,
        'isActive': s.isActive,
        'isSynced': true,
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
        'id': l.id,
        'customerId': l.customerId,
        'saleId': l.saleId,
        'transactionType': l.transactionType,
        'points': l.points,
        'monetaryValue': l.monetaryValue,
        'reference': l.reference,
        'remarks': l.remarks,
        'createdDate': l.createdDate.toIso8601String(),
        'createdBy': l.createdBy,
        'isSynced': true,
        'updatedAt': l.updatedAt?.toIso8601String(),
      };
    }
    if (entityType == 'Product') {
      final p = getProductById(entityId);
      if (p == null) return null;
      return {
        'id': p.id,
        'productName': p.productName,
        'productCode': p.productCode,
        'category': p.category,
        'brand': p.brand,
        'color': p.color,
        'createdDate': p.createdDate.toIso8601String(),
        'updatedDate': p.updatedDate.toIso8601String(),
        'isSynced': true,
        'variants': p.variants
            .map(
              (v) => {
                'size': v.size,
                'barcode': v.barcode,
                'sku': v.sku,
                'price': v.price,
                'quantity': v.quantity,
                'reorderLevel': v.reorderLevel,
                'stockIn': v.stockIn,
                'stockOut': v.stockOut,
                'lastStockUpdated': v.lastStockUpdated?.toIso8601String(),
              },
            )
            .toList(),
      };
    }
    if (entityType == 'Purchase') {
      final p = getPurchaseById(entityId);
      if (p == null) return null;
      return {
        'id': p.id,
        'purchaseNumber': p.purchaseNumber,
        'purchaseDate': p.purchaseDate.toIso8601String(),
        'supplierId': p.supplierId,
        'supplierName': p.supplierName,
        'subtotal': p.subtotal,
        'discount': p.discount,
        'tax': p.tax,
        'grandTotal': p.grandTotal,
        'paymentStatus': p.paymentStatus,
        'status': p.status,
        'expectedDeliveryDate': p.expectedDeliveryDate?.toIso8601String(),
        'createdDate': p.createdDate.toIso8601String(),
        'createdBy': p.createdBy,
        'deviceId': p.deviceId,
        'version': p.version,
        'isDeleted': p.isDeleted,
        'notes': p.notes,
        'isSynced': true,
        'updatedAt': p.updatedAt?.toIso8601String(),
        'items': p.items
            .map(
              (i) => {
                'productId': i.productId,
                'productName': i.productName,
                'variantBarcode': i.variantBarcode,
                'variantSize': i.variantSize,
                'sku': i.sku,
                'sellingPrice': i.sellingPrice,
                'receivedQuantity': i.receivedQuantity,
                'costPrice': i.costPrice,
                'quantity': i.quantity,
                'lineTotal': i.lineTotal,
              },
            )
            .toList(),
      };
    }
    if (entityType == 'Expense') {
      final e = _expensesBox.get(entityId);
      if (e == null) return null;
      return {
        'id': e.id,
        'title': e.title,
        'categoryId': e.categoryId,
        'categoryName': e.categoryName,
        'amount': e.amount,
        'date': e.date.toIso8601String(),
        'notes': e.notes,
        'receiptImagePath': e.receiptImagePath,
        'createdDate': e.createdDate.toIso8601String(),
        'createdBy': e.createdBy,
        'isSynced': true,
      };
    }
    if (entityType == 'InventoryMovement') {
      final m = _movementsBox.get(entityId);
      if (m == null) return null;
      return {
        'id': m.id,
        'productId': m.productId,
        'productName': m.productName,
        'variantBarcode': m.variantBarcode,
        'variantSize': m.variantSize,
        'quantity': m.quantity,
        'type': m.type,
        'reason': m.reason,
        'date': m.date.toIso8601String(),
        'movementReferenceId': m.movementReferenceId,
        'performedAt': m.performedAt,
      };
    }
    if (entityType == 'CustomerLedger') {
      final l = _customerLedgersBox.get(entityId);
      if (l == null) return null;
      return {
        'id': l.id,
        'customerId': l.customerId,
        'date': l.date.toIso8601String(),
        'transactionType': l.transactionType,
        'referenceId': l.referenceId,
        'debit': l.debit,
        'credit': l.credit,
        'balance': l.balance,
        'notes': l.notes,
      };
    }
    if (entityType == 'SupplierLedger') {
      final l = _supplierLedgersBox.get(entityId);
      if (l == null) return null;
      return {
        'id': l.id,
        'supplierId': l.supplierId,
        'date': l.date.toIso8601String(),
        'transactionType': l.transactionType,
        'referenceId': l.referenceId,
        'debit': l.debit,
        'credit': l.credit,
        'balance': l.balance,
        'notes': l.notes,
      };
    }
    if (entityType == 'SettingsModel') {
      final s = _settingsBox.get('app_settings');
      if (s == null) return null;
      return {
        'isDarkMode': s.isDarkMode,
        'companyName': s.companyName,
        'currencySymbol': s.currencySymbol,
        'pdfPageSize': s.pdfPageSize,
        'taxMode': s.taxMode,
        'taxRate': s.taxRate,
      };
    }
    return null;
  }

  /// Local timestamp used to decide whether a remote copy is newer.
  DateTime? _localUpdatedAt(String entityType, String entityId) {
    switch (entityType) {
      case 'Product':
        return _productsBox.get(entityId)?.updatedDate;
      case 'Customer':
        return _customersBox.get(entityId)?.updatedAt;
      case 'Supplier':
        return _suppliersBox.get(entityId)?.updatedDate;
      case 'Sale':
        return _salesBox.get(entityId)?.updatedAt;
      case 'Purchase':
        return _purchasesBox.get(entityId)?.updatedAt;
      case 'LoyaltyTransaction':
        return _loyaltyTransactionsBox.get(entityId)?.updatedAt;
      case 'Expense':
        return _expensesBox.get(entityId)?.createdDate;
      default:
        return null;
    }
  }

  /// Writes a record pulled from the cloud into local storage.
  ///
  /// Resolution is last-write-wins on `updatedAt`, and a record with an
  /// unsent local change always wins so a pull can never discard work the
  /// device has not uploaded yet.
  ///
  /// Returns true when the local copy was replaced.
  Future<bool> applyRemote(
    String entityType,
    String entityId,
    Map<String, dynamic> json,
  ) async {
    final hasPendingLocalChange = _syncQueueBox.values.any(
      (item) =>
          item.entityType == entityType &&
          item.entityId == entityId &&
          item.status != SyncState.dead,
    );
    if (hasPendingLocalChange) return false;

    final remoteUpdated = EntityCodec.remoteUpdatedAt(json);
    final localUpdated = _localUpdatedAt(entityType, entityId);
    if (remoteUpdated != null &&
        localUpdated != null &&
        !remoteUpdated.isAfter(localUpdated)) {
      return false;
    }

    switch (entityType) {
      case 'Product':
        await _productsBox.put(entityId, EntityCodec.product(json));
        _rebuildBarcodeIndex();
        _notify(DataTopic.products);
        _notify(DataTopic.inventory);
      case 'Customer':
        await _customersBox.put(entityId, EntityCodec.customer(json));
        _customerBalances.remove(entityId);
        _notify(DataTopic.customers);
      case 'Supplier':
        await _suppliersBox.put(entityId, EntityCodec.supplier(json));
        _supplierBalances.remove(entityId);
        _notify(DataTopic.suppliers);
      case 'Sale':
        await _salesBox.put(entityId, EntityCodec.sale(json));
        _notify(DataTopic.sales);
      case 'Purchase':
        await _purchasesBox.put(entityId, EntityCodec.purchase(json));
        _costPriceIndex = null;
        _notify(DataTopic.purchases);
      case 'Expense':
        await _expensesBox.put(entityId, EntityCodec.expense(json));
        _notify(DataTopic.expenses);
      case 'ExpenseCategory':
        await _expenseCategoriesBox.put(
          entityId,
          EntityCodec.expenseCategory(json),
        );
        _notify(DataTopic.expenses);
      case 'InventoryMovement':
        await _movementsBox.put(entityId, EntityCodec.movement(json));
        _notify(DataTopic.inventory);
      case 'LoyaltyTransaction':
        await _loyaltyTransactionsBox.put(
          entityId,
          EntityCodec.loyaltyTransaction(json),
        );
        _notify(DataTopic.loyalty);
      case 'CustomerLedger':
        await _customerLedgersBox.put(
          entityId,
          EntityCodec.customerLedger(json),
        );
        _notify(DataTopic.customers);
      case 'SupplierLedger':
        await _supplierLedgersBox.put(
          entityId,
          EntityCodec.supplierLedger(json),
        );
        _notify(DataTopic.suppliers);
      case 'SettingsModel':
        // Merge rather than replace. The payload carries only the shared
        // trading settings, so putting the rebuilt record straight in wiped
        // every field it does not mention — including the biometric
        // enrolment, which is meaningless coming from another device and must
        // survive a pull.
        final incoming = EntityCodec.settings(json);
        final local = _settingsBox.get('app_settings');
        if (local != null) {
          incoming.isBiometricEnabled = local.isBiometricEnabled;
        }
        await _settingsBox.put('app_settings', incoming);
        _notify(DataTopic.settings);
      case 'CompanyModel':
        await _companyBox.put('profile', EntityCodec.company(json));
        _notify(DataTopic.settings);
      case 'InvoiceSettingsModel':
        await _invoiceSettingsBox.put(
          'invoice_settings',
          EntityCodec.invoiceSettings(json),
        );
        _notify(DataTopic.settings);
      case 'LoyaltySettingsModel':
        await _loyaltySettingsBox.put(
          'loyalty_settings',
          EntityCodec.loyaltySettings(json),
        );
        _notify(DataTopic.loyalty);
      default:
        return false;
    }
    return true;
  }

  /// Rebuilds derived state after a bulk pull.
  Future<void> reconcileAfterPull() async {
    _rebuildBarcodeIndex();
    _costPriceIndex = null;
    for (final customer in _customersBox.values) {
      _customerBalances[customer.id] = customer.currentBalance;
    }
    for (final supplier in _suppliersBox.values) {
      _supplierBalances[supplier.id] = supplier.currentBalance;
    }
    for (final topic in DataTopic.all) {
      _notify(topic);
    }
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

    // Every local write is a change worth telling other devices about.
    // Stock-in/stock-out mutate the same Product instance in place and would
    // otherwise leave this timestamp frozen at creation time forever, which
    // is what let a stale local copy always outrank a genuine remote update.
    product.updatedDate = DateTime.now();

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
    await enqueueSync(entityType: 'Product', entityId: id, action: 'DELETE');
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
    if (quantity <= 0) {
      throw const AppException('Quantity must be greater than 0.');
    }

    final product = _productsBox.get(productId);
    if (product == null) {
      throw const AppException('That product no longer exists.');
    }

    final variantIndex = product.variants.indexWhere(
      (v) => v.barcode == variantBarcode,
    );
    if (variantIndex == -1) {
      throw const AppException('That variant no longer exists on the product.');
    }

    final variant = product.variants[variantIndex];
    variant.quantity += quantity;
    variant.stockIn += quantity;
    variant.lastStockUpdated = DateTime.now();

    await saveProduct(product);

    // Record movement
    final movement = InventoryMovement(
      id: Ids.generate(),
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
    if (quantity <= 0) {
      throw const AppException('Quantity must be greater than 0.');
    }

    final product = _productsBox.get(productId);
    if (product == null) {
      throw const AppException('That product no longer exists.');
    }

    final variantIndex = product.variants.indexWhere(
      (v) => v.barcode == variantBarcode,
    );
    if (variantIndex == -1) {
      throw const AppException('That variant no longer exists on the product.');
    }

    final variant = product.variants[variantIndex];
    if (variant.quantity < quantity) {
      throw AppException(
        'Not enough stock for ${product.productName} (${variant.size}). '
        'Available: ${variant.quantity}, requested: $quantity.',
      );
    }

    variant.quantity -= quantity;
    variant.stockOut += quantity;
    variant.lastStockUpdated = DateTime.now();

    await saveProduct(product);

    // Record movement
    final movement = InventoryMovement(
      id: Ids.generate(),
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

    // Keep the audit trail bounded; it is a convenience log, not a ledger.
    if (_historyBox.length > 2000) {
      final excess = _historyBox.keys.take(_historyBox.length - 2000).toList();
      await _historyBox.deleteAll(excess);
    }
    _notify(DataTopic.history);
  }

  List<ActionHistory> getHistory() {
    return _historyBox.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> clearHistory() async {
    await _historyBox.clear();
    _notify(DataTopic.history);
  }

  // --- SETTINGS ---
  SettingsModel getSettings() {
    if (!_isInitialized) {
      return SettingsModel(
        isDarkMode: true,
        companyName: 'ATOMID STORE',
        currencySymbol: '₹',
        pdfPageSize: 'A4',
        taxMode: 'inclusive',
        taxRate: 0,
      );
    }
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
    return _invoiceSettingsBox.get('invoice_settings') ??
        InvoiceSettingsModel();
  }

  Future<void> saveInvoiceSettings(InvoiceSettingsModel settings) async {
    await _invoiceSettingsBox.put('invoice_settings', settings);
    await enqueueSync(
      entityType: 'InvoiceSettingsModel',
      entityId: 'invoice_settings',
      action: 'UPDATE',
    );
  }

  // --- DOCUMENT NUMBERING ---

  /// Identifies this installation. Set once from [SessionService] so offline
  /// document numbers from different devices cannot collide.
  String _deviceTag = '0000';
  set deviceId(String value) => _deviceTag = Ids.shortCode(value);

  /// The short tag stamped on document numbers, recorded in backups so a file
  /// can be traced back to the device that wrote it.
  String get deviceTag => _deviceTag;

  /// `INV-20260810-A3F1-0001`
  ///
  /// The device tag is what keeps two tills billing offline from both issuing
  /// invoice 0001 for the day.
  String getNextInvoiceNumber() {
    final company = getCompany();
    final base = company.invoicePrefix.trim().isEmpty
        ? 'INV'
        : company.invoicePrefix.trim().toUpperCase();
    final prefix = '$base-${_documentDateStamp()}-$_deviceTag-';
    return '$prefix${_nextCounter(prefix, _salesBox.values.map((s) => s.invoiceNumber))}';
  }

  String _documentDateStamp() {
    final now = DateTime.now();
    return '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
  }

  String _nextCounter(String prefix, Iterable<String> existingNumbers) {
    int maxCounter = 0;
    for (final number in existingNumbers) {
      if (!number.startsWith(prefix)) continue;
      final counter = int.tryParse(number.substring(prefix.length)) ?? 0;
      if (counter > maxCounter) maxCounter = counter;
    }
    return (maxCounter + 1).toString().padLeft(4, '0');
  }

  /// Persists a sale. Ledger, stock and loyalty effects belong to
  /// [SaleService] so the whole checkout can be rolled back as one unit.
  Future<void> saveSale(Sale sale) async {
    final isNew = _salesBox.get(sale.id) == null;
    await _salesBox.put(sale.id, sale);
    _indexSale(sale, isNew: isNew);
    await enqueueSync(
      entityType: 'Sale',
      entityId: sale.id,
      // Sales are the highest-value record in the app; they upload first.
      priority: 1,
      action: isNew ? 'CREATE' : 'UPDATE',
    );
  }

  /// Removes a sale that failed part-way through checkout.
  Future<void> deleteSale(String id) async {
    final sale = _salesBox.get(id);
    await _salesBox.delete(id);
    if (sale != null && sale.customerId.isNotEmpty) {
      _salesByCustomer[sale.customerId]?.removeWhere((s) => s.id == id);
    }
    await enqueueSync(entityType: 'Sale', entityId: id, action: 'DELETE');
  }

  void _indexSale(Sale sale, {required bool isNew}) {
    if (sale.customerId.isEmpty) return;
    final sales = _salesByCustomer.putIfAbsent(sale.customerId, () => []);
    if (isNew) {
      sales.add(sale);
    } else {
      final at = sales.indexWhere((s) => s.id == sale.id);
      at >= 0 ? sales[at] = sale : sales.add(sale);
    }
  }

  /// Removes an inventory movement written by a checkout that was rolled back.
  Future<void> deleteMovement(String id) async {
    await _movementsBox.delete(id);
    await enqueueSync(
      entityType: 'InventoryMovement',
      entityId: id,
      action: 'DELETE',
    );
  }

  /// The most recent movement recorded for a reference, used when unwinding.
  InventoryMovement? getMovementByReference(String referenceId) {
    for (final movement in _movementsBox.values) {
      if (movement.movementReferenceId == referenceId) return movement;
    }
    return null;
  }

  List<InventoryMovement> getMovementsByReference(String referenceId) =>
      _movementsBox.values
          .where((m) => m.movementReferenceId == referenceId)
          .toList();

  List<Sale> getAllSales() {
    return _salesBox.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  Sale? getSaleById(String id) {
    return _salesBox.get(id);
  }

  /// Today's takings, invoice list and unit count, computed once.
  ///
  /// The dashboard asks for all three, and each used to scan and sort every
  /// sale ever recorded — three full passes on every rebuild, growing with the
  /// shop's history. They are derived together and cached until a sale
  /// changes, so opening the home screen costs one pass on the first build and
  /// nothing on the rest.
  _TodayTotals get _todayTotals {
    final now = DateTime.now();
    final cached = _todayCache;
    if (cached != null && cached.isFor(now)) return cached;

    final sales = <Sale>[];
    var revenue = 0.0;
    var units = 0;

    for (final sale in _salesBox.values) {
      final date = sale.date;
      if (date.year != now.year ||
          date.month != now.month ||
          date.day != now.day) {
        continue;
      }
      sales.add(sale);
      revenue += sale.grandTotal;
      for (final item in sale.items) {
        units += item.quantity;
      }
    }
    sales.sort((a, b) => b.date.compareTo(a.date));

    return _todayCache = _TodayTotals(
      day: DateTime(now.year, now.month, now.day),
      sales: List.unmodifiable(sales),
      revenue: Fmt.round2(revenue),
      units: units,
    );
  }

  _TodayTotals? _todayCache;

  List<Sale> getTodaySales() => _todayTotals.sales;

  double getTodayRevenue() => _todayTotals.revenue;

  int getTodayItemsSold() => _todayTotals.units;

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

  /// Soft-deletes a supplier so the deletion reaches other devices.
  ///
  /// A hard local delete leaves the cloud copy alive and reappearing on the
  /// next pull, and orphans the supplier name on historical purchases.
  Future<void> deleteSupplier(String id) async {
    final supplier = _suppliersBox.get(id);
    if (supplier == null) return;
    supplier.isDeleted = true;
    supplier.isActive = false;
    supplier.updatedDate = DateTime.now();
    await _suppliersBox.put(id, supplier);
    await enqueueSync(entityType: 'Supplier', entityId: id, action: 'UPDATE');
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
    return _suppliersBox.values
        .where((s) => !s.isDeleted && s.supplierCategory == category)
        .toList()
      ..sort((a, b) => b.createdDate.compareTo(a.createdDate));
  }

  bool isSupplierCodeDuplicate(String code, {String? excludeId}) {
    return _suppliersBox.values.any(
      (s) => s.supplierCode == code && s.id != excludeId,
    );
  }

  // --- PURCHASES ---
  String getNextPurchaseNumber() {
    final prefix = 'PUR-${_documentDateStamp()}-$_deviceTag-';
    return '$prefix${_nextCounter(prefix, _purchasesBox.values.map((p) => p.purchaseNumber))}';
  }

  /// Saves a purchase to the local database.
  /// Note: Stock updates and supplier ledger entries are now handled by PurchaseService.
  Future<void> savePurchase(Purchase purchase) async {
    final isNew = _purchasesBox.get(purchase.id) == null;
    await _purchasesBox.put(purchase.id, purchase);
    _costPriceIndex = null; // cost prices may have moved
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
  // Cached barcode -> latest cost price. Rebuilt only when a purchase changes,
  // instead of re-sorting every purchase on each dashboard rebuild.
  Map<String, double>? _costPriceIndex;

  Map<String, double> _latestCostPrices() {
    final cached = _costPriceIndex;
    if (cached != null) return cached;

    final prices = <String, double>{};
    final sortedPurchases = _purchasesBox.values.toList()
      ..sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));
    for (final purchase in sortedPurchases) {
      for (final item in purchase.items) {
        prices[item.variantBarcode] = item.costPrice;
      }
    }
    return _costPriceIndex = prices;
  }

  Map<String, double> calculateInventoryValue() {
    double retailValue = 0;
    double costValue = 0;

    final latestCostPrices = _latestCostPrices();

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
    _indexCustomerMobile(customer);
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
    return _customersBox.values
        .where((c) => !c.isDeleted && c.customerGroup == group)
        .toList()
      ..sort((a, b) => b.createdDate.compareTo(a.createdDate));
  }

  List<CustomerLedger> getLedgerForCustomer(String customerId) {
    return _customerLedgersBox.values
        .where((l) => l.customerId == customerId)
        .toList()
      ..sort(
        (a, b) => a.date.compareTo(b.date),
      ); // Chronological for balance logic
  }

  /// Appends a ledger entry and advances the running balance.
  ///
  /// The balance is carried forward from the previous entry rather than
  /// recomputed from history, so a customer with a long ledger costs one write
  /// per transaction instead of one per historical row.
  /// Returns the id of the entry written, so a caller running a multi-step
  /// transaction can hand it to [deleteLedgerEntry] to compensate.
  Future<String> addLedgerEntry({
    required String customerId,
    required DateTime date,
    required String transactionType,
    required String referenceId,
    double debit = 0,
    double credit = 0,
    String notes = '',
  }) async {
    final customer = getCustomerById(customerId);
    if (customer == null) {
      throw const AppException('That customer no longer exists.');
    }

    final previousBalance =
        _customerBalances[customerId] ?? customer.currentBalance;
    final newBalance = Fmt.round2(previousBalance + debit - credit);

    final entry = CustomerLedger(
      id: Ids.generate(),
      customerId: customerId,
      date: date,
      transactionType: transactionType,
      referenceId: referenceId,
      debit: debit,
      credit: credit,
      notes: notes,
    )..balance = newBalance;

    await _customerLedgersBox.put(entry.id, entry);
    await enqueueSync(
      entityType: 'CustomerLedger',
      entityId: entry.id,
      action: 'CREATE',
    );

    _customerBalances[customerId] = newBalance;
    customer.currentBalance = newBalance;
    await saveCustomer(customer);
    return entry.id;
  }

  /// Removes a ledger entry and rebuilds the customer's running balance.
  ///
  /// Balances are carried forward, so dropping a row in the middle invalidates
  /// every balance after it — the full recalculation is the only correct
  /// repair. Mirrors [addLedgerEntry] in enqueueing nothing of its own: ledger
  /// rows ride to the cloud with their customer, not as separate documents.
  Future<void> deleteLedgerEntry(String entryId) async {
    final entry = _customerLedgersBox.get(entryId);
    if (entry == null) return;
    final customerId = entry.customerId;
    await _customerLedgersBox.delete(entryId);
    await recalculateCustomerLedger(customerId);
  }

  /// Recomputes a customer's ledger from scratch. Used after a merge or an
  /// out-of-order import, where carrying forward is not valid.
  Future<void> recalculateCustomerLedger(String customerId) async {
    final customer = getCustomerById(customerId);
    if (customer == null) return;

    double running = customer.openingBalance;
    for (final entry in getLedgerForCustomer(customerId)) {
      running = Fmt.round2(running + entry.debit - entry.credit);
      entry.balance = running;
      await _customerLedgersBox.put(entry.id, entry);
      // The running balance changed, so the stored entry no longer matches
      // what was uploaded.
      await enqueueSync(
        entityType: 'CustomerLedger',
        entityId: entry.id,
        action: 'UPDATE',
      );
    }
    _customerBalances[customerId] = running;
    customer.currentBalance = running;
    await saveCustomer(customer);
  }

  // --- SUPPLIER LEDGER ---
  List<SupplierLedger> getLedgerForSupplier(String supplierId) {
    return _supplierLedgersBox.values
        .where((l) => l.supplierId == supplierId)
        .toList()
      ..sort(
        (a, b) => a.date.compareTo(b.date),
      ); // Chronological for balance logic
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
    if (supplier == null) {
      throw const AppException('That supplier no longer exists.');
    }

    // A supplier balance is what we owe them: a purchase (credit) raises it,
    // a payment (debit) lowers it.
    final previousBalance =
        _supplierBalances[supplierId] ?? supplier.currentBalance;
    final newBalance = Fmt.round2(previousBalance + credit - debit);

    final entry = SupplierLedger(
      id: Ids.generate(),
      supplierId: supplierId,
      date: date,
      transactionType: transactionType,
      referenceId: referenceId,
      credit: credit,
      debit: debit,
      notes: notes,
    )..balance = newBalance;

    await _supplierLedgersBox.put(entry.id, entry);
    await enqueueSync(
      entityType: 'SupplierLedger',
      entityId: entry.id,
      action: 'CREATE',
    );

    _supplierBalances[supplierId] = newBalance;
    supplier.currentBalance = newBalance;
    await saveSupplier(supplier);
  }

  // --- LOYALTY ---
  LoyaltySettingsModel getLoyaltySettings() {
    return _loyaltySettingsBox.get('loyalty_settings') ??
        LoyaltySettingsModel();
  }

  Future<void> saveLoyaltySettings(LoyaltySettingsModel settings) async {
    await _loyaltySettingsBox.put('loyalty_settings', settings);
    await enqueueSync(
      entityType: 'LoyaltySettingsModel',
      entityId: 'loyalty_settings',
      action: 'UPDATE',
    );
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

  /// Returns the id of the transaction written, so a caller running a
  /// multi-step transaction can hand it to [deleteLoyaltyTransaction].
  Future<String> addLoyaltyTransaction({
    required String customerId,
    String? saleId,
    required String
    transactionType, // Earn, Redeem, Refund, Expire, ManualAdjustment
    required double points,
    required double monetaryValue,
    String reference = '',
    String remarks = '',
    required String createdBy,
  }) async {
    final customer = getCustomerById(customerId);
    if (customer == null) {
      throw const AppException('That customer no longer exists.');
    }

    final tx = LoyaltyTransaction(
      id: Ids.generate(),
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

    await _recomputeRewardPoints(customerId);
    return tx.id;
  }

  /// Removes a loyalty transaction and restores the customer's point balance.
  ///
  /// Used to compensate a checkout that failed after awarding or redeeming
  /// points, so a rolled-back sale cannot leave points behind.
  Future<void> deleteLoyaltyTransaction(String transactionId) async {
    final tx = _loyaltyTransactionsBox.get(transactionId);
    if (tx == null) return;
    final customerId = tx.customerId;
    await _loyaltyTransactionsBox.delete(transactionId);
    await enqueueSync(
      entityType: 'LoyaltyTransaction',
      entityId: transactionId,
      action: 'DELETE',
    );
    await _recomputeRewardPoints(customerId);
  }

  /// Re-derives a customer's point balance from their transaction history.
  Future<void> _recomputeRewardPoints(String customerId) async {
    final customer = getCustomerById(customerId);
    if (customer == null) return;

    double totalPoints = 0;
    for (final t in getLoyaltyTransactions(customerId)) {
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
    final maxAllowedValue =
        subtotal * (settings.maxRedemptionPercentage / 100.0);

    return potentialValue > maxAllowedValue ? maxAllowedValue : potentialValue;
  }

  // --- EXPENSES ---
  List<Expense> getExpenses() {
    return _expensesBox.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
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
    return _expenseCategoriesBox.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> saveExpenseCategory(ExpenseCategory category) async {
    await _expenseCategoriesBox.put(category.id, category);
    await enqueueSync(
      entityType: 'ExpenseCategory',
      entityId: category.id,
      action: 'UPDATE',
    );
  }

  Future<void> deleteExpenseCategory(String categoryId) async {
    await _expenseCategoriesBox.delete(categoryId);
    await enqueueSync(
      entityType: 'ExpenseCategory',
      entityId: categoryId,
      action: 'DELETE',
    );
  }
}
