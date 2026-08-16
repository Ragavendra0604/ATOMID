import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/widgets/brand_title.dart';

enum _Mode { signIn, signUp }

/// Signing in to the cloud copy of this device's data.
///
/// This is not a door into the app — every screen works without it, on-device.
/// It is the key to one account's backup at `/users/{uid}`, and the only thing
/// it decides is whether the sync queue has somewhere to go.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _isSignUp => _mode == _Mode.signUp;

  void _switchMode(_Mode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _notice = null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      final auth = ref.read(authServiceProvider);
      final email = _email.text.trim();

      if (_isSignUp) {
        await auth.signUp(email, _password.text);
        // Work captured before the account existed belongs to it, so it goes
        // up with everything else rather than being stranded on the device.
        await ref
            .read(storageRepositoryProvider)
            .enqueueAllExistingDataForSync();
      } else {
        await auth.signIn(email, _password.text);
      }

      unawaited(ref.read(syncServiceProvider).processQueue());

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error, fallback: _fallback));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _fallback => _isSignUp
      ? 'The account could not be created. Please try again.'
      : 'Could not sign in. Check the email and password.';

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email address first.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(authServiceProvider).resetPassword(email);
      if (!mounted) return;
      setState(() => _notice = 'A reset link is on its way to $email.');
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = describeError(
          error,
          fallback: 'Could not send a reset link.',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: ResponsivePadding.getScreenPadding(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: BrandTitle(
                        name: ref.watch(
                          settingsProvider.select((s) => s.companyName),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        logoSize: 44,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Sign in to back this device up and keep it in step '
                      'with your other devices.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),

                    SegmentedButton<_Mode>(
                      segments: const [
                        ButtonSegment(
                          value: _Mode.signIn,
                          label: Text('Sign in'),
                        ),
                        ButtonSegment(
                          value: _Mode.signUp,
                          label: Text('Create account'),
                        ),
                      ],
                      selected: {_mode},
                      showSelectedIcon: false,
                      onSelectionChanged: (values) => _switchMode(values.first),
                    ),
                    const SizedBox(height: 24),

                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty) return 'Email is required';
                        if (!value.contains('@') || !value.contains('.')) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Password is required';
                        }
                        // Only enforced on the way in; an existing account may
                        // predate this rule and must still be able to sign in.
                        if (_isSignUp && v.length < 8) {
                          return 'Use at least 8 characters';
                        }
                        return null;
                      },
                    ),

                    if (_notice != null) ...[
                      const SizedBox(height: 16),
                      _Banner(
                        icon: Icons.mark_email_read_outlined,
                        message: _notice!,
                        background: scheme.primaryContainer,
                        foreground: scheme.onPrimaryContainer,
                      ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _Banner(
                        icon: Icons.error_outline,
                        message: _error!,
                        background: scheme.errorContainer,
                        foreground: scheme.onErrorContainer,
                      ),
                    ],

                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isSignUp ? 'Create account' : 'Sign in'),
                    ),

                    if (!_isSignUp)
                      TextButton(
                        onPressed: _busy ? null : _resetPassword,
                        child: const Text('Forgot your password?'),
                      ),

                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Continue on this device only'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color background;
  final Color foreground;

  const _Banner({
    required this.icon,
    required this.message,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: foreground)),
          ),
        ],
      ),
    );
  }
}
