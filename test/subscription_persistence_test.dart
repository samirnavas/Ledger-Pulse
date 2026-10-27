import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ledger_pulse/data/models/subscription_tier_model.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';
import 'package:ledger_pulse/presentation/providers/subscription_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Subscription Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Creates a new 14-day trial and persists to SharedPreferences when nothing is stored', () async {
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(subscriptionStateProvider);

      expect(state.isTrial, isTrue);
      expect(state.tier, equals(SubscriptionTier.diamond));
      expect(state.daysRemaining, inInclusiveRange(13, 14));

      // Check SharedPreferences key was populated
      final storedJson = prefs.getString('ledger_pulse_license_state');
      expect(storedJson, isNotNull);

      final restored = LicenseState.fromJson(storedJson!);
      expect(restored.tier, equals(state.tier));
      expect(restored.isTrial, equals(state.isTrial));
      expect(restored.startDate, equals(state.startDate));
      expect(restored.expiryDate, equals(state.expiryDate));
    });

    test('Restores existing license from SharedPreferences and does not overwrite with a new trial', () async {
      final existingStartDate = DateTime(2025, 1, 1, 10, 0, 0);
      final existingExpiryDate = DateTime(2025, 6, 1, 10, 0, 0);
      final existingLicense = LicenseState(
        tier: SubscriptionTier.gold,
        duration: BillingDuration.yearly,
        startDate: existingStartDate,
        expiryDate: existingExpiryDate,
        isTrial: false,
        licenseKey: 'LP-GOLD-TEST-KEY',
        gstCreditsUsedThisMonth: 12,
      );

      SharedPreferences.setMockInitialValues({
        'ledger_pulse_license_state': existingLicense.toJson(),
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(subscriptionStateProvider);

      // Verify it did not create a new 14-day diamond trial
      expect(state.isTrial, isFalse);
      expect(state.tier, equals(SubscriptionTier.gold));
      expect(state.duration, equals(BillingDuration.yearly));
      expect(state.licenseKey, equals('LP-GOLD-TEST-KEY'));
      expect(state.gstCreditsUsedThisMonth, equals(12));
      expect(state.startDate, equals(existingStartDate));
      expect(state.expiryDate, equals(existingExpiryDate));
    });

    test('Mutations persist updated license state to SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(subscriptionStateProvider.notifier);

      // 1. Upgrade plan
      notifier.upgradePlan(
        tier: SubscriptionTier.gold,
        duration: BillingDuration.monthly,
      );
      await Future<void>.delayed(Duration.zero);

      var storedJson = prefs.getString('ledger_pulse_license_state');
      expect(storedJson, isNotNull);
      var restored = LicenseState.fromJson(storedJson!);
      expect(restored.tier, equals(SubscriptionTier.gold));
      expect(restored.isTrial, isFalse);

      // 2. Consume credits
      notifier.consumeGstCredit(5);
      await Future<void>.delayed(Duration.zero);

      storedJson = prefs.getString('ledger_pulse_license_state');
      restored = LicenseState.fromJson(storedJson!);
      expect(restored.gstCreditsUsedThisMonth, equals(5));
    });
  });
}
