import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/subscription_tier_model.dart';
import 'package:ledger_pulse/data/services/licensing_service.dart';

void main() {
  group('Subscription & Licensing Paywall Tests (FR-LIC-01, FR-LIC-02, FR-LIC-03, FR-LIC-04)', () {
    test('SubscriptionTier limits and feature capabilities are enforced', () {
      expect(SubscriptionTier.silver.maxCompanies, equals(1));
      expect(SubscriptionTier.gold.maxCompanies, equals(5));
      expect(SubscriptionTier.diamond.maxCompanies, equals(50));

      expect(SubscriptionTier.silver.monthlyGstCreditLimit, equals(20));
      expect(SubscriptionTier.gold.monthlyGstCreditLimit, equals(200));
      expect(SubscriptionTier.diamond.monthlyGstCreditLimit, equals(1000));

      expect(SubscriptionTier.silver.supportsPayroll, isFalse);
      expect(SubscriptionTier.gold.supportsPayroll, isFalse);
      expect(SubscriptionTier.diamond.supportsPayroll, isTrue);

      expect(SubscriptionTier.silver.supportsManufacturing, isFalse);
      expect(SubscriptionTier.gold.supportsManufacturing, isFalse);
      expect(SubscriptionTier.diamond.supportsManufacturing, isTrue);

      expect(SubscriptionTier.silver.supportsChequePrinting, isFalse);
      expect(SubscriptionTier.gold.supportsChequePrinting, isFalse);
      expect(SubscriptionTier.diamond.supportsChequePrinting, isTrue);
    });

    test('14-Day Free Trial initializes with unrestricted Diamond tier', () {
      final trial = LicensingService.createFreeTrial();
      expect(trial.isTrial, isTrue);
      expect(trial.tier, equals(SubscriptionTier.diamond));
      expect(trial.daysRemaining, inInclusiveRange(13, 14));
      expect(trial.isExpired, isFalse);
      expect(trial.canAccessTemplate('custom_branding'), isTrue);
    });

    test('Billing duration pricing and lifetime validity (10 years) calculation', () {
      final lifetimeGold = LicensingService.activatePlan(
        tier: SubscriptionTier.gold,
        duration: BillingDuration.lifetime,
      );

      expect(lifetimeGold.isTrial, isFalse);
      expect(lifetimeGold.tier, equals(SubscriptionTier.gold));
      expect(lifetimeGold.daysRemaining, greaterThan(3600)); // ~10 years
      expect(lifetimeGold.canAccessTemplate('gstStatutory'), isTrue);
      expect(lifetimeGold.canAccessTemplate('custom_branding'), isFalse);
    });

    test('Cryptographic License Key Generation and Verification', () {
      const custId = 'CUST-LUDGER-9988';
      final key = LicensingService.generateLicenseKey(
        tier: SubscriptionTier.diamond,
        duration: BillingDuration.yearly,
        customerId: custId,
      );

      expect(key, startsWith('LP-DIA-'));

      final activated = LicensingService.validateAndActivateKey(
        licenseKey: key,
        customerId: custId,
      );

      expect(activated, isNotNull);
      expect(activated!.tier, equals(SubscriptionTier.diamond));
      expect(activated.duration, equals(BillingDuration.yearly));
      expect(activated.isTrial, isFalse);
    });

    test('GST credit consumption tracks accurately and prevents overage calculation', () {
      final state = LicenseState(
        tier: SubscriptionTier.silver,
        duration: BillingDuration.monthly,
        startDate: DateTime.now(),
        expiryDate: DateTime.now().add(const Duration(days: 30)),
        gstCreditsUsedThisMonth: 18,
      );

      expect(state.remainingGstCredits, equals(2));
      final updated = state.copyWith(gstCreditsUsedThisMonth: 25);
      expect(updated.remainingGstCredits, equals(0));
    });
  });
}
