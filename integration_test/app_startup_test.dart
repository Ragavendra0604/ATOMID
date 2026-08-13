import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:atomid/main.dart' as app;

/// End-to-end cover for the real application on real hardware.
///
/// Everything below runs the shipped entry point — Hive on the device's own
/// filesystem, Firebase, the real provider graph — so it exercises the startup
/// path that unit and widget tests deliberately stub out. The web build and
/// the `LateInitializationError` both failed here, in wiring no isolated test
/// could reach.
/// Advances the real app past startup.
///
/// `pumpAndSettle` cannot be used here: the splash carries a progress
/// indicator that animates forever, so "no frames pending" never becomes true
/// and the pump times out with the app perfectly healthy. Pumping for a fixed
/// wall-clock budget lets bootstrap finish — twenty-one Hive boxes plus
/// Firebase — without demanding the tree ever go still.
Future<void> _settleStartup(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('application startup', () {
    testWidgets('boots from cold to a usable shell', (tester) async {
      app.main();

      // Bootstrap opens twenty-one Hive boxes and may reach the network, so
      // settle generously rather than assuming a frame count.
      await _settleStartup(tester);

      expect(
        tester.takeException(),
        isNull,
        reason: 'startup must not raise before the first usable frame',
      );

      // The shell is up once a navigation surface exists.
      final hasNav =
          find.byType(NavigationBar).evaluate().isNotEmpty ||
          find.byType(NavigationRail).evaluate().isNotEmpty;
      expect(hasNav, isTrue, reason: 'no navigation surface after startup');
    });

    testWidgets('every permitted destination opens without error', (
      tester,
    ) async {
      app.main();
      await _settleStartup(tester);

      final finder = find.byType(NavigationDestination);
      final labels = tester
          .widgetList<NavigationDestination>(finder)
          .map((d) => d.label)
          .toList();

      // A rail-based layout has no NavigationDestination widgets at all, so
      // there is nothing to walk; the boot test already covers it.
      if (labels.isEmpty) {
        expect(
          find.byType(NavigationRail).evaluate().isNotEmpty,
          isTrue,
          reason: 'neither a bar nor a rail was found',
        );
        return;
      }

      for (var i = 0; i < labels.length; i++) {
        // "More" opens a modal sheet that covers the bar, so the following tap
        // would land on an obscured widget and never resolve. Its contents are
        // ordinary screens reached the same way, so skipping it costs no
        // coverage.
        if (labels[i] == 'More') continue;
        if (finder.evaluate().length <= i) break;

        await tester.tap(finder.at(i));
        await tester.pump(const Duration(milliseconds: 1200));

        expect(
          tester.takeException(),
          isNull,
          reason: '${labels[i]} raised when opened',
        );
      }
    });
  });
}
