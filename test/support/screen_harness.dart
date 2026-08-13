import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/repositories/firebase_repository.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/domain/services/auth_service.dart';
import 'package:atomid/domain/services/session_service.dart';
import 'package:atomid/domain/services/sync_service.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

import 'test_store.dart';

/// Drives real screens against a real [StorageRepository].
///
/// Screens are rendered through the same provider graph the app builds at
/// startup rather than against per-screen mocks, so a layout test also
/// exercises the queries behind it. Firebase is never initialised in tests, so
/// [FirebaseRepository] reports itself uninitialised and the cloud paths stay
/// inert without needing a stub.
class ScreenHarness {
  final TestStore store;
  final SessionService session;
  final FirebaseRepository firebaseRepo;
  final AuthService authService;
  final SyncService syncService;

  ScreenHarness._(
    this.store,
    this.session,
    this.firebaseRepo,
    this.authService,
    this.syncService,
  );

  StorageRepository get repository => store.repository;

  static Future<ScreenHarness> open() async {
    final store = await TestStore.open();
    final firebaseRepo = FirebaseRepository();
    final authService = AuthService(firebaseRepo);
    final session = SessionService(authService);

    final syncService = SyncService(
      store.repository,
      firebaseRepo,
      authService,
      session,
    );

    return ScreenHarness._(
      store,
      session,
      firebaseRepo,
      authService,
      syncService,
    );
  }

  Future<void> close() async {
    // After a long render sweep Windows can still hold a lock on the temp
    // Hive files, and the recursive delete then blocks indefinitely. The
    // directory is throwaway and the OS reclaims it, so a stuck teardown must
    // not be allowed to fail an otherwise green suite.
    try {
      await store.close().timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  Widget wrap(Widget screen) => ProviderScope(
    overrides: [
      storageRepositoryProvider.overrideWithValue(store.repository),
      firebaseRepositoryProvider.overrideWithValue(firebaseRepo),
      authServiceProvider.overrideWithValue(authService),
      sessionServiceProvider.overrideWithValue(session),
      syncServiceProvider.overrideWithValue(syncService),
    ],
    // A stock theme keeps the render deterministic; the app theme pulls
    // Google Fonts, which is not available to a hermetic test.
    child: MaterialApp(theme: ThemeData(useMaterial3: true), home: screen),
  );
}

/// A viewport to render at, in logical pixels.
class Viewport {
  final String label;
  final double width;
  final double height;

  const Viewport(this.label, this.width, this.height);

  @override
  String toString() => '$label (${width.round()}x${height.round()})';
}

/// The width matrix, from the smallest phone still in use up to a desktop
/// window.
const responsiveMatrix = <Viewport>[
  Viewport('phone-320', 320, 640),
  Viewport('phone-360', 360, 740),
  Viewport('phone-375', 375, 812),
  Viewport('phone-390', 390, 844),
  Viewport('phone-414', 414, 896),
  Viewport('phablet-480', 480, 900),
  Viewport('tablet-600', 600, 960),
  Viewport('tablet-768', 768, 1024),
  Viewport('tablet-834', 834, 1112),
  Viewport('desktop-1024', 1024, 768),
  Viewport('desktop-1280', 1280, 800),
  Viewport('desktop-1440', 1440, 900),
  Viewport('desktop-1920', 1920, 1080),
];

/// Renders [screen] at [viewport] and returns the layout error, if any.
///
/// Overflow is reported through FlutterError during layout and paint, which
/// the test binding records; taking it here turns "the sheet is visibly
/// broken" into an assertable value.
Future<Object?> renderAt(
  WidgetTester tester,
  ScreenHarness harness,
  Widget screen,
  Viewport viewport,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(viewport.width, viewport.height);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(harness.wrap(screen));
  await tester.pump(const Duration(milliseconds: 300));

  return tester.takeException();
}
