import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/ids.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/domain/pricing.dart';
import 'package:atomid/domain/services/session_service.dart';
import 'package:atomid/presentation/providers/cart_notifier.dart';

/// Everything the till needs to commit a sale.
class CheckoutRequest {
  final List<CartItem> items;
  final Customer? customer;
  final String paymentMethod;
  final String notes;

  /// What the cashier typed into the discount box, as a percentage of the
  /// subtotal. Percentages are what a till operator thinks in, and they scale
  /// with the basket rather than needing mental arithmetic per sale.
  final double discountPercent;

  final bool redeemPoints;
  final String createdBy;

  const CheckoutRequest({
    required this.items,
    required this.paymentMethod,
    this.customer,
    this.notes = '',
    this.discountPercent = 0,
    this.redeemPoints = false,
    this.createdBy = 'POS',
  });

  bool get isCredit => paymentMethod.toLowerCase() == 'credit';
}

/// Owns the checkout transaction.
///
/// A sale touches five stores — sales, products, movements, ledger, loyalty.
/// Hive has no multi-box transaction, so every write is recorded as it happens
/// and unwound in reverse if a later step fails. Without this a failure part
/// way through left a committed sale, a debited customer and stock deducted
/// for only some of the basket.
class SaleService {
  final StorageRepository _repo;
  final SessionService _session;

  SaleService(this._repo, this._session);

  /// Prices a cart without committing anything. Used to render the checkout
  /// summary so the preview and the receipt come from one calculation.
  SaleTotals preview(CheckoutRequest request) {
    return SalePricing.compute(
      lineItemTotal: request.items.fold(0.0, (sum, i) => sum + i.total),
      settings: _repo.getSettings(),
      loyalty: _repo.getLoyaltySettings(),
      requestedDiscountPercent: request.discountPercent,
      availablePoints: request.customer?.totalRewardPoints ?? 0,
      redeemPoints: request.redeemPoints,
    );
  }

  /// Validates and commits a sale, or throws having changed nothing.
  Future<Sale> checkout(CheckoutRequest request) async {
    if (request.items.isEmpty) {
      throw const AppException('Add at least one item before checking out.');
    }

    _assertStockAvailable(request);

    final totals = preview(request);
    _assertCreditAllowed(request, totals);

    final now = DateTime.now();
    final sale = Sale(
      id: Ids.generate(),
      invoiceNumber: _repo.getNextInvoiceNumber(),
      date: now,
      customerId: request.customer?.id ?? '',
      customerName: request.customer?.name ?? 'Walk-In Customer',
      items: request.items
          .map(
            (item) => SaleItem(
              productId: item.product.id,
              productName: item.product.productName,
              productCode: item.product.productCode,
              variantBarcode: item.variant.barcode,
              variantSize: item.variant.size,
              price: item.variant.price,
              quantity: item.quantity,
              total: Fmt.round2(item.total),
            ),
          )
          .toList(),
      subtotal: totals.subtotal,
      discountPercent: totals.discountPercent,
      discountAmount: totals.manualDiscount,
      rewardDiscountAmount: totals.rewardDiscount,
      rewardPointsEarned: totals.pointsEarned,
      taxAmount: totals.taxAmount,
      grandTotal: totals.grandTotal,
      paymentMethod: request.paymentMethod,
      notes: request.notes,
      deviceId: _session.deviceId,
      createdBy: request.createdBy,
      updatedAt: now,
    );

    final undo = <Future<void> Function()>[];

    try {
      await _repo.saveSale(sale);
      undo.add(() => _repo.deleteSale(sale.id));

      for (final item in request.items) {
        await _repo.performStockOut(
          productId: item.product.id,
          variantBarcode: item.variant.barcode,
          quantity: item.quantity,
          reason: 'Sale (${sale.invoiceNumber})',
          movementReferenceId: sale.id,
          performedAt: request.createdBy,
        );
        undo.add(
          () => _repo.performStockIn(
            productId: item.product.id,
            variantBarcode: item.variant.barcode,
            quantity: item.quantity,
            reason: 'Reversal of failed sale',
            movementReferenceId: sale.id,
            performedAt: 'System',
          ),
        );
      }

      if (request.customer != null) {
        await _recordLedger(sale, request, undo);
        await _recordLoyalty(sale, request, totals, undo);
        await _updateLifetimeSpend(request.customer!, totals.grandTotal, undo);
      }

      return sale;
    } catch (error, stack) {
      debugPrint('Checkout failed, unwinding: $error\n$stack');
      await _unwind(undo, sale);
      rethrow;
    }
  }

