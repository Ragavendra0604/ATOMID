import 'package:hive_ce/hive.dart';

part 'settings_model.g.dart';

@HiveType(typeId: 3)
class SettingsModel extends HiveObject {
  @HiveField(0)
  bool isDarkMode;

  @HiveField(1)
  String companyName;

  @HiveField(2)
  String currencySymbol;

  @HiveField(3)
  String pdfPageSize;

  @HiveField(4)
  String taxMode; // 'inclusive' or 'exclusive'

  @HiveField(5)
  double taxRate;

  /// When this record last changed.
  @HiveField(10)
  DateTime? updatedAt;

  // Additive GST & billing configuration fields
  @HiveField(11)
  bool roundOffEnabled;

  /// Whether the product form refuses to save without an HSN. A data-entry
  /// policy only — the invoice prints whatever HSN a product carries
  /// regardless of this switch.
  @HiveField(12)
  bool hsnRequired;

  @HiveField(13)
  String walkInPosPolicy; // 'USE_SHOP_STATE', 'REQUIRE_STATE', 'ASK_AT_CHECKOUT'

  @HiveField(14)
  bool showGstBreakdown;

  @HiveField(15)
  bool showHsnSummary;

  @HiveField(16)
  String defaultUqc;

  @HiveField(17)
  String thermalReceiptSize; // '58mm' or '80mm'

  @HiveField(18)
  bool showTaxOnThermalReceipt;

  /// How tax is split out of a tax-inclusive price when the two readings
  /// disagree by a paisa. 'SHELF_PRICE' keeps the marked price exact and
  /// takes the tax as the remainder; 'TAX_RATE' computes every tax figure as
  /// rate x taxable, which can put the line total a paisa above the shelf
  /// price. A shop preference — neither reading has been confirmed as the
  /// legally required one.
  @HiveField(19)
  String inclusiveTaxRounding; // 'SHELF_PRICE' or 'TAX_RATE'

  /// Which invoice design prints by default. Holds an `InvoiceTemplate.id`
  /// rather than the enum, so an id written by a newer build survives a
  /// round trip through an older one. Presentation only: the template never
  /// takes part in pricing.
  @HiveField(20)
  String invoiceTemplate; // an InvoiceTemplate.id, e.g. 'THERMAL'

  SettingsModel({
    this.isDarkMode = true,
    this.companyName = 'ATOMID STORE',
    this.currencySymbol = '₹',
    this.pdfPageSize = 'A4',
    this.taxMode = 'inclusive',
    this.taxRate = 0,
    this.updatedAt,
    this.roundOffEnabled = true,
    this.hsnRequired = false,
    this.walkInPosPolicy = 'USE_SHOP_STATE',
    this.showGstBreakdown = true,
    this.showHsnSummary = true,
    this.defaultUqc = 'PCS',
    this.thermalReceiptSize = '80mm',
    this.showTaxOnThermalReceipt = true,
    this.inclusiveTaxRounding = 'SHELF_PRICE',
    this.invoiceTemplate = 'THERMAL',
  });

  /// Returns a copy with only the named fields changed.
  SettingsModel copyWith({
    bool? isDarkMode,
    String? companyName,
    String? currencySymbol,
    String? pdfPageSize,
    String? taxMode,
    double? taxRate,
    DateTime? updatedAt,
    bool? roundOffEnabled,
    bool? hsnRequired,
    String? walkInPosPolicy,
    bool? showGstBreakdown,
    bool? showHsnSummary,
    String? defaultUqc,
    String? thermalReceiptSize,
    bool? showTaxOnThermalReceipt,
    String? inclusiveTaxRounding,
    String? invoiceTemplate,
  }) {
    return SettingsModel(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      companyName: companyName ?? this.companyName,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      pdfPageSize: pdfPageSize ?? this.pdfPageSize,
      taxMode: taxMode ?? this.taxMode,
      taxRate: taxRate ?? this.taxRate,
      updatedAt: updatedAt ?? this.updatedAt,
      roundOffEnabled: roundOffEnabled ?? this.roundOffEnabled,
      hsnRequired: hsnRequired ?? this.hsnRequired,
      walkInPosPolicy: walkInPosPolicy ?? this.walkInPosPolicy,
      showGstBreakdown: showGstBreakdown ?? this.showGstBreakdown,
      showHsnSummary: showHsnSummary ?? this.showHsnSummary,
      defaultUqc: defaultUqc ?? this.defaultUqc,
      thermalReceiptSize: thermalReceiptSize ?? this.thermalReceiptSize,
      showTaxOnThermalReceipt:
          showTaxOnThermalReceipt ?? this.showTaxOnThermalReceipt,
      inclusiveTaxRounding: inclusiveTaxRounding ?? this.inclusiveTaxRounding,
      invoiceTemplate: invoiceTemplate ?? this.invoiceTemplate,
    );
  }
}
