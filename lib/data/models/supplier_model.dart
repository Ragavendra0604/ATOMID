import 'package:hive_ce/hive.dart';

part 'supplier_model.g.dart';

@HiveType(typeId: 5)
class Supplier extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String supplierCode;

  @HiveField(2)
  String supplierName;

  @HiveField(3)
  String phone;

  @HiveField(4)
  String email;

  @HiveField(5)
  String address;

  @HiveField(6)
  String gstNumber;

  @HiveField(7)
  String contactPerson;

  @HiveField(8)
  String notes;

  @HiveField(9)
  DateTime createdDate;

  @HiveField(10)
  DateTime updatedDate;

  @HiveField(11)
  bool isActive;

  @HiveField(12)
  bool isSynced;

  @HiveField(13)
  int version;

  @HiveField(14)
  String deviceId;

  @HiveField(15)
  String createdBy;

  @HiveField(16)
  bool isDeleted;

  @HiveField(17)
  DateTime? lastSyncedAt;

  @HiveField(18)
  String paymentTerms;

  @HiveField(19)
  double currentBalance;

  @HiveField(20)
  double rating;

  @HiveField(21)
  String supplierCategory;

  @HiveField(22)
  List<String> attachments;

  Supplier({
    required this.id,
    required this.supplierCode,
    required this.supplierName,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.gstNumber = '',
    this.contactPerson = '',
    this.notes = '',
    required this.createdDate,
    required this.updatedDate,
    this.isActive = true,
    this.isSynced = false,
    this.version = 1,
    this.deviceId = '',
    this.createdBy = '',
    this.isDeleted = false,
    this.lastSyncedAt,
    this.paymentTerms = 'Net 30',
    this.currentBalance = 0.0,
    this.rating = 0.0,
    this.supplierCategory = 'General',
    this.attachments = const [],
  });
}
