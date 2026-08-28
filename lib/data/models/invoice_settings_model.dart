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

  /// When this record last changed, so two devices editing the same
  /// settings resolve on recency rather than on which pull landed last.
  @HiveField(7)
  DateTime? updatedAt;

  /// Prints the `For <business>` / `Authorized Signatory` block at the foot of
  /// the invoice. On by default: Rule 46(q) of the CGST Rules requires a tax
  /// invoice to carry the supplier's signature unless it is issued
  /// electronically with a digital signature or an e-invoice IRN.
  @HiveField(8)
  bool showSignature;

  InvoiceSettingsModel({
    this.footerText = 'Thank you for your business!',
    this.showUpiQr = false,
    this.upiId = '',
    this.upiQrImagePath = '',
    this.showCompanyLogo = true,
    this.termsAndConditions =
        '1. Goods once sold will not be taken back.\n2. Subject to local jurisdiction.',
    this.fontName = 'Roboto',
    this.updatedAt,
    this.showSignature = true,
  });
}
