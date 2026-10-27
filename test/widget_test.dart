import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_pulse/main.dart';
import 'package:ledger_pulse/core/constants/strings.dart';
import 'package:ledger_pulse/data/mock/mock_ledger_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/sync_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';
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

void main() {
  testWidgets('LedgerPulseApp starts with SplashScreen and transitions to Dashboard with active company',
      (WidgetTester tester) async {
    final mockRepo = MockLedgerRepository();
    addTearDown(mockRepo.dispose);

    final testCompany = Company(
      id: 'cmp_test_1',
      name: 'Test Enterprise',
      legalName: 'Test Enterprise Ltd',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
              () => FakeAuthController(const AuthState(isAuthenticated: true))),
          ledgerUpdatesStreamProvider.overrideWith((ref) => Stream.value(null)),
          ledgerRepositoryProvider.overrideWithValue(mockRepo),
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

    // Complete splash animation sequence & transition
    await tester.pumpAndSettle();

    // Verify top metric cards are visible on Dashboard
    expect(find.text(AppStrings.youWillGet), findsOneWidget);
    expect(find.text(AppStrings.youWillGive), findsOneWidget);

    // Verify Customers tab is rendered
    expect(find.text(AppStrings.customersTab), findsOneWidget);
    expect(find.text(AppStrings.suppliersTab), findsOneWidget);

    // Verify search bar
    expect(find.text(AppStrings.searchHint), findsOneWidget);
  });

  testWidgets('LedgerPulseApp displays zero-company state on fresh authenticated install without companies',
      (WidgetTester tester) async {
    final mockRepo = MockLedgerRepository();
    addTearDown(mockRepo.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
              () => FakeAuthController(const AuthState(isAuthenticated: true))),
          ledgerUpdatesStreamProvider.overrideWith((ref) => Stream.value(null)),
          ledgerRepositoryProvider.overrideWithValue(mockRepo),
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
    expect(find.text('Create your first company'), findsAtLeastNWidgets(1));
    expect(find.text('Company Name *'), findsOneWidget);
  });

  testWidgets('LedgerPulseApp transitions from SplashScreen to PhoneInput when unauthenticated',
      (WidgetTester tester) async {
    final mockRepo = MockLedgerRepository();
    addTearDown(mockRepo.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
              () => FakeAuthController(const AuthState(isAuthenticated: false))),
          ledgerUpdatesStreamProvider.overrideWith((ref) => Stream.value(null)),
          ledgerRepositoryProvider.overrideWithValue(mockRepo),
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
    expect(find.text(AppStrings.enterPhoneTitle), findsOneWidget);
    expect(find.text(AppStrings.getOtpButton), findsOneWidget);
  });
}
