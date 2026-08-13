import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/domain/services/sale_service.dart';
import 'package:atomid/domain/services/session_service.dart';
import 'package:atomid/presentation/providers/cart_notifier.dart';

import '../support/test_store.dart';

class MockSessionService extends Mock implements SessionService {}

/// Fails at the loyalty step, which runs *after* the ledger has been written.
///
/// This is the shape of failure that used to leave a customer debited for a
/// sale that no longer existed.
class _LoyaltyFailsRepository extends StorageRepository {
  @override
  Future<String> addLoyaltyTransaction({
    required String customerId,
    String? saleId,
    required String transactionType,
    required double points,
    required double monetaryValue,
    String reference = '',
    String remarks = '',
    required String createdBy,
  }) async {
    throw const AppException('Loyalty store unavailable.');
  }
}

/// Fails on the second ledger leg, leaving the first already committed.
class _PaymentLegFailsRepository extends StorageRepository {
  @override
  Future<String> addLedgerEntry({
    required String customerId,
    required DateTime date,
    required String transactionType,
    required String referenceId,
    double debit = 0,
    double credit = 0,
    String notes = '',
  }) async {
    if (transactionType == 'Payment') {
      throw const AppException('Ledger unavailable.');
    }
    return super.addLedgerEntry(
      customerId: customerId,
      date: date,
      transactionType: transactionType,
      referenceId: referenceId,
      debit: debit,
      credit: credit,
      notes: notes,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;
  late SaleService service;

  setUp(() async {
    store = await TestStore.open(repository: _LoyaltyFailsRepository());
    final session = MockSessionService();
    when(() => session.deviceId).thenReturn('dev_test_abcd');
    service = SaleService(store.repository, session);

    // Loyalty must be on, otherwise the failing step is never reached.
    await store.repository.saveLoyaltySettings(
      LoyaltySettingsModel(
        isLoyaltyEnabled: true,
        spendAmountForPoint: 100,
        pointsEarnedPerSpend: 5,
      ),
    );
  });

  tearDown(() => store.close());

  group('checkout rollback', () {
    test('a failure after the ledger write leaves the customer whole', () async {
      final product = await store.addProduct(price: 500, quantity: 5);
      final customer = await store.addCustomer();

      await expectLater(
        service.checkout(
          CheckoutRequest(
            items: [
              CartItem(product: product, variant: product.variants.first),
            ],
            customer: customer,
            paymentMethod: 'Cash',
          ),
        ),
        throwsA(isA<AppException>()),
      );

      final repo = store.repository;

      expect(repo.getAllSales(), isEmpty, reason: 'the sale must be removed');

      expect(
        repo.getLedgerForCustomer(customer.id),
        isEmpty,
        reason: 'the ledger entries must be reversed, not left behind',
      );

      final stored = repo.getCustomerById(customer.id)!;
      expect(
        stored.currentBalance,
        0,
        reason: 'a rolled-back sale must not leave the customer debited',
      );
      expect(
        stored.lifetimeSpend,
        0,
        reason: 'lifetime spend must be put back',
      );

      expect(
        repo.getProductById(product.id)!.variants.first.quantity,
        5,
        reason: 'stock must be restored',
      );
    });

    test('a credit sale that fails leaves no outstanding balance', () async {
      final product = await store.addProduct(price: 500, quantity: 5);
      final customer = await store.addCustomer(creditLimit: 10000);

      await expectLater(
        service.checkout(
          CheckoutRequest(
            items: [
              CartItem(product: product, variant: product.variants.first),
            ],
            customer: customer,
            paymentMethod: 'Credit',
          ),
        ),
        throwsA(isA<AppException>()),
      );

      // A credit sale writes only the debit leg, so this is the case where a
      // missing reversal was most visible: money owed for nothing.
      expect(store.repository.getLedgerForCustomer(customer.id), isEmpty);
      expect(store.repository.getCustomerById(customer.id)!.currentBalance, 0);
    });
  });

  group('checkout rollback mid-ledger', () {
    late TestStore legStore;
    late SaleService legService;

    setUp(() async {
      await store.close();
      legStore = await TestStore.open(
        repository: _PaymentLegFailsRepository(),
      );
      final session = MockSessionService();
      when(() => session.deviceId).thenReturn('dev_test_abcd');
      legService = SaleService(legStore.repository, session);
    });

    tearDown(() async {
      await legStore.close();
      // The outer tearDown closes `store`, which this group already closed.
      store = await TestStore.open();
    });

    test('the debit leg is reversed when the payment leg fails', () async {
      final product = await legStore.addProduct(price: 500, quantity: 5);
      final customer = await legStore.addCustomer();

      await expectLater(
        legService.checkout(
          CheckoutRequest(
            items: [
              CartItem(product: product, variant: product.variants.first),
            ],
            customer: customer,
            paymentMethod: 'Cash',
          ),
        ),
        throwsA(isA<AppException>()),
      );

      expect(
        legStore.repository.getLedgerForCustomer(customer.id),
        isEmpty,
        reason: 'the committed debit leg must not survive the failure',
      );
      expect(
        legStore.repository.getCustomerById(customer.id)!.currentBalance,
        0,
      );
    });
  });
}
