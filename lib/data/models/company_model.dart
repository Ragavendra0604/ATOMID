import 'package:hive_ce/hive.dart';

part 'company_model.g.dart';

@HiveType(typeId: 10)
class CompanyModel extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String logoPath;

  @HiveField(2)
  String ownerName;

  @HiveField(3)
  String gstNumber;

  @HiveField(4)
  String panNumber;

  @HiveField(5)
  String phone1;

  @HiveField(6)
  String phone2;

  @HiveField(7)
  String email;

  @HiveField(8)
  String website;

  @HiveField(9)
  String address;

  @HiveField(10)
  String city;

  @HiveField(11)
  String state;

  @HiveField(12)
  String country;

  @HiveField(13)
  String pincode;

  @HiveField(14)
  String invoicePrefix;

  @HiveField(15)
  String barcodePrefix;

  @HiveField(16)
  String currency;

  @HiveField(17)
  String financialYear;

  /// When this record last changed, so two devices editing the same
  /// settings resolve on recency rather than on which pull landed last.
  @HiveField(18)
  DateTime? updatedAt;

  CompanyModel({
    this.name = '',
    this.logoPath = '',
    this.ownerName = '',
    this.gstNumber = '',
    this.panNumber = '',
    this.phone1 = '',
    this.phone2 = '',
    this.email = '',
    this.website = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.country = '',
    this.pincode = '',
    this.invoicePrefix = 'INV',
    this.barcodePrefix = 'BR',
    this.currency = '₹',
    this.financialYear = '',
    this.updatedAt,
  });
}
