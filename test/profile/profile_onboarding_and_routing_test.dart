import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/domain/models/workspace_profile_header.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_controller.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../sync/support/fake_remote_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userUuidA = 'a1111111-1111-4111-8111-111111111111';
  const userUuidB = 'b2222222-2222-4222-8222-222222222222';

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
      currentUserId: userUuidA,
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

  group('Profile Onboarding and Multi-Profile Routing', () {
    test('1. First signup with Expense profile creates Expense profile and opens it immediately', () async {
      final container = createContainer();
      final controller = container.read(profileSessionProvider.notifier);

      // Initially zero profiles -> Onboarding required
      await controller.loadProfilesForUser(userUuidA);
      expect(container.read(profileSessionProvider), isA<OnboardingRequiredSessionState>());

      // User chooses Expense Tracker during onboarding
      final created = await profileRepo.createProfile(
        name: 'My Personal Expenses',
        type: ProfileType.expense,
        accountId: userUuidA,
      );

      expect(created.type, equals(ProfileType.expense));

      // Reload profiles -> ActiveProfileReadySessionState with Expense
      await controller.loadProfilesForUser(userUuidA);
      final state = container.read(profileSessionProvider);
      expect(state, isA<ActiveProfileReadySessionState>());

      final ready = state as ActiveProfileReadySessionState;
      expect(ready.activeProfile.id, equals(created.id));
      expect(ready.activeProfile.type, equals(ProfileType.expense));
      expect(ready.availableProfiles.length, equals(1));
    });

    test('2. First signup with Ledger profile creates Ledger profile and opens it immediately', () async {
      final container = createContainer();
      final controller = container.read(profileSessionProvider.notifier);

      // Initially zero profiles
      await controller.loadProfilesForUser(userUuidA);
      expect(container.read(profileSessionProvider), isA<OnboardingRequiredSessionState>());

      // User chooses Business Ledger during onboarding
      final created = await profileRepo.createProfile(
        name: 'Apex Traders',
        type: ProfileType.ledger,
        accountId: userUuidA,
      );

      expect(created.type, equals(ProfileType.ledger));

      // Reload profiles -> ActiveProfileReadySessionState with Ledger
      await controller.loadProfilesForUser(userUuidA);
      final state = container.read(profileSessionProvider);
      expect(state, isA<ActiveProfileReadySessionState>());

      final ready = state as ActiveProfileReadySessionState;
      expect(ready.activeProfile.id, equals(created.id));
      expect(ready.activeProfile.type, equals(ProfileType.ledger));
      expect(ready.availableProfiles.length, equals(1));
    });

    test('3. Existing account login with one profile opens it directly', () async {
      final container = createContainer();
      final controller = container.read(profileSessionProvider.notifier);

      final profile = await profileRepo.createProfile(
        name: 'Single Shop',
        type: ProfileType.ledger,
        accountId: userUuidA,
      );

      // Login with isLogin: true
      await controller.loadProfilesForUser(userUuidA, isLogin: true);

      final state = container.read(profileSessionProvider);
      expect(state, isA<ActiveProfileReadySessionState>());
      final ready = state as ActiveProfileReadySessionState;
      expect(ready.activeProfile.id, equals(profile.id));
      expect(ready.activeProfile.name, equals('Single Shop'));
    });

    test('4. Existing account login with multiple profiles routes to profile selector', () async {
      final container = createContainer();
      final controller = container.read(profileSessionProvider.notifier);

      // Seed 2 profiles
      final p1 = await profileRepo.createProfile(
        name: 'Personal Wallet',
        type: ProfileType.expense,
        accountId: userUuidA,
      );
      final p2 = await profileRepo.createProfile(
        name: 'Enterprise Ledger',
        type: ProfileType.ledger,
        accountId: userUuidA,
      );

      // Set a cached active profile in SharedPreferences to ensure login overrides cache
      await prefs.setString('last_active_profile_$userUuidA', p1.id);

      // Fresh login MUST show profile selector even if cached active profile exists
      await controller.loadProfilesForUser(userUuidA, isLogin: true);

      final state = container.read(profileSessionProvider);
      expect(state, isA<ProfileSelectionRequiredSessionState>());
      final selectorState = state as ProfileSelectionRequiredSessionState;
      expect(selectorState.profiles.length, equals(2));
      expect(selectorState.profiles.map((p) => p.id), containsAll([p1.id, p2.id]));
    });

    test('5. Existing account login with zero profiles routes to onboarding and never creates a Ledger profile', () async {
      final container = createContainer();
      final controller = container.read(profileSessionProvider.notifier);

      // Login with 0 profiles
      await controller.loadProfilesForUser(userUuidA, isLogin: true);

      final state = container.read(profileSessionProvider);
      expect(state, isA<OnboardingRequiredSessionState>());

      // Verify database has ZERO companies/profiles created silently
      final companies = await db.select(db.companies).get();
      expect(companies, isEmpty, reason: 'Must never silently create a Ledger profile during login');
    });

    test('6. Creating a second profile of the other type preserves both and isolates domain data', () async {
      // Create first: Expense
      final p1 = await profileRepo.createProfile(
        name: 'Home Expenses',
        type: ProfileType.expense,
        accountId: userUuidA,
      );

      // Create second: Ledger
      final p2 = await profileRepo.createProfile(
        name: 'Bookstore Books',
        type: ProfileType.ledger,
        accountId: userUuidA,
      );

      expect(p1.id, isNot(equals(p2.id)));
      expect(p1.type, equals(ProfileType.expense));
      expect(p2.type, equals(ProfileType.ledger));

      // Check accessible profiles from repository
      final profiles = await profileRepo.getAccessibleProfiles(userUuidA);
      expect(profiles.length, equals(2));

      final expenseProf = profiles.firstWhere((p) => p.id == p1.id);
      final ledgerProf = profiles.firstWhere((p) => p.id == p2.id);

      expect(expenseProf.type, equals(ProfileType.expense));
      expect(ledgerProf.type, equals(ProfileType.ledger));

      // Check Drift database persistence for both companies
      final dbP1 = await (db.select(db.companies)..where((c) => c.id.equals(p1.id))).getSingle();
      final dbP2 = await (db.select(db.companies)..where((c) => c.id.equals(p2.id))).getSingle();

      expect(dbP1.mode, equals('expense'));
      expect(dbP2.mode, equals('ledger'));
    });

    test('7. Switching profiles preserves active profile and updates domain state', () async {
      final container = createContainer();
      final controller = container.read(profileSessionProvider.notifier);

      final p1 = await profileRepo.createProfile(
        name: 'Expense Profile',
        type: ProfileType.expense,
        accountId: userUuidA,
      );
      final p2 = await profileRepo.createProfile(
        name: 'Ledger Profile',
        type: ProfileType.ledger,
        accountId: userUuidA,
      );

      // Initial active profile is p1
      await prefs.setString('last_active_profile_$userUuidA', p1.id);
      await controller.loadProfilesForUser(userUuidA, isLogin: false);

      final state1 = container.read(profileSessionProvider);
      expect(state1, isA<ActiveProfileReadySessionState>());
      if (state1 is ActiveProfileReadySessionState) {
        expect(state1.activeProfile.id, equals(p1.id));
      }

      // Switch to p2
      await controller.switchProfile(p2);

      final state2 = container.read(profileSessionProvider);
      expect(state2, isA<ActiveProfileReadySessionState>());
      if (state2 is ActiveProfileReadySessionState) {
        expect(state2.activeProfile.id, equals(p2.id));
        expect(state2.activeProfile.type, equals(ProfileType.ledger));
      }

      // Check SharedPreferences was updated
      expect(prefs.getString('last_active_profile_$userUuidA'), equals(p2.id));
    });

    test('8. Immutable profile type prevents mutating mode after creation', () {
      final now = DateTime.now();
      final company = Company(
        id: 'cmp_test_1',
        name: 'Fixed Profile',
        legalName: 'Fixed Profile',
        mode: CompanyMode.expenseTracker,
        createdAt: now,
        updatedAt: now,
      );

      // Attempting to change mode via copyWith throws StateError
      expect(
        () => company.copyWith(mode: CompanyMode.ledger),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Profile type is immutable'),
        )),
      );

      // Preserving the mode is permitted
      final updatedName = company.copyWith(name: 'Updated Name');
      expect(updatedName.name, equals('Updated Name'));
      expect(updatedName.mode, equals(CompanyMode.expenseTracker));
    });

    test('9. Profile switching enforces membership authorization and rejects unauthorized access', () async {
      final container = createContainer();
      final controller = container.read(profileSessionProvider.notifier);

      // Create profile owned by userUuidA
      await profileRepo.createProfile(
        name: 'User A Profile',
        type: ProfileType.ledger,
        accountId: userUuidA,
      );

      // Create profile owned by userUuidB (userUuidA has NO membership to profileB)
      final profileB = await profileRepo.createProfile(
        name: 'User B Secret Profile',
        type: ProfileType.expense,
        accountId: userUuidB,
      );

      // Load user A profiles
      await controller.loadProfilesForUser(userUuidA, isLogin: false);
      expect(container.read(profileSessionProvider), isA<ActiveProfileReadySessionState>());

      // User A attempts to switch to user B's profile
      await controller.switchProfile(profileB);

      // Must be rejected with SessionErrorState (Access Revoked)
      final state = container.read(profileSessionProvider);
      expect(state, isA<SessionErrorState>());
      final errorState = state as SessionErrorState;
      expect(errorState.message, contains('Access Revoked'));
    });
  });
}

class _StubAuthController extends AuthController {
  final AuthState _state;
  _StubAuthController(this._state);

  @override
  AuthState build() => _state;
}
