// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'supplier_ledger_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SupplierLedgerAdapter extends TypeAdapter<SupplierLedger> {
  @override
  final typeId = 22;

  @override
  SupplierLedger read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SupplierLedger(
      id: fields[0] as String,
      supplierId: fields[1] as String,
      date: fields[2] as DateTime,
      transactionType: fields[3] as String,
      referenceId: fields[4] as String,
      credit: fields[5] == null ? 0 : (fields[5] as num).toDouble(),
      debit: fields[6] == null ? 0 : (fields[6] as num).toDouble(),
      balance: fields[7] == null ? 0 : (fields[7] as num).toDouble(),
      notes: fields[8] == null ? '' : fields[8] as String,
    );
  }

  @override
  void write(BinaryWriter writer, SupplierLedger obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.supplierId)
      ..writeByte(2)
      ..write(obj.date)
      ..writeByte(3)
      ..write(obj.transactionType)
      ..writeByte(4)
      ..write(obj.referenceId)
      ..writeByte(5)
      ..write(obj.credit)
      ..writeByte(6)
      ..write(obj.debit)
      ..writeByte(7)
      ..write(obj.balance)
      ..writeByte(8)
      ..write(obj.notes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupplierLedgerAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
