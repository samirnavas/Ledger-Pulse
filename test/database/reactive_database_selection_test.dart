import 'dart:async';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/local/connection/connection.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/domain/repositories/i_auth_repository.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_controller.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_state.dart';

/// Test mock auth repository that allows dynamic state emission
class ReactiveMockAuthRepository implements IAuthRepository {
  bool _isAuth = false;
  String? _uid;
  String? _email;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  ReactiveMockAuthRepository({bool isAuth = false, String? uid, String? email})
      : _isAuth = isAuth,
        _uid = uid,
        _email = email;

  void emitLogin(String uid, {String? email}) {
    _isAuth = true;
    _uid = uid;
    _email = email ?? '$uid@example.com';
    _controller.add(true);
  }

  void emitLogout() {
    _isAuth = false;
    _uid = null;
    _email = null;
    _controller.add(false);
  }

  void emitTokenRefresh() {
    // Session token refreshed but user identity unchanged
    _controller.add(true);
  }

  @override
  bool get isAuthenticated => _isAuth;

  @override
  String? get currentUserId => _uid;

  @override
  String? get currentUserEmail => _email;

  @override
  String? get currentPhoneNumber => null;

  @override
  String? get currentUserName => 'Test User';

  @override
  String? get currentSessionToken => _isAuth ? 'header.payload.signature' : null;

  @override
  Stream<bool> get authStateStream => _controller.stream;

  @override
  Future<bool> signInWithEmailAndPassword({required String email, required String password}) async {
    emitLogin('usr_${email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}', email: email);
    return true;
  }

  Future<bool> signInWithPhone(String phone, String password) async => true;

  @override
  Future<bool> sendOtp(String phone) async => true;

  @override
  Future<bool> verifyOtp(String phone, String otp) async => true;

