// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'loyalty_transaction_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LoyaltyTransactionAdapter extends TypeAdapter<LoyaltyTransaction> {
  @override
  final typeId = 20;

  @override
  LoyaltyTransaction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LoyaltyTransaction(
      id: fields[0] as String,
      customerId: fields[1] as String,
      saleId: fields[2] as String?,
      transactionType: fields[3] as String,
      points: (fields[4] as num).toDouble(),
      monetaryValue: (fields[5] as num).toDouble(),
      reference: fields[6] == null ? '' : fields[6] as String,
      remarks: fields[7] == null ? '' : fields[7] as String,
      createdDate: fields[8] as DateTime,
      createdBy: fields[9] as String,
      isSynced: fields[10] == null ? false : fields[10] as bool,
      updatedAt: fields[11] as DateTime?,
      version: fields[12] == null ? 1 : (fields[12] as num).toInt(),
      deviceId: fields[13] == null ? '' : fields[13] as String,
      isDeleted: fields[14] == null ? false : fields[14] as bool,
      lastSyncedAt: fields[15] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, LoyaltyTransaction obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.customerId)
      ..writeByte(2)
      ..write(obj.saleId)
      ..writeByte(3)
      ..write(obj.transactionType)
      ..writeByte(4)
      ..write(obj.points)
      ..writeByte(5)
      ..write(obj.monetaryValue)
      ..writeByte(6)
      ..write(obj.reference)
      ..writeByte(7)
      ..write(obj.remarks)
      ..writeByte(8)
      ..write(obj.createdDate)
      ..writeByte(9)
      ..write(obj.createdBy)
      ..writeByte(10)
      ..write(obj.isSynced)
      ..writeByte(11)
      ..write(obj.updatedAt)
      ..writeByte(12)
      ..write(obj.version)
      ..writeByte(13)
      ..write(obj.deviceId)
      ..writeByte(14)
      ..write(obj.isDeleted)
      ..writeByte(15)
      ..write(obj.lastSyncedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoyaltyTransactionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
