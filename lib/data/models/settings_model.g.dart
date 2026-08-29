// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SettingsModelAdapter extends TypeAdapter<SettingsModel> {
  @override
  final typeId = 3;

  @override
  SettingsModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SettingsModel(
      isDarkMode: fields[0] == null ? true : fields[0] as bool,
      companyName: fields[1] == null ? 'ATOMID STORE' : fields[1] as String,
      currencySymbol: fields[2] == null ? '₹' : fields[2] as String,
      pdfPageSize: fields[3] == null ? 'A4' : fields[3] as String,
      taxMode: fields[4] == null ? 'inclusive' : fields[4] as String,
      taxRate: fields[5] == null ? 0 : (fields[5] as num).toDouble(),
      updatedAt: fields[10] as DateTime?,
      roundOffEnabled: fields[11] == null ? true : fields[11] as bool,
      hsnRequired: fields[12] == null ? false : fields[12] as bool,
      walkInPosPolicy: fields[13] == null
          ? 'USE_SHOP_STATE'
          : fields[13] as String,
      showGstBreakdown: fields[14] == null ? true : fields[14] as bool,
      showHsnSummary: fields[15] == null ? true : fields[15] as bool,
      defaultUqc: fields[16] == null ? 'PCS' : fields[16] as String,
      thermalReceiptSize: fields[17] == null ? '80mm' : fields[17] as String,
      showTaxOnThermalReceipt: fields[18] == null ? true : fields[18] as bool,
      inclusiveTaxRounding: fields[19] == null
          ? 'SHELF_PRICE'
          : fields[19] as String,
      invoiceTemplate: fields[20] == null ? 'THERMAL' : fields[20] as String,
    );
  }

  @override
  void write(BinaryWriter writer, SettingsModel obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.isDarkMode)
      ..writeByte(1)
      ..write(obj.companyName)
      ..writeByte(2)
      ..write(obj.currencySymbol)
      ..writeByte(3)
      ..write(obj.pdfPageSize)
      ..writeByte(4)
      ..write(obj.taxMode)
      ..writeByte(5)
      ..write(obj.taxRate)
      ..writeByte(10)
      ..write(obj.updatedAt)
      ..writeByte(11)
      ..write(obj.roundOffEnabled)
      ..writeByte(12)
      ..write(obj.hsnRequired)
      ..writeByte(13)
      ..write(obj.walkInPosPolicy)
      ..writeByte(14)
      ..write(obj.showGstBreakdown)
      ..writeByte(15)
      ..write(obj.showHsnSummary)
      ..writeByte(16)
      ..write(obj.defaultUqc)
      ..writeByte(17)
      ..write(obj.thermalReceiptSize)
      ..writeByte(18)
      ..write(obj.showTaxOnThermalReceipt)
      ..writeByte(19)
      ..write(obj.inclusiveTaxRounding)
      ..writeByte(20)
      ..write(obj.invoiceTemplate);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
