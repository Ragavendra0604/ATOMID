import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class FirebaseRepository {
  bool get isInitialized => Firebase.apps.isNotEmpty;

  FirebaseFirestore? get _firestore =>
      isInitialized ? FirebaseFirestore.instance : null;
  FirebaseAuth? get _auth => isInitialized ? FirebaseAuth.instance : null;

  Stream<User?> get authStateChanges =>
      isInitialized ? _auth!.authStateChanges() : Stream.empty();
  User? get currentUser => isInitialized ? _auth!.currentUser : null;
  WriteBatch? getBatch() => isInitialized ? _firestore!.batch() : null;
  CollectionReference getCollection(String path) => _firestore!.collection(path);

  Future<UserCredential> signInWithEmailPassword(
    String email,
    String password,
  ) async {
    if (!isInitialized) throw Exception('Firebase is not initialized');
    return await _auth!.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    if (!isInitialized) return;
    await _auth!.signOut();
  }

  Future<UserCredential> signUpWithEmailPassword(
    String email,
    String password,
  ) async {
    if (!isInitialized) throw Exception('Firebase is not initialized');
    return await _auth!.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> resetPassword(String email) async {
    if (!isInitialized) throw Exception('Firebase is not initialized');
    await _auth!.sendPasswordResetEmail(email: email);
  }

  Future<void> saveUserProfile({
    required String uid,
    required String email,
    String? displayName,
  }) async {
    if (!isInitialized) return;
    await _firestore!.collection('users').doc(uid).set({
      'uid': uid,
      'email': email,
      'displayName': displayName ?? '',
      'role': 'Owner',
      'createdAt': FieldValue.serverTimestamp(),
      'lastLogin': FieldValue.serverTimestamp(),
      'isActive': true,
    }, SetOptions(merge: true));
  }

  Future<void> updateLastLogin(String uid) async {
    if (!isInitialized) return;
    await _firestore!.collection('users').doc(uid).update({
      'lastLogin': FieldValue.serverTimestamp(),
    });
  }

  Future<void> syncDocument({
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    if (!isInitialized) return;
    await _firestore!
        .collection(collection)
        .doc(documentId)
        .set(data, SetOptions(merge: true));
  }

  Future<void> deleteDocument({
    required String collection,
    required String documentId,
  }) async {
    if (!isInitialized) return;
    await _firestore!
        .collection(collection)
        .doc(documentId)
        .delete();
  }

  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    if (!isInitialized) return null;
    final doc = await _firestore!.collection('users').doc(uid).get();
    return doc.data();
  }
}
