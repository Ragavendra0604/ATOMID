import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:atomid/presentation/features/settings/invoice_settings_screen.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/data/models/invoice_settings_model.dart';

class MockStorageRepository extends Mock implements StorageRepository {}

class FakeInvoiceSettingsModel extends Fake implements InvoiceSettingsModel {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeInvoiceSettingsModel());
  });

  group('InvoiceSettingsScreen Widget Tests', () {
    late MockStorageRepository mockStorageRepo;
    late InvoiceSettingsModel mockSettings;

    setUp(() {
      mockStorageRepo = MockStorageRepository();
      mockSettings = InvoiceSettingsModel(
        footerText: 'Default Footer',
        showUpiQr: false,
        upiId: '',
        upiQrImagePath: '',
        showCompanyLogo: true,
        termsAndConditions: 'T&C',
      );

      when(() => mockStorageRepo.getInvoiceSettings()).thenReturn(mockSettings);
      when(
        () => mockStorageRepo.saveInvoiceSettings(any()),
      ).thenAnswer((_) async {});
    });

    Widget createWidgetUnderTest() {
      return ProviderScope(
        overrides: [
          storageRepositoryProvider.overrideWithValue(mockStorageRepo),
          invoiceSettingsProvider.overrideWithValue(mockSettings),
        ],
        child: const MaterialApp(home: InvoiceSettingsScreen()),
      );
    }

    testWidgets('should render all fields with initial values', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Invoice Customization'), findsOneWidget);
      expect(find.text('Invoice Footer Text'), findsOneWidget);
      expect(find.text('Terms and Conditions'), findsOneWidget);

      // Verify initial values in text fields
      expect(find.text('Default Footer'), findsOneWidget);
      expect(find.text('T&C'), findsOneWidget);
    });

    testWidgets('should toggle UPI QR settings visibility', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('UPI ID (Optional)'), findsNothing);

      // Tap the switch to show UPI QR
      final switchFinder = find.byType(Switch).last;
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(find.text('UPI ID (Optional)'), findsOneWidget);
    });

    testWidgets('should call save function when save button is pressed', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Enter new text
      await tester.enterText(
        find.byType(TextFormField).first,
        'New Footer Text',
      );
      await tester.pump();

      // Tap save
      final saveButton = find.byIcon(Icons.check);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      verify(() => mockStorageRepo.saveInvoiceSettings(any())).called(1);
    });
  });
}
