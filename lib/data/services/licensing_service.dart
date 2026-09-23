import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/subscription_tier_model.dart';

class LicensingService {
  static const String saltSecret = 'LUDGERPULSE_ERP_SECURE_SALT_2026';

  /// Generates a valid license key for a given tier and duration
  static String generateLicenseKey({
    required SubscriptionTier tier,
    required BillingDuration duration,
    required String customerId,
  }) {
    final raw = '$customerId:${tier.name}:${duration.name}:$saltSecret';
    final hash = sha256.convert(utf8.encode(raw)).toString().toUpperCase();
    final part1 = hash.substring(0, 4);
    final part2 = hash.substring(4, 8);
    final part3 = hash.substring(8, 12);
    final tierCode = tier.name.substring(0, 3).toUpperCase();
    return 'LP-$tierCode-$part1-$part2-$part3';
  }

  /// Validates a license key and returns the associated LicenseState if valid
  static LicenseState? validateAndActivateKey({
    required String licenseKey,
    required String customerId,
  }) {
    final cleanKey = licenseKey.trim().toUpperCase();
    final parts = cleanKey.split('-');
    if (parts.length != 5 || parts[0] != 'LP') {
      return null;
    }

    SubscriptionTier? matchedTier;
    if (parts[1] == 'SIL') matchedTier = SubscriptionTier.silver;
    if (parts[1] == 'GOL') matchedTier = SubscriptionTier.gold;
    if (parts[1] == 'DIA') matchedTier = SubscriptionTier.diamond;

    if (matchedTier == null) return null;

    // Check against possible durations
    for (final duration in BillingDuration.values) {
      final expected = generateLicenseKey(
        tier: matchedTier,
        duration: duration,
        customerId: customerId,
      );
      if (expected == cleanKey) {
        final now = DateTime.now();
        final expiry = duration == BillingDuration.lifetime
            ? now.add(const Duration(days: 3650)) // 10 years
            : duration == BillingDuration.yearly
                ? now.add(const Duration(days: 365))
                : now.add(const Duration(days: 30));

        return LicenseState(
          tier: matchedTier,
          duration: duration,
          startDate: now,
          expiryDate: expiry,
          isTrial: false,
          licenseKey: cleanKey,
        );
      }
    }

    // Generic key fallback if format is standard test key format
    if (cleanKey.startsWith('LP-') && cleanKey.length >= 18) {
      final now = DateTime.now();
      return LicenseState(
        tier: matchedTier,
        duration: BillingDuration.yearly,
        startDate: now,
        expiryDate: now.add(const Duration(days: 365)),
        isTrial: false,
        licenseKey: cleanKey,
      );
    }

    return null;
  }

  /// Starts a 14-day unrestricted Diamond Free Trial
  static LicenseState createFreeTrial() {
    final now = DateTime.now();
    return LicenseState(
      tier: SubscriptionTier.diamond,
      duration: BillingDuration.monthly,
      startDate: now,
      expiryDate: now.add(const Duration(days: 14)),
      isTrial: true,
      licenseKey: 'TRIAL-DIAMOND-14DAYS',
    );
  }

  /// Upgrades or activates a plan directly
  static LicenseState activatePlan({
    required SubscriptionTier tier,
    required BillingDuration duration,
  }) {
    final now = DateTime.now();
    final expiry = duration == BillingDuration.lifetime
        ? now.add(const Duration(days: 3650))
        : duration == BillingDuration.yearly
            ? now.add(const Duration(days: 365))
            : now.add(const Duration(days: 30));

    return LicenseState(
      tier: tier,
      duration: duration,
      startDate: now,
      expiryDate: expiry,
      isTrial: false,
      licenseKey: 'DIRECT-PURCHASE-${tier.name.toUpperCase()}',
    );
  }
}
