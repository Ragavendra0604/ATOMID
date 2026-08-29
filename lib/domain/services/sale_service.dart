import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/ids.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/diagnostic_log_model.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/domain/cart_item.dart';
import 'package:atomid/domain/pricing.dart';
import 'package:atomid/domain/services/session_service.dart';

/// Everything the till needs to commit a sale.
class CheckoutRequest {
  final List<CartItem> items;
  final Customer? customer;
  final String paymentMethod;
  final String notes;

  /// What the cashier typed into the discount box, as a percentage of the subtotal.
  final double discountPercent;

  /// Explicit delivery destination state code if different from customer/shop.
  final String? destinationStateCode;

  final bool redeemPoints;
  final String createdBy;

  const CheckoutRequest({
    required this.items,
    required this.paymentMethod,
    this.customer,
    this.notes = '',
    this.discountPercent = 0,
    this.destinationStateCode,
    this.redeemPoints = false,
    this.createdBy = 'POS',
  });

  bool get isCredit => paymentMethod.toLowerCase() == 'credit';
}

/// Owns the checkout transaction with complete statutory GST snapshotting.
class SaleService {
  final StorageRepository _repo;
  final SessionService _session;

  SaleService(this._repo, this._session);

  Customer? _currentCustomer(CheckoutRequest request) {
    final requested = request.customer;
    if (requested == null) return null;
    return _repo.getCustomerById(requested.id) ?? requested;
  }

  /// Prices a cart using the central GST engine without committing anything.
  SaleTotals preview(CheckoutRequest request, {DateTime? date}) {
    return SalePricing.computeCart(
      items: request.items,
      settings: _repo.getSettings(),
      loyalty: _repo.getLoyaltySettings(),
      company: _repo.getCompany(),
      customer: _currentCustomer(request),
      destinationStateCode: request.destinationStateCode,
      requestedDiscountPercent: request.discountPercent,
      availablePoints: _currentCustomer(request)?.totalRewardPoints ?? 0,
      redeemPoints: request.redeemPoints,
      transactionDate: date,
    );
  }

