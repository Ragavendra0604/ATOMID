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
      customerId: fields[3] == null ? '' : fields[3] as String,
      customerName: fields[12] == null ? '' : fields[12] as String,
      items: fields[4] == null
          ? const []
          : (fields[4] as List).cast<SaleItem>(),
      subtotal: fields[5] == null ? 0.0 : (fields[5] as num).toDouble(),
      discountPercent: fields[6] == null ? 0.0 : (fields[6] as num).toDouble(),
      discountAmount: fields[7] == null ? 0.0 : (fields[7] as num).toDouble(),
      taxAmount: fields[8] == null ? 0.0 : (fields[8] as num).toDouble(),
      grandTotal: (fields[9] as num).toDouble(),
      paymentMethod: fields[10] == null ? 'Cash' : fields[10] as String,
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
      sellerGstin: fields[22] == null ? '' : fields[22] as String,
      sellerState: fields[23] == null ? '' : fields[23] as String,
      sellerStateCode: fields[24] == null ? '' : fields[24] as String,
      sellerLegalName: fields[25] == null ? '' : fields[25] as String,
      sellerAddress: fields[26] == null ? '' : fields[26] as String,
      customerGstin: fields[27] == null ? '' : fields[27] as String,
      customerState: fields[28] == null ? '' : fields[28] as String,
      customerStateCode: fields[29] == null ? '' : fields[29] as String,
      customerAddress: fields[30] == null ? '' : fields[30] as String,
      customerPhone: fields[31] == null ? '' : fields[31] as String,
      placeOfSupply: fields[32] == null ? '' : fields[32] as String,
      placeOfSupplyBasis: fields[33] == null ? '' : fields[33] as String,
      pricingMode: fields[34] == null ? 'inclusive' : fields[34] as String,
      taxableAmount: fields[35] == null ? 0.0 : (fields[35] as num).toDouble(),
      cgstAmount: fields[36] == null ? 0.0 : (fields[36] as num).toDouble(),
      sgstAmount: fields[37] == null ? 0.0 : (fields[37] as num).toDouble(),
      utgstAmount: fields[38] == null ? 0.0 : (fields[38] as num).toDouble(),
      igstAmount: fields[39] == null ? 0.0 : (fields[39] as num).toDouble(),
      cessAmount: fields[40] == null ? 0.0 : (fields[40] as num).toDouble(),
      preRoundTotal: fields[41] == null ? 0.0 : (fields[41] as num).toDouble(),
      roundOff: fields[42] == null ? 0.0 : (fields[42] as num).toDouble(),
      documentType: fields[43] == null ? 'Tax Invoice' : fields[43] as String,
      isInterState: fields[44] == null ? false : fields[44] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Sale obj) {
    writer
      ..writeByte(45)
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
      ..write(obj.lastSyncedAt)
      ..writeByte(22)
      ..write(obj.sellerGstin)
      ..writeByte(23)
      ..write(obj.sellerState)
      ..writeByte(24)
      ..write(obj.sellerStateCode)
      ..writeByte(25)
      ..write(obj.sellerLegalName)
      ..writeByte(26)
      ..write(obj.sellerAddress)
      ..writeByte(27)
      ..write(obj.customerGstin)
      ..writeByte(28)
      ..write(obj.customerState)
      ..writeByte(29)
      ..write(obj.customerStateCode)
      ..writeByte(30)
      ..write(obj.customerAddress)
      ..writeByte(31)
      ..write(obj.customerPhone)
      ..writeByte(32)
      ..write(obj.placeOfSupply)
      ..writeByte(33)
      ..write(obj.placeOfSupplyBasis)
      ..writeByte(34)
      ..write(obj.pricingMode)
      ..writeByte(35)
      ..write(obj.taxableAmount)
      ..writeByte(36)
      ..write(obj.cgstAmount)
      ..writeByte(37)
      ..write(obj.sgstAmount)
      ..writeByte(38)
      ..write(obj.utgstAmount)
      ..writeByte(39)
      ..write(obj.igstAmount)
      ..writeByte(40)
      ..write(obj.cessAmount)
      ..writeByte(41)
      ..write(obj.preRoundTotal)
      ..writeByte(42)
      ..write(obj.roundOff)
      ..writeByte(43)
      ..write(obj.documentType)
      ..writeByte(44)
      ..write(obj.isInterState);
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
      productCode: fields[2] == null ? '' : fields[2] as String,
      variantBarcode: fields[3] as String,
      variantSize: fields[4] as String,
      price: (fields[5] as num).toDouble(),
      quantity: (fields[6] as num).toInt(),
      total: (fields[7] as num).toDouble(),
      hsn: fields[8] == null ? '' : fields[8] as String,
      uqc: fields[9] == null ? 'PCS' : fields[9] as String,
      gstRate: (fields[10] as num?)?.toDouble(),
      gstTreatment: fields[11] == null ? 'TAXABLE' : fields[11] as String,
      cessRate: fields[12] == null ? 0.0 : (fields[12] as num).toDouble(),
      taxableValue: fields[13] == null ? 0.0 : (fields[13] as num).toDouble(),
      discountAmount: fields[14] == null ? 0.0 : (fields[14] as num).toDouble(),
      cgstAmount: fields[15] == null ? 0.0 : (fields[15] as num).toDouble(),
      sgstAmount: fields[16] == null ? 0.0 : (fields[16] as num).toDouble(),
      utgstAmount: fields[17] == null ? 0.0 : (fields[17] as num).toDouble(),
      igstAmount: fields[18] == null ? 0.0 : (fields[18] as num).toDouble(),
      cessAmount: fields[19] == null ? 0.0 : (fields[19] as num).toDouble(),
      gstRateConfigId: fields[20] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SaleItem obj) {
    writer
      ..writeByte(21)
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
      ..write(obj.total)
      ..writeByte(8)
      ..write(obj.hsn)
      ..writeByte(9)
      ..write(obj.uqc)
      ..writeByte(10)
      ..write(obj.gstRate)
      ..writeByte(11)
      ..write(obj.gstTreatment)
      ..writeByte(12)
      ..write(obj.cessRate)
      ..writeByte(13)
      ..write(obj.taxableValue)
      ..writeByte(14)
      ..write(obj.discountAmount)
      ..writeByte(15)
      ..write(obj.cgstAmount)
      ..writeByte(16)
      ..write(obj.sgstAmount)
      ..writeByte(17)
      ..write(obj.utgstAmount)
      ..writeByte(18)
      ..write(obj.igstAmount)
      ..writeByte(19)
      ..write(obj.cessAmount)
      ..writeByte(20)
      ..write(obj.gstRateConfigId);
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
