import 'package:firebase_auth/firebase_auth.dart';
import 'package:atomid/data/repositories/firebase_repository.dart';

class AuthService {
  final FirebaseRepository _firebaseRepository;

  AuthService(this._firebaseRepository);

  Stream<User?> get authStateChanges => _firebaseRepository.authStateChanges;

  User? get currentUser => _firebaseRepository.currentUser;

  Future<void> signIn(String email, String password) async {
    await _firebaseRepository.signInWithEmailPassword(email, password);
    if (currentUser != null) {
      await _firebaseRepository.updateLastLogin(currentUser!.uid);
    }
  }

  Future<void> signUp(String email, String password, String? displayName) async {
    final userCredential = await _firebaseRepository.signUpWithEmailPassword(email, password);
    if (userCredential.user != null) {
      // Create user profile in Firestore
      await _firebaseRepository.saveUserProfile(
        uid: userCredential.user!.uid,
        email: email,
        displayName: displayName,
      );
    }
  }

  Future<void> resetPassword(String email) async {
    await _firebaseRepository.resetPassword(email);
  }

  Future<void> signOut() async {
    await _firebaseRepository.signOut();
  }
}