  /// Validates and commits a sale with complete GST snapshotting, or throws having changed nothing.
  Future<Sale> checkout(CheckoutRequest request) async {
    if (request.items.isEmpty) {
      throw const AppException('Add at least one item before checking out.');
    }

    _assertStockAvailable(request);

    final now = DateTime.now();
    final totals = preview(request, date: now);

    if (totals.gstResult != null && !totals.gstResult!.isValid) {
      final errorList = totals.gstResult!.errors.join('\n• ');
      throw AppException('Cannot complete billing:\n• $errorList');
    }

    _assertCreditAllowed(request, totals);

    final company = _repo.getCompany();
    final settings = _repo.getSettings();
    final customer = _currentCustomer(request);

    final gstRes = totals.gstResult;

    final saleItems = <SaleItem>[];
    for (int i = 0; i < request.items.length; i++) {
      final item = request.items[i];
      final lineRes = (gstRes != null && i < gstRes.lines.length)
          ? gstRes.lines[i]
          : null;

      saleItems.add(
        SaleItem(
          productId: item.product.id,
          // The colour is part of what was sold, not decoration: one product
          // code covers several colourways, so a bill reading only "Cotton
          // Shirt (M)" does not tell the customer which shirt they bought.
          // Snapshotted into the existing name field, so no schema change
          // and every historical sale is left exactly as it was recorded.
          productName: item.product.displayName,
          productCode: item.product.productCode,
          variantBarcode: item.variant.barcode,
          variantSize: item.variant.size,
          price: item.variant.price,
          quantity: item.quantity,
          total: lineRes != null ? lineRes.lineTotal : Fmt.round2(item.total),
          hsn: lineRes?.hsn ?? item.product.hsn,
          uqc:
              lineRes?.uqc ??
              (item.product.uqc.isNotEmpty
                  ? item.product.uqc
                  : settings.defaultUqc),
          gstRate: lineRes?.gstRate ?? item.product.gstRate,
          gstTreatment: lineRes?.gstTreatment ?? item.product.gstTreatment,
          cessRate: lineRes?.cessRate ?? item.product.cessRate,
          taxableValue: lineRes?.taxableValue ?? 0.0,
          discountAmount: lineRes?.discountAllocated ?? 0.0,
          cgstAmount: lineRes?.cgstAmount ?? 0.0,
          sgstAmount: lineRes?.sgstAmount ?? 0.0,
          utgstAmount: lineRes?.utgstAmount ?? 0.0,
          igstAmount: lineRes?.igstAmount ?? 0.0,
          cessAmount: lineRes?.cessAmount ?? 0.0,
          gstRateConfigId:
              lineRes?.gstRateConfigId ?? item.product.gstRateConfigId,
        ),
      );
    }

    final docType = (company.isGstRegistered || totals.taxAmount > 0)
        ? 'Tax Invoice'
        : 'Bill of Supply';

    final sale = Sale(
      id: Ids.generate(),
      invoiceNumber: _repo.getNextInvoiceNumber(),
      date: now,
      customerId: customer?.id ?? '',
      customerName: customer?.name ?? 'Walk-In Customer',
      items: saleItems,
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
      sellerGstin: company.gstNumber,
      sellerState: company.state,
      sellerStateCode: company.stateCode,
      sellerLegalName: company.name,
      sellerAddress: company.address,
      customerGstin: customer?.gstNumber ?? '',
      customerState: customer?.state ?? '',
      customerStateCode: customer?.stateCode ?? '',
      customerAddress: customer?.address ?? '',
      customerPhone: customer?.mobile ?? '',
      placeOfSupply: totals.placeOfSupply,
      placeOfSupplyBasis: gstRes?.placeOfSupplyBasis ?? '',
      pricingMode: settings.taxMode,
      taxableAmount: totals.taxableAmount,
      cgstAmount: totals.cgstAmount,
      sgstAmount: totals.sgstAmount,
      utgstAmount: totals.utgstAmount,
      igstAmount: totals.igstAmount,
      cessAmount: totals.cessAmount,
      preRoundTotal: totals.preRoundTotal,
      roundOff: totals.roundOff,
      documentType: docType,
      isInterState: totals.isInterState,
    );

    final undo = <Future<void> Function()>[];

    final storedCustomer = customer == null
        ? null
        : _repo.getCustomerById(customer.id);
    await _repo.openCheckoutJournal(
      saleId: sale.id,
      invoiceNumber: sale.invoiceNumber,
      customerId: customer?.id ?? '',
      previousLifetimeSpend: storedCustomer?.lifetimeSpend,
      previousUpdatedAt: storedCustomer?.updatedAt,
    );

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

      if (customer != null) {
        await _recordLedger(sale, request, undo);
        await _recordLoyalty(sale, request, totals, undo);
        await _updateLifetimeSpend(customer, totals.grandTotal, undo);
      }

      await _repo.closeCheckoutJournal(sale.id);
      return sale;
    } catch (error, stack) {
      debugPrint('Checkout failed, unwinding: $error\n$stack');
      await _repo.recordDiagnostic(
        severity: DiagnosticSeverity.warning,
        area: DiagnosticArea.checkout,
        reference: sale.invoiceNumber,
        message: 'Checkout failed and was reversed.',
        error: error,
        stack: stack,
      );
      await _unwind(undo, sale);
      await _repo.closeCheckoutJournal(sale.id);
      rethrow;
    }
  }

  void _assertStockAvailable(CheckoutRequest request) {
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
    final customer = _currentCustomer(request);
    if (!request.isCredit) return;

    if (customer == null) {
      throw const AppException(
        'Select a customer before taking a sale on credit.',
      );
    }
    if (customer.creditLimit <= 0) return;

    final projected = customer.currentBalance + totals.grandTotal;
    if (projected > customer.creditLimit) {
      final symbol = _repo.getSettings().currencySymbol;
      throw AppException(
        'This would take ${customer.name} to ${Fmt.money(projected, symbol)}, '
        'over their ${Fmt.money(customer.creditLimit, symbol)} credit limit.',
      );
    }
  }

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

  Future<void> _unwind(List<Future<void> Function()> undo, Sale sale) async {
    for (final step in undo.reversed) {
      try {
        await step();
      } catch (e, stack) {
        debugPrint('Reversal step failed for sale ${sale.invoiceNumber}: $e');
        await _repo.recordDiagnostic(
          severity: DiagnosticSeverity.error,
          area: DiagnosticArea.checkout,
          reference: sale.invoiceNumber,
          message:
              'A step of the checkout reversal failed. Stock or the customer '
              'ledger may not match this invoice.',
          error: e,
          stack: stack,
        );
      }
    }
  }
}
