import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/core/widgets/adaptive_button.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/mock/mock_auth_repository.dart';
import 'package:ledger_pulse/data/repositories/supabase_auth_repository.dart';
import 'package:ledger_pulse/domain/models/workspace_profile_header.dart';
import 'package:ledger_pulse/presentation/auth/app_root_gate.dart';
import 'package:ledger_pulse/presentation/auth/phone_input_screen.dart';
import 'package:ledger_pulse/presentation/auth/profile_onboarding_screen.dart';
import 'package:ledger_pulse/presentation/auth/profile_selector_screen.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';
import 'package:ledger_pulse/presentation/providers/database_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_controller.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  const testUserUuid = '550e8400-e29b-41d4-a716-446655440000';
  const testJwt =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI1NTBlODQwMC1lMjliLTQxZDQtYTcxNi00NDY2NTU0NDAwMDAiLCJpYXQiOjE1MTYyMzkwMjJ9.mock_signature';

  group('Signup Flow and Authentication Identity Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('1. Signup screen does NOT have Business Ledger / Expense Tracker selector',
        (tester) async {
      final mockAuth = MockAuthRepository(isAuthenticated: false, userId: null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(mockAuth),
          ],
          child: const MaterialApp(
            home: PhoneInputScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Sign Up / Login switcher exists and Phone OTP is removed
      expect(find.text('Sign Up'), findsWidgets);
      expect(find.text('Login'), findsWidgets);
      expect(find.text('Phone OTP'), findsNothing);
      expect(find.text('+91'), findsNothing);

      // Ensure we are in Sign Up mode (Create Account)
      expect(find.text('Create Account'), findsWidgets);

      // Verify personal details inputs exist
      expect(find.byKey(const Key('signup_name_field')), findsOneWidget);
      expect(find.byKey(const Key('auth_email_field')), findsOneWidget);
      expect(find.byKey(const Key('auth_password_field')), findsOneWidget);

      // Verify that profile type selector does NOT exist on the signup screen
      expect(find.text('Profile Type:'), findsNothing);
      expect(find.text('Business Ledger'), findsNothing);
      expect(find.text('Expense Tracker'), findsNothing);
    });

    test('2. Successful authentication exposes real Supabase UUID (not email/phone/usr_default)',
        () async {
      final mockAuth = MockAuthRepository(
        isAuthenticated: false,
        userId: testUserUuid,
      );

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuth),
        ],
      );
      addTearDown(container.dispose);

      final authNotifier = container.read(authControllerProvider.notifier);

      final result = await authNotifier.signUpWithEmailAndPassword(
        email: 'user@example.com',
        password: 'securePassword123',
        name: 'Jane Doe',
      );

      expect(result.isSuccess, isTrue);
      expect(result.requiresEmailConfirmation, isFalse);

      final authState = container.read(authControllerProvider);
      expect(authState.isAuthenticated, isTrue);

      // UUID verification
      expect(authState.userId, isNotNull);
      expect(authState.userId, equals(testUserUuid));
      expect(uuidRegex.hasMatch(authState.userId!), isTrue);

      // Ensure email/phone are never used as user ID
      expect(authState.userId, isNot(equals('user@example.com')));
      expect(authState.userId, isNot(equals('usr_default')));
      expect(authState.userId, isNot(startsWith('usr_supa_')));
      expect(authState.email, equals('user@example.com'));
      expect(authState.userName, equals('Jane Doe'));
    });

    testWidgets('3. Signup requiring email confirmation does NOT mark user as authenticated',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockAuth = MockAuthRepository(
        isAuthenticated: false,
        requiresEmailConfirmationOnSignUp: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(mockAuth),
          ],
          child: const MaterialApp(
            home: PhoneInputScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Screen starts in Sign Up mode by default
      expect(find.text('Create Account'), findsWidgets);

      // Fill in Name, Email, Password
      await tester.enterText(find.byKey(const Key('signup_name_field')), 'John Smith');
      await tester.enterText(find.byKey(const Key('auth_email_field')), 'john@example.com');
      await tester.enterText(find.byKey(const Key('auth_password_field')), 'password123');
      await tester.pumpAndSettle();

      // Tap Create Account
      await tester.tap(find.widgetWithText(AdaptiveButton, 'Create Account'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Verify email confirmation pending UI is displayed
      expect(find.text('Verify Your Email'), findsOneWidget);
      expect(find.text('john@example.com'), findsOneWidget);
      expect(find.text('Proceed to Login'), findsOneWidget);

      // Verify user is NOT authenticated
      expect(mockAuth.isAuthenticated, isFalse);
      expect(mockAuth.currentSessionToken, isNull);

      // Tapping "Proceed to Login" returns to Login mode
      await tester.tap(find.text('Proceed to Login'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Login'), findsWidgets);
    });

    testWidgets('3b. Sign Up / Login switcher toggles between Create Account and Login views',
        (tester) async {
      final mockAuth = MockAuthRepository(isAuthenticated: false, userId: null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(mockAuth),
          ],
          child: const MaterialApp(
            home: PhoneInputScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially in Sign Up mode
      expect(find.text('Create Account'), findsWidgets);
      expect(find.byKey(const Key('signup_name_field')), findsOneWidget);

      // Switch to Login tab via segmented control
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();

      // In Login mode: no Full Name field, Login button present
      expect(find.byKey(const Key('signup_name_field')), findsNothing);
      expect(find.byKey(const Key('auth_email_field')), findsOneWidget);
      expect(find.byKey(const Key('auth_password_field')), findsOneWidget);
      expect(find.widgetWithText(AdaptiveButton, 'Login'), findsOneWidget);

      // Switch back to Sign Up using the text link
      await tester.tap(find.text('Need an account? Sign Up'));
      await tester.pumpAndSettle();

      // Back in Sign Up mode
      expect(find.text('Create Account'), findsWidgets);
      expect(find.byKey(const Key('signup_name_field')), findsOneWidget);
      expect(find.widgetWithText(AdaptiveButton, 'Create Account'), findsOneWidget);
    });

    test('4. No fake JWT or synthetic authenticated state allowed', () async {
      final prefs = await SharedPreferences.getInstance();

      // Seed with synthetic / fake legacy credentials
      await prefs.setString('supabase_auth_user_id', 'usr_supa_bad_email_at_com');
      await prefs.setString('supabase_auth_session_token', 'jwt_fake_token_123456');

      final repo = SupabaseAuthRepository(prefs: prefs);

      // Must NOT treat fake JWT or synthetic user ID as authenticated
      expect(repo.isAuthenticated, isFalse);
      expect(repo.currentUserId, isNull);
      expect(repo.currentSessionToken, isNull);

      // Must purge fake credentials from prefs
      expect(prefs.getString('supabase_auth_user_id'), isNull);
      expect(prefs.getString('supabase_auth_session_token'), isNull);

      // Valid Supabase credentials, on the other hand, preserve legitimate offline access
      await prefs.setString('supabase_auth_user_id', testUserUuid);
      await prefs.setString('supabase_auth_session_token', testJwt);

      final validRepo = SupabaseAuthRepository(prefs: prefs);
      expect(validRepo.isAuthenticated, isTrue);
      expect(validRepo.currentUserId, equals(testUserUuid));
      expect(validRepo.currentSessionToken, equals(testJwt));
    });

    test('5. Login with zero, one, and multiple profiles lifecycle', () async {
      final db = AppDatabase(NativeDatabase.memory(), testUserUuid);
      final syncEngine = SyncEngine(db: db);
      final profileRepo = DriftProfileRepository(db: db, syncEngine: syncEngine);

      final mockAuth = MockAuthRepository(
        isAuthenticated: true,
        userId: testUserUuid,
      );

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuth),
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(syncEngine),
          profileRepositoryProvider.overrideWithValue(profileRepo),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });

      final controller = container.read(profileSessionProvider.notifier);

      // (a) ZERO PROFILES: Account has no profiles -> transitions to OnboardingRequiredSessionState
      await controller.loadProfilesForUser(testUserUuid, isLogin: true);
      final stateZero = container.read<ProfileSessionState>(profileSessionProvider);

      expect(stateZero, isA<OnboardingRequiredSessionState>());
      expect((stateZero as OnboardingRequiredSessionState).userId, equals(testUserUuid));

      // Ensure no company was created silently in DB
      final initialProfiles = await profileRepo.getAccessibleProfiles(testUserUuid);
      expect(initialProfiles, isEmpty);

      // (b) ONE PROFILE: Create first profile
      final p1 = await profileRepo.createProfile(
        name: 'Personal Finances',
        type: ProfileType.expense,
        accountId: testUserUuid,
      );
      expect(p1.id, isNotEmpty);
      expect(p1.type, equals(ProfileType.expense));

      await controller.loadProfilesForUser(testUserUuid, isLogin: true);
      final stateOne = container.read<ProfileSessionState>(profileSessionProvider);

      expect(stateOne, isA<ActiveProfileReadySessionState>());
      final singleState = stateOne as ActiveProfileReadySessionState;
      expect(singleState.activeProfile.id, equals(p1.id));
      expect(singleState.availableProfiles.length, equals(1));

      // (c) MULTIPLE PROFILES: Create second profile
      final p2 = await profileRepo.createProfile(
        name: 'Acme Traders',
        type: ProfileType.ledger,
        accountId: testUserUuid,
      );
      expect(p2.id, isNotEmpty);
      expect(p2.type, equals(ProfileType.ledger));

      await controller.loadProfilesForUser(testUserUuid, isLogin: true);
      final stateMulti = container.read<ProfileSessionState>(profileSessionProvider);

      // Since last_active_profile wasn't cached, shows ProfileSelectionRequiredSessionState
      expect(stateMulti, isA<ProfileSelectionRequiredSessionState>());
      final multiState = stateMulti as ProfileSelectionRequiredSessionState;
      expect(multiState.profiles.length, equals(2));
      expect(multiState.profiles.any((p) => p.id == p1.id), isTrue);
      expect(multiState.profiles.any((p) => p.id == p2.id), isTrue);
    });

    testWidgets('6. AppRootGate renders Onboarding when zero profiles exist',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileSessionProvider.overrideWith(
              () => _MockProfileSessionController(
                const OnboardingRequiredSessionState(testUserUuid),
              ),
            ),
          ],
          child: const MaterialApp(
            home: AppRootGate(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProfileOnboardingScreen), findsOneWidget);
    });

    testWidgets('7. AppRootGate renders ProfileSelectorScreen when multiple profiles exist',
        (tester) async {
      final profiles = [
        WorkspaceProfileHeader(
          id: 'prf_1',
          name: 'Personal Wallet',
          legalName: 'Personal Wallet',
          type: ProfileType.expense,
          role: ProfileRole.owner,
          updatedAt: DateTime.now(),
        ),
        WorkspaceProfileHeader(
          id: 'prf_2',
          name: 'Enterprise Co',
          legalName: 'Enterprise Co Ltd',
          type: ProfileType.ledger,
          role: ProfileRole.owner,
          updatedAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileSessionProvider.overrideWith(
              () => _MockProfileSessionController(
                ProfileSelectionRequiredSessionState(
                  userId: testUserUuid,
                  profiles: profiles,
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: AppRootGate(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProfileSelectorScreen), findsOneWidget);
      expect(find.text('Personal Wallet'), findsOneWidget);
      expect(find.text('Enterprise Co'), findsOneWidget);
    });
  });
}

class _MockProfileSessionController extends ProfileSessionController {
  final ProfileSessionState initialState;
  _MockProfileSessionController(this.initialState);

  @override
  ProfileSessionState build() => initialState;
}
