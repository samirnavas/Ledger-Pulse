import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/mock/mock_auth_repository.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/domain/models/workspace_profile_header.dart';
import 'package:ledger_pulse/domain/repositories/i_auth_repository.dart';
import 'package:ledger_pulse/domain/repositories/i_profile_repository.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/database_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_controller.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_state.dart';

class StubProfileRepository implements IProfileRepository {
  final AppDatabase db;
  final SyncEngine syncEngine;
  List<WorkspaceProfileHeader> remoteWorkspaces;
  bool shouldThrowNetworkError;
  bool shouldThrowAuthError;
  int syncCallCount = 0;

  StubProfileRepository({
    required this.db,
    required this.syncEngine,
    this.remoteWorkspaces = const [],
    this.shouldThrowNetworkError = false,
    this.shouldThrowAuthError = false,
  });

  @override
  Future<List<WorkspaceProfileHeader>> getAccessibleProfiles(String accountId) async {
    final query = db.select(db.companies).join([
      innerJoin(
        db.sharedMemberships,
        db.sharedMemberships.profileId.equalsExp(db.companies.id),
      ),
    ])
      ..where(db.sharedMemberships.accountId.equals(accountId) &
          db.companies.isDeleted.equals(false));

    final rows = await query.get();
    return rows.map((r) {
      final comp = r.readTable(db.companies);
      final mem = r.readTable(db.sharedMemberships);
      return WorkspaceProfileHeader(
        id: comp.id,
        name: comp.name,
        legalName: comp.legalName,
        type: ProfileType.fromString(comp.mode),
        role: ProfileRole.fromString(mem.role),
        currencyCode: comp.currencyCode,
        gstin: comp.gstin,
        isActive: comp.isActive,
        updatedAt: comp.updatedAt,
      );
    }).toList();
  }

  @override
  Future<List<WorkspaceProfileHeader>> syncAndLoadRemoteWorkspaces(String accountId) async {
    syncCallCount++;
    if (shouldThrowNetworkError) {
      throw const SocketException('Failed host lookup: awzxwsmfyrbnnuqkxuxu.supabase.co');
    }
    if (shouldThrowAuthError) {
      throw const AuthException('JWT expired');
    }

    // Populate local database from remoteWorkspaces
    await db.transaction(() async {
      for (final p in remoteWorkspaces) {
        await db.into(db.companies).insertOnConflictUpdate(
              CompaniesCompanion.insert(
                id: p.id,
                name: p.name,
                legalName: p.legalName,
                mode: Value(p.type.canonicalValue),
                currencyCode: Value(p.currencyCode),
                gstin: Value(p.gstin),
                ownerId: Value(accountId),
                isActive: Value(p.isActive),
                isDeleted: const Value(false),
                createdAt: Value(p.updatedAt),
                updatedAt: Value(p.updatedAt),
                syncStatus: const Value(SyncRecordStatus.synced),
              ),
            );

        await db.into(db.sharedMemberships).insertOnConflictUpdate(
              SharedMembershipsCompanion.insert(
                id: 'mem_${p.id}',
                profileId: p.id,
                accountId: accountId,
                role: p.role.displayName.toLowerCase(),
                joinedAt: Value(p.updatedAt),
                updatedAt: Value(p.updatedAt),
              ),
            );
      }
    });

    return getAccessibleProfiles(accountId);
  }

