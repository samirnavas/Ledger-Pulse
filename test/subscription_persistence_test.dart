import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ledger_pulse/data/models/subscription_tier_model.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';
import 'package:ledger_pulse/presentation/providers/subscription_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Subscription Persistence Unlocked Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Provides active non-expiring license state', () async {
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(subscriptionStateProvider);

      expect(state.tier, equals(SubscriptionTier.diamond));
      expect(state.isExpired, isFalse);
    });
  });
}
