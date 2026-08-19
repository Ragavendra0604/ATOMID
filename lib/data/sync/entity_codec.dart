import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/customer_ledger_model.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/expense_model.dart';
import 'package:atomid/data/models/inventory_movement_model.dart';
import 'package:atomid/data/models/invoice_settings_model.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/models/loyalty_transaction_model.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/data/models/supplier_ledger_model.dart';
import 'package:atomid/data/models/supplier_model.dart';

/// Rebuilds local models from Firestore documents.
///
/// The encode side lives in `StorageRepository.getEntityJson`; this is its
/// mirror. Anything added to a model must appear in both, and
/// `test/unit/sync_payload_test.dart` asserts the round trip so a field cannot
/// go missing silently the way `Expense.title` and `Purchase.status` did.
class EntityCodec {
  const EntityCodec._();

  /// Firestore path segment for an entity type.
  static String collectionFor(String entityType) {
    switch (entityType) {
      case 'Customer':
        return 'customers';
      case 'Sale':
        return 'sales';
      case 'Product':
        return 'products';
      case 'Supplier':
        return 'suppliers';
      case 'Purchase':
        return 'purchases';
      case 'Expense':
        return 'expenses';
      case 'ExpenseCategory':
        return 'expenseCategories';
      case 'InventoryMovement':
        return 'inventoryMovements';
      case 'LoyaltyTransaction':
        return 'loyaltyTransactions';
      case 'CustomerLedger':
        return 'customerLedgers';
      case 'SupplierLedger':
        return 'supplierLedgers';
      case 'SettingsModel':
      case 'CompanyModel':
      case 'InvoiceSettingsModel':
      case 'LoyaltySettingsModel':
        return 'config';
      default:
        return '${entityType.toLowerCase()}s';
    }
  }

  /// Types that are always fetched in full, never incrementally.
  ///
  /// These are the one-document-per-store config records. They now carry a
  /// real `updatedAt`, so recency *is* comparable — but documents written by
  /// an older build do not, and Firestore omits those from a range query
  /// rather than ranking them. Five documents in total, so fetching them
  /// whole costs nothing worth optimising and cannot strand an old one.
  static const alwaysFullPull = {
    'SettingsModel',
    'CompanyModel',
    'InvoiceSettingsModel',
    'LoyaltySettingsModel',
    'ExpenseCategory',
  };

  /// Entity types pulled down on a refresh, in dependency order — products and
  /// customers must exist before the sales that reference them.
  static const pullOrder = [
    'SettingsModel',
    'CompanyModel',
    'InvoiceSettingsModel',
    'LoyaltySettingsModel',
    'ExpenseCategory',
    'Product',
    'Customer',
    'Supplier',
    'Purchase',
    'Sale',
    'Expense',
    'InventoryMovement',
    'LoyaltyTransaction',
    'CustomerLedger',
    'SupplierLedger',
  ];

  // --- Helpers --------------------------------------------------------------

  static String _str(dynamic value, [String fallback = '']) =>
      value is String ? value : fallback;

  /// Largest and smallest values a 64-bit int can hold, as doubles. A double
  /// outside this range has no faithful int representation.
  static const double _maxInt = 9223372036854775807.0;
  static const double _minInt = -9223372036854775808.0;

  /// A number, rejecting the ones that are technically `num` but not usable.
  ///
  /// `NaN` and `Infinity` are both `num`, and Firestore will store them
  /// happily. Letting one through is worse than a crash: `Fmt.round2` and
  /// every `fold` in the app propagate `NaN`, so a single poisoned price turns
  /// a subtotal, a grand total, a day's takings and an exported report all
  /// into `NaN` with nothing pointing back at the cause.
  static double _dbl(dynamic value, [double fallback = 0]) =>
      value is num && value.isFinite ? value.toDouble() : fallback;

