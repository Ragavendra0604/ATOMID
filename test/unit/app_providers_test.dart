import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/data/models/invoice_settings_model.dart';
import 'package:atomid/data/models/product_model.dart';

class MockStorageRepository extends Mock implements StorageRepository {}

void main() {
  group('App Providers Tests', () {
    late MockStorageRepository mockStorageRepo;
    late ProviderContainer container;

    setUp(() {
      mockStorageRepo = MockStorageRepository();
      container = ProviderContainer(
        overrides: [
          storageRepositoryProvider.overrideWithValue(mockStorageRepo),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('settingsProvider should fetch from storage', () {
      final mockSettings = SettingsModel(isDarkMode: true, companyName: 'Mock', currencySymbol: 'M', pdfPageSize: 'A4');
      when(() => mockStorageRepo.getSettings()).thenReturn(mockSettings);

      final settings = container.read(settingsProvider);
      
      expect(settings.isDarkMode, isTrue);
      expect(settings.companyName, 'Mock');
      verify(() => mockStorageRepo.getSettings()).called(1);
    });

    test('invoiceSettingsProvider should fetch from storage', () {
      final mockInvSettings = InvoiceSettingsModel(footerText: 'Mock Footer');
      when(() => mockStorageRepo.getInvoiceSettings()).thenReturn(mockInvSettings);

      final invSettings = container.read(invoiceSettingsProvider);
      
      expect(invSettings.footerText, 'Mock Footer');
      verify(() => mockStorageRepo.getInvoiceSettings()).called(1);
    });

    test('searchQueryProvider should update state and filter products', () {
      final mockProducts = [
        Product(id: '1', productName: 'Apple', productCode: 'A1', category: 'F', brand: 'Brand', color: 'Red', createdDate: DateTime.now(), updatedDate: DateTime.now(), variants: []),
        Product(id: '2', productName: 'Banana', productCode: 'B1', category: 'F', brand: 'Brand', color: 'Yellow', createdDate: DateTime.now(), updatedDate: DateTime.now(), variants: []),
      ];
      
      when(() => mockStorageRepo.searchProducts('Apple')).thenReturn([mockProducts[0]]);
      
      container.read(searchQueryProvider.notifier).setQuery('Apple');
      final filtered = container.read(filteredProductsProvider);
      
      expect(container.read(searchQueryProvider), 'Apple');
      expect(filtered.length, 1);
      expect(filtered.first.productName, 'Apple');
      verify(() => mockStorageRepo.searchProducts('Apple')).called(1);
    });
  });
}
