import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/data/models/action_history_model.dart';

class PurchaseService {
  final StorageRepository _repository;

  PurchaseService(this._repository);

  Future<void> savePurchase(Purchase purchase, {bool isNew = false}) async {
    final now = DateTime.now();
    
    // Default to received for older items or direct purchases
    bool wasDraftOrIssued = true;
    
    if (!isNew) {
      final existing = _repository.getPurchaseById(purchase.id);
      if (existing != null && (existing.status == 'Received' || existing.status == 'Partially Received')) {
        wasDraftOrIssued = false;
      }
    }

    await _repository.savePurchase(purchase);

    // If it transitions to Received and hasn't been received before
    if (purchase.status == 'Received' && wasDraftOrIssued) {
      // 1. Perform Stock In for all items
      for (var item in purchase.items) {
        await _repository.performStockIn(
          productId: item.productId,
          variantBarcode: item.variantBarcode,
          quantity: item.quantity,
          reason: 'PO Received (${purchase.purchaseNumber})',
          movementReferenceId: purchase.id,
          performedAt: 'Purchase from ${purchase.supplierName}',
        );
      }

      // 2. Credit Supplier Ledger
      if (purchase.supplierId.isNotEmpty) {
        await _repository.addSupplierLedgerEntry(
          supplierId: purchase.supplierId,
          date: purchase.purchaseDate,
          transactionType: 'Purchase',
          referenceId: purchase.purchaseNumber,
          credit: purchase.grandTotal,
          notes: 'PO #${purchase.purchaseNumber} Received',
        );
      }
    }

    await _repository.saveHistory(
      ActionHistory(
        id: '${purchase.id}_purchase_action',
        barcode: purchase.purchaseNumber,
        productName: 'Purchase from ${purchase.supplierName}',
        action: 'PO ${isNew ? 'Created' : 'Updated'} (Status: ${purchase.status}, Total: ${purchase.grandTotal.toStringAsFixed(2)})',
        date: now,
      ),
    );
  }

  Future<void> markAsIssued(Purchase purchase) async {
    purchase.status = 'Issued';
    purchase.updatedAt = DateTime.now();
    await savePurchase(purchase);
  }

  Future<void> markAsReceived(Purchase purchase) async {
    purchase.status = 'Received';
    purchase.updatedAt = DateTime.now();
    
    // Mark all items as fully received
    for (var item in purchase.items) {
      item.receivedQuantity = item.quantity;
    }
    
    await savePurchase(purchase);
  }
}
