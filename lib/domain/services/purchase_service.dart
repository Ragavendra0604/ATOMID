import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/ids.dart';
import 'package:atomid/data/models/action_history_model.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';

/// Statuses a purchase order can hold, in lifecycle order.
class PurchaseStatus {
  static const draft = 'Draft';
  static const issued = 'Issued';
  static const received = 'Received';
  static const cancelled = 'Cancelled';

  static const all = [draft, issued, received, cancelled];

  /// A received order has already moved stock and money; it is read-only.
  static bool isSettled(String status) => status == received;
}

class PurchaseService {
  final StorageRepository _repository;

  PurchaseService(this._repository);

  /// Persists a purchase and, when it crosses into [PurchaseStatus.received]
  /// for the first time, moves stock and credits the supplier ledger.
  ///
  /// [previousStatus] must be the status the record held *before* the caller
  /// mutated it. Re-reading it here does not work: Hive returns the same
  /// instance the caller just modified, so the transition is invisible and the
  /// stock-in silently never happens.
  Future<void> savePurchase(
    Purchase purchase, {
    bool isNew = false,
    String? previousStatus,
  }) async {
    if (purchase.items.isEmpty) {
      throw const AppException('A purchase needs at least one item.');
    }

    final priorStatus = isNew ? null : previousStatus;
    final becomesReceived =
        purchase.status == PurchaseStatus.received &&
        priorStatus != PurchaseStatus.received;

    purchase.updatedAt = DateTime.now();
    await _repository.savePurchase(purchase);

    if (becomesReceived) {
      for (final item in purchase.items) {
        item.receivedQuantity = item.quantity;
        await _repository.performStockIn(
          productId: item.productId,
          variantBarcode: item.variantBarcode,
          quantity: item.quantity,
          reason: 'PO Received (${purchase.purchaseNumber})',
          movementReferenceId: purchase.id,
          performedAt: 'Purchase from ${purchase.supplierName}',
        );
      }

      if (purchase.supplierId.isNotEmpty) {
        await _repository.addSupplierLedgerEntry(
          supplierId: purchase.supplierId,
          date: purchase.purchaseDate,
          transactionType: 'Purchase',
          referenceId: purchase.purchaseNumber,
          credit: purchase.grandTotal,
          notes: 'PO #${purchase.purchaseNumber} received',
        );
      }

      // Persist the receivedQuantity values written above.
      await _repository.savePurchase(purchase);
    }

    await _repository.saveHistory(
      ActionHistory(
        id: Ids.generate(),
        barcode: purchase.purchaseNumber,
        productName: 'Purchase from ${purchase.supplierName}',
        action:
            'PO ${isNew ? 'created' : 'updated'} · ${purchase.status} · '
            '${Fmt.amount(purchase.grandTotal)}',
        date: DateTime.now(),
      ),
    );
  }

  Future<void> markAsIssued(Purchase purchase) async {
    if (purchase.status != PurchaseStatus.draft) {
      throw const AppException('Only a draft order can be issued.');
    }
    final previous = purchase.status;
    purchase.status = PurchaseStatus.issued;
    await savePurchase(purchase, previousStatus: previous);
  }

  Future<void> markAsReceived(Purchase purchase) async {
    if (PurchaseStatus.isSettled(purchase.status)) {
      throw const AppException('This order has already been received.');
    }
    if (purchase.status == PurchaseStatus.cancelled) {
      throw const AppException('A cancelled order cannot be received.');
    }
    final previous = purchase.status;
    purchase.status = PurchaseStatus.received;
    await savePurchase(purchase, previousStatus: previous);
  }

  Future<void> cancel(Purchase purchase) async {
    if (PurchaseStatus.isSettled(purchase.status)) {
      throw const AppException(
        'A received order cannot be cancelled. Record a return instead.',
      );
    }
    final previous = purchase.status;
    purchase.status = PurchaseStatus.cancelled;
    await savePurchase(purchase, previousStatus: previous);
  }
}
