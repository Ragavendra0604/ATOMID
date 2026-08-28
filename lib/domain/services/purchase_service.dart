import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/ids.dart';
import 'package:atomid/data/models/action_history_model.dart';
import 'package:atomid/data/models/diagnostic_log_model.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/domain/gst/gst_engine.dart';
import 'package:atomid/domain/gst/gst_models.dart';
import 'package:atomid/domain/gst/gst_states.dart';

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

  /// Computes and freezes the GST breakdown for a purchase.
  ///
  /// Delegates every figure to [Gst.compute]. This method used to carry its
  /// own copy of the arithmetic, which had drifted from the engine in ways
  /// that all understated tax: a null rate became 0%, an unknown supplier
  /// state became the shop's own (so an inter-state purchase was booked as
  /// CGST + SGST), and an unconfigured shop fell back to a hardcoded Tamil
  /// Nadu. One authority now answers for both what the shop sells and what it
  /// buys.
  ///
  /// Throws [AppException] when the inputs cannot support a safe calculation.
  /// Blocking is the point: a purchase that cannot be taxed correctly must not
  /// be recorded with a plausible-looking wrong number.
  void computePurchaseGst(Purchase purchase) {
    final problem = tryComputePurchaseGst(purchase);
    if (problem != null) throw AppException(problem);
  }

  /// [computePurchaseGst] without the throw: returns the reason it could not
  /// compute, or null when it did.
  ///
  /// The purchase form builds a running preview on every keystroke, inside
  /// `build`. An exception there is an error screen rather than a message, so
  /// the live path asks for the reason and shows it while the save path
  /// throws and refuses.
  String? tryComputePurchaseGst(Purchase purchase) {
    final company = _repository.getCompany();
    final settings = _repository.getSettings();
    final supplier = _repository.getSupplierById(purchase.supplierId);

    // --- the shop, as recipient ------------------------------------------
    //
    // No hardcoded state. If the business has not been configured, that is a
    // setup error the shopkeeper can fix, not something to paper over.
    final shop = GstStates.resolvePartyState(
      label: 'Shop',
      stateCode: company.stateCode,
      stateName: company.state,
      gstin: company.gstNumber,
    );
    if (!shop.isResolved) {
      return '${shop.error} Set it in Settings > Business Details.';
    }

    // --- the supplier, as the party supplying ------------------------------
    //
    // The order's own copy wins over the supplier master, so a correction made
    // on one order never rewrites another. A GSTIN is read for its state
    // prefix only when no state was recorded, and a GSTIN that disagrees with
    // a recorded state blocks rather than picking a side.
    final supplierState = GstStates.resolvePartyState(
      label: 'Supplier',
      stateCode: purchase.supplierStateCode.isNotEmpty
          ? purchase.supplierStateCode
          : supplier?.stateCode,
      stateName: purchase.supplierState.isNotEmpty
          ? purchase.supplierState
          : supplier?.state,
      gstin: purchase.supplierGstin.isNotEmpty
          ? purchase.supplierGstin
          : supplier?.gstNumber,
    );
    if (!supplierState.isResolved) {
      return supplierState.error;
    }

    final lines = [
      for (final item in purchase.items)
        GstLineInput(
          productId: item.productId,
          productName: item.productName,
          variantBarcode: item.variantBarcode,
          variantSize: item.variantSize,
          unitPrice: item.costPrice,
          quantity: item.quantity,
          hsn: item.hsn,
          uqc: item.uqc.isNotEmpty ? item.uqc : settings.defaultUqc,
          gstTreatment: item.gstTreatment,
          gstRate: item.gstRate,
          cessRate: item.cessRate,
          gstRateConfigId: item.gstRateConfigId,
          lineDiscount: item.discountAmount,
        ),
    ];

    final result = Gst.compute(
      GstCalculationInput(
        transactionDate: purchase.purchaseDate,
        // The supplier is the one making the supply, so it is the seller here;
        // the place of supply is this shop.
        sellerState: supplierState.state!.name,
        sellerStateCode: supplierState.state!.code,
        sellerGstin: purchase.supplierGstin.isNotEmpty
            ? purchase.supplierGstin
            : (supplier?.gstNumber ?? ''),
        customerState: shop.state!.name,
        customerStateCode: shop.state!.code,
        customerGstin: company.gstNumber,
        destinationStateCode: shop.state!.code,
        pricingMode: purchase.pricingMode,
        isWalkIn: false,
        roundOffEnabled: settings.roundOffEnabled,
        lines: lines,
      ),
    );

    if (!result.isValid) {
      return 'Cannot calculate GST on this purchase:\n'
          '• ${result.errors.join('\n• ')}';
    }

    for (var i = 0; i < purchase.items.length; i++) {
      final item = purchase.items[i];
      final line = result.lines[i];
      item.gstTreatment = line.gstTreatment;
      item.gstRate = line.gstRate;
      item.cessRate = line.cessRate;
      item.gstRateConfigId = line.gstRateConfigId;
      item.discountAmount = line.discountAllocated;
      item.taxableValue = line.taxableValue;
      item.cgstAmount = line.cgstAmount;
      item.sgstAmount = line.sgstAmount;
      item.utgstAmount = line.utgstAmount;
      item.igstAmount = line.igstAmount;
      item.cessAmount = line.cessAmount;
      item.lineTotal = line.lineTotal;
    }

    purchase.isInterState = result.isInterState;
    purchase.supplierState = supplierState.state!.name;
    purchase.supplierStateCode = supplierState.state!.code;
    if (purchase.supplierGstin.isEmpty && supplier != null) {
      purchase.supplierGstin = supplier.gstNumber;
    }

    // Recipient snapshot, frozen with the figures it produced.
    purchase.recipientName = company.name;
    purchase.recipientGstin = company.gstNumber;
    purchase.recipientState = shop.state!.name;
    purchase.recipientStateCode = shop.state!.code;

    purchase.subtotal = result.subtotal;
    purchase.discount = result.discountAmount;
    purchase.taxableAmount = result.taxableAmount;
    purchase.cgstAmount = result.cgstAmount;
    purchase.sgstAmount = result.sgstAmount;
    purchase.utgstAmount = result.utgstAmount;
    purchase.igstAmount = result.igstAmount;
    purchase.cessAmount = result.cessAmount;
    purchase.tax = result.totalTax;
    purchase.preRoundTotal = result.preRoundTotal;
    purchase.roundOff = result.roundOff;
    purchase.grandTotal = result.payableAmount;
    return null;
  }

  /// Persists a purchase and, when it crosses into [PurchaseStatus.received]
  /// for the first time, moves stock and credits the supplier ledger.
  Future<void> savePurchase(
    Purchase purchase, {
    bool isNew = false,
    String? previousStatus,
  }) async {
    if (purchase.items.isEmpty) {
      throw const AppException('A purchase needs at least one item.');
    }

    // Always ensure statutory GST calculation is computed on the purchase
    computePurchaseGst(purchase);

    final priorStatus = isNew ? null : previousStatus;
    final becomesReceived =
        purchase.status == PurchaseStatus.received &&
        priorStatus != PurchaseStatus.received;

    if (becomesReceived) {
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

        undo.add(() => _repository.deleteSupplierLedgerEntry(ledgerId));
      }

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
