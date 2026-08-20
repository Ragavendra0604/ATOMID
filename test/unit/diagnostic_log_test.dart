import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/data/models/diagnostic_log_model.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/domain/services/sale_service.dart';
import 'package:atomid/domain/services/session_service.dart';
import 'package:atomid/presentation/providers/cart_notifier.dart';

import '../support/test_store.dart';

class MockSessionService extends Mock implements SessionService {}

/// Fails at the loyalty step — after the sale, the stock movement and the
/// ledger have all been written — so the checkout has to unwind.
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

/// Fails the checkout *and* the reversal of its stock movement, which is the
/// state that leaves the shelf disagreeing with the books.
class _UnwindAlsoFailsRepository extends _LoyaltyFailsRepository {
  @override
  Future<void> performStockIn({
    required String productId,
    required String variantBarcode,
    required int quantity,
    required String reason,
    String movementReferenceId = '',
    String performedAt = '',
  }) async {
    if (reason.startsWith('Reversal')) {
      throw const AppException('Disk full.');
    }
    return super.performStockIn(
      productId: productId,
      variantBarcode: variantBarcode,
      quantity: quantity,
      reason: reason,
      movementReferenceId: movementReferenceId,
      performedAt: performedAt,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;
  late SaleService service;

  Future<void> openWith(StorageRepository repo) async {
    store = await TestStore.open(repository: repo);
    final session = MockSessionService();
    when(() => session.deviceId).thenReturn('dev_test_abcd');
    service = SaleService(store.repository, session);
    await store.repository.saveLoyaltySettings(
      LoyaltySettingsModel(
        isLoyaltyEnabled: true,
        spendAmountForPoint: 100,
        pointsEarnedPerSpend: 5,
      ),
    );
  }

  Future<void> failingCheckout() async {
    final product = await store.addProduct(price: 500, quantity: 5);
    final customer = await store.addCustomer();
    await expectLater(
      service.checkout(
        CheckoutRequest(
          items: [CartItem(product: product, variant: product.variants.first)],
          customer: customer,
          paymentMethod: 'Cash',
        ),
      ),
      throwsA(isA<AppException>()),
    );
  }

  tearDown(() => store.close());

  group('diagnostics are recorded where a person can read them', () {
    test('a reversed checkout leaves a warning naming the invoice', () async {
      await openWith(_LoyaltyFailsRepository());
      await failingCheckout();

      final logs = store.repository.getDiagnostics();
      expect(logs, isNotEmpty, reason: 'the failure must be recorded at all');

      final entry = logs.first;
      expect(entry.area, DiagnosticArea.checkout);
      expect(entry.severity, DiagnosticSeverity.warning);
      expect(
        entry.reference,
        isNotEmpty,
        reason: 'a diagnostic without the invoice number cannot be acted on',
      );
      expect(
        entry.detail,
        contains('Loyalty store unavailable'),
        reason: 'the underlying cause must survive into the record',
      );
    });

    test(
      'a checkout that unwinds cleanly is a warning, not an error',
      () async {
        await openWith(_LoyaltyFailsRepository());
        await failingCheckout();

        expect(
          store.repository.getDiagnostics(severity: DiagnosticSeverity.error),
          isEmpty,
          reason:
              'everything was reversed, so nothing here needs a human — '
              'flagging it would train the shopkeeper to ignore the badge',
        );
      },
    );

    test('a failed reversal is escalated to an error', () async {
      await openWith(_UnwindAlsoFailsRepository());
      await failingCheckout();

      final errors = store.repository.getDiagnostics(
        severity: DiagnosticSeverity.error,
      );
      expect(
        errors,
        isNotEmpty,
        reason:
            'stock was taken and could not be put back — a person must know',
      );
      expect(errors.first.message, contains('reversal'));
    });

    test('records are newest first', () async {
      await openWith(_LoyaltyFailsRepository());
      await failingCheckout();
      await failingCheckout();

      final logs = store.repository.getDiagnostics();
      expect(logs.length, greaterThanOrEqualTo(2));
      for (var i = 1; i < logs.length; i++) {
        expect(
          logs[i - 1].occurredAt.isBefore(logs[i].occurredAt),
          isFalse,
          reason: 'the most recent failure must be the one on screen',
        );
      }
    });

    test('two failures in the same millisecond both survive', () async {
      await openWith(StorageRepository());
      final repo = store.repository;

      for (var i = 0; i < 20; i++) {
        await repo.recordDiagnostic(
          severity: DiagnosticSeverity.error,
          area: DiagnosticArea.checkout,
          reference: 'INV-$i',
          message: 'failure $i',
        );
      }

      expect(
        repo.getDiagnostics().length,
        20,
        reason: 'ids must not collide when failures arrive in a burst',
      );
    });

    test(
      'the log is bounded so a long-running till cannot fill its disk',
      () async {
        await openWith(StorageRepository());
        final repo = store.repository;

        for (var i = 0; i < 540; i++) {
          await repo.recordDiagnostic(
            severity: DiagnosticSeverity.warning,
            area: DiagnosticArea.checkout,
            reference: 'INV-$i',
            message: 'failure $i',
          );
        }

        expect(repo.getDiagnostics(limit: 1000).length, lessThanOrEqualTo(500));
      },
    );

    test('clearing removes the records', () async {
      await openWith(_LoyaltyFailsRepository());
      await failingCheckout();
      expect(store.repository.getDiagnostics(), isNotEmpty);

      await store.repository.clearDiagnostics();
      expect(store.repository.getDiagnostics(), isEmpty);
    });
  });
}
