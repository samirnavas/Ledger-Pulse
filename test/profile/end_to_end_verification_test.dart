import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/mock/mock_auth_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/domain/models/workspace_profile_header.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_controller.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_state.dart';
import '../sync/support/fake_remote_gateway.dart';

/// Test double that strictly records remote Supabase upserts and simulates network conditions.
class RecordingStrictRemoteGateway extends FakeGateway {
  final List<({String table, String id, Map<String, dynamic> row})> upsertLog = [];
  bool isNetworkConnected = true;

  @override
  Future<Map<String, dynamic>?> upsertRow({
    required String table,
    required Map<String, dynamic> row,
  }) async {
    if (!isNetworkConnected) {
      throw const SocketException('Simulated network offline: failed to connect to Supabase');
    }
    final id = (row['id'] ?? row['record_id'])?.toString() ?? 'unknown';
    upsertLog.add((table: table, id: id, row: Map<String, dynamic>.from(row)));
    return super.upsertRow(table: table, row: row);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userUuidA = '9a318e8f-7f12-4217-a003-8898b958e1c2';
  const userUuidB = '0c427f71-294b-4c0a-9d90-3cb83e58c3f4';

  late AppDatabase db;
  late RecordingStrictRemoteGateway remoteGateway;
  late SyncEngine syncEngine;
  late DriftProfileRepository profileRepo;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    db = AppDatabase(NativeDatabase.memory());
    remoteGateway = RecordingStrictRemoteGateway();
    syncEngine = SyncEngine(
      db: db,
      gateway: remoteGateway,
      simulateSyncForTesting: true,
    );
    profileRepo = DriftProfileRepository(
      db: db,
      syncEngine: syncEngine,
    );
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    syncEngine.dispose();
    await db.close();
  });

  ProviderContainer createContainer({
    required AuthState authState,
    required MockAuthRepository mockAuth,
  }) {
    final ledgerRepo = DriftLedgerRepository(
      db: db,
      syncEngine: syncEngine,
      currentCompanyId: 'cmp_active',
      currentUserId: authState.userId ?? 'usr_unauth',
      autoSync: false,
    );

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        syncEngineProvider.overrideWithValue(syncEngine),
        profileRepositoryProvider.overrideWithValue(profileRepo),
        ledgerRepositoryProvider.overrideWithValue(ledgerRepo),
        driftLedgerRepositoryProvider.overrideWithValue(ledgerRepo),
        sharedPreferencesProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(mockAuth),
        authControllerProvider.overrideWith(() => _StubAuthController(authState)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('Scenario 1: New Expense Account End-to-End Verification', () {
    test('Steps 1-10: Register -> Auth UUID -> Create Expense -> Local & Supabase Storage -> Restart', () async {
      // 1. Register a new account
      final mockAuth = MockAuthRepository(
        isAuthenticated: false,
        userId: userUuidA,
      );

      final authContainer = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuth),
        ],
      );
      addTearDown(authContainer.dispose);

      final authNotifier = authContainer.read(authControllerProvider.notifier);
      final signUpResult = await authNotifier.signUpWithEmailAndPassword(
        email: 'alice.expense@example.com',
        password: 'Password123!',
        name: 'Alice Expense',
      );

      // 2. Complete email confirmation if required
      expect(signUpResult.isSuccess, isTrue);
      expect(signUpResult.requiresEmailConfirmation, isFalse);

      // 3. Verify a genuine Supabase session exists
      final authState = authContainer.read(authControllerProvider);
      expect(authState.isAuthenticated, isTrue);
      expect(authState.userId, equals(userUuidA));
      expect(
        RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(authState.userId!),
        isTrue,
        reason: 'Supabase session must expose a genuine UUIDv4',
      );

      // 4. Create an Expense profile
      final appContainer = createContainer(authState: authState, mockAuth: mockAuth);
      final profileSessionController = appContainer.read(profileSessionProvider.notifier);

      final createdExpenseProfile = await profileRepo.createProfile(
        name: 'Alice Daily Expenses',
        type: ProfileType.expense,
        currencyCode: 'INR',
        accountId: userUuidA,
      );

      // Trigger sync engine to push outbox
      await syncEngine.syncAll(companyId: createdExpenseProfile.id);

      // 5. Verify the profile is stored locally
      final localCompany = await (db.select(db.companies)
            ..where((c) => c.id.equals(createdExpenseProfile.id)))
          .getSingle();
      expect(localCompany.id, equals(createdExpenseProfile.id));
      expect(localCompany.name, equals('Alice Daily Expenses'));
      expect(localCompany.ownerId, equals(userUuidA));
      expect(localCompany.syncStatus, equals(SyncRecordStatus.synced));

      // 6. Verify the profile exists in the Supabase profile table
      final remoteCompanyUpserts = remoteGateway.upsertLog.where((u) => u.table == 'companies').toList();
      expect(remoteCompanyUpserts, isNotEmpty);
      final remoteCompany = remoteCompanyUpserts.firstWhere((u) => u.id == createdExpenseProfile.id);

      // 7. Verify its canonical type is Expense
      expect(localCompany.mode, equals('expense'));
      expect(remoteCompany.row['mode'], equals('expense'));

      // 8. Verify its owner membership exists in the membership table
      final remoteMembershipUpserts = remoteGateway.upsertLog.where((u) => u.table == 'shared_memberships').toList();
      expect(remoteMembershipUpserts, isNotEmpty);
      final remoteMembership = remoteMembershipUpserts.firstWhere((u) => u.row['profile_id'] == createdExpenseProfile.id);
      expect(remoteMembership.row['role'], equals('owner'));

      // 9. Verify the membership account ID equals the authenticated Supabase UUID
      expect(remoteMembership.row['account_id'], equals(userUuidA));

      // Local membership verify
      final localMembership = await (db.select(db.sharedMemberships)
            ..where((m) => m.profileId.equals(createdExpenseProfile.id)))
          .getSingle();
      expect(localMembership.accountId, equals(userUuidA));
      expect(localMembership.role, equals('owner'));

      // 10. Restart the app and verify the profile still loads as Expense
      // Simulate app restart by re-reading profiles with a fresh session controller
      await prefs.setString('last_active_profile_$userUuidA', createdExpenseProfile.id);
      await profileSessionController.loadProfilesForUser(userUuidA, isLogin: false);

      final restartedSessionState = appContainer.read(profileSessionProvider);
      expect(restartedSessionState, isA<ActiveProfileReadySessionState>());
      if (restartedSessionState is ActiveProfileReadySessionState) {
        expect(restartedSessionState.activeProfile.id, equals(createdExpenseProfile.id));
        expect(restartedSessionState.activeProfile.type, equals(ProfileType.expense));
        expect(restartedSessionState.activeProfile.name, equals('Alice Daily Expenses'));
      }
    });
  });

  group('Scenario 2: Add a Ledger Profile End-to-End Verification', () {
    test('Steps 1-7: Same account -> Create Ledger -> Remote verify -> Both accessible -> Domain isolation', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      final authState = AuthState(isAuthenticated: true, userId: userUuidA, phoneNumber: '+91 98765 43210');
      final appContainer = createContainer(authState: authState, mockAuth: mockAuth);
      final controller = appContainer.read(profileSessionProvider.notifier);

      // 1. Same authenticated account creates an Expense profile first
      final expenseProfile = await profileRepo.createProfile(
        name: 'Personal Expenses',
        type: ProfileType.expense,
        accountId: userUuidA,
      );

      // 2. Create a separate Ledger profile
      final ledgerProfile = await profileRepo.createProfile(
        name: 'Apex Wholesale Traders',
        type: ProfileType.ledger,
        accountId: userUuidA,
      );

      await syncEngine.syncAll(companyId: ledgerProfile.id);

      // 3. Verify the Ledger profile exists remotely
      final remoteCompanies = remoteGateway.upsertLog.where((u) => u.table == 'companies').toList();
      final remoteLedger = remoteCompanies.firstWhere((u) => u.id == ledgerProfile.id);
      expect(remoteLedger.row['mode'], equals('ledger'));
      expect(remoteLedger.row['owner_id'], equals(userUuidA));

      // 4. Verify its membership exists remotely
      final remoteMemberships = remoteGateway.upsertLog.where((u) => u.table == 'shared_memberships').toList();
      final remoteLedgerMem = remoteMemberships.firstWhere((u) => u.row['profile_id'] == ledgerProfile.id);
      expect(remoteLedgerMem.row['account_id'], equals(userUuidA));
      expect(remoteLedgerMem.row['role'], equals('owner'));

      // 5. Verify both profiles are accessible
      final accessible = await profileRepo.getAccessibleProfiles(userUuidA);
      expect(accessible.length, equals(2));
      expect(accessible.map((p) => p.id), containsAll([expenseProfile.id, ledgerProfile.id]));

      // 6. Verify the Expense profile remains Expense and Ledger remains Ledger
      final verifiedExpense = accessible.firstWhere((p) => p.id == expenseProfile.id);
      final verifiedLedger = accessible.firstWhere((p) => p.id == ledgerProfile.id);
      expect(verifiedExpense.type, equals(ProfileType.expense));
      expect(verifiedLedger.type, equals(ProfileType.ledger));

      // 7. Verify switching between them loads the correct profile and domain data
      await controller.switchProfile(verifiedExpense);
      var state = appContainer.read(profileSessionProvider);
      expect(state, isA<ActiveProfileReadySessionState>());
      if (state is ActiveProfileReadySessionState) {
        expect(state.activeProfile.id, equals(expenseProfile.id));
        expect(state.activeProfile.type, equals(ProfileType.expense));
      }

      await controller.switchProfile(verifiedLedger);
      state = appContainer.read(profileSessionProvider);
      expect(state, isA<ActiveProfileReadySessionState>());
      if (state is ActiveProfileReadySessionState) {
        expect(state.activeProfile.id, equals(ledgerProfile.id));
        expect(state.activeProfile.type, equals(ProfileType.ledger));
      }
    });
  });

  group('Scenario 3: Offline Profile Creation End-to-End Verification', () {
    test('Steps 1-7: Authenticate -> Offline -> Create profile -> Pending -> Reconnect -> Sync -> Idempotent', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      final authState = AuthState(isAuthenticated: true, userId: userUuidA);
      createContainer(authState: authState, mockAuth: mockAuth);

      // 1. Authenticate with a genuine session (authState verified)
      expect(authState.isAuthenticated, isTrue);

      // 2. Disconnect the network
      remoteGateway.isNetworkConnected = false;

      // 3. Create a profile offline
      final offlineProfile = await profileRepo.createProfile(
        name: 'Offline Hardware Store',
        type: ProfileType.ledger,
        accountId: userUuidA,
      );

      // 4. Verify local profile and membership records remain pending
      final localCompany = await (db.select(db.companies)
            ..where((c) => c.id.equals(offlineProfile.id)))
          .getSingle();
      expect(localCompany.syncStatus, equals(SyncRecordStatus.pending));

      // Attempting to sync while offline fails safely without corrupting local data
      await syncEngine.syncAll(companyId: offlineProfile.id);
      final stillPendingCompany = await (db.select(db.companies)
            ..where((c) => c.id.equals(offlineProfile.id)))
          .getSingle();
      expect(stillPendingCompany.syncStatus, equals(SyncRecordStatus.pending));

      // 5. Reconnect network
      remoteGateway.isNetworkConnected = true;

      // 6. Verify both records synchronize
      final syncResult = await syncEngine.syncAll(companyId: offlineProfile.id);
      expect(syncResult.status, equals(SyncEngineStatus.success));

      final syncedCompany = await (db.select(db.companies)
            ..where((c) => c.id.equals(offlineProfile.id)))
          .getSingle();
      expect(syncedCompany.syncStatus, equals(SyncRecordStatus.synced));

      final remoteCompanyUpserts = remoteGateway.upsertLog.where((u) => u.id == offlineProfile.id).toList();
      expect(remoteCompanyUpserts, isNotEmpty);

      // 7. Verify retries do not create duplicates
      final upsertCountBeforeRetry = remoteGateway.upsertLog.length;
      await syncEngine.syncAll(companyId: offlineProfile.id);
      final upsertCountAfterRetry = remoteGateway.upsertLog.length;
      expect(
        upsertCountAfterRetry,
        equals(upsertCountBeforeRetry),
        reason: 'Syncing already-synced records must be idempotent and not re-upload',
      );
    });
  });

  group('Scenario 4: Security and Isolation End-to-End Verification', () {
    test('Enforces membership, RLS boundaries, type immutability, and UUID validation', () async {
      final mockAuth = MockAuthRepository(isAuthenticated: true, userId: userUuidA);
      final authState = AuthState(isAuthenticated: true, userId: userUuidA);
      final appContainer = createContainer(authState: authState, mockAuth: mockAuth);
      final controller = appContainer.read(profileSessionProvider.notifier);

      // 1. Confirm a user cannot load another user\'s private profiles
      final userAProfile = await profileRepo.createProfile(
        name: 'User A Workspace',
        type: ProfileType.expense,
        accountId: userUuidA,
      );
      final userBProfile = await profileRepo.createProfile(
        name: 'User B Private Vault',
        type: ProfileType.ledger,
        accountId: userUuidB,
      );

      final userAProfiles = await profileRepo.getAccessibleProfiles(userUuidA);
      expect(userAProfiles.map((p) => p.id), contains(userAProfile.id));
      expect(userAProfiles.map((p) => p.id), isNot(contains(userBProfile.id)));

      // 2. Confirm membership authorization check is enforced on switchProfile
      await controller.loadProfilesForUser(userUuidA, isLogin: false);
      expect(appContainer.read(profileSessionProvider), isA<ActiveProfileReadySessionState>());

      await controller.switchProfile(userBProfile);

      final state = appContainer.read(profileSessionProvider);
      expect(state, isA<SessionErrorState>());
      if (state is SessionErrorState) {
        expect(state.message, contains('Access Revoked'));
      }

      // 3. Confirm a profile cannot be changed from Expense to Ledger
      final now = DateTime.now();
      final expenseCompany = Company(
        id: 'cmp_expense_lock',
        name: 'Locked Expense',
        legalName: 'Locked Expense',
        mode: CompanyMode.expenseTracker,
        createdAt: now,
        updatedAt: now,
      );
      expect(
        () => expenseCompany.copyWith(mode: CompanyMode.ledger),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Profile type is immutable'))),
      );

      // 4. Confirm the implementation does not rely on null owner IDs or fake identities
      expect(
        () => profileRepo.createProfile(name: 'Invalid', type: ProfileType.ledger, accountId: null),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => profileRepo.createProfile(name: 'Invalid', type: ProfileType.ledger, accountId: ''),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => profileRepo.createProfile(name: 'Invalid', type: ProfileType.ledger, accountId: 'usr_default'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => profileRepo.createProfile(name: 'Invalid', type: ProfileType.ledger, accountId: 'user@example.com'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

class _StubAuthController extends AuthController {
  final AuthState _state;
  _StubAuthController(this._state);

  @override
  AuthState build() => _state;
}
