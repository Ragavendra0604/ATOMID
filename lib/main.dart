import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/core/theme/theme_provider.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/features/splash/splash_screen.dart';
import 'package:atomid/domain/services/session_service.dart';
import 'package:atomid/domain/services/auth_service.dart';
import 'package:atomid/data/repositories/firebase_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:atomid/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storageRepo = StorageRepository();
  await storageRepo.init();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }

  final firebaseRepo = FirebaseRepository();
  final authService = AuthService(firebaseRepo);
  final sessionService = SessionService(authService, firebaseRepo);
  await sessionService.init();

  final container = ProviderContainer(
    overrides: [
      storageRepositoryProvider.overrideWithValue(storageRepo),
      sessionServiceProvider.overrideWithValue(sessionService),
      firebaseRepositoryProvider.overrideWithValue(firebaseRepo),
      authServiceProvider.overrideWithValue(authService),
    ],
  );

  // Start the sync service
  try {
    container.read(syncServiceProvider).start();
  } catch (e) {
    debugPrint('SyncService start error: $e');
  }

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