  void _assertStockAvailable(CheckoutRequest request) {
    // Sum per variant: the same variant can appear once but with a quantity
    // that has since outrun the shelf.
    final wanted = <String, int>{};
    for (final item in request.items) {
      wanted.update(
        item.variant.barcode,
        (value) => value + item.quantity,
        ifAbsent: () => item.quantity,
      );
    }

    for (final item in request.items) {
      final product = _repo.getProductById(item.product.id);
      if (product == null) {
        throw AppException(
          '${item.product.productName} is no longer in your catalogue.',
        );
      }
      final variant = product.variants.cast<dynamic>().firstWhere(
        (v) => v.barcode == item.variant.barcode,
        orElse: () => null,
      );
      if (variant == null) {
        throw AppException(
          '${item.product.productName} (${item.variant.size}) is no longer available.',
        );
      }
      final required = wanted[item.variant.barcode] ?? item.quantity;
      if (variant.quantity < required) {
        throw AppException(
          'Only ${variant.quantity} left of ${item.product.productName} '
          '(${item.variant.size}) — the basket has $required.',
        );
      }
    }
  }

  void _assertCreditAllowed(CheckoutRequest request, SaleTotals totals) {
    final customer = request.customer;
    if (!request.isCredit) return;

    if (customer == null) {
      throw const AppException(
        'Select a customer before taking a sale on credit.',
      );
    }
    if (customer.creditLimit <= 0) return; // no limit configured

    final projected = customer.currentBalance + totals.grandTotal;
    if (projected > customer.creditLimit) {
      final symbol = _repo.getSettings().currencySymbol;
      throw AppException(
        'This would take ${customer.name} to ${Fmt.money(projected, symbol)}, '
        'over their ${Fmt.money(customer.creditLimit, symbol)} credit limit.',
      );
    }
  }

  /// Registers each reversal onto [undo] as its write lands, so a failure on
  /// the second leg still unwinds the first.
  Future<void> _recordLedger(
    Sale sale,
    CheckoutRequest request,
    List<Future<void> Function()> undo,
  ) async {
    final debitId = await _repo.addLedgerEntry(
      customerId: sale.customerId,
      date: sale.date,
      transactionType: 'Sale',
      referenceId: sale.invoiceNumber,
      debit: sale.grandTotal,
      notes: 'Invoice ${sale.invoiceNumber}',
    );
    undo.add(() => _repo.deleteLedgerEntry(debitId));

    if (!request.isCredit) {
      final creditId = await _repo.addLedgerEntry(
        customerId: sale.customerId,
        date: sale.date,
        transactionType: 'Payment',
        referenceId: sale.invoiceNumber,
        credit: sale.grandTotal,
        notes: 'Paid by ${sale.paymentMethod}',
      );
      undo.add(() => _repo.deleteLedgerEntry(creditId));
    }
  }

  /// Registers each reversal onto [undo] as its write lands, so a failure on
  /// the earn leg still unwinds the redemption.
  Future<void> _recordLoyalty(
    Sale sale,
    CheckoutRequest request,
    SaleTotals totals,
    List<Future<void> Function()> undo,
  ) async {
    if (totals.rewardDiscount > 0) {
      final redeemId = await _repo.addLoyaltyTransaction(
        customerId: sale.customerId,
        saleId: sale.id,
        transactionType: 'Redeem',
        points: -totals.pointsRedeemed,
        monetaryValue: totals.rewardDiscount,
        reference: sale.invoiceNumber,
        createdBy: request.createdBy,
      );
      undo.add(() => _repo.deleteLoyaltyTransaction(redeemId));
    }

    if (totals.pointsEarned > 0) {
      final earnId = await _repo.addLoyaltyTransaction(
        customerId: sale.customerId,
        saleId: sale.id,
        transactionType: 'Earn',
        points: totals.pointsEarned,
        monetaryValue: 0,
        reference: sale.invoiceNumber,
        createdBy: request.createdBy,
      );
      undo.add(() => _repo.deleteLoyaltyTransaction(earnId));
    }
  }

  /// Adds to the customer's lifetime spend and registers the restore on [undo].
  Future<void> _updateLifetimeSpend(
    Customer customer,
    double amount,
    List<Future<void> Function()> undo,
  ) async {
    final stored = _repo.getCustomerById(customer.id);
    if (stored == null) return;

    final previousSpend = stored.lifetimeSpend;
    final previousUpdatedAt = stored.updatedAt;

    stored.lifetimeSpend = Fmt.round2(stored.lifetimeSpend + amount);
    stored.updatedAt = DateTime.now();
    await _repo.saveCustomer(stored);

    undo.add(() async {
      final current = _repo.getCustomerById(customer.id);
      if (current == null) return;
      current.lifetimeSpend = previousSpend;
      current.updatedAt = previousUpdatedAt;
      await _repo.saveCustomer(current);
    });
  }

  /// Runs compensating actions newest-first. Each is isolated: one failing
  /// reversal must not prevent the others from running.
  Future<void> _unwind(List<Future<void> Function()> undo, Sale sale) async {
    for (final step in undo.reversed) {
      try {
        await step();
      } catch (e) {
        debugPrint('Reversal step failed for sale ${sale.invoiceNumber}: $e');
      }
    }
  }
}
