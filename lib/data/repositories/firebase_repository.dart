import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// One pending cloud write, described in plain Dart.
///
/// The sync engine used to assemble Firestore `WriteBatch` objects itself,
/// which welded it to a live backend: there was no way to observe what it
/// intended to write without a real project behind it. Describing the intent
/// here keeps every scheduling decision — batching, ordering, retries —
/// testable, and leaves Firestore's types on this side of the boundary.
class SyncWrite {
  final String collection;
  final String documentId;

  /// Null for a delete.
  final Map<String, dynamic>? data;

  const SyncWrite.put({
    required this.collection,
    required this.documentId,
    required Map<String, dynamic> this.data,
  });

  const SyncWrite.delete({required this.collection, required this.documentId})
    : data = null;

  bool get isDelete => data == null;
}

/// Thin wrapper over Firebase that keeps every document under one account.
///
/// Everything lives at `/users/{uid}/…`, so the account that wrote a record is
/// the only account that can read it. There is no shared namespace to get the
/// scoping wrong in: an account either owns the path or is refused by the
/// rules.
class FirebaseRepository {
  static const String usersCollection = 'users';

  bool get isInitialized => Firebase.apps.isNotEmpty;

  FirebaseFirestore? get _firestore =>
      isInitialized ? FirebaseFirestore.instance : null;
  FirebaseAuth? get _auth => isInitialized ? FirebaseAuth.instance : null;

  Stream<User?> get authStateChanges =>
      isInitialized ? _auth!.authStateChanges() : const Stream.empty();

  User? get currentUser => isInitialized ? _auth!.currentUser : null;

  /// Commits a set of writes as one atomic batch.
  ///
  /// Overridden in tests to observe what sync decided to send without a live
  /// project. The server timestamp and the source-device tag are stamped here
  /// so callers never need a Firestore import.
  Future<void> commitBatch({
    required String uid,
    required List<SyncWrite> writes,
    required String sourceDevice,
  }) async {
    if (!isInitialized || writes.isEmpty) return;

    final batch = _firestore!.batch();
    for (final write in writes) {
      final ref = userCollection(uid, write.collection).doc(write.documentId);

      if (write.isDelete) {
        batch.delete(ref);
      } else {
        batch.set(ref, {
          ...write.data!,
          'syncedAt': FieldValue.serverTimestamp(),
          'sourceDevice': sourceDevice,
        }, SetOptions(merge: true));
      }
    }
    await batch.commit();
  }

  /// Account-scoped collection. Everything the sync engine writes goes here.
  CollectionReference<Map<String, dynamic>> userCollection(
    String uid,
    String path,
  ) {
    _requireFirebase();
    return _firestore!.collection(usersCollection).doc(uid).collection(path);
  }

  DocumentReference<Map<String, dynamic>> userDoc(String uid) {
    _requireFirebase();
    return _firestore!.collection(usersCollection).doc(uid);
  }

  void _requireFirebase() {
    if (!isInitialized) {
      throw StateError('Firebase is not initialised on this platform.');
    }
  }

  // --- Authentication -------------------------------------------------------

  Future<UserCredential> signInWithEmailPassword(
    String email,
    String password,
  ) async {
    _requireFirebase();
    return _auth!.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> signUpWithEmailPassword(
    String email,
    String password,
  ) async {
    _requireFirebase();
    return _auth!.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> resetPassword(String email) async {
    _requireFirebase();
    await _auth!.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() async {
    if (!isInitialized) return;
    await _auth!.signOut();
  }

  // --- Documents ------------------------------------------------------------

  Future<void> syncDocument({
    required String uid,
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    if (!isInitialized) return;
    await userCollection(
      uid,
      collection,
    ).doc(documentId).set(data, SetOptions(merge: true));
  }

  Future<void> deleteDocument({
    required String uid,
    required String collection,
    required String documentId,
  }) async {
    if (!isInitialized) return;
    await userCollection(uid, collection).doc(documentId).delete();
  }

  /// Reads a whole collection, a page at a time, calling [onPage] with each.
  ///
  /// This used to be a single `limit(500)` query whose result was returned
  /// wholesale. Two things were wrong with that, and both lost data silently:
  /// a shop with more than 500 products simply never received the rest, and
  /// with no `orderBy` the 500 it did receive were an arbitrary subset that
  /// could differ between runs. Nothing surfaced — the pull reported success.
  ///
  /// Paging by document id is deliberate for a full pull: every document has
  /// one, whereas ordering by `updatedAt` would quietly skip any record
  /// written before that field existed. The incremental path has to order by
  /// the field it filters on, which is a constraint Firestore imposes.
  ///
  /// [onPage] runs between fetches so records are applied as they arrive and
  /// peak memory stays one page, not one collection.
  Future<int> fetchCollectionPages({
    required String uid,
    required String collection,
    required Future<void> Function(List<Map<String, dynamic>> page) onPage,
    DateTime? since,
    int pageSize = 300,
  }) async {
    if (!isInitialized) return 0;

    var fetched = 0;
    DocumentSnapshot<Map<String, dynamic>>? cursor;

    while (true) {
      Query<Map<String, dynamic>> query = userCollection(uid, collection);

      if (since != null) {
        query = query
            .where('updatedAt', isGreaterThan: since.toIso8601String())
            .orderBy('updatedAt');
      } else {
        query = query.orderBy(FieldPath.documentId);
      }

      if (cursor != null) query = query.startAfterDocument(cursor);

      final snapshot = await query.limit(pageSize).get();
      if (snapshot.docs.isEmpty) break;

      await onPage(
        snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList(),
      );
      fetched += snapshot.docs.length;

      // A short page is the last page. Stopping here saves the round trip
      // that would come back empty.
      if (snapshot.docs.length < pageSize) break;
      cursor = snapshot.docs.last;
    }

    return fetched;
  }
}
