import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:atomid/data/repositories/firebase_repository.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/domain/services/auth_service.dart';
import 'package:atomid/domain/services/expense_service.dart';
import 'package:atomid/domain/services/session_service.dart';
import 'package:atomid/domain/services/sync_service.dart';
import 'package:atomid/firebase_options.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

/// Outcome of starting the app, so the splash screen can report precisely
/// what worked rather than dying on the first exception.
class BootstrapResult {
  final ProviderContainer container;

  /// Local storage is the only hard requirement — the app is offline-first.
  final bool storageReady;

  /// Cloud features. False simply means "this session is device-only".
  final bool cloudReady;

  /// Boxes that had to be rebuilt because they could not be recovered.
  final List<String> recoveredBoxes;

  final Object? fatalError;
  final String? cloudMessage;

  const BootstrapResult({
    required this.container,
    required this.storageReady,
    required this.cloudReady,
    this.recoveredBoxes = const [],
    this.fatalError,
    this.cloudMessage,
  });

  bool get canRunApp => storageReady;
}

/// Builds every long-lived service once and wires it into one container.
///
/// This is the single construction path. Previously `main` built four services
/// by hand while `app_providers` also had live constructors for two of them,
/// so a different entry point could silently get a different object graph.
Future<BootstrapResult> bootstrap() async {
  final storageRepo = StorageRepository();
  final firebaseRepo = FirebaseRepository();
  final authService = AuthService(firebaseRepo);
  final sessionService = SessionService(authService);

  var cloudReady = false;
  String? cloudMessage;

  // Cloud first, but never fatally: an offline-first till must open even when
  // Firebase is unreachable or unconfigured for the platform.
  //
  // The unsupported-platform case is caught rather than pre-checked. It used
  // to be a hand-written `isSupported` getter living inside
  // `firebase_options.dart` — a generated file — so the next
  // `flutterfire configure` deleted it and startup stopped compiling.
  // `currentPlatform` throwing UnsupportedError is the generated contract, and
  // catching it is the part the generator cannot take away.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    cloudReady = true;
  } on UnsupportedError {
    cloudMessage =
        'Cloud sync is not configured for this platform. '
        'Everything is saved on this device.';
  } catch (error, stack) {
    debugPrint('Firebase init failed: $error\n$stack');
    cloudMessage = 'Could not reach the cloud. Working on this device only.';
  }

  try {
    await storageRepo.init();
    await sessionService.init();
  } catch (error, stack) {
    debugPrint('Storage init failed: $error\n$stack');
    return BootstrapResult(
      container: ProviderContainer(),
      storageReady: false,
      cloudReady: cloudReady,
      fatalError: error,
    );
  }

  // Document numbering needs the device tag so two tills billing offline
  // cannot both issue invoice 0001.
  storageRepo.deviceId = sessionService.deviceId;

  final syncService = SyncService(
    storageRepo,
    firebaseRepo,
    authService,
    sessionService,
  );

  final container = ProviderContainer(
    overrides: [
      storageRepositoryProvider.overrideWithValue(storageRepo),
      firebaseRepositoryProvider.overrideWithValue(firebaseRepo),
      authServiceProvider.overrideWithValue(authService),
      sessionServiceProvider.overrideWithValue(sessionService),
      syncServiceProvider.overrideWithValue(syncService),
    ],
  );

  // Seed the categories a new install expects to find.
  await ExpenseService(storageRepo).seedDefaultCategories();

  if (cloudReady) syncService.start();

  return BootstrapResult(
    container: container,
    storageReady: true,
    cloudReady: cloudReady,
    recoveredBoxes: storageRepo.recoveredBoxes,
    cloudMessage: cloudMessage,
  );
}
