import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/core/theme/theme_provider.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/features/splash/splash_screen.dart';
import 'package:atomid/domain/services/session_service.dart';
import 'package:atomid/domain/services/auth_service.dart';
import 'package:atomid/data/repositories/firebase_repository.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:atomid/firebase_options.dart';

import 'package:flutter/foundation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Add Global Error Boundaries for Web (and Native) crashes
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformError: $error\n$stack');
    return true; // Prevent app crash if possible
  };

  // Create uninitialized services to populate the ProviderContainer
  final storageRepo = StorageRepository();
  final firebaseRepo = FirebaseRepository();
  final authService = AuthService(firebaseRepo);
  final sessionService = SessionService(authService, firebaseRepo);

  final container = ProviderContainer(
    overrides: [
      storageRepositoryProvider.overrideWithValue(storageRepo),
      sessionServiceProvider.overrideWithValue(sessionService),
      firebaseRepositoryProvider.overrideWithValue(firebaseRepo),
      authServiceProvider.overrideWithValue(authService),
    ],
  );

  runApp(
    UncontrolledProviderScope(container: container, child: const AtomidApp()),
  );
}
class AtomidApp extends ConsumerWidget {
  const AtomidApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'Atomid Store',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}
