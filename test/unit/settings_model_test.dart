import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/domain/pricing.dart';

void main() {
  SettingsModel configured() => SettingsModel(
    isDarkMode: false,
    companyName: 'Nila Traders',
    currencySymbol: r'$',
    pdfPageSize: 'Letter',
    taxMode: TaxMode.exclusive,
    taxRate: 18,
  );

  test('defaults are sensible for a fresh store', () {
    final settings = SettingsModel();
    expect(settings.companyName, 'ATOMID STORE');
    expect(settings.currencySymbol, '₹');
    expect(settings.taxMode, TaxMode.inclusive);
    expect(settings.taxRate, 0);
  });

  group('copyWith', () {
    test('changing the store name leaves tax untouched', () {
      // Regression: the settings screen rebuilt the model from only its
      // visible fields, wiping taxMode and taxRate on every save.
      final updated = configured().copyWith(companyName: 'Nila Stores');

      expect(updated.companyName, 'Nila Stores');
      expect(updated.taxRate, 18);
      expect(updated.taxMode, TaxMode.exclusive);
      expect(updated.pdfPageSize, 'Letter');
    });

    test('toggling dark mode leaves every other field untouched', () {
      final updated = configured().copyWith(isDarkMode: true);

      expect(updated.isDarkMode, isTrue);
      expect(updated.companyName, 'Nila Traders');
      expect(updated.currencySymbol, r'$');
      expect(updated.taxRate, 18);
      expect(updated.taxMode, TaxMode.exclusive);
    });

    test(
      'omitted fields keep their current value, including false and zero',
      () {
        final zeroed = SettingsModel(isDarkMode: false, taxRate: 0);
        final copy = zeroed.copyWith(companyName: 'Shop');

        expect(copy.isDarkMode, isFalse);
        expect(copy.taxRate, 0);
      },
    );

    test('every field can be changed', () {
      final updated = SettingsModel().copyWith(
        isDarkMode: false,
        companyName: 'A',
        currencySymbol: 'B',
        pdfPageSize: 'Letter',
        taxMode: TaxMode.exclusive,
        taxRate: 5,
      );

      expect(updated.isDarkMode, isFalse);
      expect(updated.companyName, 'A');
      expect(updated.currencySymbol, 'B');
      expect(updated.pdfPageSize, 'Letter');
      expect(updated.taxMode, TaxMode.exclusive);
      expect(updated.taxRate, 5);
    });
  });
}