  @override
  Future<SignUpResult> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
  }) async => SignUpResult(isSuccess: true, userId: 'usr_new_signup');

  @override
  Future<void> logout() async {
    emitLogout();
  }

  void dispose() {
    _controller.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    const MethodChannel channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async => '.',
    );
  });

  group('Deterministic Identifier & Path Sanitization Tests', () {
    test('1. Guest sessions sanitize deterministically to usr_default', () {
      expect(sanitizeDatabaseIdentifier(null), equals('usr_default'));
      expect(sanitizeDatabaseIdentifier(''), equals('usr_default'));
      expect(sanitizeDatabaseIdentifier('   '), equals('usr_default'));
      expect(sanitizeDatabaseIdentifier('usr_default'), equals('usr_default'));
      expect(sanitizeDatabaseIdentifier('default'), equals('usr_default'));
    });

    test('2. Authenticated user UUIDs sanitize deterministically with usr_ prefix', () {
      const uuid = '8beb8fd9-5c48-4bfc-86b2-fe96c4beb75e';
      final sanitized = sanitizeDatabaseIdentifier(uuid);
      expect(sanitized, equals('usr_8beb8fd9-5c48-4bfc-86b2-fe96c4beb75e'));

      // If already prefixed, prefix is not duplicated
      expect(sanitizeDatabaseIdentifier('usr_test_user'), equals('usr_test_user'));
    });

    test('3. Dangerous path traversal characters and illegal characters are stripped', () {
      const malicious = '../../etc/passwd';
      final sanitized = sanitizeDatabaseIdentifier(malicious);
      expect(sanitized.contains('/'), isFalse);
      expect(sanitized.contains('\\'), isFalse);
      expect(sanitized.contains('..'), isFalse);
      expect(sanitized, equals('usr_______etc_passwd'));
    });
  });

  group('Reactive Database Lifecycle & User Isolation Tests', () {
    const userA = '8beb8fd9-5c48-4bfc-86b2-fe96c4beb75e';
    const userB = '7d592833-acc5-405f-bc5d-092df4778f93';

    test('1. Guest startup initializes guest database', () {
      final mockAuth = ReactiveMockAuthRepository(isAuth: false);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuth),
          appDatabaseProvider.overrideWith((ref) => AppDatabase(NativeDatabase.memory(), ref.watch(activeUserIdProvider))),
        ],
      );
      addTearDown(container.dispose);

      final activeUid = container.read(activeUserIdProvider);
      expect(activeUid, equals('usr_default'));

      final db = container.read(appDatabaseProvider);
      expect(db.userId, equals('usr_default'));
    });

    test('2. Authenticated startup initializes correct user database', () {
      final mockAuth = ReactiveMockAuthRepository(isAuth: true, uid: userA);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuth),
          appDatabaseProvider.overrideWith((ref) => AppDatabase(NativeDatabase.memory(), ref.watch(activeUserIdProvider))),
        ],
      );
      addTearDown(container.dispose);

      final activeUid = container.read(activeUserIdProvider);
      expect(activeUid, equals(userA));

      final db = container.read(appDatabaseProvider);
      expect(db.userId, equals(userA));
    });

    test('3. Logging in as User A reactively switches database to User A', () async {
      final mockAuth = ReactiveMockAuthRepository(isAuth: false);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuth),
          appDatabaseProvider.overrideWith((ref) => AppDatabase(NativeDatabase.memory(), ref.watch(activeUserIdProvider))),
        ],
      );
      addTearDown(container.dispose);

      // Initially guest
      expect(container.read(activeUserIdProvider), equals('usr_default'));
      final guestDb = container.read(appDatabaseProvider);

      // User A signs in
      mockAuth.emitLogin(userA);

      // Force Riverpod propagation
      await container.pump();

      expect(container.read(activeUserIdProvider), equals(userA));
      final userADb = container.read(appDatabaseProvider);

      // Must be a different database instance
      expect(identical(guestDb, userADb), isFalse);
      expect(userADb.userId, equals(userA));
    });

    test('4. Switching from User A to User B does not expose User A records', () async {
      // Create isolated in-memory DB instances to simulate separate physical user files
      final memoryDbA = AppDatabase(NativeDatabase.memory(), userA);
      final memoryDbB = AppDatabase(NativeDatabase.memory(), userB);

      // Seed a private company in User A's database
      await memoryDbA.into(memoryDbA.profiles).insert(
        ProfilesCompanion.insert(
          id: 'cmp_user_a_private',
          name: 'User A Secret Business',
          profileType: const Value('ledger'),
          ownerId: const Value(userA),
        ),
      );
      await memoryDbA.into(memoryDbA.companies).insert(
        CompaniesCompanion.insert(
          id: 'cmp_user_a_private',
          profileId: const Value('cmp_user_a_private'),
          name: 'User A Secret Business',
          legalName: 'User A Secret Business',
          ownerId: const Value(userA),
        ),
      );
      await memoryDbA.into(memoryDbA.sharedMemberships).insert(
        SharedMembershipsCompanion.insert(
          id: 'mem_a_1',
          profileId: 'cmp_user_a_private',
          accountId: userA,
          role: 'owner',
        ),
      );

      final mockAuth = ReactiveMockAuthRepository(isAuth: true, uid: userA);

      // Container dynamically serves memoryDbA when userA is active, memoryDbB when userB is active
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuth),
          appDatabaseProvider.overrideWith((ref) {
            final uid = ref.watch(activeUserIdProvider);
            return uid == userA ? memoryDbA : memoryDbB;
          }),
        ],
      );
      addTearDown(container.dispose);

      // 1. Verify User A sees their company
      final profileRepoA = container.read(profileRepositoryProvider);
      final profilesA = await profileRepoA.getAccessibleProfiles(userA);
      expect(profilesA.length, equals(1));
      expect(profilesA.first.name, equals('User A Secret Business'));

      // 2. Switch to User B
      mockAuth.emitLogin(userB);
      await container.pump();

      expect(container.read(activeUserIdProvider), equals(userB));
      final profileRepoB = container.read(profileRepositoryProvider);
      final profilesB = await profileRepoB.getAccessibleProfiles(userB);

      // User B MUST see zero of User A's companies!
      expect(profilesB.isEmpty, isTrue);

      // 3. User B creates their own company
      await memoryDbB.into(memoryDbB.profiles).insert(
        ProfilesCompanion.insert(
          id: 'cmp_user_b_workspace',
          name: 'User B Public Shop',
          profileType: const Value('ledger'),
          ownerId: const Value(userB),
        ),
      );
      await memoryDbB.into(memoryDbB.companies).insert(
        CompaniesCompanion.insert(
          id: 'cmp_user_b_workspace',
          profileId: const Value('cmp_user_b_workspace'),
          name: 'User B Public Shop',
          legalName: 'User B Public Shop',
          ownerId: const Value(userB),
        ),
      );
      await memoryDbB.into(memoryDbB.sharedMemberships).insert(
        SharedMembershipsCompanion.insert(
          id: 'mem_b_1',
          profileId: 'cmp_user_b_workspace',
          accountId: userB,
          role: 'owner',
        ),
      );

      final profilesBAfter = await profileRepoB.getAccessibleProfiles(userB);
      expect(profilesBAfter.length, equals(1));
      expect(profilesBAfter.first.name, equals('User B Public Shop'));

      // 4. Switch back to User A -> User A's private company remains intact
      mockAuth.emitLogin(userA);
      await container.pump();

      final profileRepoA2 = container.read(profileRepositoryProvider);
      final profilesA2 = await profileRepoA2.getAccessibleProfiles(userA);
      expect(profilesA2.length, equals(1));
      expect(profilesA2.first.name, equals('User A Secret Business'));
    });

    test('5. Logging out disposes authenticated state and switches to guest database', () async {
      final mockAuth = ReactiveMockAuthRepository(isAuth: true, uid: userA);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuth),
          appDatabaseProvider.overrideWith((ref) => AppDatabase(NativeDatabase.memory(), ref.watch(activeUserIdProvider))),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(activeUserIdProvider), equals(userA));
      final userDb = container.read(appDatabaseProvider);

      // Logout
      mockAuth.emitLogout();
      await container.pump();

      expect(container.read(activeUserIdProvider), equals('usr_default'));
      final postLogoutDb = container.read(appDatabaseProvider);
      expect(identical(userDb, postLogoutDb), isFalse);
      expect(postLogoutDb.userId, equals('usr_default'));

      // Session controller must transition to UnauthenticatedSessionState
      final sessionState = container.read(profileSessionProvider);
      expect(sessionState is UnauthenticatedSessionState, isTrue);
    });

    test('6. Token refresh for the same user does NOT recreate the database instance', () async {
      final mockAuth = ReactiveMockAuthRepository(isAuth: true, uid: userA);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuth),
          appDatabaseProvider.overrideWith((ref) => AppDatabase(NativeDatabase.memory(), ref.watch(activeUserIdProvider))),
        ],
      );
      addTearDown(container.dispose);

      final initialDb = container.read(appDatabaseProvider);

      // Trigger session refresh (same user)
      mockAuth.emitTokenRefresh();
      await container.pump();

      final afterRefreshDb = container.read(appDatabaseProvider);
      // Must be the identical database instance (not closed or recreated)
      expect(identical(initialDb, afterRefreshDb), isTrue);
    });

    test('7. Database-dependent repositories rebind to new database on user switch', () async {
      final mockAuth = ReactiveMockAuthRepository(isAuth: true, uid: userA);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuth),
          appDatabaseProvider.overrideWith((ref) => AppDatabase(NativeDatabase.memory(), ref.watch(activeUserIdProvider))),
        ],
      );
      addTearDown(container.dispose);

      final initialSync = container.read(syncEngineProvider);
      final initialProfileRepo = container.read(profileRepositoryProvider);
      final initialLedgerRepo = container.read(ledgerRepositoryProvider);

      // Switch user
      mockAuth.emitLogin(userB);
      await container.pump();

      final newSync = container.read(syncEngineProvider);
      final newProfileRepo = container.read(profileRepositoryProvider);
      final newLedgerRepo = container.read(ledgerRepositoryProvider);

      // Repositories must rebind to the new user's scoped database
      expect(identical(initialSync, newSync), isFalse);
      expect(identical(initialProfileRepo, newProfileRepo), isFalse);
      expect(identical(initialLedgerRepo, newLedgerRepo), isFalse);
    });

    test('8. Rapid account switching serializes cleanly without race conditions', () async {
      final mockAuth = ReactiveMockAuthRepository(isAuth: false);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuth),
          appDatabaseProvider.overrideWith((ref) => AppDatabase(NativeDatabase.memory(), ref.watch(activeUserIdProvider))),
        ],
      );
      addTearDown(container.dispose);

      // Rapidly toggle auth events
      mockAuth.emitLogin(userA);
      mockAuth.emitLogin(userB);
      mockAuth.emitLogout();
      mockAuth.emitLogin(userA);

      await container.pump();

      // Final state must settle cleanly on userA
      expect(container.read(activeUserIdProvider), equals(userA));
      final finalDb = container.read(appDatabaseProvider);
      expect(finalDb.userId, equals(userA));
    });

    test('9. Existing database schema and migration version 12 are preserved', () {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      expect(db.schemaVersion, equals(12));
    });
  });
}
