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

  SettingsModel({
    required this.isDarkMode,
    required this.companyName,
    required this.currencySymbol,
    required this.pdfPageSize,
    this.taxMode = 'inclusive',
    this.taxRate = 0,
  });
}
