import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atomid/core/utils/ids.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/domain/services/sale_service.dart';
import 'package:atomid/domain/services/session_service.dart';
import 'package:atomid/presentation/providers/cart_notifier.dart';

import '../support/test_store.dart';

class MockSessionService extends Mock implements SessionService {}

/// Cover for a checkout the process does not live to finish.
///
/// [SaleService]'s undo list handles a failure it can catch. It cannot handle
/// the till losing power part way through, because the list dies with the
/// process — leaving a committed sale, stock off the shelf for only some of
/// the basket, and a customer charged for it. These exercise the durable
/// journal that closes that gap.
///
/// A crash is simulated the honest way: the writes a checkout would have made
/// are made, and then the in-memory unwind is simply never given the chance
/// to run — which is exactly what a power cut looks like on disk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;
  late SaleService sales;

  setUp(() async {
    store = await TestStore.open();
    final session = MockSessionService();
    when(() => session.deviceId).thenReturn('dev_test_abcd');
    sales = SaleService(store.repository, session);
  });

  tearDown(() => store.close());

  /// Leaves the store in the state a power cut mid-checkout would leave it:
  /// journal open, sale committed, only the first line's stock deducted.
  Future<Sale> crashPartWayThroughCheckout({
    required String productAId,
    required String barcodeA,
    required String productBId,
    required String barcodeB,
    String customerId = '',
    double? previousLifetimeSpend,
  }) async {
    final sale = Sale(
      id: Ids.generate(),
      invoiceNumber: store.repository.getNextInvoiceNumber(),
      date: DateTime.now(),
      customerId: customerId,
      customerName: customerId.isEmpty ? 'Walk-In Customer' : 'Asha',
      subtotal: 400,
      discountPercent: 0,
      discountAmount: 0,
      taxAmount: 0,
      grandTotal: 400,
      paymentMethod: 'Cash',
      items: [
        SaleItem(
          productId: productAId,
          productName: 'A',
          productCode: 'A',
          variantBarcode: barcodeA,
          variantSize: 'M',
          price: 200,
          quantity: 1,
          total: 200,
        ),
        SaleItem(
          productId: productBId,
          productName: 'B',
          productCode: 'B',
          variantBarcode: barcodeB,
          variantSize: 'M',
          price: 200,
          quantity: 1,
          total: 200,
        ),
      ],
    );

    await store.repository.openCheckoutJournal(
      saleId: sale.id,
      invoiceNumber: sale.invoiceNumber,
      customerId: customerId,
      previousLifetimeSpend: previousLifetimeSpend,
    );
    await store.repository.saveSale(sale);
    // Only the first line's stock comes off — then the lights go out.
    await store.repository.performStockOut(
      productId: productAId,
      variantBarcode: barcodeA,
      quantity: 1,
      reason: 'Sale (${sale.invoiceNumber})',
      movementReferenceId: sale.id,
    );
    return sale;
  }

  test('a completed checkout leaves nothing for recovery to do', () async {
    final product = await store.addProduct(price: 200, quantity: 10);
    final customer = await store.addCustomer();

    final sale = await sales.checkout(
      CheckoutRequest(
        items: [CartItem(product: product, variant: product.variants.first)],
        customer: customer,
        paymentMethod: 'Cash',
      ),
    );

    expect(store.repository.hasOpenCheckoutJournal(sale.id), isFalse);
    expect(await store.repository.recoverInterruptedCheckouts(), isEmpty);
    expect(store.repository.getSaleById(sale.id), isNotNull);
    expect(
      store.repository.getProductById(product.id)!.variants.first.quantity,
      9,
      reason: 'a successful sale must not be reversed',
    );
  });

  test('a checkout that throws also leaves nothing behind', () async {
    final product = await store.addProduct(price: 100, quantity: 1);
    // Credit limit is breached, so checkout throws and unwinds in memory.
    final customer = await store.addCustomer(creditLimit: 10);

    await expectLater(
      sales.checkout(
        CheckoutRequest(
          items: [CartItem(product: product, variant: product.variants.first)],
          customer: customer,
          paymentMethod: 'Credit',
        ),
      ),
      throwsA(anything),
    );

    expect(await store.repository.recoverInterruptedCheckouts(), isEmpty);
  });

  test('an interrupted checkout is fully reversed', () async {
    final productA = await store.addProduct(
      code: 'A',
      barcode: 'BC-A',
      price: 200,
      quantity: 10,
    );
    final productB = await store.addProduct(
      code: 'B',
      barcode: 'BC-B',
      price: 200,
      quantity: 10,
    );

    final sale = await crashPartWayThroughCheckout(
      productAId: productA.id,
      barcodeA: 'BC-A',
      productBId: productB.id,
      barcodeB: 'BC-B',
    );

    // This is the damage a crash leaves: sale committed, shelf wrong.
    expect(store.repository.getSaleById(sale.id), isNotNull);
    expect(
      store.repository.getProductById(productA.id)!.variants.first.quantity,
      9,
    );

    final recovered = await store.repository.recoverInterruptedCheckouts();
    expect(recovered, [sale.invoiceNumber]);

    // Stock is back, and only the stock that actually moved.
    expect(
      store.repository.getProductById(productA.id)!.variants.first.quantity,
      10,
    );
    expect(
      store.repository.getProductById(productB.id)!.variants.first.quantity,
      10,
      reason: 'line B never moved, so it must not be credited',
    );

    // The half-finished sale is gone from the books.
    expect(store.repository.getSaleById(sale.id), isNull);
    expect(store.repository.getAllSales(), isEmpty);
    expect(store.repository.getTodayRevenue(), 0);
    expect(store.repository.hasOpenCheckoutJournal(sale.id), isFalse);

    // And the shop is told rather than the reversal happening silently.
    expect(
      store.repository.getHistory().map((h) => h.action).join('\n'),
      contains('interrupted'),
    );
  });

  test('the customer is put back exactly as they were', () async {
    final product = await store.addProduct(price: 200, quantity: 10);
    final customer = await store.addCustomer(points: 0);

    await store.repository.saveLoyaltySettings(
      LoyaltySettingsModel(
        isLoyaltyEnabled: true,
        spendAmountForPoint: 100,
        pointsEarnedPerSpend: 5,
      ),
    );

    final stored = store.repository.getCustomerById(customer.id)!;
    stored.lifetimeSpend = 1000;
    await store.repository.saveCustomer(stored);

    final sale = await crashPartWayThroughCheckout(
      productAId: product.id,
      barcodeA: 'BC-1',
      productBId: product.id,
      barcodeB: 'BC-1',
      customerId: customer.id,
      previousLifetimeSpend: 1000,
    );

    // The crash lands after the customer has been charged and credited.
    await store.repository.addLedgerEntry(
      customerId: customer.id,
      date: sale.date,
      transactionType: 'Sale',
      referenceId: sale.invoiceNumber,
      debit: 400,
    );
    await store.repository.addLoyaltyTransaction(
      customerId: customer.id,
      saleId: sale.id,
      transactionType: 'Earn',
      points: 20,
      monetaryValue: 0,
      reference: sale.invoiceNumber,
      createdBy: 'POS',
    );
    final duringCrash = store.repository.getCustomerById(customer.id)!;
    duringCrash.lifetimeSpend = 1400;
    await store.repository.saveCustomer(duringCrash);

    expect(store.repository.getCustomerById(customer.id)!.currentBalance, 400);

    await store.repository.recoverInterruptedCheckouts();

    final after = store.repository.getCustomerById(customer.id)!;
    expect(after.currentBalance, 0, reason: 'the charge must be removed');
    expect(
      after.lifetimeSpend,
      1000,
      reason: 'lifetime spend must be restored',
    );
    expect(after.totalRewardPoints, 0, reason: 'points must be taken back');
    expect(store.repository.getLedgerForCustomer(customer.id), isEmpty);
    expect(store.repository.getLoyaltyTransactions(customer.id), isEmpty);
  });

  test('recovery interrupted half way is safe to run again', () async {
    final product = await store.addProduct(price: 200, quantity: 10);

    final sale = await crashPartWayThroughCheckout(
      productAId: product.id,
      barcodeA: 'BC-1',
      productBId: product.id,
      barcodeB: 'BC-1',
    );

    await store.repository.recoverInterruptedCheckouts();
    expect(
      store.repository.getProductById(product.id)!.variants.first.quantity,
      10,
    );

    // Re-running must not credit the stock a second time. This is what
    // protects against a crash *during* recovery.
    await store.repository.recoverInterruptedCheckouts();
    await store.repository.recoverInterruptedCheckouts();
    expect(
      store.repository.getProductById(product.id)!.variants.first.quantity,
      10,
    );
    expect(store.repository.getSaleById(sale.id), isNull);
  });

  test('recovery runs on startup, not only when asked', () async {
    final product = await store.addProduct(price: 200, quantity: 10);

    final sale = await crashPartWayThroughCheckout(
      productAId: product.id,
      barcodeA: 'BC-1',
      productBId: product.id,
      barcodeB: 'BC-1',
    );

    // Reopen the same files with a fresh repository — the closest thing to
    // relaunching the app after the power came back.
    await store.repository.dispose();
    await Hive.close();

    final restarted = StorageRepository();
    await restarted.init(storagePath: store.directory.path);

    expect(restarted.getSaleById(sale.id), isNull);
    expect(restarted.getProductById(product.id)!.variants.first.quantity, 10);
    expect(restarted.hasOpenCheckoutJournal(sale.id), isFalse);

    // Close the reopened boxes explicitly: dispose only closes the change
    // stream, and Windows will not delete the temp directory in tearDown
    // while Hive still holds handles on it.
    await restarted.dispose();
    await Hive.close();
  });
}
