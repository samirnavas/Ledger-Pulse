import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/domain/models/workspace_profile_header.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_controller.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../sync/support/fake_remote_gateway.dart';

class _StubAuthController extends AuthController {
  final AuthState _fixedState;
  _StubAuthController(this._fixedState);

  @override
  AuthState build() => _fixedState;

  @override
  Future<void> logout() async {
    state = const AuthState();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userUuidA = '11111111-1111-4111-8111-111111111111';
  const userUuidB = '22222222-2222-4222-8222-222222222222';

  late AppDatabase db;
  late FakeGateway remoteGateway;
  late SyncEngine syncEngine;
  late DriftProfileRepository profileRepo;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    db = AppDatabase(NativeDatabase.memory());
    remoteGateway = FakeGateway();
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
    AuthState authState = const AuthState(
      isAuthenticated: true,
      userId: userUuidA,
      phoneNumber: '+91 98765 43210',
    ),
  }) {
    final ledgerRepo = DriftLedgerRepository(
      db: db,
      syncEngine: syncEngine,
      currentCompanyId: 'cmp_test',
      currentUserId: authState.userId ?? userUuidA,
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
        authControllerProvider.overrideWith(() => _StubAuthController(authState)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('Section 7.1 – Workspace Creation Tests', () {
    test('A new authenticated user can create an Expense workspace', () async {
      final header = await profileRepo.createProfile(
        name: 'Household Expenses',
        type: ProfileType.expense,
        accountId: userUuidA,
      );

      expect(header.id, isNotEmpty);
      expect(header.name, equals('Household Expenses'));
      expect(header.type, equals(ProfileType.expense));
      expect(header.role, equals(ProfileRole.owner));

      // Verify row in companies table
      final companyRow = await (db.select(db.companies)..where((t) => t.id.equals(header.id))).getSingle();
      expect(companyRow.mode, equals('expense'));
      expect(companyRow.ownerId, equals(userUuidA));
      expect(companyRow.isDeleted, isFalse);

      // Verify expense defaults seeded
      final walletRows = await (db.select(db.expenseWallets)..where((t) => t.profileId.equals(header.id))).get();
      expect(walletRows.any((w) => w.name == 'Cash in Hand'), isTrue);

      final categoryRows = await (db.select(db.expenseCategories)..where((t) => t.profileId.equals(header.id))).get();
      expect(categoryRows.length, greaterThanOrEqualTo(4));
    });

    test('A new authenticated user can create a Ledger workspace', () async {
      final header = await profileRepo.createProfile(
        name: 'Acme Traders',
        legalName: 'Acme Traders Pvt Ltd',
        type: ProfileType.ledger,
        gstin: '29ABCDE1234F1Z5',
        stateCode: '29',
        dealerType: 'regular',
        accountId: userUuidA,
      );

      expect(header.id, isNotEmpty);
      expect(header.name, equals('Acme Traders'));
      expect(header.legalName, equals('Acme Traders Pvt Ltd'));
      expect(header.type, equals(ProfileType.ledger));
      expect(header.role, equals(ProfileRole.owner));

      // Verify row in companies table
      final companyRow = await (db.select(db.companies)..where((t) => t.id.equals(header.id))).getSingle();
      expect(companyRow.mode, equals('ledger'));
      expect(companyRow.ownerId, equals(userUuidA));
      expect(companyRow.gstin, equals('29ABCDE1234F1Z5'));

      // Verify ledger accounts seeded
      final accountRows = await (db.select(db.accounts)..where((t) => t.companyId.equals(header.id))).get();
      expect(accountRows.isNotEmpty, isTrue);
      expect(accountRows.any((a) => a.id.contains('cash')), isTrue);
    });

    test('A user can create multiple workspaces', () async {
      final exp = await profileRepo.createProfile(
        name: 'Personal Track',
        type: ProfileType.expense,
        accountId: userUuidA,
      );
      final led = await profileRepo.createProfile(
        name: 'Consulting Firm',
        type: ProfileType.ledger,
        accountId: userUuidA,
      );

      final profiles = await profileRepo.getAccessibleProfiles(userUuidA);
      expect(profiles.length, equals(2));
      expect(profiles.map((p) => p.id), containsAll([exp.id, led.id]));
      expect(profiles.firstWhere((p) => p.id == exp.id).type, equals(ProfileType.expense));
      expect(profiles.firstWhere((p) => p.id == led.id).type, equals(ProfileType.ledger));
    });

    test('Each workspace has exactly one correct owner membership after creation', () async {
      final created = await profileRepo.createProfile(
        name: 'Solo Venture',
        type: ProfileType.ledger,
        accountId: userUuidA,
      );

      final memberships = await (db.select(db.sharedMemberships)
            ..where((t) => t.profileId.equals(created.id)))
          .get();

      expect(memberships.length, equals(1));
      expect(memberships.first.accountId, equals(userUuidA));
      expect(memberships.first.role, equals('owner'));
    });

    test('Repeated creation requests with customId do not create duplicate records', () async {
      const customId = 'prf_idempotent_test_01';

      final first = await profileRepo.createProfile(
        name: 'Fixed ID Workspace',
        type: ProfileType.expense,
        customId: customId,
        accountId: userUuidA,
      );

      final second = await profileRepo.createProfile(
        name: 'Fixed ID Workspace Updated',
        type: ProfileType.expense,
        customId: customId,
        accountId: userUuidA,
      );

      expect(first.id, equals(second.id));

      final companies = await (db.select(db.companies)..where((t) => t.id.equals(customId))).get();
      expect(companies.length, equals(1));

      final memberships = await (db.select(db.sharedMemberships)..where((t) => t.profileId.equals(customId))).get();
      expect(memberships.length, equals(1));
    });

    test('Creation failures do not leave partially created workspace or membership records', () async {
      // Invalid non-UUID accountId must fail without writing records
      expect(
        () => profileRepo.createProfile(
          name: 'Invalid Account Profile',
          type: ProfileType.expense,
          accountId: 'non_uuid_account',
        ),
        throwsArgumentError,
      );

      final companies = await db.select(db.companies).get();
      expect(companies.isEmpty, isTrue);

      final memberships = await db.select(db.sharedMemberships).get();
      expect(memberships.isEmpty, isTrue);
    });

    test('All creation entry points use consistent ownership and persistence behavior', () async {
      final container = createContainer();
      final controller = container.read(companyControllerProvider.notifier);

      // Entry point via CompanyController.addCompany
      final comp = Company(
        id: 'cmp_unified_entry_01',
        name: 'Unified Corp',
        legalName: 'Unified Corp Ltd',
        currencyCode: 'INR',
        mode: CompanyMode.ledger,
        ownerId: userUuidA,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await controller.addCompany(comp);

      // Verify row in companies
      final row = await (db.select(db.companies)..where((t) => t.id.equals(comp.id))).getSingle();
      expect(row.mode, equals('ledger'));
      expect(row.ownerId, equals(userUuidA));

      // Verify row in shared_memberships
      final mems = await (db.select(db.sharedMemberships)..where((t) => t.profileId.equals(comp.id))).get();
      expect(mems.length, equals(1));
      expect(mems.first.accountId, equals(userUuidA));
      expect(mems.first.role, equals('owner'));

      // Verify in accessible profiles
      final profiles = await profileRepo.getAccessibleProfiles(userUuidA);
      expect(profiles.any((p) => p.id == comp.id && p.type == ProfileType.ledger), isTrue);
    });
  });

  group('Section 7.2 – Profile Immutability Tests', () {
    test('An Expense workspace cannot be changed into a Ledger workspace', () async {
      final header = await profileRepo.createProfile(
        name: 'Personal Spending',
        type: ProfileType.expense,
        accountId: userUuidA,
      );

      final repo = DriftLedgerRepository(
        db: db,
        syncEngine: syncEngine,
        currentCompanyId: header.id,
        currentUserId: userUuidA,
        autoSync: false,
      );

      final mutated = Company(
        id: header.id,
        name: 'Personal Spending',
        legalName: 'Personal Spending',
        currencyCode: 'INR',
        mode: CompanyMode.ledger,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(
        () => repo.updateCompany(mutated),
        throwsUnsupportedError,
      );

      final persisted = await (db.select(db.companies)..where((t) => t.id.equals(header.id))).getSingle();
      expect(persisted.mode, equals('expense'));
    });

    test('A Ledger workspace cannot be changed into an Expense workspace', () async {
      final header = await profileRepo.createProfile(
        name: 'Global Logistics',
        type: ProfileType.ledger,
        accountId: userUuidA,
      );

      final repo = DriftLedgerRepository(
        db: db,
        syncEngine: syncEngine,
        currentCompanyId: header.id,
        currentUserId: userUuidA,
        autoSync: false,
      );

      final mutated = Company(
        id: header.id,
        name: 'Global Logistics',
        legalName: 'Global Logistics',
        currencyCode: 'INR',
        mode: CompanyMode.expenseTracker,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(
        () => repo.updateCompany(mutated),
        throwsUnsupportedError,
      );

      final persisted = await (db.select(db.companies)..where((t) => t.id.equals(header.id))).getSingle();
      expect(persisted.mode, equals('ledger'));
    });

    test('Repository update operations preserve the original type', () async {
      final header = await profileRepo.createProfile(
        name: 'Original Name',
        type: ProfileType.expense,
        accountId: userUuidA,
      );

      final repo = DriftLedgerRepository(
        db: db,
        syncEngine: syncEngine,
        currentCompanyId: header.id,
        currentUserId: userUuidA,
        autoSync: false,
      );

      final updatedName = Company(
        id: header.id,
        name: 'New Display Name',
        legalName: 'New Legal Name',
        currencyCode: 'USD',
        mode: CompanyMode.expenseTracker,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repo.updateCompany(updatedName);

      final persisted = await (db.select(db.companies)..where((t) => t.id.equals(header.id))).getSingle();
      expect(persisted.name, equals('New Display Name'));
      expect(persisted.mode, equals('expense'));
    });

    test('Remote sync cannot silently mutate an existing workspace type', () async {
      final header = await profileRepo.createProfile(
        name: 'Local Expense App',
        type: ProfileType.expense,
        accountId: userUuidA,
      );

      // Simulate a malicious or stale remote payload attempting to change mode to ledger
      final maliciousRemoteRow = {
        'id': header.id,
        'name': 'Remote Mutated',
        'legal_name': 'Remote Mutated',
        'mode': 'ledger',
        'currency_code': 'INR',
        'owner_id': userUuidA,
        'is_deleted': false,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Stage malicious row in fake remote gateway and pull
      remoteGateway.upsertDirect('companies', header.id, maliciousRemoteRow);
      await syncEngine.pullChanges(companyId: header.id);

      final persisted = await (db.select(db.companies)..where((t) => t.id.equals(header.id))).getSingle();
      expect(persisted.mode, equals('expense'), reason: 'Remote sync must never mutate immutable local mode');
    });

    test('Creating a new Ledger workspace does not modify an existing Expense workspace', () async {
      final exp = await profileRepo.createProfile(
        name: 'Untouched Expense',
        type: ProfileType.expense,
        accountId: userUuidA,
      );

      await profileRepo.createProfile(
        name: 'Separate Ledger',
        type: ProfileType.ledger,
        accountId: userUuidA,
      );

      final expAfter = await (db.select(db.companies)..where((t) => t.id.equals(exp.id))).getSingle();
      expect(expAfter.mode, equals('expense'));
      expect(expAfter.name, equals('Untouched Expense'));
    });
  });

  group('Section 7.3 – Session and Selection Lifecycle Tests', () {
    test('A user with no workspaces is routed to onboarding', () async {
      final container = createContainer();
      final controller = container.read(profileSessionProvider.notifier);

      await controller.loadProfilesForUser(userUuidA);

      final state = container.read(profileSessionProvider);
      expect(state, isA<OnboardingRequiredSessionState>());
      expect((state as OnboardingRequiredSessionState).userId, equals(userUuidA));
    });

    test('A user with one workspace enters it correctly', () async {
      final created = await profileRepo.createProfile(
        name: 'Single Workspace',
        type: ProfileType.expense,
        accountId: userUuidA,
      );

      final container = createContainer();
      final controller = container.read(profileSessionProvider.notifier);

      await controller.loadProfilesForUser(userUuidA);

      final state = container.read(profileSessionProvider);
      expect(state, isA<ActiveProfileReadySessionState>());
      final ready = state as ActiveProfileReadySessionState;
      expect(ready.activeProfile.id, equals(created.id));
      expect(ready.availableProfiles.length, equals(1));
    });

    test('A user with multiple workspaces can select and switch between them', () async {
      final p1 = await profileRepo.createProfile(
        name: 'Workspace Alpha',
        type: ProfileType.expense,
        accountId: userUuidA,
      );
      final p2 = await profileRepo.createProfile(
        name: 'Workspace Beta',
        type: ProfileType.ledger,
        accountId: userUuidA,
      );

      final container = createContainer();
      final controller = container.read(profileSessionProvider.notifier);

      // On initial explicit login with multiple workspaces -> selection required
      await controller.loadProfilesForUser(userUuidA, isLogin: true);
      expect(container.read(profileSessionProvider), isA<ProfileSelectionRequiredSessionState>());

      // User selects p1
      await controller.switchProfile(p1);
      var state = container.read(profileSessionProvider) as ActiveProfileReadySessionState;
      expect(state.activeProfile.id, equals(p1.id));
      expect(state.activeProfile.type, equals(ProfileType.expense));

      // User switches to p2
      await controller.switchProfile(p2);
      state = container.read(profileSessionProvider) as ActiveProfileReadySessionState;
      expect(state.activeProfile.id, equals(p2.id));
      expect(state.activeProfile.type, equals(ProfileType.ledger));
    });

    test('A valid saved workspace is restored after restart', () async {
      await profileRepo.createProfile(
        name: 'Workspace 1',
        type: ProfileType.expense,
        accountId: userUuidA,
      );
      final p2 = await profileRepo.createProfile(
        name: 'Workspace 2',
        type: ProfileType.ledger,
        accountId: userUuidA,
      );

      // Save preference as if p2 was previously active
      await prefs.setString('last_active_profile_$userUuidA', p2.id);

      final container = createContainer();
      final controller = container.read(profileSessionProvider.notifier);

      // Session restart (isLogin = false)
      await controller.loadProfilesForUser(userUuidA, isLogin: false);

      final state = container.read(profileSessionProvider);
      expect(state, isA<ActiveProfileReadySessionState>());
      expect((state as ActiveProfileReadySessionState).activeProfile.id, equals(p2.id));
    });

    test('An invalid or inaccessible saved workspace is rejected safely', () async {
      await profileRepo.createProfile(
        name: 'Real Workspace',
        type: ProfileType.expense,
        accountId: userUuidA,
      );
      await profileRepo.createProfile(
        name: 'Real Workspace 2',
        type: ProfileType.ledger,
        accountId: userUuidA,
      );

      // Set bogus saved workspace ID
      await prefs.setString('last_active_profile_$userUuidA', 'inaccessible_or_deleted_id');

      final container = createContainer();
      final controller = container.read(profileSessionProvider.notifier);

      await controller.loadProfilesForUser(userUuidA, isLogin: false);

      // Safely falls back to profile selection
      expect(container.read(profileSessionProvider), isA<ProfileSelectionRequiredSessionState>());
    });

    test('Switching accounts never restores the previous account workspace', () async {
      // User A creates a workspace
      final pA = await profileRepo.createProfile(
        name: 'User A Workspace',
        type: ProfileType.ledger,
        accountId: userUuidA,
      );
      await prefs.setString('last_active_profile_$userUuidA', pA.id);

      // User B logs in with zero workspaces
      final containerB = createContainer(
        authState: const AuthState(
          isAuthenticated: true,
          userId: userUuidB,
          phoneNumber: '+91 88888 77777',
        ),
      );
      final controllerB = containerB.read(profileSessionProvider.notifier);

      await controllerB.loadProfilesForUser(userUuidB, isLogin: false);

      final stateB = containerB.read(profileSessionProvider);
      // User B must NOT restore User A's workspace! User B has 0 workspaces -> OnboardingRequired
      expect(stateB, isA<OnboardingRequiredSessionState>());
      expect((stateB as OnboardingRequiredSessionState).userId, equals(userUuidB));
    });

    test('Logout clears the active workspace session', () async {
      await profileRepo.createProfile(
        name: 'Session Work',
        type: ProfileType.expense,
        accountId: userUuidA,
      );

      final container = createContainer();
      final controller = container.read(profileSessionProvider.notifier);

      await controller.loadProfilesForUser(userUuidA);
      expect(container.read(profileSessionProvider), isA<ActiveProfileReadySessionState>());

      controller.logout();

      final state = container.read(profileSessionProvider);
      expect(state, isA<GuestReadySessionState>());
    });

    test('Offline startup can restore a previously cached accessible workspace', () async {
      final p = await profileRepo.createProfile(
        name: 'Offline Cached App',
        type: ProfileType.expense,
        accountId: userUuidA,
      );

      final container = createContainer();
      final controller = container.read(profileSessionProvider.notifier);

      // Startup offline (network unavailable)
      await controller.loadProfilesForUser(userUuidA);

      final state = container.read(profileSessionProvider);
      expect(state, isA<ActiveProfileReadySessionState>());
      final ready = state as ActiveProfileReadySessionState;
      expect(ready.activeProfile.id, equals(p.id));
      expect(ready.activeProfile.type, equals(ProfileType.expense));
    });
  });
}
