import 'package:flutter_test/flutter_test.dart';
import 'package:atomid/data/models/invoice_settings_model.dart';
import 'package:atomid/data/models/settings_model.dart';

void main() {
  group('InvoiceSettings Model Tests', () {
    test('should create InvoiceSettingsModel with default values', () {
      final settings = InvoiceSettingsModel();

      expect(settings.footerText, 'Thank you for your business!');
      expect(settings.showUpiQr, false);
      expect(settings.upiId, '');
      expect(settings.upiQrImagePath, '');
      expect(settings.showCompanyLogo, true);
      expect(
        settings.termsAndConditions,
        '1. Goods once sold will not be taken back.\n2. Subject to local jurisdiction.',
      );
    });

    test('should allow overriding default values', () {
      final settings = InvoiceSettingsModel(
        footerText: 'Custom Footer',
        showUpiQr: true,
        upiId: 'test@upi',
        upiQrImagePath: '/path/to/img.png',
        showCompanyLogo: false,
        termsAndConditions: 'No returns',
      );

      expect(settings.footerText, 'Custom Footer');
      expect(settings.showUpiQr, true);
      expect(settings.upiId, 'test@upi');
      expect(settings.upiQrImagePath, '/path/to/img.png');
      expect(settings.showCompanyLogo, false);
      expect(settings.termsAndConditions, 'No returns');
    });
  });

  group('Settings Model Tests', () {
    test('should create SettingsModel with default values', () {
      final settings = SettingsModel(
        isDarkMode: false,
        companyName: 'Atomid Store',
        currencySymbol: '\$',
        pdfPageSize: 'A4',
      );

      expect(settings.isDarkMode, false);
      expect(settings.companyName, 'Atomid Store');
      expect(settings.currencySymbol, '\$');
      expect(settings.taxRate, 0.0);
      expect(settings.pdfPageSize, 'A4');
    });
  });
}
