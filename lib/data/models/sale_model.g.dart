// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sale_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SaleAdapter extends TypeAdapter<Sale> {
  @override
  final typeId = 6;

  @override
  Sale read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Sale(
      id: fields[0] as String,
      invoiceNumber: fields[1] as String,
      date: fields[2] as DateTime,
      customerId: fields[3] as String,
      customerName: fields[12] as String,
      items: (fields[4] as List).cast<SaleItem>(),
      subtotal: (fields[5] as num).toDouble(),
      discountPercent: (fields[6] as num).toDouble(),
      discountAmount: (fields[7] as num).toDouble(),
      taxAmount: (fields[8] as num).toDouble(),
      grandTotal: (fields[9] as num).toDouble(),
      paymentMethod: fields[10] as String,
      notes: fields[11] == null ? '' : fields[11] as String,
      rewardDiscountAmount: fields[13] == null
          ? 0
          : (fields[13] as num).toDouble(),
      rewardPointsEarned: fields[14] == null
          ? 0
          : (fields[14] as num).toDouble(),
      isSynced: fields[15] == null ? false : fields[15] as bool,
      updatedAt: fields[16] as DateTime?,
      version: fields[17] == null ? 1 : (fields[17] as num).toInt(),
      deviceId: fields[18] == null ? '' : fields[18] as String,
      createdBy: fields[19] == null ? '' : fields[19] as String,
      isDeleted: fields[20] == null ? false : fields[20] as bool,
      lastSyncedAt: fields[21] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Sale obj) {
    writer
      ..writeByte(22)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.invoiceNumber)
      ..writeByte(2)
      ..write(obj.date)
      ..writeByte(3)
      ..write(obj.customerId)
      ..writeByte(4)
      ..write(obj.items)
      ..writeByte(5)
      ..write(obj.subtotal)
      ..writeByte(6)
      ..write(obj.discountPercent)
      ..writeByte(7)
      ..write(obj.discountAmount)
      ..writeByte(8)
      ..write(obj.taxAmount)
      ..writeByte(9)
      ..write(obj.grandTotal)
      ..writeByte(10)
      ..write(obj.paymentMethod)
      ..writeByte(11)
      ..write(obj.notes)
      ..writeByte(12)
      ..write(obj.customerName)
      ..writeByte(13)
      ..write(obj.rewardDiscountAmount)
      ..writeByte(14)
      ..write(obj.rewardPointsEarned)
      ..writeByte(15)
      ..write(obj.isSynced)
      ..writeByte(16)
      ..write(obj.updatedAt)
      ..writeByte(17)
      ..write(obj.version)
      ..writeByte(18)
      ..write(obj.deviceId)
      ..writeByte(19)
      ..write(obj.createdBy)
      ..writeByte(20)
      ..write(obj.isDeleted)
      ..writeByte(21)
      ..write(obj.lastSyncedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SaleItemAdapter extends TypeAdapter<SaleItem> {
  @override
  final typeId = 7;

  @override
  SaleItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SaleItem(
      productId: fields[0] as String,
      productName: fields[1] as String,
      productCode: fields[2] as String,
      variantBarcode: fields[3] as String,
      variantSize: fields[4] as String,
      price: (fields[5] as num).toDouble(),
      quantity: (fields[6] as num).toInt(),
      total: (fields[7] as num).toDouble(),
    );
  }

  @override
  void write(BinaryWriter writer, SaleItem obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.productId)
      ..writeByte(1)
      ..write(obj.productName)
      ..writeByte(2)
      ..write(obj.productCode)
      ..writeByte(3)
      ..write(obj.variantBarcode)
      ..writeByte(4)
      ..write(obj.variantSize)
      ..writeByte(5)
      ..write(obj.price)
      ..writeByte(6)
      ..write(obj.quantity)
      ..writeByte(7)
      ..write(obj.total);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaleItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
