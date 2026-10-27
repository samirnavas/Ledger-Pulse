import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/modules/module_catalog.dart';
import '../../data/models/company_mode.dart';
import '../../data/models/subscription_tier_model.dart';
import '../../data/services/licensing_service.dart';
import 'auth_providers.dart';


class SubscriptionNotifier extends Notifier<LicenseState> {
  static const _kLicensePrefsKey = 'ledger_pulse_license_state';

  @override
  LicenseState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    if (prefs != null) {
      final jsonString = prefs.getString(_kLicensePrefsKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        try {
          return LicenseState.fromJson(jsonString);
        } catch (e) {
          debugPrint('Error loading license state: $e');
        }
      }
    }

    // Default to an active 14-day Diamond trial for initial user onboarding when nothing is stored
    final initialTrial = LicensingService.createFreeTrial();
    _persistLicense(initialTrial);
    return initialTrial;
  }

  Future<void> _persistLicense(LicenseState license) async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      if (prefs != null) {
        await prefs.setString(_kLicensePrefsKey, license.toJson());
      }
    } catch (e) {
      debugPrint('Error saving license state: $e');
    }
  }

  void upgradePlan({
    required SubscriptionTier tier,
    required BillingDuration duration,
  }) {
    state = LicensingService.activatePlan(tier: tier, duration: duration);
    _persistLicense(state);
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
      _persistLicense(state);
      return true;
    }
    return false;
  }

  void consumeGstCredit([int credits = 1]) {
    state = state.copyWith(
      gstCreditsUsedThisMonth: state.gstCreditsUsedThisMonth + credits,
    );
    _persistLicense(state);
  }

  void resetTrial() {
    state = LicensingService.createFreeTrial();
    _persistLicense(state);
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

/// Checks whether a subscription tier entitles access to an [AppModule].
bool tierAllows(SubscriptionTier tier, AppModule module) {
  final minTier = ModuleCatalog.minTierFor(module);
  return tier.index >= minTier.index;
}

/// Entitlement provider for an [AppModule] based on current subscription state and expiry.
final tierAllowsProvider = Provider.family<bool, AppModule>((ref, module) {
  final sub = ref.watch(subscriptionStateProvider);
  if (sub.isExpired) return false;
  return tierAllows(sub.tier, module);
});

