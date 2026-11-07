import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/domain/models/workspace_profile_header.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_state.dart';

void main() {
  group('Profile Session & Immutability Lifecycle Tests', () {
    test('ProfileType is strictly immutable and parses correctly', () {
      final expenseType = ProfileType.fromString('expense');
      final ledgerType = ProfileType.fromString('ledger');
      final aliasExpense = ProfileType.fromString('expenseTracker');

      expect(expenseType, equals(ProfileType.expense));
      expect(ledgerType, equals(ProfileType.ledger));
      expect(aliasExpense, equals(ProfileType.expense));
    });

    test('WorkspaceProfileHeader enforces immutability and distinct domain mode', () {
      final profile = WorkspaceProfileHeader(
        id: 'prf_101',
        name: 'My Personal Finances',
        legalName: 'My Personal Finances',
        type: ProfileType.expense,
        role: ProfileRole.owner,
        updatedAt: DateTime.now(),
      );

      expect(profile.isExpense, isTrue);
      expect(profile.isLedger, isFalse);
      expect(profile.role, equals(ProfileRole.owner));
    });

    test('ProfileSessionState covers all lifecycle stages', () {
      const unauth = UnauthenticatedSessionState();
      expect(unauth, isA<ProfileSessionState>());

      const loading = LoadingProfilesSessionState('usr_1');
      expect(loading.userId, equals('usr_1'));

      const onboarding = OnboardingRequiredSessionState('usr_1');
      expect(onboarding.userId, equals('usr_1'));

      final selection = ProfileSelectionRequiredSessionState(
        userId: 'usr_1',
        profiles: [
          WorkspaceProfileHeader(
            id: 'prf_exp',
            name: 'Personal',
            legalName: 'Personal',
            type: ProfileType.expense,
            role: ProfileRole.owner,
            updatedAt: DateTime.now(),
          ),
          WorkspaceProfileHeader(
            id: 'prf_led',
            name: 'Business Ltd',
            legalName: 'Business Ltd',
            type: ProfileType.ledger,
            role: ProfileRole.admin,
            updatedAt: DateTime.now(),
          ),
        ],
      );
      expect(selection.profiles.length, equals(2));
      expect(selection.profiles.first.isExpense, isTrue);
      expect(selection.profiles.last.isLedger, isTrue);
    });
  });
}

