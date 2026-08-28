// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProductAdapter extends TypeAdapter<Product> {
  @override
  final typeId = 0;

  @override
  Product read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Product(
      id: fields[0] as String,
      productName: fields[1] as String,
      productCode: fields[2] as String,
      category: fields[3] as String,
      brand: fields[4] as String,
      color: fields[5] as String,
      createdDate: fields[6] as DateTime,
      updatedDate: fields[7] as DateTime,
      variants: (fields[8] as List).cast<ProductVariant>(),
      version: fields[9] == null ? 1 : (fields[9] as num).toInt(),
      deviceId: fields[10] == null ? '' : fields[10] as String,
      createdBy: fields[11] == null ? '' : fields[11] as String,
      isDeleted: fields[12] == null ? false : fields[12] as bool,
      lastSyncedAt: fields[13] as DateTime?,
      isSynced: fields[14] == null ? false : fields[14] as bool,
      hsn: fields[15] == null ? '' : fields[15] as String,
      uqc: fields[16] == null ? 'PCS' : fields[16] as String,
      gstTreatment: fields[17] == null ? 'TAXABLE' : fields[17] as String,
      gstRate: fields[18] == null ? 0.0 : (fields[18] as num?)?.toDouble(),
      cessRate: fields[19] == null ? 0.0 : (fields[19] as num).toDouble(),
      gstRateConfigId: fields[20] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Product obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.productName)
      ..writeByte(2)
      ..write(obj.productCode)
      ..writeByte(3)
      ..write(obj.category)
      ..writeByte(4)
      ..write(obj.brand)
      ..writeByte(5)
      ..write(obj.color)
      ..writeByte(6)
      ..write(obj.createdDate)
      ..writeByte(7)
      ..write(obj.updatedDate)
      ..writeByte(8)
      ..write(obj.variants)
      ..writeByte(9)
      ..write(obj.version)
      ..writeByte(10)
      ..write(obj.deviceId)
      ..writeByte(11)
      ..write(obj.createdBy)
      ..writeByte(12)
      ..write(obj.isDeleted)
      ..writeByte(13)
      ..write(obj.lastSyncedAt)
      ..writeByte(14)
      ..write(obj.isSynced)
      ..writeByte(15)
      ..write(obj.hsn)
      ..writeByte(16)
      ..write(obj.uqc)
      ..writeByte(17)
      ..write(obj.gstTreatment)
      ..writeByte(18)
      ..write(obj.gstRate)
      ..writeByte(19)
      ..write(obj.cessRate)
      ..writeByte(20)
      ..write(obj.gstRateConfigId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ProductVariantAdapter extends TypeAdapter<ProductVariant> {
  @override
  final typeId = 1;

  @override
  ProductVariant read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ProductVariant(
      size: fields[0] as String,
      price: (fields[1] as num).toDouble(),
      quantity: (fields[2] as num).toInt(),
      barcode: fields[3] as String,
      lastStockUpdated: fields[4] as DateTime?,
      stockIn: fields[5] == null ? 0 : (fields[5] as num).toInt(),
      stockOut: fields[6] == null ? 0 : (fields[6] as num).toInt(),
      reorderLevel: fields[7] == null ? 5 : (fields[7] as num).toInt(),
      sku: fields[8] == null ? '' : fields[8] as String,
      costPrice: fields[9] == null ? 0.0 : (fields[9] as num).toDouble(),
    );
  }

  @override
  void write(BinaryWriter writer, ProductVariant obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.size)
      ..writeByte(1)
      ..write(obj.price)
      ..writeByte(2)
      ..write(obj.quantity)
      ..writeByte(3)
      ..write(obj.barcode)
      ..writeByte(4)
      ..write(obj.lastStockUpdated)
      ..writeByte(5)
      ..write(obj.stockIn)
      ..writeByte(6)
      ..write(obj.stockOut)
      ..writeByte(7)
      ..write(obj.reorderLevel)
      ..writeByte(8)
      ..write(obj.sku)
      ..writeByte(9)
      ..write(obj.costPrice);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductVariantAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
