// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invoice_settings_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class InvoiceSettingsModelAdapter extends TypeAdapter<InvoiceSettingsModel> {
  @override
  final typeId = 50;

  @override
  InvoiceSettingsModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InvoiceSettingsModel(
      footerText: fields[0] == null
          ? 'Thank you for your business!'
          : fields[0] as String,
      showUpiQr: fields[1] == null ? false : fields[1] as bool,
      upiId: fields[2] == null ? '' : fields[2] as String,
      upiQrImagePath: fields[3] == null ? '' : fields[3] as String,
      showCompanyLogo: fields[4] == null ? true : fields[4] as bool,
      termsAndConditions: fields[5] == null
          ? '1. Goods once sold will not be taken back.\n2. Subject to local jurisdiction.'
          : fields[5] as String,
      fontName: fields[6] == null ? 'Roboto' : fields[6] as String,
      updatedAt: fields[7] as DateTime?,
      showSignature: fields[8] == null ? true : fields[8] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, InvoiceSettingsModel obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.footerText)
      ..writeByte(1)
      ..write(obj.showUpiQr)
      ..writeByte(2)
      ..write(obj.upiId)
      ..writeByte(3)
      ..write(obj.upiQrImagePath)
      ..writeByte(4)
      ..write(obj.showCompanyLogo)
      ..writeByte(5)
      ..write(obj.termsAndConditions)
      ..writeByte(6)
      ..write(obj.fontName)
      ..writeByte(7)
      ..write(obj.updatedAt)
      ..writeByte(8)
      ..write(obj.showSignature);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvoiceSettingsModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
