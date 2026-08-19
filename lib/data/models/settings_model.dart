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

  // Field 6 held `isBiometricEnabled`. The Settings screen offered it as
  // "Enable Biometric Login", and it was stored, synced and preserved across
  // restores — but nothing in the app ever read it, and there is no lock of
  // any kind here. A control that reports protection it does not provide is
  // worse than no control, so the setting was removed rather than left
  // standing as a promise the code does not keep.
  //
  // Fields 7, 8 and 9 held the outbound email credential and the shop join
  // code. They went with OTP sign-in and staff sign-up. The numbers are left
  // unused rather than recycled: Hive resolves fields by index, so reusing one
  // would read an old value back as whatever replaced it.

  /// When this record last changed, so two devices editing the same
  /// settings resolve on recency rather than on which pull landed last.
  @HiveField(10)
  DateTime? updatedAt;

  SettingsModel({
    this.isDarkMode = true,
    this.companyName = 'ATOMID STORE',
    this.currencySymbol = '₹',
    this.pdfPageSize = 'A4',
    this.taxMode = 'inclusive',
    this.taxRate = 0,
    this.updatedAt,
  });

  /// Returns a copy with only the named fields changed.
  ///
  /// Screens must build their next settings record through this rather than
  /// calling the constructor: rebuilding from a subset of fields silently
  /// reset tax on every save and on every dark-mode toggle.
  SettingsModel copyWith({
    bool? isDarkMode,
    String? companyName,
    String? currencySymbol,
    String? pdfPageSize,
    String? taxMode,
    double? taxRate,
    DateTime? updatedAt,
  }) {
    return SettingsModel(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      companyName: companyName ?? this.companyName,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      pdfPageSize: pdfPageSize ?? this.pdfPageSize,
      taxMode: taxMode ?? this.taxMode,
      taxRate: taxRate ?? this.taxRate,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
