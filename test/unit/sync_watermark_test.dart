import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atomid/data/sync/entity_codec.dart';
import 'package:atomid/domain/services/auth_service.dart';
import 'package:atomid/domain/services/session_service.dart';
import 'package:atomid/domain/services/sync_service.dart';

import '../support/fake_firebase_repository.dart';
import '../support/test_store.dart';

class _MockUser extends Mock implements User {}

class _FakeAuthService extends AuthService {
  _FakeAuthService(super.repository, {this.user});
  final User? user;
  @override
  User? get currentUser => user;
}

class _FakeSessionService extends SessionService {
  _FakeSessionService(super.auth);

  DateTime? storedWatermark;

  @override
  String get deviceId => 'dev_test_abcd';
  @override
  String? get cloudUid => 'uid_under_test';
  @override
  DateTime? get lastPulledAt => storedWatermark;
  @override
  Future<void> setLastPulledAt(DateTime value) async => storedWatermark = value;
  @override
  Future<void> clearLastPulledAt() async => storedWatermark = null;
}

/// Cover for P-1: the incremental pull path existed, was correct, and nothing
/// ever reached it — every sign-in re-downloaded every collection in full.
///
/// The risk in switching it on is the opposite failure, and it is worse:
/// Firestore's `where('updatedAt', >)` *omits* documents without the field
/// rather than ranking them, so a collection whose payloads lacked it would
/// come back empty and report success. These pin down when the watermark may
/// be used and, more importantly, when it must not be.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;
  late FakeFirebaseRepository cloud;
  late _FakeSessionService session;
  late SyncService sync;

  setUp(() async {
    store = await TestStore.open();
    cloud = FakeFirebaseRepository();
    final auth = _FakeAuthService(cloud, user: _MockUser());
    session = _FakeSessionService(auth);
    sync = SyncService(store.repository, cloud, auth, session);
  });

  tearDown(() => store.close());

  group('the first pull', () {
    test('asks for everything, because nothing is trusted yet', () async {
      expect(
        session.lastPulledAt,
        isNull,
        reason: 'precondition: a fresh install has no watermark',
      );

      await sync.pullAll();

      expect(
        cloud.sinceByCollection,
        isNotEmpty,
        reason: 'the pull should actually have asked for something',
      );
      for (final entry in cloud.sinceByCollection.entries) {
        expect(
          entry.value,
          isNull,
          reason: '${entry.key} must be fetched in full on a first pull',
        );
      }
    });

    test('records a watermark once every collection answered', () async {
      final before = DateTime.now();
      await sync.pullAll();

      expect(session.lastPulledAt, isNotNull);
      expect(
        session.lastPulledAt!.isBefore(
          before.subtract(const Duration(seconds: 1)),
        ),
        isFalse,
        reason: 'the watermark should be from this pull, not the past',
      );
    });
  });

  group('a subsequent pull', () {
    test('asks only for what changed', () async {
      await sync.pullAll();
      final firstWatermark = session.lastPulledAt!;
      cloud.sinceByCollection.clear();

      await sync.pullAll();

      final incremental = EntityCodec.pullOrder
          .where((t) => !EntityCodec.alwaysFullPull.contains(t))
          .map(EntityCodec.collectionFor);

      for (final collection in incremental) {
        expect(
          cloud.sinceByCollection[collection],
          firstWatermark,
          reason: '$collection should have been asked incrementally',
        );
      }
    });

    test('still fetches config records in full', () async {
      await sync.pullAll();
      cloud.sinceByCollection.clear();
      await sync.pullAll();

      // All four config singletons share one collection.
      expect(
        cloud.sinceByCollection['config'],
        isNull,
        reason:
            'config keeps no timestamp of its own, so it cannot be '
            'filtered on one',
      );
    });

    test('an explicit full refresh ignores the watermark', () async {
      await sync.pullAll();
      cloud.sinceByCollection.clear();

      await sync.pullAll(full: true);

      for (final entry in cloud.sinceByCollection.entries) {
        expect(
          entry.value,
          isNull,
          reason: '${entry.key} must ignore the watermark when full is asked',
        );
      }
    });
  });

  group('the watermark never advances past an incomplete pull', () {
    test('a failed collection leaves it untouched', () async {
      cloud.failingCollections.add('customers');

      await sync.pullAll();

      expect(
        session.lastPulledAt,
        isNull,
        reason:
            'advancing here would mean those customers are never '
            'requested again',
      );
    });

    test('a later success does advance it', () async {
      cloud.failingCollections.add('customers');
      await sync.pullAll();
      expect(session.lastPulledAt, isNull);

      cloud.failingCollections.clear();
      await sync.pullAll();

      expect(session.lastPulledAt, isNotNull);
    });

    test('a pull that failed still asked for everything', () async {
      cloud.failingCollections.add('customers');
      await sync.pullAll();
      cloud.failingCollections.clear();
      cloud.sinceByCollection.clear();

      await sync.pullAll();

      expect(
        cloud.sinceByCollection[EntityCodec.collectionFor('Sale')],
        isNull,
        reason: 'with no trustworthy watermark the retry must be full',
      );
    });
  });

  /// The rules live on the real [SessionService], so these exercise it rather
  /// than the fake — a fake that stores whatever it is handed would prove
  /// nothing about them.
  group('a watermark that cannot be trusted is discarded', () {
    late SessionService real;

    setUp(() async {
      // `initialised: false` keeps `authStateChanges` on the empty stream, so
      // init() can subscribe without a live Firebase behind it.
      real = SessionService(
        _FakeAuthService(FakeFirebaseRepository(initialised: false)),
      );
      await real.init();
    });

    tearDown(() => real.dispose());

    test('a value written and read back survives the round trip', () async {
      final at = DateTime(2026, 6, 15, 10, 30);
      await real.setLastPulledAt(at);

      expect(real.lastPulledAt, at);
    });

    test('one dated in the future is refused', () async {
      await real.setLastPulledAt(DateTime.now().add(const Duration(days: 2)));

      expect(
        real.lastPulledAt,
        isNull,
        reason:
            'trusting it would skip every record written between now and '
            'then — a full pull is the safe answer',
      );
    });

    test('clearing it forces the next pull to be full', () async {
      await real.setLastPulledAt(DateTime(2026, 6, 15));
      expect(real.lastPulledAt, isNotNull);

      await real.clearLastPulledAt();

      expect(real.lastPulledAt, isNull);
    });
  });
}
