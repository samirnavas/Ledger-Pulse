import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_pulse/main.dart';
import 'package:ledger_pulse/core/constants/strings.dart';
import 'package:ledger_pulse/data/mock/mock_ledger_repository.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';

class FakeAuthController extends AuthController {
  final AuthState _initialState;
  FakeAuthController(this._initialState);

  @override
  AuthState build() => _initialState;
}

void main() {
  testWidgets('LedgerPulseApp starts with SplashScreen and transitions to Dashboard',
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
