import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/action_history_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/domain/services/session_service.dart';
import 'package:atomid/domain/services/customer_service.dart';

class MockStorageRepository extends Mock implements StorageRepository {}

class MockSessionService extends Mock implements SessionService {}

class FakeCustomer extends Fake implements Customer {}

class FakeActionHistory extends Fake implements ActionHistory {}

void main() {
  late CustomerService customerService;
  late MockStorageRepository mockStorageRepo;
  late MockSessionService mockSessionService;

  setUpAll(() {
    registerFallbackValue(FakeCustomer());
    registerFallbackValue(FakeActionHistory());
  });

  setUp(() {
    mockStorageRepo = MockStorageRepository();
    mockSessionService = MockSessionService();
    customerService = CustomerService(mockStorageRepo, mockSessionService);

    when(() => mockSessionService.deviceId).thenReturn('device_123');
  });

  group('CustomerService Tests', () {
    test('isDuplicate should return true if mobile matches', () {
      final existingCustomer = Customer(
        id: 'c1',
        code: 'C-01',
        name: 'Test',
        mobile: '1234567890',
        createdDate: DateTime.now(),
      );

      when(
        () => mockStorageRepo.getAllCustomers(),
      ).thenReturn([existingCustomer]);

      final result = customerService.isDuplicate(
        '1234567890',
        'email@test.com',
      );
      expect(result, isTrue);
    });

    test('isDuplicate should return false if excluding same id', () {
      final existingCustomer = Customer(
        id: 'c1',
        code: 'C-01',
        name: 'Test',
        mobile: '1234567890',
        createdDate: DateTime.now(),
      );

      when(
        () => mockStorageRepo.getAllCustomers(),
      ).thenReturn([existingCustomer]);

      final result = customerService.isDuplicate(
        '1234567890',
        'email@test.com',
        excludeId: 'c1',
      );
      expect(result, isFalse);
    });

    test('saveCustomer should inject deviceId if empty', () async {
      final customer = Customer(
        id: 'c2',
        code: 'C-02',
        name: 'New',
        mobile: '0987654321',
        createdDate: DateTime.now(),
      );

      when(
        () => mockStorageRepo.saveCustomer(any()),
      ).thenAnswer((_) async => {});

      await customerService.saveCustomer(customer);

      verify(() => mockStorageRepo.saveCustomer(customer)).called(1);
      expect(customer.deviceId, 'device_123');
      expect(customer.updatedAt, isNotNull);
    });

    test(
      'mergeCustomers should combine stats and soft delete secondary',
      () async {
        final primary = Customer(
          id: 'p1',
          code: 'C-P',
          name: 'Primary',
          mobile: '111',
          createdDate: DateTime.now(),
          totalRewardPoints: 10,
          lifetimeSpend: 100,
          currentBalance: 50,
          tags: ['vip'],
        );

        final secondary = Customer(
          id: 's1',
          code: 'C-S',
          name: 'Secondary',
          mobile: '222',
          createdDate: DateTime.now(),
          totalRewardPoints: 5,
          lifetimeSpend: 50,
          currentBalance: 20,
          tags: ['new'],
        );

        when(() => mockStorageRepo.getCustomerById('p1')).thenReturn(primary);
        when(() => mockStorageRepo.getCustomerById('s1')).thenReturn(secondary);
        when(
          () => mockStorageRepo.reassignCustomerLedger(
            fromCustomerId: 's1',
            toCustomerId: 'p1',
          ),
        ).thenAnswer((_) async => {});
        when(
          () => mockStorageRepo.saveCustomer(any()),
        ).thenAnswer((_) async => {});
        when(
          () => mockStorageRepo.saveHistory(any()),
        ).thenAnswer((_) async => {});

        await customerService.mergeCustomers('p1', 's1');

        expect(primary.totalRewardPoints, 15);
        expect(primary.lifetimeSpend, 150);
        expect(primary.tags, containsAll(['vip', 'new']));

        expect(secondary.isDeleted, isTrue);
        expect(secondary.status, 'Merged');

        // Balance is the ledger's job now, not a hand-added field — verified
        // for real (with a real StorageRepository) in
        // customer_merge_ledger_test.dart.
        verify(
          () => mockStorageRepo.reassignCustomerLedger(
            fromCustomerId: 's1',
            toCustomerId: 'p1',
          ),
        ).called(1);
        verify(() => mockStorageRepo.saveCustomer(primary)).called(1);
        verify(() => mockStorageRepo.saveCustomer(secondary)).called(1);
        verify(() => mockStorageRepo.saveHistory(any())).called(1);
      },
    );
  });
}
