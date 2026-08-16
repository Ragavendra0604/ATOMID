import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/models/settings_model.dart';

import '../support/test_store.dart';

/// A cloud pull must not erase settings that only exist on this device.
///
/// `applyRemote` replaces the stored settings with whatever the codec rebuilds
/// from the payload, so any field the payload does not carry is not merely
/// left un-synced — it is wiped. Biometric enrolment is deliberately
/// device-local, which makes preserving it a requirement rather than an
/// optimisation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;

  setUp(() async => store = await TestStore.open());
  tearDown(() => store.close());

  /// applyRemote refuses to touch a record with unsent local edits, and
  /// saving always enqueues one.
  Future<void> drainQueue() async {
    for (final item in store.repository.getPendingSyncItems()) {
      await store.repository.deleteSyncItem(item.id);
    }
  }

  test('a newer remote settings doc keeps device-local fields', () async {
    await store.repository.saveSettings(
      SettingsModel(
        companyName: 'Local Store',
        taxRate: 5,
        isBiometricEnabled: true,
      ),
    );
    await drainQueue();

    // What another till would publish: the shared trading settings only.
    final applied = await store.repository
        .applyRemote('SettingsModel', 'app_settings', {
          'id': 'settings',
          'isDarkMode': true,
          'companyName': 'Renamed From Another Till',
          'currencySymbol': r'$',
          'pdfPageSize': 'Letter',
          'taxMode': 'exclusive',
          'taxRate': 12.5,
          'updatedAt': DateTime.now()
              .add(const Duration(days: 1))
              .toIso8601String(),
        });

    expect(applied, isTrue, reason: 'the remote change should be accepted');

    final stored = store.repository.getSettings();

    // Shared trading settings must follow the cloud.
    expect(stored.companyName, 'Renamed From Another Till');
    expect(stored.taxRate, 12.5);
    expect(stored.taxMode, 'exclusive');

    // Device-local settings must survive it.
    expect(
      stored.isBiometricEnabled,
      isTrue,
      reason: 'biometric enrolment is per-device and cannot come from a peer',
    );
  });
}
