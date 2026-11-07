import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/domain/models/workspace_profile_header.dart';
import 'package:ledger_pulse/presentation/auth/app_root_gate.dart';
import 'package:ledger_pulse/presentation/auth/phone_input_screen.dart';
import 'package:ledger_pulse/presentation/auth/profile_onboarding_screen.dart';
import 'package:ledger_pulse/presentation/auth/profile_selector_screen.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_controller.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_state.dart';
import 'package:ledger_pulse/presentation/widgets/active_profile_indicator_pill.dart';

void main() {
  group('Account & Profile UI Integration Tests', () {
    testWidgets('AppRootGate displays PhoneInputScreen when unauthenticated',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileSessionProvider.overrideWith(
              () => _MockProfileSessionController(
                const UnauthenticatedSessionState(),
              ),
            ),
          ],
          child: const MaterialApp(
            home: AppRootGate(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PhoneInputScreen), findsOneWidget);
    });

    testWidgets('AppRootGate displays loading screen when LoadingProfilesSessionState',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileSessionProvider.overrideWith(
              () => _MockProfileSessionController(
                const LoadingProfilesSessionState('usr_test'),
              ),
            ),
          ],
          child: const MaterialApp(
            home: AppRootGate(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Loading your workspaces...'), findsOneWidget);
    });

    testWidgets('AppRootGate routes to ProfileOnboardingScreen when onboarding is required',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileSessionProvider.overrideWith(
              () => _MockProfileSessionController(
                const OnboardingRequiredSessionState('usr_new'),
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
      expect(find.text('Setup Your Workspace'), findsOneWidget);
      expect(find.text('Personal & Expense'), findsOneWidget);
      expect(find.text('Business Ledger'), findsOneWidget);
    });

    testWidgets('AppRootGate routes to ProfileSelectorScreen when multiple profiles exist',
        (tester) async {
      final profiles = [
        WorkspaceProfileHeader(
          id: 'prf_exp_01',
          name: 'Personal Expenses',
          legalName: 'Personal Expenses',
          type: ProfileType.expense,
          role: ProfileRole.owner,
          currencyCode: 'INR',
          updatedAt: DateTime.now(),
        ),
        WorkspaceProfileHeader(
          id: 'prf_led_01',
          name: 'Acme Traders',
          legalName: 'Acme Traders LLP',
          type: ProfileType.ledger,
          role: ProfileRole.admin,
          currencyCode: 'INR',
          gstin: '29ABCDE1234F1Z5',
          updatedAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileSessionProvider.overrideWith(
              () => _MockProfileSessionController(
                ProfileSelectionRequiredSessionState(
                  userId: 'usr_test',
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
      expect(find.text('Personal Expenses'), findsOneWidget);
      expect(find.text('Acme Traders'), findsOneWidget);
      expect(find.text('EXPENSE'), findsOneWidget);
      expect(find.text('LEDGER'), findsOneWidget);
      expect(find.text('Role: Owner'), findsOneWidget);
      expect(find.text('Role: Administrator'), findsOneWidget);
      expect(find.text('+ Create New Workspace'), findsOneWidget);
    });

    testWidgets('ProfileOnboardingScreen toggles separate setup forms for Expense and Ledger',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ProfileOnboardingScreen(userId: 'usr_test'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Starts in Expense mode by default
      expect(find.text('Expense Profile Setup'), findsOneWidget);
      expect(find.text('Profile Name'), findsOneWidget);
      expect(find.text('GSTIN (Optional)'), findsNothing);

      // Tap on Business Ledger card
      await tester.tap(find.text('Business Ledger'));
      await tester.pumpAndSettle();

      // Now shows Business Details and GSTIN fields
      expect(find.text('Business Details & Compliance'), findsOneWidget);
      expect(find.text('Business / Company Name *'), findsOneWidget);
      expect(find.text('Legal Registered Name (Optional)'), findsOneWidget);
      expect(find.text('GSTIN (Optional)'), findsOneWidget);
    });

    testWidgets('ActiveProfileIndicatorPill shows active workspace name and domain badge',
        (tester) async {
      final activeProfile = WorkspaceProfileHeader(
        id: 'prf_led_01',
        name: 'Apex Enterprises',
        legalName: 'Apex Enterprises',
        type: ProfileType.ledger,
        role: ProfileRole.owner,
        currencyCode: 'INR',
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileSessionProvider.overrideWith(
              () => _MockProfileSessionController(
                ActiveProfileReadySessionState(
                  userId: 'usr_test',
                  activeProfile: activeProfile,
                  availableProfiles: [activeProfile],
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: ActiveProfileIndicatorPill(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Apex Enterprises'), findsOneWidget);
      expect(find.text('BUSINESS'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
    });

    testWidgets('AppRootGate renders error view with Revoked Access message when unauthorized',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileSessionProvider.overrideWith(
              () => _MockProfileSessionController(
                const SessionErrorState(
                  'Access Revoked: Your access to this workspace has been removed.',
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

      expect(find.text('Access Revoked'), findsWidgets);
      expect(find.text('Choose Another Workspace'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);
    });
  });
}

class _MockProfileSessionController extends ProfileSessionController {
  final ProfileSessionState initialState;

  _MockProfileSessionController(this.initialState);

  @override
  ProfileSessionState build() => initialState;
}
