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
      items: fields[5] == null
          ? const []
          : (fields[5] as List).cast<PurchaseItem>(),
      subtotal: fields[6] == null ? 0.0 : (fields[6] as num).toDouble(),
      discount: fields[7] == null ? 0 : (fields[7] as num).toDouble(),
      tax: fields[8] == null ? 0 : (fields[8] as num).toDouble(),
      grandTotal: (fields[9] as num).toDouble(),
      notes: fields[10] == null ? '' : fields[10] as String,
      createdDate: fields[11] as DateTime?,
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
      supplierInvoiceNumber: fields[22] == null ? '' : fields[22] as String,
      supplierInvoiceDate: fields[23] as DateTime?,
      supplierGstin: fields[24] == null ? '' : fields[24] as String,
      supplierState: fields[25] == null ? '' : fields[25] as String,
      supplierStateCode: fields[26] == null ? '' : fields[26] as String,
      supplierAddress: fields[27] == null ? '' : fields[27] as String,
      itcEligibility: fields[28] == null
          ? 'REQUIRES_DETERMINATION'
          : fields[28] as String,
      recipientName: fields[37] == null ? '' : fields[37] as String,
      recipientGstin: fields[38] == null ? '' : fields[38] as String,
      recipientState: fields[39] == null ? '' : fields[39] as String,
      recipientStateCode: fields[40] == null ? '' : fields[40] as String,
      pricingMode: fields[41] == null ? 'exclusive' : fields[41] as String,
      preRoundTotal: fields[42] == null ? 0.0 : (fields[42] as num).toDouble(),
      taxableAmount: fields[29] == null ? 0.0 : (fields[29] as num).toDouble(),
      cgstAmount: fields[30] == null ? 0.0 : (fields[30] as num).toDouble(),
      sgstAmount: fields[31] == null ? 0.0 : (fields[31] as num).toDouble(),
      utgstAmount: fields[32] == null ? 0.0 : (fields[32] as num).toDouble(),
      igstAmount: fields[33] == null ? 0.0 : (fields[33] as num).toDouble(),
      cessAmount: fields[34] == null ? 0.0 : (fields[34] as num).toDouble(),
      roundOff: fields[35] == null ? 0.0 : (fields[35] as num).toDouble(),
      isInterState: fields[36] == null ? false : fields[36] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Purchase obj) {
    writer
      ..writeByte(43)
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
      ..write(obj.expectedDeliveryDate)
      ..writeByte(22)
      ..write(obj.supplierInvoiceNumber)
      ..writeByte(23)
      ..write(obj.supplierInvoiceDate)
      ..writeByte(24)
      ..write(obj.supplierGstin)
      ..writeByte(25)
      ..write(obj.supplierState)
      ..writeByte(26)
      ..write(obj.supplierStateCode)
      ..writeByte(27)
      ..write(obj.supplierAddress)
      ..writeByte(28)
      ..write(obj.itcEligibility)
      ..writeByte(29)
      ..write(obj.taxableAmount)
      ..writeByte(30)
      ..write(obj.cgstAmount)
      ..writeByte(31)
      ..write(obj.sgstAmount)
      ..writeByte(32)
      ..write(obj.utgstAmount)
      ..writeByte(33)
      ..write(obj.igstAmount)
      ..writeByte(34)
      ..write(obj.cessAmount)
      ..writeByte(35)
      ..write(obj.roundOff)
      ..writeByte(36)
      ..write(obj.isInterState)
      ..writeByte(37)
      ..write(obj.recipientName)
      ..writeByte(38)
      ..write(obj.recipientGstin)
      ..writeByte(39)
      ..write(obj.recipientState)
      ..writeByte(40)
      ..write(obj.recipientStateCode)
      ..writeByte(41)
      ..write(obj.pricingMode)
      ..writeByte(42)
      ..write(obj.preRoundTotal);
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
      hsn: fields[10] == null ? '' : fields[10] as String,
      uqc: fields[11] == null ? 'PCS' : fields[11] as String,
      gstRate: (fields[12] as num?)?.toDouble(),
      gstTreatment: fields[13] == null ? 'TAXABLE' : fields[13] as String,
      cessRate: fields[14] == null ? 0.0 : (fields[14] as num).toDouble(),
      taxableValue: fields[15] == null ? 0.0 : (fields[15] as num).toDouble(),
      discountAmount: fields[16] == null ? 0.0 : (fields[16] as num).toDouble(),
      cgstAmount: fields[17] == null ? 0.0 : (fields[17] as num).toDouble(),
      sgstAmount: fields[18] == null ? 0.0 : (fields[18] as num).toDouble(),
      utgstAmount: fields[19] == null ? 0.0 : (fields[19] as num).toDouble(),
      igstAmount: fields[20] == null ? 0.0 : (fields[20] as num).toDouble(),
      cessAmount: fields[21] == null ? 0.0 : (fields[21] as num).toDouble(),
      gstRateConfigId: fields[22] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PurchaseItem obj) {
    writer
      ..writeByte(23)
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
      ..write(obj.receivedQuantity)
      ..writeByte(10)
      ..write(obj.hsn)
      ..writeByte(11)
      ..write(obj.uqc)
      ..writeByte(12)
      ..write(obj.gstRate)
      ..writeByte(13)
      ..write(obj.gstTreatment)
      ..writeByte(14)
      ..write(obj.cessRate)
      ..writeByte(15)
      ..write(obj.taxableValue)
      ..writeByte(16)
      ..write(obj.discountAmount)
      ..writeByte(17)
      ..write(obj.cgstAmount)
      ..writeByte(18)
      ..write(obj.sgstAmount)
      ..writeByte(19)
      ..write(obj.utgstAmount)
      ..writeByte(20)
      ..write(obj.igstAmount)
      ..writeByte(21)
      ..write(obj.cessAmount)
      ..writeByte(22)
      ..write(obj.gstRateConfigId);
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
