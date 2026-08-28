// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'supplier_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SupplierAdapter extends TypeAdapter<Supplier> {
  @override
  final typeId = 5;

  @override
  Supplier read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Supplier(
      id: fields[0] as String,
      supplierCode: fields[1] as String,
      supplierName: fields[2] as String,
      phone: fields[3] == null ? '' : fields[3] as String,
      email: fields[4] == null ? '' : fields[4] as String,
      address: fields[5] == null ? '' : fields[5] as String,
      gstNumber: fields[6] == null ? '' : fields[6] as String,
      contactPerson: fields[7] == null ? '' : fields[7] as String,
      notes: fields[8] == null ? '' : fields[8] as String,
      createdDate: fields[9] as DateTime,
      updatedDate: fields[10] as DateTime,
      isActive: fields[11] == null ? true : fields[11] as bool,
      isSynced: fields[12] == null ? false : fields[12] as bool,
      version: fields[13] == null ? 1 : (fields[13] as num).toInt(),
      deviceId: fields[14] == null ? '' : fields[14] as String,
      createdBy: fields[15] == null ? '' : fields[15] as String,
      isDeleted: fields[16] == null ? false : fields[16] as bool,
      lastSyncedAt: fields[17] as DateTime?,
      paymentTerms: fields[18] == null ? 'Net 30' : fields[18] as String,
      currentBalance: fields[19] == null ? 0.0 : (fields[19] as num).toDouble(),
      rating: fields[20] == null ? 0.0 : (fields[20] as num).toDouble(),
      supplierCategory: fields[21] == null ? 'General' : fields[21] as String,
      attachments: fields[22] == null
          ? const []
          : (fields[22] as List).cast<String>(),
      state: fields[23] == null ? '' : fields[23] as String,
      stateCode: fields[24] == null ? '' : fields[24] as String,
      city: fields[25] == null ? '' : fields[25] as String,
      pincode: fields[26] == null ? '' : fields[26] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Supplier obj) {
    writer
      ..writeByte(27)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.supplierCode)
      ..writeByte(2)
      ..write(obj.supplierName)
      ..writeByte(3)
      ..write(obj.phone)
      ..writeByte(4)
      ..write(obj.email)
      ..writeByte(5)
      ..write(obj.address)
      ..writeByte(6)
      ..write(obj.gstNumber)
      ..writeByte(7)
      ..write(obj.contactPerson)
      ..writeByte(8)
      ..write(obj.notes)
      ..writeByte(9)
      ..write(obj.createdDate)
      ..writeByte(10)
      ..write(obj.updatedDate)
      ..writeByte(11)
      ..write(obj.isActive)
      ..writeByte(12)
      ..write(obj.isSynced)
      ..writeByte(13)
      ..write(obj.version)
      ..writeByte(14)
      ..write(obj.deviceId)
      ..writeByte(15)
      ..write(obj.createdBy)
      ..writeByte(16)
      ..write(obj.isDeleted)
      ..writeByte(17)
      ..write(obj.lastSyncedAt)
      ..writeByte(18)
      ..write(obj.paymentTerms)
      ..writeByte(19)
      ..write(obj.currentBalance)
      ..writeByte(20)
      ..write(obj.rating)
      ..writeByte(21)
      ..write(obj.supplierCategory)
      ..writeByte(22)
      ..write(obj.attachments)
      ..writeByte(23)
      ..write(obj.state)
      ..writeByte(24)
      ..write(obj.stateCode)
      ..writeByte(25)
      ..write(obj.city)
      ..writeByte(26)
      ..write(obj.pincode);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupplierAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
