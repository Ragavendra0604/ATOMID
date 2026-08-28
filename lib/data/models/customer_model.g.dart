// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CustomerAdapter extends TypeAdapter<Customer> {
  @override
  final typeId = 15;

  @override
  Customer read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Customer(
      id: fields[0] as String,
      code: fields[1] as String,
      name: fields[2] as String,
      mobile: fields[3] as String,
      gstNumber: fields[4] == null ? '' : fields[4] as String,
      address: fields[5] == null ? '' : fields[5] as String,
      creditLimit: fields[6] == null ? 0 : (fields[6] as num).toDouble(),
      creditDays: fields[7] == null ? 0 : (fields[7] as num).toInt(),
      openingBalance: fields[8] == null ? 0 : (fields[8] as num).toDouble(),
      currentBalance: fields[9] == null ? 0 : (fields[9] as num).toDouble(),
      status: fields[10] == null ? 'Active' : fields[10] as String,
      createdDate: fields[11] as DateTime,
      totalRewardPoints: fields[12] == null
          ? 0
          : (fields[12] as num).toDouble(),
      lifetimeSpend: fields[13] == null ? 0 : (fields[13] as num).toDouble(),
      isSynced: fields[14] == null ? false : fields[14] as bool,
      updatedAt: fields[15] as DateTime?,
      version: fields[16] == null ? 1 : (fields[16] as num).toInt(),
      deviceId: fields[17] == null ? '' : fields[17] as String,
      createdBy: fields[18] == null ? '' : fields[18] as String,
      isDeleted: fields[19] == null ? false : fields[19] as bool,
      lastSyncedAt: fields[20] as DateTime?,
      email: fields[21] == null ? '' : fields[21] as String,
      customerGroup: fields[22] == null ? 'General' : fields[22] as String,
      notes: fields[23] == null ? '' : fields[23] as String,
      tags: fields[24] == null ? const [] : (fields[24] as List).cast<String>(),
      attachments: fields[25] == null
          ? const []
          : (fields[25] as List).cast<String>(),
      state: fields[26] == null ? '' : fields[26] as String,
      stateCode: fields[27] == null ? '' : fields[27] as String,
      city: fields[28] == null ? '' : fields[28] as String,
      pincode: fields[29] == null ? '' : fields[29] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Customer obj) {
    writer
      ..writeByte(30)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.code)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.mobile)
      ..writeByte(4)
      ..write(obj.gstNumber)
      ..writeByte(5)
      ..write(obj.address)
      ..writeByte(6)
      ..write(obj.creditLimit)
      ..writeByte(7)
      ..write(obj.creditDays)
      ..writeByte(8)
      ..write(obj.openingBalance)
      ..writeByte(9)
      ..write(obj.currentBalance)
      ..writeByte(10)
      ..write(obj.status)
      ..writeByte(11)
      ..write(obj.createdDate)
      ..writeByte(12)
      ..write(obj.totalRewardPoints)
      ..writeByte(13)
      ..write(obj.lifetimeSpend)
      ..writeByte(14)
      ..write(obj.isSynced)
      ..writeByte(15)
      ..write(obj.updatedAt)
      ..writeByte(16)
      ..write(obj.version)
      ..writeByte(17)
      ..write(obj.deviceId)
      ..writeByte(18)
      ..write(obj.createdBy)
      ..writeByte(19)
      ..write(obj.isDeleted)
      ..writeByte(20)
      ..write(obj.lastSyncedAt)
      ..writeByte(21)
      ..write(obj.email)
      ..writeByte(22)
      ..write(obj.customerGroup)
      ..writeByte(23)
      ..write(obj.notes)
      ..writeByte(24)
      ..write(obj.tags)
      ..writeByte(25)
      ..write(obj.attachments)
      ..writeByte(26)
      ..write(obj.state)
      ..writeByte(27)
      ..write(obj.stateCode)
      ..writeByte(28)
      ..write(obj.city)
      ..writeByte(29)
      ..write(obj.pincode);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomerAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
