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

  @HiveField(6)
  bool isBiometricEnabled;



  // Fields 7, 8 and 9 held the outbound email credential and the shop join
  // code. They went with OTP sign-in and staff sign-up. The numbers are left
  // unused rather than recycled: Hive resolves fields by index, so reusing one
  // would read an old value back as whatever replaced it.

  SettingsModel({
    this.isDarkMode = true,
    this.companyName = 'ATOMID STORE',
    this.currencySymbol = '₹',
    this.pdfPageSize = 'A4',
    this.taxMode = 'inclusive',
    this.taxRate = 0,
    this.isBiometricEnabled = false,
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
    bool? isBiometricEnabled,
  }) {
    return SettingsModel(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      companyName: companyName ?? this.companyName,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      pdfPageSize: pdfPageSize ?? this.pdfPageSize,
      taxMode: taxMode ?? this.taxMode,
      taxRate: taxRate ?? this.taxRate,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
    );
  }
}
