import 'package:hive_ce/hive.dart';

part 'invoice_settings_model.g.dart';

@HiveType(typeId: 50)
class InvoiceSettingsModel extends HiveObject {
  @HiveField(0)
  String footerText;

  @HiveField(1)
  bool showUpiQr;

  @HiveField(2)
  String upiId;

  @HiveField(3)
  String upiQrImagePath;

  @HiveField(4)
  bool showCompanyLogo;

  @HiveField(5)
  String termsAndConditions;

  @HiveField(6)
  String fontName;

  InvoiceSettingsModel({
    this.footerText = 'Thank you for your business!',
    this.showUpiQr = false,
    this.upiId = '',
    this.upiQrImagePath = '',
    this.showCompanyLogo = true,
    this.termsAndConditions =
        '1. Goods once sold will not be taken back.\n2. Subject to local jurisdiction.',
    this.fontName = 'Roboto',
  });
}
