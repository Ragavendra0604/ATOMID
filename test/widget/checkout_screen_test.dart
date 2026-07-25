import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:atomid/presentation/features/billing/checkout_screen.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/providers/cart_notifier.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/data/models/invoice_settings_model.dart';
import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/data/models/customer_model.dart';

class MockStorageRepository extends Mock implements StorageRepository {}

void main() {
  group('CheckoutScreen Widget Tests', () {
    late MockStorageRepository mockStorageRepo;

    setUp(() {
      mockStorageRepo = MockStorageRepository();
      when(() => mockStorageRepo.getAllCustomers()).thenReturn([]);
      when(() => mockStorageRepo.getSettings()).thenReturn(SettingsModel(isDarkMode: false, companyName: 'Mock', currencySymbol: '\$', pdfPageSize: 'A4'));
      when(() => mockStorageRepo.getInvoiceSettings()).thenReturn(InvoiceSettingsModel());
      when(() => mockStorageRepo.getCompany()).thenReturn(CompanyModel(name: 'Mock', address: 'Mock', phone1: 'Mock', email: 'Mock'));
    });

    Widget createWidgetUnderTest() {
      return ProviderScope(
        overrides: [
          storageRepositoryProvider.overrideWithValue(mockStorageRepo),
          customersProvider.overrideWithValue(<Customer>[]),
          cartProvider.overrideWith(() => CartNotifier()),
        ],
        child: const MaterialApp(
          home: CheckoutScreen(
            subtotal: 100.0,
            taxAmount: 5.0,
            grandTotal: 105.0,
          ),
        ),
      );
    }

    testWidgets('should render subtotal, tax and total', (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('\$100.0'), findsOneWidget); // Settings currency is \$
    });

    testWidgets('should render New Customer button', (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.person_add), findsOneWidget);
    });

    testWidgets('should render Manual Discount input', (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Manual Discount'), findsOneWidget);
    });

    testWidgets('should calculate manual discount correctly', (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Enter manual discount
      final discountInput = find.byType(TextFormField).first;
      await tester.enterText(discountInput, '10');
      await tester.pumpAndSettle();

      expect(find.text('10'), findsOneWidget);
    });
  });
}
