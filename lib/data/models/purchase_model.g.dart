// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'purchase_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PurchaseAdapter extends TypeAdapter<Purchase> {
  @override
  final typeId = 8;

  @override
  Purchase read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Purchase(
      id: fields[0] as String,
      purchaseNumber: fields[1] as String,
      supplierId: fields[2] as String,
      supplierName: fields[3] as String,
      purchaseDate: fields[4] as DateTime,
      items: (fields[5] as List).cast<PurchaseItem>(),
      subtotal: (fields[6] as num).toDouble(),
      discount: fields[7] == null ? 0 : (fields[7] as num).toDouble(),
      tax: fields[8] == null ? 0 : (fields[8] as num).toDouble(),
      grandTotal: (fields[9] as num).toDouble(),
      notes: fields[10] == null ? '' : fields[10] as String,
      createdDate: fields[11] as DateTime,
      isSynced: fields[12] == null ? false : fields[12] as bool,
      version: fields[13] == null ? 1 : (fields[13] as num).toInt(),
      deviceId: fields[14] == null ? '' : fields[14] as String,
      createdBy: fields[15] == null ? '' : fields[15] as String,
      isDeleted: fields[16] == null ? false : fields[16] as bool,
      lastSyncedAt: fields[17] as DateTime?,
      updatedAt: fields[18] as DateTime?,
      status: fields[19] == null ? 'Received' : fields[19] as String,
      paymentStatus: fields[20] == null ? 'Unpaid' : fields[20] as String,
      expectedDeliveryDate: fields[21] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Purchase obj) {
    writer
      ..writeByte(22)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.purchaseNumber)
      ..writeByte(2)
      ..write(obj.supplierId)
      ..writeByte(3)
      ..write(obj.supplierName)
      ..writeByte(4)
      ..write(obj.purchaseDate)
      ..writeByte(5)
      ..write(obj.items)
      ..writeByte(6)
      ..write(obj.subtotal)
      ..writeByte(7)
      ..write(obj.discount)
      ..writeByte(8)
      ..write(obj.tax)
      ..writeByte(9)
      ..write(obj.grandTotal)
      ..writeByte(10)
      ..write(obj.notes)
      ..writeByte(11)
      ..write(obj.createdDate)
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
      ..write(obj.updatedAt)
      ..writeByte(19)
      ..write(obj.status)
      ..writeByte(20)
      ..write(obj.paymentStatus)
      ..writeByte(21)
      ..write(obj.expectedDeliveryDate);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PurchaseAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PurchaseItemAdapter extends TypeAdapter<PurchaseItem> {
  @override
  final typeId = 9;

  @override
  PurchaseItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PurchaseItem(
      productId: fields[0] as String,
      productName: fields[1] as String,
      variantBarcode: fields[2] as String,
      variantSize: fields[3] as String,
      sku: fields[4] == null ? '' : fields[4] as String,
      quantity: (fields[5] as num).toInt(),
      costPrice: (fields[6] as num).toDouble(),
      sellingPrice: (fields[7] as num).toDouble(),
      lineTotal: (fields[8] as num).toDouble(),
      receivedQuantity: fields[9] == null ? 0 : (fields[9] as num).toInt(),
    );
  }

  @override
  void write(BinaryWriter writer, PurchaseItem obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.productId)
      ..writeByte(1)
      ..write(obj.productName)
      ..writeByte(2)
      ..write(obj.variantBarcode)
      ..writeByte(3)
      ..write(obj.variantSize)
      ..writeByte(4)
      ..write(obj.sku)
      ..writeByte(5)
      ..write(obj.quantity)
      ..writeByte(6)
      ..write(obj.costPrice)
      ..writeByte(7)
      ..write(obj.sellingPrice)
      ..writeByte(8)
      ..write(obj.lineTotal)
      ..writeByte(9)
      ..write(obj.receivedQuantity);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PurchaseItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
