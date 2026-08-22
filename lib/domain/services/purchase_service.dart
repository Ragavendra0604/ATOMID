import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/ids.dart';
import 'package:atomid/data/models/action_history_model.dart';
import 'package:atomid/data/models/diagnostic_log_model.dart';
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
  ///
  /// A multi-item order used to be saved as `Received` first and only then
  /// stocked in one item at a time; if a later line failed (its product or
  /// variant had since been deleted — routine, for an order sitting in
  /// `Issued` for a while) the order was left `Received` with only some of
  /// its stock actually moved and the supplier never credited. Because a
  /// `Received` order is settled — [PurchaseStatus.isSettled] blocks both
  /// retrying and cancelling it — that order had no way back except editing
  /// Hive by hand. Every line is now validated up front, and the status is
  /// only written as `Received` once receiving has fully succeeded; if a
  /// later step still fails, the stock already moved for this attempt is
  /// unwound and the order is left exactly as it was before the attempt.
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

    if (becomesReceived) {
      // Hold the status back until receiving actually succeeds, before
      // validating — so a rejected receive leaves the object's in-memory
      // status matching what is (and stays) on disk, not stuck showing
      // "Received" for a save that never happened.
      purchase.status = priorStatus ?? PurchaseStatus.issued;
      _assertReceivable(purchase);
    }

    purchase.updatedAt = DateTime.now();
    await _repository.savePurchase(purchase);

    if (becomesReceived) {
      await _receive(purchase, priorStatus);
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

  /// Rejects a receive attempt before anything is written, if any line can't
  /// actually be stocked in.
  void _assertReceivable(Purchase purchase) {
    for (final item in purchase.items) {
      final product = _repository.getProductById(item.productId);
      final variant = product?.variants.cast<dynamic>().firstWhere(
        (v) => v.barcode == item.variantBarcode,
        orElse: () => null,
      );
      if (product == null || variant == null) {
        throw AppException(
          '${item.productName} (${item.variantSize}) is no longer in your '
          'catalogue — remove it from the order before receiving.',
        );
      }
      if (item.quantity <= 0) {
        throw AppException(
          '${item.productName}: quantity must be greater than 0.',
        );
      }
    }
  }

  /// Moves stock, credits the supplier, and only then marks the order
  /// received. Unwinds everything it already did if a later step fails.
  Future<void> _receive(Purchase purchase, String? priorStatus) async {
    final undo = <Future<void> Function()>[];

    try {
      for (final item in purchase.items) {
        await _repository.performStockIn(
          productId: item.productId,
          variantBarcode: item.variantBarcode,
          quantity: item.quantity,
          reason: 'PO Received (${purchase.purchaseNumber})',
          movementReferenceId: purchase.id,
          performedAt: 'Purchase from ${purchase.supplierName}',
        );
        item.receivedQuantity = item.quantity;
        undo.add(
          () => _repository.performStockOut(
            productId: item.productId,
            variantBarcode: item.variantBarcode,
            quantity: item.quantity,
            reason: 'Reversal of failed PO receipt',
            movementReferenceId: purchase.id,
            performedAt: 'System',
          ),
        );
      }

      if (purchase.supplierId.isNotEmpty) {
        final ledgerId = await _repository.addSupplierLedgerEntry(
          supplierId: purchase.supplierId,
          date: purchase.purchaseDate,
          transactionType: 'Purchase',
          referenceId: purchase.purchaseNumber,
          credit: purchase.grandTotal,
          notes: 'PO #${purchase.purchaseNumber} received',
        );

        // Registered like every other step. Without it, a failure in the
        // savePurchase below unwound the stock but left the supplier credited
        // for goods the order still says were never received — the shop owing
        // money its own records do not account for.
        undo.add(() => _repository.deleteSupplierLedgerEntry(ledgerId));
      }

      // Every line moved and the supplier is credited — now it is safe to
      // call this order Received.
      purchase.status = PurchaseStatus.received;
      await _repository.savePurchase(purchase);
    } catch (error, stack) {
      debugPrint('Receiving failed, unwinding: $error\n$stack');
      await _repository.recordDiagnostic(
        severity: DiagnosticSeverity.warning,
        area: DiagnosticArea.receiving,
        reference: purchase.purchaseNumber,
        message: 'Receiving failed and was reversed.',
        error: error,
        stack: stack,
      );
      for (final step in undo.reversed) {
        try {
          await step();
        } catch (undoError, undoStack) {
          debugPrint(
            'Reversal step failed for PO ${purchase.purchaseNumber}: $undoError',
          );
          // As in checkout: the contained failure is a warning, but a failed
          // reversal means received stock or the supplier ledger no longer
          // matches this order.
          await _repository.recordDiagnostic(
            severity: DiagnosticSeverity.error,
            area: DiagnosticArea.receiving,
            reference: purchase.purchaseNumber,
            message:
                'A step of the receiving reversal failed. Stock or the '
                'supplier ledger may not match this order.',
            error: undoError,
            stack: undoStack,
          );
        }
      }
      for (final item in purchase.items) {
        item.receivedQuantity = 0;
      }
      purchase.status = priorStatus ?? PurchaseStatus.issued;
      await _repository.savePurchase(purchase);
      rethrow;
    }
  }
}
