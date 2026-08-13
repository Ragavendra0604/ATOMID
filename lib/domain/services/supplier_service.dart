import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:uuid/uuid.dart';
import 'package:atomid/data/models/action_history_model.dart';

class SupplierService {
  final StorageRepository _repository;
  final Uuid _uuid = const Uuid();

  SupplierService(this._repository);

  bool isDuplicate(String code, {String? excludeId}) {
    if (code.isEmpty) return false;
    return _repository.isSupplierCodeDuplicate(code, excludeId: excludeId);
  }

  Future<void> saveSupplier(
    Supplier supplier, {
    bool isNew = false,
    double openingBalance = 0,
  }) async {
    final now = DateTime.now();

    await _repository.saveSupplier(supplier);

    await _repository.saveHistory(
      ActionHistory(
        id: _uuid.v4(),
        barcode: supplier.supplierCode,
        productName: supplier.supplierName,
        action: isNew ? 'Supplier Created' : 'Supplier Updated',
        date: now,
      ),
    );

    if (isNew && openingBalance > 0) {
      await _repository.addSupplierLedgerEntry(
        supplierId: supplier.id,
        date: now,
        transactionType: 'Opening Balance',
        referenceId:
            'OPENING-${now.millisecondsSinceEpoch.toString().substring(5)}',
        credit: openingBalance, // We owe them money from start
        notes: 'Initial account balance',
      );
    }
  }

  Future<void> deleteSupplier(Supplier supplier) async {
    await _repository.saveHistory(
      ActionHistory(
        id: _uuid.v4(),
        barcode: supplier.supplierCode,
        productName: supplier.supplierName,
        action: 'Supplier Deleted',
        date: DateTime.now(),
      ),
    );
    await _repository.deleteSupplier(supplier.id);
  }
}
