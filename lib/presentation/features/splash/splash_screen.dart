import 'package:flutter/material.dart';
import 'package:atomid/presentation/widgets/app_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:atomid/firebase_options.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _controller.forward();
    _initializeApp();
  }

  String _initStatus = 'Initializing...';
  String _errorMessage = '';

  Future<void> _initializeApp() async {
    try {
      debugPrint('Initializing Firebase...');
      setState(() => _initStatus = 'Initializing Firebase...');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('Firebase Initialized');

      debugPrint('Initializing Storage...');
      setState(() => _initStatus = 'Initializing Storage...');
      await ref.read(storageRepositoryProvider).init();
      debugPrint('Storage Initialized');

      debugPrint('Initializing Session...');
      setState(() => _initStatus = 'Initializing Session...');
      await ref.read(sessionServiceProvider).init();
      debugPrint('Session Initialized');

      debugPrint('Starting Sync...');
      setState(() => _initStatus = 'Starting Sync...');
      ref.read(syncServiceProvider).start();
      debugPrint('Sync Started');

      // Add a small delay for the animation to play
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const AppShell()));
      }
    } catch (e, stack) {
      debugPrint('Startup Error: $e\n$stack');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _initStatus = 'Error occurred during startup';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/logo.jpeg', // Make sure this asset exists or handle error
                      width: 120,
                      height: 120,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.store,
                        size: 120,
                        color: Colors.amber,
                      ),
                    ),
                    if (_errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(color: Colors.red, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      Text(
                        _initStatus,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