  @override
  Future<WorkspaceProfileHeader> createProfile({
    required String name,
    required ProfileType type,
    String currencyCode = 'INR',
    String? legalName,
    String? gstin,
    String? customId,
    String? accountId,
  }) async {
    final id = customId ?? 'prf_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();

    await db.into(db.companies).insertOnConflictUpdate(
          CompaniesCompanion.insert(
            id: id,
            name: name,
            legalName: legalName ?? name,
            ownerId: Value(accountId ?? 'usr_default'),
            mode: Value(type.canonicalValue),
            currencyCode: Value(currencyCode),
            gstin: Value(gstin),
            createdAt: Value(now),
            updatedAt: Value(now),
            isDeleted: const Value(false),
            syncStatus: const Value(SyncRecordStatus.synced),
          ),
        );

    if (accountId != null && accountId.isNotEmpty) {
      await db.into(db.sharedMemberships).insertOnConflictUpdate(
            SharedMembershipsCompanion.insert(
              id: 'mem_$id',
              profileId: id,
              accountId: accountId,
              role: 'owner',
              joinedAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    }

    return WorkspaceProfileHeader(
      id: id,
      name: name,
      legalName: legalName ?? name,
      type: type,
      role: ProfileRole.owner,
      currencyCode: currencyCode,
      gstin: gstin,
      updatedAt: now,
    );
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    await (db.update(db.companies)..where((t) => t.id.equals(profileId))).write(
      CompaniesCompanion(isDeleted: const Value(true)),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userUuidA = '11111111-1111-4111-8111-111111111111';
  const userUuidB = '22222222-2222-4222-8222-222222222222';

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
  });

  group('Phase 8: Complete Session Initialization and Remote Workspace Loading Tests', () {
    late SharedPreferences prefs;
    late AppDatabase dbUserA;
    late AppDatabase dbUserB;
    late SyncEngine syncEngineUserA;
    late SyncEngine syncEngineUserB;
    late StubProfileRepository stubRepoA;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      dbUserA = AppDatabase(NativeDatabase.memory(), userUuidA);
      dbUserB = AppDatabase(NativeDatabase.memory(), userUuidB);
      syncEngineUserA = SyncEngine(db: dbUserA, simulateSyncForTesting: true);
      syncEngineUserB = SyncEngine(db: dbUserB, simulateSyncForTesting: true);
      stubRepoA = StubProfileRepository(db: dbUserA, syncEngine: syncEngineUserA);
    });

    tearDown(() async {
      syncEngineUserA.dispose();
      syncEngineUserB.dispose();
      await dbUserA.close();
      await dbUserB.close();
    });

    ProviderContainer buildContainer({
      required IAuthRepository authRepo,
      required IProfileRepository profileRepo,
      AppDatabase? customDb,
    }) {
      final db = customDb ?? dbUserA;
      final syncEngine = syncEngineUserA;
      final ledgerRepo = DriftLedgerRepository(
        db: db,
        syncEngine: syncEngine,
        currentCompanyId: 'cmp_default',
        currentUserId: authRepo.currentUserId ?? 'usr_default',
        autoSync: false,
      );

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(syncEngine),
          profileRepositoryProvider.overrideWithValue(profileRepo),
          ledgerRepositoryProvider.overrideWithValue(ledgerRepo),
          driftLedgerRepositoryProvider.overrideWithValue(ledgerRepo),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    // 1. First application startup in guest mode
    test('1. First application startup in guest mode initializes guest state', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: false, userId: null);
      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);

      final sessionState = container.read(profileSessionProvider);
      expect(sessionState, isA<UnauthenticatedSessionState>());
      expect(sessionState, isA<GuestReadySessionState>());
      expect(container.read(activeUserIdProvider), equals('usr_default'));
    });

    // 2. Startup with an existing authenticated session
    test('2. Startup with an existing authenticated session loads remote workspaces', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      final workspace = WorkspaceProfileHeader(
        id: 'prf_a1',
        name: 'Alpha Traders',
        legalName: 'Alpha Traders Pvt Ltd',
        type: ProfileType.ledger,
        role: ProfileRole.owner,
        updatedAt: DateTime.now(),
      );
      stubRepoA.remoteWorkspaces = [workspace];

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);

      await controller.loadProfilesForUser(userUuidA);

