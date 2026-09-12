import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/bootstrap.dart';
import 'package:atomid/core/theme/theme_provider.dart';
import 'package:atomid/presentation/features/splash/splash_screen.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/widgets/app_shell.dart';
import 'package:atomid/presentation/features/hardware/global_barcode_listener.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint(
      'FlutterError: ${details.exceptionAsString()}\n${details.stack}',
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    return true;
  };

  runApp(const AtomidBootstrap());
}

/// Runs startup, then hands the built container to the app.
///
/// Startup used to happen inside the splash screen's `initState`, which meant
/// a failure there left the user stranded on a logo with a red exception
/// string and no way forward.
class AtomidBootstrap extends StatefulWidget {
  const AtomidBootstrap({super.key});

  @override
  State<AtomidBootstrap> createState() => _AtomidBootstrapState();
}

class _AtomidBootstrapState extends State<AtomidBootstrap> {
  late Future<BootstrapResult> _startup;

  @override
  void initState() {
    super.initState();
    _startup = bootstrap();
  }

  void _retry() {
    setState(() => _startup = bootstrap());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BootstrapResult>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SplashScreen();
        }

        final result = snapshot.data;
        if (result == null || !result.canRunApp) {
          return StartupFailureScreen(
            error: result?.fatalError ?? snapshot.error,
            onRetry: _retry,
          );
        }

        return UncontrolledProviderScope(
          container: result.container,
          child: AtomidApp(startup: result),
        );
      },
    );
  }
}

class AtomidApp extends ConsumerWidget {
  final BootstrapResult startup;

  const AtomidApp({super.key, required this.startup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'Atomid',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      debugShowCheckedModeBanner: false,
      home: GlobalBarcodeListener(
        child: AppShell(startup: startup),
      ),
    );
  }
}
