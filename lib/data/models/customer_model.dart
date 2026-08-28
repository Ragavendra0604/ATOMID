import 'package:hive_ce/hive.dart';

part 'customer_model.g.dart';

@HiveType(typeId: 15)
class Customer extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String code;

  @HiveField(2)
  String name;

  @HiveField(3)
  String mobile;

  @HiveField(4)
  String gstNumber;

  @HiveField(5)
  String address;

  @HiveField(6)
  double creditLimit;

  @HiveField(7)
  int creditDays;

  @HiveField(8)
  double openingBalance;

  @HiveField(9)
  double currentBalance;

  @HiveField(10)
  String status;

  @HiveField(11)
  DateTime createdDate;

  @HiveField(12)
  double totalRewardPoints;

  @HiveField(13)
  double lifetimeSpend;

  @HiveField(14)
  bool isSynced;

  @HiveField(15)
  DateTime? updatedAt;

  @HiveField(16)
  int version;

  @HiveField(17)
  String deviceId;

  @HiveField(18)
  String createdBy;

  @HiveField(19)
  bool isDeleted;

  @HiveField(20)
  DateTime? lastSyncedAt;

  @HiveField(21)
  String email;

  @HiveField(22)
  String customerGroup;

  @HiveField(23)
  String notes;

  @HiveField(24)
  List<String> tags;

  @HiveField(25)
  List<String> attachments;

  // Additive GST fields
  @HiveField(26)
  String state;

  @HiveField(27)
  String stateCode;

  @HiveField(28)
  String city;

  @HiveField(29)
  String pincode;

  Customer({
    required this.id,
    required this.code,
    required this.name,
    required this.mobile,
    this.gstNumber = '',
    this.address = '',
    this.creditLimit = 0,
    this.creditDays = 0,
    this.openingBalance = 0,
    this.currentBalance = 0,
    this.status = 'Active',
    required this.createdDate,
    this.totalRewardPoints = 0,
    this.lifetimeSpend = 0,
    this.isSynced = false,
    this.updatedAt,
    this.version = 1,
    this.deviceId = '',
    this.createdBy = '',
    this.isDeleted = false,
    this.lastSyncedAt,
    this.email = '',
    this.customerGroup = 'General',
    this.notes = '',
    this.tags = const [],
    this.attachments = const [],
    this.state = '',
    this.stateCode = '',
    this.city = '',
    this.pincode = '',
  });
}
