import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ledger_pulse/data/repositories/supabase_auth_repository.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const validUuid = '550e8400-e29b-41d4-a716-446655440000';
  const validJwt =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI1NTBlODQwMC1lMjliLTQxZDQtYTcxNi00NDY2NTU0NDAwMDAiLCJpYXQiOjE1MTYyMzkwMjJ9.mock_signature';

  group('Device Auth Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('User logs in once and authentication is persisted to device storage', () async {
      final prefs = await SharedPreferences.getInstance();

      // 1. Initial State: Clean device, unauthenticated
      final initialRepo = SupabaseAuthRepository(prefs: prefs);
      expect(initialRepo.isAuthenticated, isFalse);
      expect(initialRepo.currentPhoneNumber, isNull);
      expect(initialRepo.currentUserId, isNull);

      // 2. Persist genuine authenticated Supabase credentials
      const testPhone = '+91 98765 43210';
      await prefs.setString('supabase_auth_phone_number', testPhone);
      await prefs.setString('supabase_auth_user_id', validUuid);
      await prefs.setString('supabase_auth_session_token', validJwt);

      // 3. Simulate app restart on the same device
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      // Verify repository and AuthController immediately reflect authenticated state
      final restoredRepo = container.read(authRepositoryProvider);
      final restoredState = container.read(authControllerProvider);

      expect(restoredRepo.isAuthenticated, isTrue,
          reason: 'Device should remember previous sign-in');
      expect(restoredRepo.currentUserId, equals(validUuid));
      expect(restoredRepo.currentPhoneNumber, equals(testPhone));
      expect(restoredState.isAuthenticated, isTrue,
          reason: 'AuthController must be authenticated on launch without OTP');
      expect(restoredState.userId, equals(validUuid));
      expect(restoredState.phoneNumber, equals(testPhone));
    });

    test('Logging out removes device authentication', () async {
      final prefs = await SharedPreferences.getInstance();

      // Seed signed-in state with valid credentials
      await prefs.setString('supabase_auth_phone_number', '+91 98765 43210');
      await prefs.setString('supabase_auth_user_id', validUuid);
      await prefs.setString('supabase_auth_session_token', validJwt);

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final authController = container.read(authControllerProvider.notifier);
      final repo = container.read(authRepositoryProvider);

      expect(repo.isAuthenticated, isTrue);
      expect(container.read(authControllerProvider).isAuthenticated, isTrue);

      // Perform Logout
      await authController.logout();

      expect(repo.isAuthenticated, isFalse);
      expect(container.read(authControllerProvider).isAuthenticated, isFalse);
      expect(prefs.getString('supabase_auth_user_id'), isNull);
      expect(prefs.getString('supabase_auth_phone_number'), isNull);
      expect(prefs.getString('supabase_auth_session_token'), isNull);
    });
  });
}
