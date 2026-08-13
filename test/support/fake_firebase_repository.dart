import 'package:atomid/data/repositories/firebase_repository.dart';

/// A cloud that never exists, but records what it was asked to do.
///
/// Subclassing the real repository keeps the seam honest: if a Firestore type
/// ever leaks back into the sync engine, this stops compiling.
class FakeFirebaseRepository extends FirebaseRepository {
  FakeFirebaseRepository({this.initialised = true});

  final bool initialised;

  /// Every batch handed to the cloud, in the order it was committed.
  final List<List<SyncWrite>> committedBatches = [];

  /// Documents the cloud will return, keyed by collection.
  final Map<String, List<Map<String, dynamic>>> remoteDocuments = {};

  /// Collections that should throw instead of answering.
  final Set<String> failingCollections = {};

  /// Thrown by the next [commitBatch]; cleared once used.
  Object? nextCommitError;

  int commitAttempts = 0;
  int fetchAttempts = 0;

  /// Stores created, and profiles written, so registration can be checked
  /// without a live project.

  @override
  bool get isInitialized => initialised;

  List<SyncWrite> get allWrites =>
      committedBatches.expand((batch) => batch).toList();

  @override
  Future<void> commitBatch({
    required String uid,
    required List<SyncWrite> writes,
    required String sourceDevice,
  }) async {
    commitAttempts++;
    final error = nextCommitError;
    if (error != null) {
      nextCommitError = null;
      throw error;
    }
    committedBatches.add(List.of(writes));
  }

  @override
  Future<int> fetchCollectionPages({
    required String uid,
    required String collection,
    required Future<void> Function(List<Map<String, dynamic>> page) onPage,
    DateTime? since,
    int pageSize = 300,
  }) async {
    fetchAttempts++;
    if (failingCollections.contains(collection)) {
      throw Exception('permission-denied: $collection');
    }

    final documents = remoteDocuments[collection] ?? const [];
    if (documents.isEmpty) return 0;

    // Delivered in pages so a test can prove the caller handles more than one.
    for (var i = 0; i < documents.length; i += pageSize) {
      await onPage(documents.skip(i).take(pageSize).toList());
    }
    return documents.length;
  }
}
