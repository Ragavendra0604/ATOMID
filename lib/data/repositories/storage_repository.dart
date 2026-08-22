import 'dart:async';
import 'dart:convert';

import 'package:atomid/core/utils/platform_io.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, setEquals;
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
import 'package:atomid/data/models/diagnostic_log_model.dart';
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
  static const diagnostics = 'diagnostics';

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
    diagnostics,
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
  static const String checkoutJournalBoxName = 'checkout_journal';
  static const String diagnosticLogBoxName = 'diagnostic_logs';
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
  late Box<DiagnosticLog> _diagnosticLogBox;
  late Box<Expense> _expensesBox;
  late Box<ExpenseCategory> _expenseCategoriesBox;

  /// In-flight checkouts. Untyped on purpose: these rows are scratch state
  /// that never syncs and never outlives a successful sale, so giving them a
  /// Hive type id and an adapter would be permanent ceremony for temporary
  /// data.
  late Box<dynamic> _checkoutJournalBox;

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

  // Product id -> the barcodes it is currently indexed under, for the same
  // reason: a variant removed or re-barcoded has to have its old key dropped,
  // and the previous variant list is gone by the time the write lands.
  final Map<String, List<String>> _indexedBarcodes = {};

  // Customer -> their sales, so visit counts do not rescan the sales box.
  final Map<String, List<Sale>> _salesByCustomer = {};

  // Sale id -> the customer it is currently filed under, so a sale reassigned
  // to a different customer (or voided) leaves its old list.
  final Map<String, String> _indexedSaleCustomer = {};

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
    final diagnosticLogOpen = _safeOpenBox<DiagnosticLog>(diagnosticLogBoxName);
    final expensesOpen = _safeOpenBox<Expense>(expensesBoxName);
    final expenseCategoriesOpen = _safeOpenBox<ExpenseCategory>(
      expenseCategoriesBoxName,
    );
    final checkoutJournalOpen = _safeOpenBox<dynamic>(checkoutJournalBoxName);

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
    _diagnosticLogBox = await diagnosticLogOpen;
    _expensesBox = await expensesOpen;
    _expenseCategoriesBox = await expenseCategoriesOpen;
    _checkoutJournalBox = await checkoutJournalOpen;

    _rebuildBarcodeIndex();
    _rebuildCustomerIndexes();
    _rebuildLedgerBalances();
    await resetStuckSyncItems();

    // Marked ready before recovery runs so the unwind below can use the full
    // public API rather than a half-built repository.
    _isInitialized = true;

    // A till loses power mid-sale eventually. Recovery must never be the
    // reason the app will not open, so a failure here is logged and the
    // journal is left for the next launch to retry.
    try {
      await recoverInterruptedCheckouts();
    } catch (error, stack) {
      debugPrint('Checkout recovery failed: $error\n$stack');
      await recordDiagnostic(
        severity: DiagnosticSeverity.error,
        area: DiagnosticArea.startup,
        reference: 'startup',
        message:
            'Checkout recovery could not run. Interrupted sales, if any, are '
            'still pending reversal.',
        error: error,
        stack: stack,
      );
    }
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

  // --- DERIVED STATE ---------------------------------------------------------
  //
  // Every index below is derived from a box and has to be brought back in step
  // whenever that box changes. There are two families of write — local
  // (`saveX`) and remote (`applyRemote`) — and they used to maintain these by
  // hand, separately. They drifted: `applyRemote` wrote the record and left
  // `_mobileIndex` and `_salesByCustomer` untouched, so after a cloud pull the
  // shop saw a complete customer list and a phone lookup that found nobody,
  // until the next restart rebuilt the indexes from scratch.
  //
  // [_reindex] is now the one way to do it, and both families call it.

  /// Brings every index derived from one record back in step with what is
  /// stored. Safe to call when the record has just been deleted.
  void _reindex(String entityType, String entityId) {
    switch (entityType) {
      case 'Product':
        final product = _productsBox.get(entityId);
        product == null
            ? _unindexProduct(entityId)
            : _indexProductBarcodes(product);
      case 'Customer':
        final customer = _customersBox.get(entityId);
        if (customer == null) return;
        _indexCustomerMobile(customer);
        // The cache mirrors the record rather than being trusted over it, so
        // a remote write cannot leave a balance the ledger disagrees with.
        _customerBalances[entityId] = customer.currentBalance;
      case 'Sale':
        final sale = _salesBox.get(entityId);
        sale == null ? _unindexSale(entityId) : _indexSaleForCustomer(sale);
      case 'Supplier':
        final supplier = _suppliersBox.get(entityId);
        if (supplier != null) {
          _supplierBalances[entityId] = supplier.currentBalance;
        }
      case 'Purchase':
        // Cost prices feed inventory valuation. Cheaper to drop the whole
        // index than to work out what one purchase changed.
        _costPriceIndex = null;
    }
  }

  /// Checks every derived structure against the records it is derived from,
  /// and every stored balance against the entries that should explain it.
  ///
  /// Returns one line per discrepancy, empty when the store is coherent.
  ///
  /// This exists because the expensive bugs in this repository have all been
  /// the same shape: a box says one thing and something derived from it says
  /// another, with no symptom until a cashier types a phone number and gets
  /// nothing. An index that silently disagrees with its source is not
  /// detectable by reading either one alone, so it needs a check that holds
  /// both at once. Used by the test suite, and safe to call from the System
  /// Console when a shop reports something that "looks wrong".
  List<String> auditDerivedState() {
    final problems = <String>[];

    // --- barcode index ---
    final expectedBarcodes = <String, String>{};
    for (final product in _productsBox.values) {
      for (final variant in product.variants) {
        if (variant.barcode.isNotEmpty) {
          expectedBarcodes[variant.barcode] = product.id;
        }
      }
    }
    for (final entry in expectedBarcodes.entries) {
      final indexed = _barcodeIndex[entry.key];
      if (indexed == null) {
        problems.add('barcode ${entry.key} is not indexed');
      } else if (indexed.id != entry.value) {
        problems.add('barcode ${entry.key} points at the wrong product');
      }
    }
    for (final barcode in _barcodeIndex.keys) {
      if (!expectedBarcodes.containsKey(barcode)) {
        problems.add('barcode $barcode is indexed but belongs to no variant');
      }
    }

    // --- mobile index ---
    final expectedMobiles = <String, String>{};
    for (final customer in _customersBox.values) {
      if (customer.isDeleted) continue;
      final key = normaliseMobile(customer.mobile);
      if (key.isNotEmpty) expectedMobiles[key] = customer.id;
    }
    for (final entry in expectedMobiles.entries) {
      if (_mobileIndex[entry.key]?.id != entry.value) {
        problems.add('mobile ${entry.key} does not resolve to its customer');
      }
    }
    for (final key in _mobileIndex.keys) {
      if (!expectedMobiles.containsKey(key)) {
        problems.add('mobile $key is indexed but belongs to no customer');
      }
    }

    // --- sales by customer ---
    final expectedSales = <String, Set<String>>{};
    for (final sale in _salesBox.values) {
      if (sale.customerId.isEmpty || sale.isDeleted) continue;
      expectedSales.putIfAbsent(sale.customerId, () => {}).add(sale.id);
    }
    for (final entry in expectedSales.entries) {
      final indexed =
          _salesByCustomer[entry.key]?.map((s) => s.id).toSet() ?? {};
      if (!setEquals(indexed, entry.value)) {
        problems.add(
          'sales for customer ${entry.key} disagree: '
          'index has ${indexed.length}, box has ${entry.value.length}',
        );
      }
    }
    for (final customerId in _salesByCustomer.keys) {
      final indexed = _salesByCustomer[customerId] ?? const [];
      if (indexed.isNotEmpty && !expectedSales.containsKey(customerId)) {
        problems.add(
          'customer $customerId has indexed sales that no longer '
          'reference them',
        );
      }
    }

    // --- balances against their ledgers ---
    for (final customer in _customersBox.values) {
      final cached = _customerBalances[customer.id];
      if (cached != null &&
          Fmt.round2(cached) != Fmt.round2(customer.currentBalance)) {
        problems.add(
          'cached balance for customer ${customer.id} ($cached) disagrees '
          'with the record (${customer.currentBalance})',
        );
      }

      final entries = getLedgerForCustomer(customer.id);
      if (entries.isEmpty) continue;
      var running = customer.openingBalance;
      for (final entry in entries) {
        running = Fmt.round2(running + entry.debit - entry.credit);
      }
      if (Fmt.round2(running) != Fmt.round2(customer.currentBalance)) {
        problems.add(
          'customer ${customer.id} balance is ${customer.currentBalance} but '
          'their ledger sums to $running',
        );
      }
    }

    for (final supplier in _suppliersBox.values) {
      final cached = _supplierBalances[supplier.id];
      if (cached != null &&
          Fmt.round2(cached) != Fmt.round2(supplier.currentBalance)) {
        problems.add(
          'cached balance for supplier ${supplier.id} disagrees with the '
          'record',
        );
      }
    }

    // --- loyalty points against their transactions ---
    for (final customer in _customersBox.values) {
      var points = 0.0;
      for (final tx in getLoyaltyTransactions(customer.id)) {
        points += tx.points;
      }

      // Reported, not clamped away. `_recomputeRewardPoints` floors the
      // stored balance at zero, so clamping here too made a ledger that sums
      // negative agree with the balance derived from it — and this check
      // returned clean on precisely the corruption it exists to catch: more
      // points redeemed than the customer ever held.
      if (points < 0) {
        problems.add(
          'customer ${customer.id} has redeemed more points than they hold — '
          'their transactions sum to $points',
        );
      }

      final expected = points < 0 ? 0.0 : points;
      if (Fmt.round2(expected) != Fmt.round2(customer.totalRewardPoints)) {
        problems.add(
          'customer ${customer.id} holds ${customer.totalRewardPoints} points '
          'but their transactions sum to $expected',
        );
      }
    }

    return problems;
  }

  void _rebuildBarcodeIndex() {
    _barcodeIndex.clear();
    _indexedBarcodes.clear();
    for (final product in _productsBox.values) {
      _indexProductBarcodes(product);
    }
  }

  /// Points each of a product's barcodes at it, and releases any it used to
  /// own — a renamed or removed variant must not keep answering scans.
  void _indexProductBarcodes(Product product) {
    _releaseBarcodes(product.id);

    final owned = <String>[];
    for (final variant in product.variants) {
      if (variant.barcode.isEmpty) continue;
      _barcodeIndex[variant.barcode] = product;
      owned.add(variant.barcode);
    }
    _indexedBarcodes[product.id] = owned;
  }

  void _unindexProduct(String productId) {
    _releaseBarcodes(productId);
    _indexedBarcodes.remove(productId);
  }

  /// Drops only the barcodes this product still owns, so a barcode that has
  /// since moved to a different product is left alone.
  void _releaseBarcodes(String productId) {
    for (final barcode in _indexedBarcodes[productId] ?? const <String>[]) {
      if (_barcodeIndex[barcode]?.id == productId) {
        _barcodeIndex.remove(barcode);
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
    _indexedSaleCustomer.clear();
    for (final sale in _salesBox.values) {
      _indexSaleForCustomer(sale);
    }
  }

  /// Files a sale under its customer, moving it out of the previous one if the
  /// association changed.
  ///
  /// Walk-in and voided sales are deliberately left out: this index is what
  /// [getCustomerStats] counts, so a sale attached to nobody — or one that has
  /// been voided — must not read as somebody's visit.
  void _indexSaleForCustomer(Sale sale) {
    _unindexSale(sale.id);
    if (sale.customerId.isEmpty || sale.isDeleted) return;

    final sales = _salesByCustomer.putIfAbsent(sale.customerId, () => []);
    final at = sales.indexWhere((s) => s.id == sale.id);
    at >= 0 ? sales[at] = sale : sales.add(sale);
    _indexedSaleCustomer[sale.id] = sale.customerId;
  }

  void _unindexSale(String saleId) {
    final previous = _indexedSaleCustomer.remove(saleId);
    if (previous == null) return;
    _salesByCustomer[previous]?.removeWhere((s) => s.id == saleId);
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
        await _settingsBox.put('app_settings', EntityCodec.settings(json));
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

  // --- DIAGNOSTICS ---

  /// Records a local failure where a person can find it later.
  ///
  /// Deliberately swallows its own errors. Every caller is already inside a
  /// `catch` handling something that went wrong, and a diagnostic write that
  /// threw would replace the original failure with a less useful one — the
  /// classic case of the logger destroying the evidence it was called to
  /// preserve.
  Future<void> recordDiagnostic({
    required String severity,
    required String area,
    required String reference,
    required String message,
    Object? error,
    StackTrace? stack,
  }) async {
    try {
      final detail = error == null
          ? null
          : (stack == null ? '$error' : '$error\n$stack');
      final id = _diagnosticId();
      await _diagnosticLogBox.put(
        id,
        DiagnosticLog(
          id: id,
          occurredAt: DateTime.now(),
          severity: severity,
          area: area,
          reference: reference,
          message: message,
          detail: detail,
        ),
      );

      // Bounded like the sync log: a till left running for a year must not
      // fill its disk with failure records.
      if (_diagnosticLogBox.length > 500) {
        await _diagnosticLogBox.deleteAll(
          _diagnosticLogBox.keys.take(_diagnosticLogBox.length - 500).toList(),
        );
      }
      _notify(DataTopic.diagnostics);
    } catch (_) {
      // Nothing useful left to do: the original error is already propagating.
    }
  }

  /// Monotonic within a millisecond, so two failures in the same tick — an
  /// unwind reversing several steps — cannot overwrite each other.
  int _diagnosticSeq = 0;
  String _diagnosticId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_diagnosticSeq++}';

  /// Local failures, newest first.
  List<DiagnosticLog> getDiagnostics({int limit = 200, String? severity}) {
    final logs =
        _diagnosticLogBox.values
            .where((log) => severity == null || log.severity == severity)
            .toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return logs.length > limit ? logs.sublist(0, limit) : logs;
  }

  Future<void> clearDiagnostics() async {
    await _diagnosticLogBox.clear();
    _notify(DataTopic.diagnostics);
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
  /// Every payload leaves here carrying a non-null `updatedAt`, whatever the
  /// underlying model calls its own timestamp. That uniformity is what makes
  /// an incremental pull safe: Firestore's `where('updatedAt', >)` does not
  /// merely rank a document without the field lower, it omits it entirely, so
  /// a collection whose payloads lacked the field would come back empty and
  /// report success. Eleven of the fifteen collections were in that state.
  Map<String, dynamic>? getEntityJson(String entityType, String entityId) {
    final json = _encodeEntity(entityType, entityId);
    if (json == null) return null;

    // `??=` rather than a plain assignment: the four models that keep a real
    // `updatedAt` have already written theirs, and theirs is the more truthful
    // one. This only fills the gap — including when the model's own field is
    // null, which is just as invisible to the query as an absent one.
    json['updatedAt'] ??= _syncTimestampFor(
      entityType,
      entityId,
    ).toIso8601String();
    return json;
  }

  /// The best "when did this last change" a record can offer.
  ///
  /// Local time, deliberately: it has to be comparable against the values
  /// already written into `updatedAt` by [_encodeEntity], which come from
  /// local `DateTime`s. Mixing a UTC watermark against local record stamps
  /// would compare an offset string against a `Z`-suffixed one and quietly
  /// select the wrong rows.
  DateTime _syncTimestampFor(String entityType, String entityId) {
    switch (entityType) {
      case 'Product':
        return _productsBox.get(entityId)?.updatedDate ?? DateTime.now();
      case 'Customer':
        final c = _customersBox.get(entityId);
        return c?.updatedAt ?? c?.createdDate ?? DateTime.now();
      case 'Supplier':
        return _suppliersBox.get(entityId)?.updatedDate ?? DateTime.now();
      case 'Sale':
        final s = _salesBox.get(entityId);
        return s?.updatedAt ?? s?.date ?? DateTime.now();
      case 'Purchase':
        final p = _purchasesBox.get(entityId);
        return p?.updatedAt ?? p?.createdDate ?? DateTime.now();
      case 'LoyaltyTransaction':
        final l = _loyaltyTransactionsBox.get(entityId);
        return l?.updatedAt ?? l?.createdDate ?? DateTime.now();
      case 'Expense':
        return _expensesBox.get(entityId)?.createdDate ?? DateTime.now();
      case 'InventoryMovement':
        return _movementsBox.get(entityId)?.date ?? DateTime.now();
      case 'CustomerLedger':
        return _customerLedgersBox.get(entityId)?.date ?? DateTime.now();
      case 'SupplierLedger':
        return _supplierLedgersBox.get(entityId)?.date ?? DateTime.now();
      case 'SettingsModel':
        return _settingsBox.get('app_settings')?.updatedAt ?? DateTime.now();
      case 'CompanyModel':
        return _companyBox.get('profile')?.updatedAt ?? DateTime.now();
      case 'InvoiceSettingsModel':
        return _invoiceSettingsBox.get('invoice_settings')?.updatedAt ??
            DateTime.now();
      case 'LoyaltySettingsModel':
        return _loyaltySettingsBox.get('loyalty_settings')?.updatedAt ??
            DateTime.now();
      default:
        // ExpenseCategory keeps no timestamp of its own. Stamping the upload
        // moment is honest enough: it is pulled in full every time regardless
        // (see EntityCodec.alwaysFullPull).
        return DateTime.now();
    }
  }

  Map<String, dynamic>? _encodeEntity(String entityType, String entityId) {
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
        'isDeleted': s.isDeleted,
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
      // Config singletons. These returned null, which skipped the recency
      // comparison entirely and let whichever pull arrived last overwrite a
      // newer local edit — two tills changing the tax rate would resolve on
      // arrival order rather than on which change was actually more recent.
      case 'SettingsModel':
        return _settingsBox.get('app_settings')?.updatedAt;
      case 'CompanyModel':
        return _companyBox.get('profile')?.updatedAt;
      case 'InvoiceSettingsModel':
        return _invoiceSettingsBox.get('invoice_settings')?.updatedAt;
      case 'LoyaltySettingsModel':
        return _loyaltySettingsBox.get('loyalty_settings')?.updatedAt;
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
    Map<String, dynamic> raw,
  ) async {
    // The record is stored under `entityId`, and every index is built from
    // the record's own `id`. If those two disagree the store is immediately
    // incoherent: a lookup by key finds the record, a lookup through an index
    // does not, and `auditDerivedState` reports mismatches nobody can explain.
    //
    // The live pull cannot produce that — `fetchCollectionPages` overwrites
    // `id` with the Firestore document id — but a restore, a hand-edited
    // document or a future caller could. Pinning it here makes "the record's
    // id is its key" true by construction rather than by convention.
    //
    // Config singletons are unaffected: their decoders do not read `id` at
    // all, and their local key ('app_settings') differs from their document
    // id ('settings') by design.
    final json = {...raw, 'id': entityId};

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
        _reindex('Product', entityId);
        _notify(DataTopic.products);
        _notify(DataTopic.inventory);
      case 'Customer':
        await _customersBox.put(entityId, EntityCodec.customer(json));
        _reindex('Customer', entityId);
        _notify(DataTopic.customers);
      case 'Supplier':
        await _suppliersBox.put(entityId, EntityCodec.supplier(json));
        _reindex('Supplier', entityId);
        _notify(DataTopic.suppliers);
      case 'Sale':
        await _salesBox.put(entityId, EntityCodec.sale(json));
        _reindex('Sale', entityId);
        _notify(DataTopic.sales);
      case 'Purchase':
        await _purchasesBox.put(entityId, EntityCodec.purchase(json));
        _reindex('Purchase', entityId);
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
        // Every field the model carries is in the payload, so a straight
        // replace loses nothing. This used to merge in order to protect the
        // per-device biometric enrolment; that setting controlled nothing and
        // has been removed, so the special case went with it.
        await _settingsBox.put('app_settings', EntityCodec.settings(json));
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

  /// Rebuilds every derived structure after a bulk pull or a restore.
  ///
  /// [applyRemote] already reindexes each record it writes, so this is the
  /// safety net rather than the mechanism: it also catches records that
  /// arrived by some other route, and anything a future index forgets to
  /// maintain incrementally. The customer indexes in particular were missing
  /// here, which is what left phone lookup answering nothing after a pull
  /// until the app was next restarted.
  Future<void> reconcileAfterPull() async {
    _rebuildBarcodeIndex();
    _rebuildCustomerIndexes();
    _rebuildLedgerBalances();
    _costPriceIndex = null;
    _todayCache = null;
    for (final topic in DataTopic.all) {
      _notify(topic);
    }
  }

  // --- PRODUCTS ---
  Future<void> saveProduct(Product product) async {
    // Every local write is a change worth telling other devices about.
    // Stock-in/stock-out mutate the same Product instance in place and would
    // otherwise leave this timestamp frozen at creation time forever, which
    // is what let a stale local copy always outrank a genuine remote update.
    product.updatedDate = DateTime.now();

    await _productsBox.put(product.id, product);
    _reindex('Product', product.id);

    await enqueueSync(
      entityType: 'Product',
      entityId: product.id,
      action: 'UPDATE',
    );
  }

  Future<void> deleteProduct(String id) async {
    await _productsBox.delete(id);
    _reindex('Product', id);
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
        // Its own id, not the movement's. Sharing one across two record
        // spaces bought nothing and would collide the moment a movement
        // wanted to write more than one history line.
        id: Ids.generate(),
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
        // Its own id, not the movement's. Sharing one across two record
        // spaces bought nothing and would collide the moment a movement
        // wanted to write more than one history line.
        id: Ids.generate(),
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
    // Stamped on every local edit so two devices changing the same
    // setting resolve on which edit was newer, not on which pull landed
    // last. Config records carried no timestamp at all before this.
    settings.updatedAt = DateTime.now();
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
    settings.updatedAt = DateTime.now();
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

  // --- CHECKOUT JOURNAL ---
  //
  // A checkout writes to five boxes and Hive has no transaction spanning
  // them. [SaleService] already unwinds a *thrown* failure with an in-memory
  // list of compensations, but that list dies with the process: pull the plug
  // between deducting stock for item 2 and item 3 and the sale is committed,
  // the shelf is wrong, and nothing ever notices.
  //
  // So a row is written here before the first box is touched, and removed
  // once the sale is complete. Anything still present at startup is a
  // checkout that was interrupted, and it is unwound.
  //
  // The row deliberately carries almost nothing — the sale's identity, and
  // the one value that cannot be re-derived afterwards (the customer's
  // lifetime spend from before the sale). Recovery finds everything else by
  // asking which records point at the sale: movements by reference, ledger
  // rows by invoice number, loyalty rows by sale id. That is what makes it
  // correct wherever the crash landed — a step-by-step log would be wrong the
  // moment the crash fell between doing a step and recording that step.

  /// Declares a checkout as in flight. Must be called before the first write.
  Future<void> openCheckoutJournal({
    required String saleId,
    required String invoiceNumber,
    String customerId = '',
    double? previousLifetimeSpend,
    DateTime? previousUpdatedAt,
  }) async {
    if (!_isInitialized) return;
    await _checkoutJournalBox.put(
      saleId,
      jsonEncode({
        'saleId': saleId,
        'invoiceNumber': invoiceNumber,
        'customerId': customerId,
        'previousLifetimeSpend': previousLifetimeSpend,
        'previousUpdatedAt': previousUpdatedAt?.toIso8601String(),
        'startedAt': DateTime.now().toIso8601String(),
      }),
    );
    // Forced to disk rather than left to Hive's own scheduling: surviving a
    // power cut in the next millisecond is the entire point of this row.
    await _checkoutJournalBox.flush();
  }

  /// Marks a checkout as finished — committed, or already unwound in memory.
  Future<void> closeCheckoutJournal(String saleId) async {
    if (!_isInitialized) return;
    await _checkoutJournalBox.delete(saleId);
    await _checkoutJournalBox.flush();
  }

  /// True while a checkout is mid-flight. Exposed for tests.
  bool hasOpenCheckoutJournal(String saleId) =>
      _checkoutJournalBox.containsKey(saleId);

  /// Unwinds every checkout that was interrupted before it completed.
  ///
  /// Returns the invoice numbers reversed, newest first. Runs automatically
  /// during [init]; safe to call again at any time, and safe to interrupt —
  /// every step either finds work to do or finds it already done.
  Future<List<String>> recoverInterruptedCheckouts() async {
    final recovered = <String>[];

    for (final key in _checkoutJournalBox.keys.toList()) {
      final raw = _checkoutJournalBox.get(key);
      if (raw is! String) {
        await _checkoutJournalBox.delete(key);
        continue;
      }

      Map<String, dynamic> row;
      try {
        row = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        await _checkoutJournalBox.delete(key);
        continue;
      }

      final saleId = row['saleId'] as String? ?? key.toString();
      final invoiceNumber = row['invoiceNumber'] as String? ?? saleId;

      try {
        await _unwindInterruptedCheckout(saleId, invoiceNumber, row);
        recovered.add(invoiceNumber);
      } catch (error, stack) {
        // Left in the journal on purpose: a checkout that could not be
        // unwound now is retried on the next launch rather than forgotten.
        debugPrint('Could not recover $invoiceNumber: $error\n$stack');
        await recordDiagnostic(
          severity: DiagnosticSeverity.error,
          area: DiagnosticArea.startup,
          reference: invoiceNumber,
          message:
              'An interrupted sale could not be reversed at startup. It will '
              'be retried on the next launch.',
          error: error,
          stack: stack,
        );
        continue;
      }

      await _checkoutJournalBox.delete(key);
    }

    if (recovered.isNotEmpty) await _checkoutJournalBox.flush();
    return recovered;
  }

  Future<void> _unwindInterruptedCheckout(
    String saleId,
    String invoiceNumber,
    Map<String, dynamic> row,
  ) async {
    // 1. Put back any stock this sale took off the shelf.
    //
    // Driven by the movement records rather than the sale's line items: a
    // movement exists only for stock that was actually deducted, so this
    // reverses exactly what happened and nothing that did not. Each original
    // is removed as it is reversed, so running this twice is a no-op.
    final movements = getMovementsByReference(
      saleId,
    ).where((m) => m.type == 'Stock Out').toList();

    for (final movement in movements) {
      try {
        await performStockIn(
          productId: movement.productId,
          variantBarcode: movement.variantBarcode,
          quantity: movement.quantity,
          reason: 'Recovered interrupted sale ($invoiceNumber)',
          movementReferenceId: saleId,
          performedAt: 'System',
        );
      } on AppException catch (error) {
        // The product was deleted since. Nothing to put stock back into, and
        // refusing to continue would strand the rest of the reversal.
        debugPrint('Stock not restored for $invoiceNumber: $error');
        // Recorded because this is real stock the shop paid for that the app
        // has now decided it cannot account for. The reversal is correct to
        // continue; the shopkeeper still needs to know a count is off.
        await recordDiagnostic(
          severity: DiagnosticSeverity.error,
          area: DiagnosticArea.startup,
          reference: invoiceNumber,
          message:
              'Stock could not be returned for ${movement.quantity} × '
              '${movement.variantBarcode} — the product no longer exists. '
              'Check this count by hand.',
          error: error,
        );
      }
      await deleteMovement(movement.id);
    }

    final customerId = row['customerId'] as String? ?? '';
    if (customerId.isNotEmpty) {
      // 2. Remove what the sale charged them, and any points it moved.
      for (final entry in getLedgerForCustomer(
        customerId,
      ).where((e) => e.referenceId == invoiceNumber).toList()) {
        await deleteLedgerEntry(entry.id);
      }

      for (final tx in getLoyaltyTransactions(
        customerId,
      ).where((t) => t.saleId == saleId).toList()) {
        await deleteLoyaltyTransaction(tx.id);
      }

      // 3. Put lifetime spend back. This is the one figure that cannot be
      // recomputed from what is left behind, which is why it is journalled.
      final previousSpend = (row['previousLifetimeSpend'] as num?)?.toDouble();
      final customer = getCustomerById(customerId);
      if (customer != null && previousSpend != null) {
        customer.lifetimeSpend = previousSpend;
        final previousUpdatedAt = row['previousUpdatedAt'] as String?;
        customer.updatedAt = previousUpdatedAt == null
            ? null
            : DateTime.tryParse(previousUpdatedAt);
        await saveCustomer(customer);
      }
    }

    // 4. Finally the sale itself, so a half-finished one never reaches a
    // report or the cloud.
    await deleteSale(saleId);

    // The shop is told. A sale that silently reverses itself overnight is
    // worse than one that failed loudly at the till.
    await saveHistory(
      ActionHistory(
        id: Ids.generate(),
        barcode: invoiceNumber,
        productName: 'Interrupted sale reversed',
        action:
            'Sale $invoiceNumber was interrupted before it finished and has '
            'been reversed. Stock and balances were restored.',
        date: DateTime.now(),
      ),
    );
  }

  /// Persists a sale. Ledger, stock and loyalty effects belong to
  /// [SaleService] so the whole checkout can be rolled back as one unit.
  Future<void> saveSale(Sale sale) async {
    final isNew = _salesBox.get(sale.id) == null;
    await _salesBox.put(sale.id, sale);
    _reindex('Sale', sale.id);
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
    await _salesBox.delete(id);
    _reindex('Sale', id);
    await enqueueSync(entityType: 'Sale', entityId: id, action: 'DELETE');
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
    return _salesBox.values.where((s) => !s.isDeleted).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
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
      if (sale.isDeleted) continue;
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

  /// Sales between two calendar days, both ends included.
  ///
  /// Compared against a half-open window `[startOfDay, dayAfterEnd)` rather
  /// than the previous `isAfter(start - 1 day) && isBefore(end + 1 day)`,
  /// which quietly pulled in a whole extra day at each end. These figures get
  /// reconciled against the till, so being a day out is worse than being
  /// approximate.
  List<Sale> getSalesByDateRange(DateTime start, DateTime end) {
    final from = startOfDay(start);
    final until = startOfDay(end).add(const Duration(days: 1));
    return _salesBox.values.where((s) {
      if (s.isDeleted) return false;
      return !s.date.isBefore(from) && s.date.isBefore(until);
    }).toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Midnight at the start of [value]'s calendar day, in local time.
  ///
  /// Business dates are what the shop reads on a report, so they are local
  /// rather than UTC. Sync timestamps are a separate concern and stay as they
  /// are.
  static DateTime startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  // --- SUPPLIERS ---
  Future<void> saveSupplier(Supplier supplier) async {
    final isNew = _suppliersBox.get(supplier.id) == null;
    await _suppliersBox.put(supplier.id, supplier);
    _reindex('Supplier', supplier.id);
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
    _reindex('Purchase', purchase.id);
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

  /// Purchases between two calendar days, both ends included. Same half-open
  /// window as [getSalesByDateRange], for the same reason.
  List<Purchase> getPurchasesByDateRange(DateTime start, DateTime end) {
    final from = startOfDay(start);
    final until = startOfDay(end).add(const Duration(days: 1));
    return _purchasesBox.values.where((p) {
      return !p.purchaseDate.isBefore(from) && p.purchaseDate.isBefore(until);
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
    company.updatedAt = DateTime.now();
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
    _reindex('Customer', customer.id);
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

  /// Moves every ledger entry from one customer to another, folding in the
  /// source's opening balance as one traceable line first so it is not lost.
  ///
  /// Used by a customer merge. Hand-adding `currentBalance` was tried first
  /// and dropped: it left the source's ledger rows filed under an id nobody
  /// queries again, and the very next transaction on the target recomputed
  /// its running balance from a cache that never heard about the merge.
  /// Routing through the real ledger — and [recalculateCustomerLedger] to
  /// settle both balances afterward — is what keeps the total and the detail
  /// agreeing.
  Future<void> reassignCustomerLedger({
    required String fromCustomerId,
    required String toCustomerId,
  }) async {
    final from = getCustomerById(fromCustomerId);
    if (from == null) return;

    if (from.openingBalance != 0) {
      await addLedgerEntry(
        customerId: fromCustomerId,
        date: from.createdDate,
        transactionType: 'Merge',
        referenceId: 'MERGE-$toCustomerId',
        debit: from.openingBalance > 0 ? from.openingBalance : 0,
        credit: from.openingBalance < 0 ? -from.openingBalance : 0,
        notes: 'Opening balance carried into merge',
      );
      from.openingBalance = 0;
    }

    for (final entry in getLedgerForCustomer(fromCustomerId)) {
      entry.customerId = toCustomerId;
      await _customerLedgersBox.put(entry.id, entry);
      await enqueueSync(
        entityType: 'CustomerLedger',
        entityId: entry.id,
        action: 'UPDATE',
      );
    }

    await recalculateCustomerLedger(toCustomerId);
    await recalculateCustomerLedger(fromCustomerId); // now empty -> zero
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
    settings.updatedAt = DateTime.now();
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

  // `calculateEarnedPoints` and `calculateMaxRedemptionValue` used to sit
  // here as a second implementation of the reward rules. They had no callers
  // and had already drifted from `SalePricing` — no guard against a zero
  // redemption value, and no rounding — so anyone reaching for the obvious
  // repository method would have got money that disagreed with the till.
  // `SalePricing` is the single source for reward arithmetic.

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