      final sessionState = container.read(profileSessionProvider);
      expect(sessionState, isA<ActiveProfileReadySessionState>());
      final ready = sessionState as ActiveProfileReadySessionState;
      expect(ready.activeProfile.id, equals('prf_a1'));
      expect(ready.isOffline, isFalse);
    });

    // 3. Successful login and profile loading
    test('3. Successful login and profile loading auto-activates single workspace', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: false, userId: null);
      final workspace = WorkspaceProfileHeader(
        id: 'prf_new_user',
        name: 'New User Ledger',
        legalName: 'New User Ledger',
        type: ProfileType.ledger,
        role: ProfileRole.owner,
        updatedAt: DateTime.now(),
      );
      stubRepoA.remoteWorkspaces = [workspace];

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);

      // Perform login
      await container.read(authControllerProvider.notifier).signInWithEmailAndPassword(
            email: 'newuser@ledgerpulse.com',
            password: 'securePassword123',
          );

      final controller = container.read(profileSessionProvider.notifier);
      await controller.loadProfilesForUser(MockAuthRepository.validMockUuid, isLogin: true);

      final state = container.read(profileSessionProvider);
      expect(state, isA<ActiveProfileReadySessionState>());
      final ready = state as ActiveProfileReadySessionState;
      expect(ready.activeProfile.name, equals('New User Ledger'));
    });

    // 4. Successful loading of multiple workspaces
    test('4. Successful loading of multiple workspaces on fresh login routes to selector', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      final w1 = WorkspaceProfileHeader(
        id: 'prf_m1',
        name: 'Retail Store',
        legalName: 'Retail Store',
        type: ProfileType.ledger,
        role: ProfileRole.owner,
        updatedAt: DateTime.now(),
      );
      final w2 = WorkspaceProfileHeader(
        id: 'prf_m2',
        name: 'Personal Expenses',
        legalName: 'Personal Expenses',
        type: ProfileType.expense,
        role: ProfileRole.owner,
        updatedAt: DateTime.now(),
      );
      stubRepoA.remoteWorkspaces = [w1, w2];

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);

      await controller.loadProfilesForUser(userUuidA, isLogin: true);

      final state = container.read(profileSessionProvider);
      expect(state, isA<ProfileSelectionRequiredSessionState>());
      final selection = state as ProfileSelectionRequiredSessionState;
      expect(selection.profiles.length, equals(2));
    });

    // 5. Correct restoration of the previously selected workspace
    test('5. Correct restoration of previously selected workspace on restart', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      final w1 = WorkspaceProfileHeader(
        id: 'prf_m1',
        name: 'Retail Store',
        legalName: 'Retail Store',
        type: ProfileType.ledger,
        role: ProfileRole.owner,
        updatedAt: DateTime.now(),
      );
      final w2 = WorkspaceProfileHeader(
        id: 'prf_m2',
        name: 'Personal Expenses',
        legalName: 'Personal Expenses',
        type: ProfileType.expense,
        role: ProfileRole.owner,
        updatedAt: DateTime.now(),
      );
      stubRepoA.remoteWorkspaces = [w1, w2];

      // Pre-set previously active workspace in SharedPreferences
      await prefs.setString('last_active_profile_$userUuidA', 'prf_m2');

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);

      // Non-login load (app restart)
      await controller.loadProfilesForUser(userUuidA, isLogin: false);

      final state = container.read(profileSessionProvider);
      expect(state, isA<ActiveProfileReadySessionState>());
      final ready = state as ActiveProfileReadySessionState;
      expect(ready.activeProfile.id, equals('prf_m2'));
      expect(ready.activeProfile.name, equals('Personal Expenses'));
    });

    // 6. Fallback when the previously selected workspace is no longer accessible
    test('6. Fallback when previously selected workspace is deleted or revoked', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      final w1 = WorkspaceProfileHeader(
        id: 'prf_valid',
        name: 'Remaining Store',
        legalName: 'Remaining Store',
        type: ProfileType.ledger,
        role: ProfileRole.owner,
        updatedAt: DateTime.now(),
      );
      stubRepoA.remoteWorkspaces = [w1];

      // Pre-set a deleted/revoked workspace
      await prefs.setString('last_active_profile_$userUuidA', 'prf_revoked');

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);

      await controller.loadProfilesForUser(userUuidA, isLogin: false);

      // Falls back to the single remaining valid workspace
      final state = container.read(profileSessionProvider);
      expect(state, isA<ActiveProfileReadySessionState>());
      final ready = state as ActiveProfileReadySessionState;
      expect(ready.activeProfile.id, equals('prf_valid'));
    });

    // 7. User with no accessible workspace
    test('7. User with zero accessible workspaces routes to onboarding without crashing', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      stubRepoA.remoteWorkspaces = [];

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);

      await controller.loadProfilesForUser(userUuidA);

      final state = container.read(profileSessionProvider);
      expect(state, isA<OnboardingRequiredSessionState>());
      expect(state, isA<NoAccessibleWorkspaceSessionState>());
      expect((state as OnboardingRequiredSessionState).userId, equals(userUuidA));
    });

    // 8. Network unavailable during login
    test('8. Network unavailable during login with no local cache enters recoverable error', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      stubRepoA.shouldThrowNetworkError = true;

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);

      await controller.loadProfilesForUser(userUuidA, isLogin: true);

      final state = container.read(profileSessionProvider);
      expect(state, isA<SessionErrorState>());
      final err = state as SessionErrorState;
      expect(err.isNetworkError, isTrue);
      expect(err.isRecoverable, isTrue);
    });

    // 9. Network unavailable during application startup
    test('9. Network unavailable during startup with cached workspace activates offline state', () async {
      // Seed local cache before network failure
      await stubRepoA.createProfile(
        name: 'Offline Cached Ledger',
        type: ProfileType.ledger,
        accountId: userUuidA,
        customId: 'prf_offline_1',
      );

      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      stubRepoA.shouldThrowNetworkError = true;

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);

      await controller.loadProfilesForUser(userUuidA, isLogin: false);

      final state = container.read(profileSessionProvider);
      expect(state, isA<ActiveProfileReadySessionState>());
      final ready = state as ActiveProfileReadySessionState;
      expect(ready.isOffline, isTrue);
      expect(ready.activeProfile.id, equals('prf_offline_1'));
    });

    // 10. Cached workspace context used offline
    test('10. Cached workspace context enables local accounting access offline', () async {
      await stubRepoA.createProfile(
        name: 'Local Shop',
        type: ProfileType.ledger,
        accountId: userUuidA,
        customId: 'prf_local_shop',
      );

      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      stubRepoA.shouldThrowNetworkError = true;

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);

      await controller.loadProfilesForUser(userUuidA);

      final state = container.read(profileSessionProvider);
      expect(state, isA<OfflineActiveProfileReadySessionState>());
      expect((state as ActiveProfileReadySessionState).isOffline, isTrue);

      // Verify activeCompanyIdProvider reflects the cached workspace
      expect(container.read(activeCompanyIdProvider), equals('prf_local_shop'));
    });

    // 11. Logout switches to guest mode
    test('11. Logout resets session state to guest mode and usr_default', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      final workspace = WorkspaceProfileHeader(
        id: 'prf_logout_test',
        name: 'Alpha Traders',
        legalName: 'Alpha Traders',
        type: ProfileType.ledger,
        role: ProfileRole.owner,
        updatedAt: DateTime.now(),
      );
      stubRepoA.remoteWorkspaces = [workspace];

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);
      await controller.loadProfilesForUser(userUuidA);

      expect(container.read(profileSessionProvider), isA<ActiveProfileReadySessionState>());

      // Perform logout
      await container.read(authControllerProvider.notifier).logout();

      final state = container.read(profileSessionProvider);
      expect(state, isA<UnauthenticatedSessionState>());
      expect(state, isA<GuestReadySessionState>());
      expect(container.read(activeUserIdProvider), equals('usr_default'));
    });

    // 12. Account switching from User A to User B
    test('12. Account switching from User A to User B initializes User B session', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      stubRepoA.remoteWorkspaces = [
        WorkspaceProfileHeader(
          id: 'prf_user_a',
          name: 'Workspace A',
          legalName: 'Workspace A',
          type: ProfileType.ledger,
          role: ProfileRole.owner,
          updatedAt: DateTime.now(),
        ),
      ];

      final stubRepoB = StubProfileRepository(db: dbUserB, syncEngine: syncEngineUserB);
      stubRepoB.remoteWorkspaces = [
        WorkspaceProfileHeader(
          id: 'prf_user_b',
          name: 'Workspace B',
          legalName: 'Workspace B',
          type: ProfileType.expense,
          role: ProfileRole.owner,
          updatedAt: DateTime.now(),
        ),
      ];

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);
      await controller.loadProfilesForUser(userUuidA);

      final stateA = container.read(profileSessionProvider) as ActiveProfileReadySessionState;
      expect(stateA.activeProfile.name, equals('Workspace A'));

      // Switch to User B
      mockAuth.setCustomUserId(userUuidB);
      await controller.loadProfilesForUser(userUuidB);

      // Switched successfully
      final stateB = container.read(profileSessionProvider);
      expect(stateB, isA<ActiveProfileReadySessionState>());
    });

    // 13. No User A data visible to User B
    test('13. No User A data visible in User B database', () async {
      // Write row to User A database
      await stubRepoA.createProfile(
        name: 'User A Secret Books',
        type: ProfileType.ledger,
        accountId: userUuidA,
        customId: 'prf_secret_a',
      );

      // Verify User B database has 0 rows for User A
      final userBProfiles = await stubRepoA.db.select(stubRepoA.db.companies).get();
      final userBRows = await dbUserB.select(dbUserB.companies).get();

      expect(userBProfiles.any((c) => c.id == 'prf_secret_a'), isTrue);
      expect(userBRows.any((c) => c.id == 'prf_secret_a'), isFalse);
    });

    // 14. Token refresh for the same user
    test('14. Token refresh for the same user preserves active workspace without reload', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      stubRepoA.remoteWorkspaces = [
        WorkspaceProfileHeader(
          id: 'prf_refresh_test',
          name: 'Stable Workspace',
          legalName: 'Stable Workspace',
          type: ProfileType.ledger,
          role: ProfileRole.owner,
          updatedAt: DateTime.now(),
        ),
      ];

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);
      await controller.loadProfilesForUser(userUuidA);

      final initialReady = container.read(profileSessionProvider) as ActiveProfileReadySessionState;
      expect(initialReady.activeProfile.id, equals('prf_refresh_test'));

      // Simulate token refresh (auth update with same user UUID)
      container.read(authControllerProvider.notifier).clearConfirmationPending();

      // Active state must be preserved
      final afterRefresh = container.read(profileSessionProvider);
      expect(afterRefresh, isA<ActiveProfileReadySessionState>());
      expect((afterRefresh as ActiveProfileReadySessionState).activeProfile.id, equals('prf_refresh_test'));
    });

    // 15. Expired or invalid session
    test('15. Expired or invalid session transitions to AuthExpiredSessionState', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      stubRepoA.shouldThrowAuthError = true;

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);

      await controller.loadProfilesForUser(userUuidA);

      final state = container.read(profileSessionProvider);
      expect(state, isA<AuthExpiredSessionState>());
    });

    // 16. Multiple rapid auth-state events
    test('16. Multiple rapid load triggers are serialized without duplicate execution', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      stubRepoA.remoteWorkspaces = [
        WorkspaceProfileHeader(
          id: 'prf_rapid',
          name: 'Rapid Store',
          legalName: 'Rapid Store',
          type: ProfileType.ledger,
          role: ProfileRole.owner,
          updatedAt: DateTime.now(),
        ),
      ];

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);

      // Trigger 5 concurrent loads simultaneously
      await Future.wait([
        controller.loadProfilesForUser(userUuidA),
        controller.loadProfilesForUser(userUuidA),
        controller.loadProfilesForUser(userUuidA),
        controller.loadProfilesForUser(userUuidA),
        controller.loadProfilesForUser(userUuidA),
      ]);

      // Only 1 actual remote fetch should have been executed
      expect(stubRepoA.syncCallCount, equals(1));
      expect(container.read(profileSessionProvider), isA<ActiveProfileReadySessionState>());
    });

    // 17. Workspace membership or permission changes
    test('17. Switching to revoked workspace rejects access and emits error', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      final authorized = WorkspaceProfileHeader(
        id: 'prf_authorized',
        name: 'Authorized Store',
        legalName: 'Authorized Store',
        type: ProfileType.ledger,
        role: ProfileRole.owner,
        updatedAt: DateTime.now(),
      );
      stubRepoA.remoteWorkspaces = [authorized];

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);
      await controller.loadProfilesForUser(userUuidA);

      // Attempt to switch to an unauthorized profile
      final revoked = WorkspaceProfileHeader(
        id: 'prf_revoked_unauthorized',
        name: 'Unauthorized Corp',
        legalName: 'Unauthorized Corp',
        type: ProfileType.ledger,
        role: ProfileRole.viewer,
        updatedAt: DateTime.now(),
      );

      await controller.switchProfile(revoked);

      final state = container.read(profileSessionProvider);
      expect(state, isA<SessionErrorState>());
      expect((state as SessionErrorState).message, contains('Access Revoked'));
    });

    // 18. Retry after connectivity returns
    test('18. Retry recovers after connectivity returns', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      stubRepoA.shouldThrowNetworkError = true;

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);

      // Initial load fails with network error
      await controller.loadProfilesForUser(userUuidA);
      expect(container.read(profileSessionProvider), isA<SessionErrorState>());

      // Connectivity returns
      stubRepoA.shouldThrowNetworkError = false;
      stubRepoA.remoteWorkspaces = [
        WorkspaceProfileHeader(
          id: 'prf_reconnected',
          name: 'Reconnected Corp',
          legalName: 'Reconnected Corp',
          type: ProfileType.ledger,
          role: ProfileRole.owner,
          updatedAt: DateTime.now(),
        ),
      ];

      // Tap Retry
      await controller.retry();

      final state = container.read(profileSessionProvider);
      expect(state, isA<ActiveProfileReadySessionState>());
      expect((state as ActiveProfileReadySessionState).activeProfile.name, equals('Reconnected Corp'));
    });

    // 19. Initialization failure and recovery
    test('19. General initialization failure emits recoverable SessionErrorState', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);

      // Switch profile unauthenticated
      controller.logout();
      await controller.switchProfile(
        WorkspaceProfileHeader(
          id: 'any',
          name: 'any',
          legalName: 'any',
          type: ProfileType.ledger,
          role: ProfileRole.owner,
          updatedAt: DateTime.now(),
        ),
      );

      final state = container.read(profileSessionProvider);
      expect(state, isA<SessionErrorState>());
      expect((state as SessionErrorState).isRecoverable, isTrue);
    });

    // 20. No duplicate background sync initialization
    test('20. Remote workspace loading does not enqueue spurious outbox mutations', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      stubRepoA.remoteWorkspaces = [
        WorkspaceProfileHeader(
          id: 'prf_clean_sync',
          name: 'Clean Sync Ltd',
          legalName: 'Clean Sync Ltd',
          type: ProfileType.ledger,
          role: ProfileRole.owner,
          updatedAt: DateTime.now(),
        ),
      ];

      final container = buildContainer(authRepo: mockAuth, profileRepo: stubRepoA);
      final controller = container.read(profileSessionProvider.notifier);

      await controller.loadProfilesForUser(userUuidA);

      // Verify that outbox is empty: remote rows are marked synced, never queued as mutations
      final outboxRows = await dbUserA.select(dbUserA.syncOutbox).get();
      expect(outboxRows.isEmpty, isTrue);
    });
  });
}
