import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/presentation/auth/profile_onboarding_screen.dart';
import '../helpers/golden_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Preview Profile Onboarding (Workspace Creation Page)', (WidgetTester tester) async {
    await expectPageGolden(
      tester,
      page: const ProfileOnboardingScreen(userId: 'preview_user_123'),
      goldenName: 'profile_onboarding_page',
    );
  });
}
