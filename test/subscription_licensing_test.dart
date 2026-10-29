import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/subscription_tier_model.dart';
import 'package:ledger_pulse/data/services/licensing_service.dart';

void main() {
  group('Subscription & Licensing Unlocked Tests', () {
    test('All capabilities are unlocked and non-expiring', () {
      expect(SubscriptionTier.silver.maxCompanies, equals(999));
      expect(SubscriptionTier.gold.maxCompanies, equals(999));
      expect(SubscriptionTier.diamond.maxCompanies, equals(999));

      expect(SubscriptionTier.silver.supportsPayroll, isTrue);
      expect(SubscriptionTier.gold.supportsPayroll, isTrue);
      expect(SubscriptionTier.diamond.supportsPayroll, isTrue);

      expect(SubscriptionTier.silver.supportsManufacturing, isTrue);
      expect(SubscriptionTier.gold.supportsManufacturing, isTrue);
      expect(SubscriptionTier.diamond.supportsManufacturing, isTrue);
    });

    test('LicensingService returns unlocked active state', () {
      final trial = LicensingService.createFreeTrial();
      expect(trial.tier, equals(SubscriptionTier.diamond));
      expect(trial.isExpired, isFalse);
      expect(trial.canAccessTemplate('custom_branding'), isTrue);
    });
  });
}
