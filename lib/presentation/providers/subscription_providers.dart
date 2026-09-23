import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/subscription_tier_model.dart';
import '../../data/services/licensing_service.dart';

class SubscriptionNotifier extends Notifier<LicenseState> {
  @override
  LicenseState build() {
    // Default to an active 14-day Diamond trial for initial user onboarding
    return LicensingService.createFreeTrial();
  }

  void upgradePlan({
    required SubscriptionTier tier,
    required BillingDuration duration,
  }) {
    state = LicensingService.activatePlan(tier: tier, duration: duration);
  }

  bool activateLicenseKey({
    required String licenseKey,
    required String customerId,
  }) {
    final activated = LicensingService.validateAndActivateKey(
      licenseKey: licenseKey,
      customerId: customerId,
    );
    if (activated != null) {
      state = activated;
      return true;
    }
    return false;
  }

  void consumeGstCredit([int credits = 1]) {
    state = state.copyWith(
      gstCreditsUsedThisMonth: state.gstCreditsUsedThisMonth + credits,
    );
  }

  void resetTrial() {
    state = LicensingService.createFreeTrial();
  }
}

final subscriptionStateProvider =
    NotifierProvider<SubscriptionNotifier, LicenseState>(
  SubscriptionNotifier.new,
);

final currentSubscriptionTierProvider = Provider<SubscriptionTier>((ref) {
  return ref.watch(subscriptionStateProvider).tier;
});

final isSubscriptionExpiredProvider = Provider<bool>((ref) {
  return ref.watch(subscriptionStateProvider).isExpired;
});

final isTrialActiveProvider = Provider<bool>((ref) {
  final sub = ref.watch(subscriptionStateProvider);
  return sub.isTrial && !sub.isExpired;
});

final trialDaysRemainingProvider = Provider<int>((ref) {
  final sub = ref.watch(subscriptionStateProvider);
  if (!sub.isTrial) return 0;
  return sub.daysRemaining;
});

final featureAccessProvider = Provider.family<bool, String>((ref, featureKey) {
  final sub = ref.watch(subscriptionStateProvider);
  if (sub.isExpired) return false;

  switch (featureKey) {
    case 'payroll':
      return sub.tier.supportsPayroll;
    case 'manufacturing':
      return sub.tier.supportsManufacturing;
    case 'ecommerce_sync':
      return sub.tier.supportsEcommerceSync;
    case 'cheque_printing':
      return sub.tier.supportsChequePrinting;
    case 'custom_sql_studio':
      return sub.tier.supportsCustomSqlStudio;
    case 'custom_branding':
      return sub.tier.supportsCustomBranding;
    default:
      return true;
  }
});
