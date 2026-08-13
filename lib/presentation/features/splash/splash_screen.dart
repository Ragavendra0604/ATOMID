import 'package:flutter/material.dart';

import 'package:atomid/core/theme/brand.dart';
import 'package:atomid/core/theme/theme_provider.dart';

/// Shown while [bootstrap] runs.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _scale = Tween<double>(
      begin: 0.85,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: Scaffold(
        body: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandMark(size: 132, padding: 16),
                  const SizedBox(height: 24),
                  Text(
                    Brand.appName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Opening your store…',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when local storage could not be opened at all.
///
/// This is the only genuinely fatal startup condition: without Hive there is
/// nowhere to read or write. Everything else degrades to device-only mode.
class StartupFailureScreen extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const StartupFailureScreen({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.storage_rounded,
                    size: 56,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Atomid could not open its database',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'This usually means another copy of Atomid is already '
                    'running, or the storage folder is not writable. Close '
                    'any other window and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      height: 1.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 24),
                    ExpansionTile(
                      title: const Text(
                        'Technical details',
                        style: TextStyle(fontSize: 13),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(
                            error.toString(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
