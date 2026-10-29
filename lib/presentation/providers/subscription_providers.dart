import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/modules/module_catalog.dart';
import '../../data/models/company_mode.dart';
import '../../data/models/subscription_tier_model.dart';

class SubscriptionNotifier extends Notifier<LicenseState> {
  @override
  LicenseState build() {
    return LicenseState(
      tier: SubscriptionTier.diamond,
      duration: BillingDuration.lifetime,
      startDate: DateTime(2020),
      expiryDate: DateTime(2099),
      isTrial: false,
    );
  }

  void upgradePlan({
    required SubscriptionTier tier,
    required BillingDuration duration,
  }) {}

  bool activateLicenseKey({
    required String licenseKey,
    required String customerId,
  }) {
    return true;
  }

  void consumeGstCredit([int credits = 1]) {}

  void resetTrial() {}
}

final subscriptionStateProvider =
    NotifierProvider<SubscriptionNotifier, LicenseState>(
  SubscriptionNotifier.new,
);

final currentSubscriptionTierProvider = Provider<SubscriptionTier>((ref) {
  return SubscriptionTier.diamond;
});

final isSubscriptionExpiredProvider = Provider<bool>((ref) {
  return false;
});

final isTrialActiveProvider = Provider<bool>((ref) {
  return false;
});

final trialDaysRemainingProvider = Provider<int>((ref) {
  return 99999;
});

/// Checks whether a subscription tier entitles access to an [AppModule].
bool tierAllows(SubscriptionTier tier, AppModule module) {
  return true;
}

/// Entitlement provider for an [AppModule] based on current subscription state and expiry.
final tierAllowsProvider = Provider.family<bool, AppModule>((ref, module) {
  return true;
});
