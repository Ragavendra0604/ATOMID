import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/customer_ledger_model.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/expense_model.dart';
import 'package:atomid/data/models/gst_rate_config_model.dart';
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

/// Rebuilds local models from Firestore documents and cloud backups.
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
      case 'GstRateConfig':
        return 'gstRateConfigs';
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
  static const alwaysFullPull = {
    'SettingsModel',
    'CompanyModel',
    'InvoiceSettingsModel',
    'LoyaltySettingsModel',
    'ExpenseCategory',
    'GstRateConfig',
  };

  /// Entity types pulled down on a refresh, in dependency order.
  static const pullOrder = [
    'SettingsModel',
    'CompanyModel',
    'InvoiceSettingsModel',
    'LoyaltySettingsModel',
    'ExpenseCategory',
    'GstRateConfig',
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

  static const double _maxInt = 9223372036854775807.0;
  static const double _minInt = -9223372036854775808.0;

  static double _dbl(dynamic value, [double fallback = 0]) =>
      value is num && value.isFinite ? value.toDouble() : fallback;

  static double? _dblOrNull(dynamic value) =>
      value is num && value.isFinite ? value.toDouble() : null;

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

  static List<dynamic> _list(dynamic value) =>
      value is List ? value : const <dynamic>[];

  static String? _strOrNull(dynamic value) => value is String ? value : null;

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
    hsn: _str(json['hsn']),
    uqc: _str(json['uqc'], 'PCS'),
    gstTreatment: _str(json['gstTreatment'], 'TAXABLE'),
    gstRate: _dblOrNull(json['gstRate']),
    cessRate: _dbl(json['cessRate']),
    gstRateConfigId: _strOrNull(json['gstRateConfigId']),
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
            costPrice: _dbl(v['costPrice']),
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
    state: _str(json['state']),
    stateCode: _str(json['stateCode']),
    city: _str(json['city']),
    pincode: _str(json['pincode']),
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
    state: _str(json['state']),
    stateCode: _str(json['stateCode']),
    city: _str(json['city']),
    pincode: _str(json['pincode']),
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
    sellerGstin: _str(json['sellerGstin']),
    sellerState: _str(json['sellerState']),
    sellerStateCode: _str(json['sellerStateCode']),
    sellerLegalName: _str(json['sellerLegalName']),
    sellerAddress: _str(json['sellerAddress']),
    customerGstin: _str(json['customerGstin']),
    customerState: _str(json['customerState']),
    customerStateCode: _str(json['customerStateCode']),
    customerAddress: _str(json['customerAddress']),
    customerPhone: _str(json['customerPhone']),
    placeOfSupply: _str(json['placeOfSupply']),
    placeOfSupplyBasis: _str(json['placeOfSupplyBasis']),
    pricingMode: _str(json['pricingMode'], 'inclusive'),
    taxableAmount: _dbl(json['taxableAmount']),
    cgstAmount: _dbl(json['cgstAmount']),
    sgstAmount: _dbl(json['sgstAmount']),
    utgstAmount: _dbl(json['utgstAmount']),
    igstAmount: _dbl(json['igstAmount']),
    cessAmount: _dbl(json['cessAmount']),
    preRoundTotal: _dbl(json['preRoundTotal']),
    roundOff: _dbl(json['roundOff']),
    documentType: _str(json['documentType'], 'Tax Invoice'),
    isInterState: _bool(json['isInterState']),
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
            hsn: _str(i['hsn']),
            uqc: _str(i['uqc'], 'PCS'),
            gstRate: _dblOrNull(i['gstRate']),
            gstTreatment: _str(i['gstTreatment'], 'TAXABLE'),
            cessRate: _dbl(i['cessRate']),
            taxableValue: _dbl(i['taxableValue']),
            discountAmount: _dbl(i['discountAmount']),
            cgstAmount: _dbl(i['cgstAmount']),
            sgstAmount: _dbl(i['sgstAmount']),
            utgstAmount: _dbl(i['utgstAmount']),
            igstAmount: _dbl(i['igstAmount']),
            cessAmount: _dbl(i['cessAmount']),
            gstRateConfigId: _strOrNull(i['gstRateConfigId']),
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
    supplierInvoiceNumber: _str(json['supplierInvoiceNumber']),
    supplierInvoiceDate: _dateOrNull(json['supplierInvoiceDate']),
    supplierGstin: _str(json['supplierGstin']),
    supplierState: _str(json['supplierState']),
    supplierStateCode: _str(json['supplierStateCode']),
    supplierAddress: _str(json['supplierAddress']),
    itcEligibility: _str(json['itcEligibility'], 'REQUIRES_DETERMINATION'),
    taxableAmount: _dbl(json['taxableAmount']),
    cgstAmount: _dbl(json['cgstAmount']),
    sgstAmount: _dbl(json['sgstAmount']),
    utgstAmount: _dbl(json['utgstAmount']),
    igstAmount: _dbl(json['igstAmount']),
    cessAmount: _dbl(json['cessAmount']),
    roundOff: _dbl(json['roundOff']),
    preRoundTotal: _dbl(json['preRoundTotal']),
    pricingMode: _str(json['pricingMode'], 'exclusive'),
    recipientName: _str(json['recipientName']),
    recipientGstin: _str(json['recipientGstin']),
    recipientState: _str(json['recipientState']),
    recipientStateCode: _str(json['recipientStateCode']),
    isInterState: _bool(json['isInterState']),
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
            hsn: _str(i['hsn']),
            uqc: _str(i['uqc'], 'PCS'),
            gstRate: _dblOrNull(i['gstRate']),
            gstTreatment: _str(i['gstTreatment'], 'TAXABLE'),
            cessRate: _dbl(i['cessRate']),
            taxableValue: _dbl(i['taxableValue']),
            discountAmount: _dbl(i['discountAmount']),
            cgstAmount: _dbl(i['cgstAmount']),
            sgstAmount: _dbl(i['sgstAmount']),
            utgstAmount: _dbl(i['utgstAmount']),
            igstAmount: _dbl(i['igstAmount']),
            cessAmount: _dbl(i['cessAmount']),
            gstRateConfigId: _strOrNull(i['gstRateConfigId']),
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

  static GstRateConfig gstRateConfig(Map<String, dynamic> json) =>
      GstRateConfig(
        id: _str(json['id']),
        rateName: _str(json['rateName']),
        rate: _dbl(json['rate']),
        cessRate: _dbl(json['cessRate']),
        effectiveFrom: _date(json['effectiveFrom'], DateTime(2017, 7, 1)),
        effectiveTo: _dateOrNull(json['effectiveTo']),
        description: _str(json['description']),
        isDeleted: _bool(json['isDeleted']),
        updatedAt: _dateOrNull(json['updatedAt']),
        isSynced: true,
      );

  static SettingsModel settings(Map<String, dynamic> json) => SettingsModel(
    isDarkMode: _bool(json['isDarkMode'], true),
    companyName: _str(json['companyName'], 'ATOMID STORE'),
    currencySymbol: _str(json['currencySymbol'], '₹'),
    pdfPageSize: _str(json['pdfPageSize'], 'A4'),
    taxMode: _str(json['taxMode'], 'inclusive'),
    taxRate: _dbl(json['taxRate']),
    updatedAt: _dateOrNull(json['updatedAt']),
    roundOffEnabled: _bool(json['roundOffEnabled'], true),
    hsnRequired: _bool(json['hsnRequired'], false),
    walkInPosPolicy: _str(json['walkInPosPolicy'], 'USE_SHOP_STATE'),
    showGstBreakdown: _bool(json['showGstBreakdown'], true),
    showHsnSummary: _bool(json['showHsnSummary'], true),
    defaultUqc: _str(json['defaultUqc'], 'PCS'),
    thermalReceiptSize: _str(json['thermalReceiptSize'], '80mm'),
    showTaxOnThermalReceipt: _bool(json['showTaxOnThermalReceipt'], true),
    inclusiveTaxRounding: _str(json['inclusiveTaxRounding'], 'SHELF_PRICE'),
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
    stateCode: _str(json['stateCode']),
    gstRegistrationStatus: _str(json['gstRegistrationStatus'], 'Registered'),
    tradeName: _str(json['tradeName']),
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
        showSignature: _bool(json['showSignature'], true),
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
