import 'package:firebase_auth/firebase_auth.dart';

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
  Future<void> signUp(String email, String password) async {
    _requireAvailable();
    final credential = await _firebaseRepository.signUpWithEmailPassword(
      email,
      password,
    );
    if (credential.user == null) {
      throw const AppException('The account could not be created.');
    }
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
