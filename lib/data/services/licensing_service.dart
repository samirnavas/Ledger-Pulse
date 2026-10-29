import '../models/subscription_tier_model.dart';

class LicensingService {
  static const String saltSecret = 'LUDGERPULSE_ERP_SECURE_SALT_2026';

  static String generateLicenseKey({
    required SubscriptionTier tier,
    required BillingDuration duration,
    required String customerId,
  }) {
    return 'LP-DIA-LIFETIME';
  }

  static LicenseState? validateAndActivateKey({
    required String licenseKey,
    required String customerId,
  }) {
    return LicenseState(
      tier: SubscriptionTier.diamond,
      duration: BillingDuration.lifetime,
      startDate: DateTime(2020),
      expiryDate: DateTime(2099),
      isTrial: false,
      licenseKey: 'LIFETIME-ACTIVE',
    );
  }

  static LicenseState createFreeTrial() {
    return LicenseState(
      tier: SubscriptionTier.diamond,
      duration: BillingDuration.lifetime,
      startDate: DateTime(2020),
      expiryDate: DateTime(2099),
      isTrial: false,
      licenseKey: 'LIFETIME-ACTIVE',
    );
  }

  static LicenseState activatePlan({
    required SubscriptionTier tier,
    required BillingDuration duration,
  }) {
    return LicenseState(
      tier: SubscriptionTier.diamond,
      duration: BillingDuration.lifetime,
      startDate: DateTime(2020),
      expiryDate: DateTime(2099),
      isTrial: false,
      licenseKey: 'LIFETIME-ACTIVE',
    );
  }
}
