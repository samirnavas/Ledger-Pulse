import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paypr/data/local/database.dart';
import 'package:paypr/data/local/drift_ledger_repository.dart';
import 'package:paypr/main.dart';
import 'package:paypr/data/models/company_model.dart';
import 'package:paypr/data/models/sync_model.dart';
import 'package:paypr/data/models/user_profile_model.dart';
import 'package:paypr/presentation/providers/auth_providers.dart';
import 'package:paypr/presentation/providers/company_providers.dart';
import 'package:paypr/presentation/providers/ledger_providers.dart';
import 'package:paypr/presentation/providers/profile_provider.dart';
import 'package:paypr/presentation/providers/profile_session_controller.dart';
import 'package:paypr/presentation/providers/profile_session_state.dart';
import 'package:paypr/domain/models/workspace_profile_header.dart';
import 'package:paypr/presentation/home/home_shell.dart';
import 'package:paypr/presentation/auth/first_use_setup_screen.dart';
import 'package:paypr/presentation/providers/sync_providers.dart';
import 'package:lottie/lottie.dart';

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
  testWidgets('PayprApp starts with SplashScreen and transitions to Dashboard with active company',
      (WidgetTester tester) async {
    for (final asset in ['paypr_splash.json', 'paypr_splash_light.json']) {
      final composition = await tester.runAsync(
        () => AssetLottie('assets/animations/$asset').load(),
      );
      expect(composition?.images.values.single.loadedImage, isNotNull);
    }

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
        child: const PayprApp(),
      ),
    );

    // Verify initial splash screen is shown
    await tester.pump();
    expect(find.byType(LottieBuilder), findsOneWidget);

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

  testWidgets('PayprApp displays zero-company state on fresh authenticated install without companies',
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
        child: const PayprApp(),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(FirstUseSetupScreen), findsOneWidget);
    expect(find.text('Set up Paypr'), findsOneWidget);
  });

  testWidgets('The splash opens the Paypr welcome screen when unauthenticated',
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
          profileSessionProvider.overrideWith(
            () => TestProfileSession(const UnauthenticatedSessionState()),
          ),
          ledgerUpdatesStreamProvider.overrideWith((ref) => Stream.value(null)),
          ledgerRepositoryProvider.overrideWithValue(repo),
          driftLedgerRepositoryProvider.overrideWithValue(repo),
          syncControllerProvider.overrideWith(FakeSyncNotifier.new),
        ],
        child: const PayprApp(),
      ),
    );

    // Splash is shown
    await tester.pump();
    expect(find.byType(LottieBuilder), findsOneWidget);

    // Wait for splash animation sequence
    await tester.pumpAndSettle();

    expect(find.byType(PayprWelcomeScreen), findsOneWidget);
    expect(find.text('Paypr'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });
}
