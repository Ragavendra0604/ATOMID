import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/models/settings_model.dart';

import '../support/test_store.dart';

/// Settings are a single shared record, so a pull replaces them wholesale.
///
/// This file used to guard a device-local field — biometric enrolment — that
/// had to survive a pull because no peer could meaningfully supply it. That
/// setting controlled nothing and has been removed, so every field the model
/// carries now comes from the payload and a straight replace is correct.
///
/// What still matters, and is what these assert: the shared trading settings
/// follow the cloud, and a device with an unsent local edit is never
/// overwritten before it has had the chance to upload.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;

  setUp(() async => store = await TestStore.open());
  tearDown(() => store.close());

  /// `applyRemote` refuses to touch a record with unsent local edits, and
  /// saving always enqueues one — so a test about the *remote* winning has to
  /// clear the queue first.
  Future<void> drainQueue() async {
    for (final item in store.repository.getPendingSyncItems()) {
      await store.repository.deleteSyncItem(item.id);
    }
  }

  Map<String, dynamic> remoteSettings({
    String companyName = 'Renamed From Another Till',
    double taxRate = 12.5,
    DateTime? updatedAt,
  }) => {
    'id': 'settings',
    'isDarkMode': true,
    'companyName': companyName,
    'currencySymbol': r'$',
    'pdfPageSize': 'Letter',
    'taxMode': 'exclusive',
    'taxRate': taxRate,
    'updatedAt': (updatedAt ?? DateTime.now().add(const Duration(days: 1)))
        .toIso8601String(),
  };

  test('a newer remote settings doc replaces the trading settings', () async {
    await store.repository.saveSettings(
      SettingsModel(companyName: 'Local Store', taxRate: 5),
    );
    await drainQueue();

    final applied = await store.repository.applyRemote(
      'SettingsModel',
      'app_settings',
      remoteSettings(),
    );

    expect(applied, isTrue, reason: 'the remote change should be accepted');

    final stored = store.repository.getSettings();
    expect(stored.companyName, 'Renamed From Another Till');
    expect(stored.taxRate, 12.5);
    expect(stored.taxMode, 'exclusive');
    expect(stored.currencySymbol, r'$');
    expect(stored.pdfPageSize, 'Letter');
  });

  /// Regression cover for B-2. Config records carried no timestamp, so
  /// `_localUpdatedAt` returned null for them and the recency comparison was
  /// skipped entirely — whichever pull arrived last won, regardless of which
  /// edit was actually newer.
  group('config edits resolve on recency, not arrival order', () {
    test('an older remote settings doc loses to a newer local one', () async {
      await store.repository.saveSettings(
        SettingsModel(companyName: 'Newer Local', taxRate: 9),
      );
      await drainQueue();

      final applied = await store.repository.applyRemote(
        'SettingsModel',
        'app_settings',
        remoteSettings(
          companyName: 'Older Remote',
          taxRate: 1,
          updatedAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      );

      expect(
        applied,
        isFalse,
        reason:
            'a stale edit from another till must not win just because it '
            'arrived second',
      );
      expect(store.repository.getSettings().companyName, 'Newer Local');
      expect(store.repository.getSettings().taxRate, 9);
    });

    test('a newer remote settings doc still wins', () async {
      await store.repository.saveSettings(
        SettingsModel(companyName: 'Older Local', taxRate: 9),
      );
      await drainQueue();

      final applied = await store.repository.applyRemote(
        'SettingsModel',
        'app_settings',
        remoteSettings(companyName: 'Newer Remote', taxRate: 1),
      );

      expect(applied, isTrue);
      expect(store.repository.getSettings().companyName, 'Newer Remote');
    });

    test('a local save stamps the timestamp the comparison needs', () async {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      await store.repository.saveSettings(SettingsModel(companyName: 'Local'));

      final stamped = store.repository.getSettings().updatedAt;
      expect(stamped, isNotNull);
      expect(stamped!.isAfter(before), isTrue);
    });

    test('the payload carries it, so a peer can compare too', () async {
      await store.repository.saveSettings(SettingsModel(companyName: 'Local'));

      final json = store.repository.getEntityJson(
        'SettingsModel',
        'app_settings',
      );
      expect(json?['updatedAt'], isA<String>());
      expect(DateTime.tryParse(json!['updatedAt'] as String), isNotNull);
    });
  });

  test('an unsent local settings edit is not overwritten by a pull', () async {
    await store.repository.saveSettings(
      SettingsModel(companyName: 'Local Store', taxRate: 5),
    );
    // Deliberately *not* draining: the save left a pending queue item, which
    // is what tells applyRemote this device has work the cloud has not seen.

    final applied = await store.repository.applyRemote(
      'SettingsModel',
      'app_settings',
      remoteSettings(),
    );

    expect(applied, isFalse, reason: 'unsent local work must win');
    final stored = store.repository.getSettings();
    expect(stored.companyName, 'Local Store');
    expect(stored.taxRate, 5);
  });
}
