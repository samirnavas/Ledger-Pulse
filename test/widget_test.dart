import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/main.dart';
import 'package:ledger_pulse/core/constants/strings.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/sync_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_controller.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_state.dart';
import 'package:ledger_pulse/domain/models/workspace_profile_header.dart';
import 'package:ledger_pulse/presentation/home/home_shell.dart';
import 'package:ledger_pulse/presentation/auth/phone_input_screen.dart';
import 'package:ledger_pulse/presentation/providers/sync_providers.dart';

class FakeAuthController extends AuthController {
  final AuthState _initialState;
  FakeAuthController(this._initialState);

  @override
  AuthState build() => _initialState;
}

class FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncResult> triggerSync({String? companyId, bool isAutoSync = false}) async {
    return SyncResult(success: true, timestamp: DateTime.now());
  }

  @override
  Future<void> autoSyncOnAppOpen() async {}
}

class TestUserProfileNotifier extends UserProfileNotifier {
  final UserProfile _initial;
  TestUserProfileNotifier(this._initial);

  @override
  UserProfile build() => _initial;
}

class TestProfileSession extends ProfileSessionController {
  final ProfileSessionState initial;

  TestProfileSession(this.initial);

  @override
  ProfileSessionState build() => initial;
}

void main() {
  testWidgets('LedgerPulseApp starts with SplashScreen and transitions to Dashboard with active company',
      (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = DriftLedgerRepository(db: db, postingEngine: null);
    addTearDown(() async {
      repo.dispose();
      await db.close();
    });

    final testCompany = Company(
      id: 'cmp_test_1',
      name: 'Test Enterprise',
      legalName: 'Test Enterprise Ltd',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final workspace = WorkspaceProfileHeader(
      id: testCompany.id,
      name: testCompany.name,
      legalName: testCompany.legalName,
      type: ProfileType.ledger,
      role: ProfileRole.owner,
      updatedAt: testCompany.updatedAt,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
              () => FakeAuthController(const AuthState(isAuthenticated: true, userId: 'usr_test'))),
          profileSessionProvider.overrideWith(() => TestProfileSession(
            OfflineActiveProfileReadySessionState(
              userId: 'usr_test', activeProfile: workspace, availableProfiles: [workspace],
            ),
          )),
          ledgerUpdatesStreamProvider.overrideWith((ref) => Stream.value(null)),
          ledgerRepositoryProvider.overrideWithValue(repo),
          driftLedgerRepositoryProvider.overrideWithValue(repo),
          userProfileProvider.overrideWith(() => TestUserProfileNotifier(
                UserProfile(
                  id: 'usr_test',
                  name: 'Test User',
                  phoneNumber: '+91 99999 88888',
                  email: 'test@example.com',
                  companies: [testCompany],
                  activeCompanyId: 'cmp_test_1',
                ),
              )),
          syncControllerProvider.overrideWith(FakeSyncNotifier.new),
        ],
        child: const LedgerPulseApp(),
      ),
    );

    // Verify initial splash screen is shown
    await tester.pump();
    expect(find.text(AppStrings.appName), findsOneWidget);
    expect(find.text('Smart Digital Ledger & Bookkeeping'), findsOneWidget);

    // Advance the splash and route transitions. The shell can still be
    // loading its repository after the route has appeared.
    final home = find.byType(HomeShell);
    for (var step = 0; step < 30 && home.evaluate().isEmpty; step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(home, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('LedgerPulseApp displays zero-company state on fresh authenticated install without companies',
      (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = DriftLedgerRepository(db: db, postingEngine: null);
    addTearDown(() async {
      repo.dispose();
      await db.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
              () => FakeAuthController(const AuthState(isAuthenticated: true, userId: 'usr_fresh'))),
          profileSessionProvider.overrideWith(() => TestProfileSession(
            const OnboardingRequiredSessionState('usr_fresh'),
          )),
          ledgerUpdatesStreamProvider.overrideWith((ref) => Stream.value(null)),
          ledgerRepositoryProvider.overrideWithValue(repo),
          driftLedgerRepositoryProvider.overrideWithValue(repo),
          companiesProvider.overrideWith((ref) async => const <Company>[]),
          userProfileProvider.overrideWith(() => TestUserProfileNotifier(
                UserProfile(
                  id: 'usr_fresh',
                  name: '',
                  phoneNumber: '+91 99999 88888',
                  email: '',
                  companies: const [],
                ),
              )),
          syncControllerProvider.overrideWith(FakeSyncNotifier.new),
        ],
        child: const LedgerPulseApp(),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    // Zero-company state form is visible
    expect(find.text('Set Up Your Workspace'), findsOneWidget);
    expect(find.text('Business Ledger'), findsOneWidget);
  });

  testWidgets('LedgerPulseApp transitions from SplashScreen to PhoneInput when unauthenticated',
      (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = DriftLedgerRepository(db: db, postingEngine: null);
    addTearDown(() async {
      repo.dispose();
      await db.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
              () => FakeAuthController(const AuthState(isAuthenticated: false))),
          ledgerUpdatesStreamProvider.overrideWith((ref) => Stream.value(null)),
          ledgerRepositoryProvider.overrideWithValue(repo),
          driftLedgerRepositoryProvider.overrideWithValue(repo),
          syncControllerProvider.overrideWith(FakeSyncNotifier.new),
        ],
        child: const LedgerPulseApp(),
      ),
    );

    // Splash is shown
    await tester.pump();
    expect(find.text(AppStrings.appName), findsOneWidget);

    // Wait for splash animation sequence
    await tester.pumpAndSettle();

    // Phone input screen is visible
    expect(find.byType(PhoneInputScreen), findsOneWidget);
    expect(find.text('Create Account'), findsWidgets);
  });
}
