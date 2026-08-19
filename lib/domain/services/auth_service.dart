import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/data/repositories/firebase_repository.dart';

/// The one account this installation syncs with.
///
/// Signing in is not a permission boundary — every screen works without it,
/// on-device, exactly as before. It is the key to the cloud copy and nothing
/// else: the account owns its data at `/users/{uid}` and no other account can
/// reach it.
class AuthService {
  final FirebaseRepository _firebaseRepository;

  AuthService(this._firebaseRepository);

  Stream<User?> get authStateChanges => _firebaseRepository.authStateChanges;

  User? get currentUser => _firebaseRepository.currentUser;

  String? get uid => currentUser?.uid;

  bool get isSignedIn => currentUser != null;

  bool get isAvailable => _firebaseRepository.isInitialized;

  Future<void> signIn(String email, String password) async {
    _requireAvailable();
    await _firebaseRepository.signInWithEmailPassword(email, password);
  }

  /// Creates the account this device will sync with.
  ///
  /// A verification email is sent immediately. This account is the sole key to
  /// the cloud copy of the whole business, and password recovery goes to this
  /// address — an unverified typo would mean the owner cannot get back in and
  /// someone else might. Verification is not *enforced* before syncing,
  /// deliberately: locking a shop out of its own till because a confirmation
  /// email was slow would be the worse failure.
  Future<void> signUp(String email, String password) async {
    _requireAvailable();
    final credential = await _firebaseRepository.signUpWithEmailPassword(
      email,
      password,
    );
    final user = credential.user;
    if (user == null) {
      throw const AppException('The account could not be created.');
    }

    // Never fatal: the account exists and works either way, and a failure
    // here is a mail problem, not a sign-up problem.
    try {
      await _firebaseRepository.sendEmailVerification(user);
    } catch (error, stack) {
      debugPrint('Verification email could not be sent: $error\n$stack');
    }
  }

  /// True once the owner has confirmed their address. Surfaced so the app can
  /// prompt without blocking.
  bool get isEmailVerified => currentUser?.emailVerified ?? false;

  /// Re-sends the confirmation email, for the address bar that never arrived.
  Future<void> resendVerificationEmail() async {
    _requireAvailable();
    final user = currentUser;
    if (user == null) {
      throw const AppException('Sign in first, then request a new email.');
    }
    if (user.emailVerified) return;
    await _firebaseRepository.sendEmailVerification(user);
  }

  Future<void> resetPassword(String email) async {
    _requireAvailable();
    await _firebaseRepository.resetPassword(email);
  }

  Future<void> signOut() => _firebaseRepository.signOut();

  void _requireAvailable() {
    if (!isAvailable) {
      throw const AppException(
        'Cloud sync is not available on this platform. '
        'Your data is still saved on this device.',
      );
    }
  }
}
