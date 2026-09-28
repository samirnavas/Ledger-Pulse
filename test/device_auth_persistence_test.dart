import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ledger_pulse/data/repositories/supabase_auth_repository.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

      // 2. User enters phone number and completes OTP verification
      const testPhone = '+91 98765 43210';
      await initialRepo.sendOtp(testPhone);
      final verified = await initialRepo.verifyOtp(testPhone, '123456');
      expect(verified, isTrue);
      expect(initialRepo.isAuthenticated, isTrue);
      expect(initialRepo.currentPhoneNumber, equals(testPhone));
      expect(initialRepo.currentUserId, isNotNull);

      // Verify SharedPreferences has persisted the keys
      expect(prefs.getString('supabase_auth_phone_number'), equals(testPhone));
      expect(prefs.getString('supabase_auth_user_id'), isNotNull);
      expect(prefs.getString('supabase_auth_session_token'), isNotNull);

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
      expect(restoredRepo.currentPhoneNumber, equals(testPhone));
      expect(restoredState.isAuthenticated, isTrue,
          reason: 'AuthController must be authenticated on launch without OTP');
      expect(restoredState.phoneNumber, equals(testPhone));
    });

    test('Logging out removes device authentication', () async {
      final prefs = await SharedPreferences.getInstance();
      
      // Seed signed-in state
      await prefs.setString('supabase_auth_phone_number', '+91 98765 43210');
      await prefs.setString('supabase_auth_user_id', 'usr_test_123');
      await prefs.setString('supabase_auth_session_token', 'jwt_test_token');

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