  /// An integer, rejecting non-finite and out-of-range values.
  ///
  /// `toInt()` throws outright on `NaN`/`Infinity` — which aborted the pull
  /// for a whole collection — and cannot faithfully represent a double beyond
  /// the 64-bit range. Both resolve to the fallback rather than to a crash or
  /// an arbitrary number. Found by fuzzing.
  static int _int(dynamic value, [int fallback = 0]) {
    if (value is! num || !value.isFinite) return fallback;
    if (value > _maxInt || value < _minInt) return fallback;
    return value.toInt();
  }

  static bool _bool(dynamic value, [bool fallback = false]) =>
      value is bool ? value : fallback;

  static DateTime _date(dynamic value, [DateTime? fallback]) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _dateOrNull(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;

  static List<String> _strList(dynamic value) =>
      value is List ? value.whereType<String>().toList() : const [];

  /// A list field, or empty when the payload holds something else.
  ///
  /// Every scalar above type-checks and falls back. The list fields did not —
  /// they used a raw `as List?`, which throws a `TypeError` on a Map, String,
  /// bool or number. That is not a one-record failure: `SyncService.pullAll`
  /// catches per *collection*, so a single malformed document aborted the pull
  /// for every product (or sale, or purchase) in the store, and because the
  /// watermark only advances on a fully successful pull, that collection then
  /// stayed behind indefinitely. Found by fuzzing the decoder.
  static List<dynamic> _list(dynamic value) =>
      value is List ? value : const <dynamic>[];

  /// An optional string, or null when the payload holds a non-string.
  ///
  /// `as String?` throws on an int; this is the same defensive shape as
  /// [_str] but preserving the "absent" case the models expect.
  static String? _strOrNull(dynamic value) => value is String ? value : null;

  /// The timestamp used to decide which copy of a record wins.
  ///
  /// The most recent of everything the payload offers, rather than the first
  /// field that happens to be present. Payloads now carry a uniform
  /// `updatedAt` alongside whatever the model calls its own timestamp
  /// (`updatedDate` on Product and Supplier), and preferring one blindly
  /// means any disagreement between them can reject a genuinely newer record
  /// — silently, and in the direction that loses an edit. Taking the maximum
  /// cannot fail that way: a newer value wins whichever field it arrives in.
  static DateTime? remoteUpdatedAt(Map<String, dynamic> json) {
    final candidates = <DateTime>[
      for (final key in const ['updatedAt', 'updatedDate', 'createdDate'])
        ?_dateOrNull(json[key]),
    ];
    if (candidates.isEmpty) return null;
    return candidates.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  // --- Decoders -------------------------------------------------------------

  static Product product(Map<String, dynamic> json) => Product(
    id: _str(json['id']),
    productName: _str(json['productName']),
    productCode: _str(json['productCode']),
    category: _str(json['category'], 'General'),
    brand: _str(json['brand']),
    color: _str(json['color']),
    createdDate: _date(json['createdDate'], DateTime.now()),
    updatedDate: _date(json['updatedDate'], DateTime.now()),
    version: _int(json['version'], 1),
    deviceId: _str(json['deviceId']),
    createdBy: _str(json['createdBy']),
    isDeleted: _bool(json['isDeleted']),
    isSynced: true,
    lastSyncedAt: DateTime.now(),
    variants: _list(json['variants'])
        .whereType<Map>()
        .map(
          (v) => ProductVariant(
            size: _str(v['size']),
            price: _dbl(v['price']),
            quantity: _int(v['quantity']),
            barcode: _str(v['barcode']),
            sku: _str(v['sku']),
            stockIn: _int(v['stockIn']),
            stockOut: _int(v['stockOut']),
            reorderLevel: _int(v['reorderLevel'], 5),
            lastStockUpdated: _dateOrNull(v['lastStockUpdated']),
          ),
        )
        .toList(),
  );

  static Customer customer(Map<String, dynamic> json) => Customer(
    id: _str(json['id']),
    code: _str(json['code']),
    name: _str(json['name']),
    mobile: _str(json['mobile']),
    gstNumber: _str(json['gstNumber']),
    address: _str(json['address']),
    creditLimit: _dbl(json['creditLimit']),
    creditDays: _int(json['creditDays']),
    openingBalance: _dbl(json['openingBalance']),
    currentBalance: _dbl(json['currentBalance']),
    status: _str(json['status'], 'Active'),
    createdDate: _date(json['createdDate'], DateTime.now()),
    totalRewardPoints: _dbl(json['totalRewardPoints']),
    lifetimeSpend: _dbl(json['lifetimeSpend']),
    isSynced: true,
    lastSyncedAt: DateTime.now(),
    updatedAt: _dateOrNull(json['updatedAt']),
    version: _int(json['version'], 1),
    deviceId: _str(json['deviceId']),
    createdBy: _str(json['createdBy']),
    isDeleted: _bool(json['isDeleted']),
    email: _str(json['email']),
    customerGroup: _str(json['customerGroup'], 'General'),
    notes: _str(json['notes']),
    tags: _strList(json['tags']),
    attachments: _strList(json['attachments']),
  );

  static Supplier supplier(Map<String, dynamic> json) => Supplier(
    id: _str(json['id']),
    supplierCode: _str(json['code']),
    supplierName: _str(json['name']),
    phone: _str(json['phone']),
    email: _str(json['email']),
    address: _str(json['address']),
    gstNumber: _str(json['gstNumber']),
    contactPerson: _str(json['contactPerson']),
    notes: _str(json['notes']),
    isActive: _bool(json['isActive'], true),
    isSynced: true,
    createdDate: _date(json['createdDate'], DateTime.now()),
    updatedDate: _date(json['updatedDate'], DateTime.now()),
    paymentTerms: _str(json['paymentTerms']),
    currentBalance: _dbl(json['currentBalance']),
    rating: _dbl(json['rating']),
    supplierCategory: _str(json['supplierCategory']),
    attachments: _strList(json['attachments']),
    isDeleted: _bool(json['isDeleted']),
  );

  static Sale sale(Map<String, dynamic> json) => Sale(
    id: _str(json['id']),
    invoiceNumber: _str(json['invoiceNumber']),
    date: _date(json['date'], DateTime.now()),
    customerId: _str(json['customerId']),
    customerName: _str(json['customerName'], 'Walk-In Customer'),
    subtotal: _dbl(json['subtotal']),
    discountPercent: _dbl(json['discountPercent']),
    discountAmount: _dbl(json['discountAmount']),
    rewardDiscountAmount: _dbl(json['rewardDiscountAmount']),
    rewardPointsEarned: _dbl(json['rewardPointsEarned']),
    taxAmount: _dbl(json['taxAmount']),
    grandTotal: _dbl(json['grandTotal']),
    paymentMethod: _str(json['paymentMethod'], 'Cash'),
    notes: _str(json['notes']),
    isSynced: true,
    lastSyncedAt: DateTime.now(),
    updatedAt: _dateOrNull(json['updatedAt']),
    version: _int(json['version'], 1),
    deviceId: _str(json['deviceId']),
    createdBy: _str(json['createdBy']),
    isDeleted: _bool(json['isDeleted']),
    items: _list(json['items'])
        .whereType<Map>()
        .map(
          (i) => SaleItem(
            productId: _str(i['productId']),
            productName: _str(i['productName']),
            productCode: _str(i['productCode']),
            variantBarcode: _str(i['variantBarcode']),
            variantSize: _str(i['variantSize']),
            price: _dbl(i['price']),
            quantity: _int(i['quantity']),
            total: _dbl(i['total']),
          ),
        )
        .toList(),
  );

  static Purchase purchase(Map<String, dynamic> json) => Purchase(
    id: _str(json['id']),
    purchaseNumber: _str(json['purchaseNumber']),
    supplierId: _str(json['supplierId']),
    supplierName: _str(json['supplierName']),
    purchaseDate: _date(json['purchaseDate'], DateTime.now()),
    subtotal: _dbl(json['subtotal']),
    discount: _dbl(json['discount']),
    tax: _dbl(json['tax']),
    grandTotal: _dbl(json['grandTotal']),
    notes: _str(json['notes']),
    createdDate: _date(json['createdDate'], DateTime.now()),
    isSynced: true,
    lastSyncedAt: DateTime.now(),
    updatedAt: _dateOrNull(json['updatedAt']),
    expectedDeliveryDate: _dateOrNull(json['expectedDeliveryDate']),
    status: _str(json['status'], 'Received'),
    paymentStatus: _str(json['paymentStatus'], 'Unpaid'),
    version: _int(json['version'], 1),
    deviceId: _str(json['deviceId']),
    createdBy: _str(json['createdBy']),
    isDeleted: _bool(json['isDeleted']),
    items: _list(json['items'])
        .whereType<Map>()
        .map(
          (i) => PurchaseItem(
            productId: _str(i['productId']),
            productName: _str(i['productName']),
            variantBarcode: _str(i['variantBarcode']),
            variantSize: _str(i['variantSize']),
            sku: _str(i['sku']),
            quantity: _int(i['quantity']),
            costPrice: _dbl(i['costPrice']),
            sellingPrice: _dbl(i['sellingPrice']),
            lineTotal: _dbl(i['lineTotal']),
            receivedQuantity: _int(i['receivedQuantity']),
          ),
        )
        .toList(),
  );

  static Expense expense(Map<String, dynamic> json) => Expense(
    id: _str(json['id']),
    title: _str(json['title']),
    categoryId: _str(json['categoryId']),
    categoryName: _str(json['categoryName']),
    amount: _dbl(json['amount']),
    date: _date(json['date'], DateTime.now()),
    notes: _str(json['notes']),
    receiptImagePath: _strOrNull(json['receiptImagePath']),
    createdDate: _date(json['createdDate'], DateTime.now()),
    createdBy: _str(json['createdBy']),
    isSynced: true,
  );

  /// The itemised credit history behind a customer's balance.
  ///
  /// The balance itself rides on the customer record, so it always survived a
  /// device swap — but the entries that explain it did not, because ledgers
  /// were never in the syncable set. "You owe 4,200" with no statement behind
  /// it is not a usable answer for the person being asked to pay it.
  static CustomerLedger customerLedger(Map<String, dynamic> json) =>
      CustomerLedger(
        id: _str(json['id']),
        customerId: _str(json['customerId']),
        date: _date(json['date'], DateTime.now()),
        transactionType: _str(json['transactionType']),
        referenceId: _str(json['referenceId']),
        debit: _dbl(json['debit']),
        credit: _dbl(json['credit']),
        balance: _dbl(json['balance']),
        notes: _str(json['notes']),
      );

  static SupplierLedger supplierLedger(Map<String, dynamic> json) =>
      SupplierLedger(
        id: _str(json['id']),
        supplierId: _str(json['supplierId']),
        date: _date(json['date'], DateTime.now()),
        transactionType: _str(json['transactionType']),
        referenceId: _str(json['referenceId']),
        debit: _dbl(json['debit']),
        credit: _dbl(json['credit']),
        balance: _dbl(json['balance']),
        notes: _str(json['notes']),
      );

  static ExpenseCategory expenseCategory(Map<String, dynamic> json) =>
      ExpenseCategory(
        id: _str(json['id']),
        name: _str(json['name']),
        iconName: _str(json['iconName'], 'receipt'),
      );

  static InventoryMovement movement(Map<String, dynamic> json) =>
      InventoryMovement(
        id: _str(json['id']),
        productId: _str(json['productId']),
        productName: _str(json['productName']),
        variantBarcode: _str(json['variantBarcode']),
        variantSize: _str(json['variantSize']),
        quantity: _int(json['quantity']),
        type: _str(json['type']),
        reason: _str(json['reason']),
        date: _date(json['date'], DateTime.now()),
        movementReferenceId: _str(json['movementReferenceId']),
        performedAt: _str(json['performedAt']),
      );

  static LoyaltyTransaction loyaltyTransaction(Map<String, dynamic> json) =>
      LoyaltyTransaction(
        id: _str(json['id']),
        customerId: _str(json['customerId']),
        saleId: _strOrNull(json['saleId']),
        transactionType: _str(json['transactionType']),
        points: _dbl(json['points']),
        monetaryValue: _dbl(json['monetaryValue']),
        reference: _str(json['reference']),
        remarks: _str(json['remarks']),
        createdDate: _date(json['createdDate'], DateTime.now()),
        createdBy: _str(json['createdBy']),
        isSynced: true,
        updatedAt: _dateOrNull(json['updatedAt']),
      );

  static SettingsModel settings(Map<String, dynamic> json) => SettingsModel(
    isDarkMode: _bool(json['isDarkMode'], true),
    companyName: _str(json['companyName'], 'ATOMID STORE'),
    currencySymbol: _str(json['currencySymbol'], '₹'),
    pdfPageSize: _str(json['pdfPageSize'], 'A4'),
    taxMode: _str(json['taxMode'], 'inclusive'),
    taxRate: _dbl(json['taxRate']),
    updatedAt: _dateOrNull(json['updatedAt']),
  );

  static CompanyModel company(Map<String, dynamic> json) => CompanyModel(
    name: _str(json['name']),
    logoPath: _str(json['logoPath']),
    ownerName: _str(json['ownerName']),
    gstNumber: _str(json['gstNumber']),
    panNumber: _str(json['panNumber']),
    phone1: _str(json['phone1']),
    phone2: _str(json['phone2']),
    email: _str(json['email']),
    website: _str(json['website']),
    address: _str(json['address']),
    city: _str(json['city']),
    state: _str(json['state']),
    country: _str(json['country']),
    pincode: _str(json['pincode']),
    invoicePrefix: _str(json['invoicePrefix'], 'INV'),
    barcodePrefix: _str(json['barcodePrefix'], 'BR'),
    currency: _str(json['currency'], '₹'),
    financialYear: _str(json['financialYear']),
    updatedAt: _dateOrNull(json['updatedAt']),
  );

  static InvoiceSettingsModel invoiceSettings(Map<String, dynamic> json) =>
      InvoiceSettingsModel(
        footerText: _str(json['footerText'], 'Thank you for your business!'),
        showUpiQr: _bool(json['showUpiQr']),
        upiId: _str(json['upiId']),
        upiQrImagePath: _str(json['upiQrImagePath']),
        showCompanyLogo: _bool(json['showCompanyLogo'], true),
        termsAndConditions: _str(json['termsAndConditions']),
        fontName: _str(json['fontName'], 'Roboto'),
        updatedAt: _dateOrNull(json['updatedAt']),
      );

  static LoyaltySettingsModel loyaltySettings(Map<String, dynamic> json) =>
      LoyaltySettingsModel(
        isLoyaltyEnabled: _bool(json['isLoyaltyEnabled']),
        spendAmountForPoint: _dbl(json['spendAmountForPoint'], 100),
        pointsEarnedPerSpend: _dbl(json['pointsEarnedPerSpend'], 1),
        pointRedemptionValue: _dbl(json['pointRedemptionValue'], 1),
        maxRedemptionPercentage: _dbl(json['maxRedemptionPercentage'], 50),
        minBillAmountForRedemption: _dbl(json['minBillAmountForRedemption']),
        updatedAt: _dateOrNull(json['updatedAt']),
      );
}
