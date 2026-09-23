import 'dart:convert';
import 'package:flutter/foundation.dart';

enum SubscriptionTier {
  silver,
  gold,
  diamond;

  String get displayName {
    switch (this) {
      case SubscriptionTier.silver:
        return 'Silver Plan';
      case SubscriptionTier.gold:
        return 'Gold Plan';
      case SubscriptionTier.diamond:
        return 'Diamond ERP';
    }
  }

  String get badgeText {
    switch (this) {
      case SubscriptionTier.silver:
        return 'SILVER';
      case SubscriptionTier.gold:
        return 'GOLD';
      case SubscriptionTier.diamond:
        return 'DIAMOND';
    }
  }

  int get maxCompanies {
    switch (this) {
      case SubscriptionTier.silver:
        return 1;
      case SubscriptionTier.gold:
        return 5;
      case SubscriptionTier.diamond:
        return 50; // Unlimited in practice
    }
  }

  int get monthlyGstCreditLimit {
    switch (this) {
      case SubscriptionTier.silver:
        return 20;
      case SubscriptionTier.gold:
        return 200;
      case SubscriptionTier.diamond:
        return 1000;
    }
  }

  bool get supportsCustomBranding => this == SubscriptionTier.diamond;
  bool get supportsPayroll => this == SubscriptionTier.diamond;
  bool get supportsManufacturing => this == SubscriptionTier.diamond;
  bool get supportsEcommerceSync => this == SubscriptionTier.diamond;
  bool get supportsChequePrinting => this == SubscriptionTier.diamond;
  bool get supportsCustomSqlStudio => this != SubscriptionTier.silver;
  bool get supportsAdvancedReports => this != SubscriptionTier.silver;
}

enum BillingDuration {
  monthly,
  yearly,
  lifetime;

  String get displayName {
    switch (this) {
      case BillingDuration.monthly:
        return 'Monthly';
      case BillingDuration.yearly:
        return 'Yearly (Save 20%)';
      case BillingDuration.lifetime:
        return 'Lifetime (10-Year License)';
    }
  }

  int get priceInRupeesSilver {
    switch (this) {
      case BillingDuration.monthly:
        return 499;
      case BillingDuration.yearly:
        return 4790;
      case BillingDuration.lifetime:
        return 14999;
    }
  }

  int get priceInRupeesGold {
    switch (this) {
      case BillingDuration.monthly:
        return 999;
      case BillingDuration.yearly:
        return 9590;
      case BillingDuration.lifetime:
        return 29999;
    }
  }

  int get priceInRupeesDiamond {
    switch (this) {
      case BillingDuration.monthly:
        return 1999;
      case BillingDuration.yearly:
        return 19190;
      case BillingDuration.lifetime:
        return 49999;
    }
  }
}

@immutable
class LicenseState {
  final SubscriptionTier tier;
  final BillingDuration duration;
  final DateTime startDate;
  final DateTime expiryDate;
  final bool isTrial;
  final String? licenseKey;
  final int gstCreditsUsedThisMonth;

  const LicenseState({
    required this.tier,
    required this.duration,
    required this.startDate,
    required this.expiryDate,
    this.isTrial = false,
    this.licenseKey,
    this.gstCreditsUsedThisMonth = 0,
  });

  bool get isExpired => DateTime.now().isAfter(expiryDate);

  int get daysRemaining {
    final diff = expiryDate.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  int get remainingGstCredits {
    final limit = tier.monthlyGstCreditLimit;
    final remaining = limit - gstCreditsUsedThisMonth;
    return remaining < 0 ? 0 : remaining;
  }

  bool get canCreateCompany {
    if (isExpired) return false;
    return true;
  }

  bool canAccessTemplate(String templateTypeId) {
    if (isExpired) return false;
    if (tier == SubscriptionTier.diamond) return true;
    if (tier == SubscriptionTier.gold) {
      return templateTypeId != 'custom_branding';
    }
    // Silver only allows classic or minimal or gstStatutory
    return templateTypeId == 'classic' || templateTypeId == 'minimal' || templateTypeId == 'gstStatutory';
  }

  LicenseState copyWith({
    SubscriptionTier? tier,
    BillingDuration? duration,
    DateTime? startDate,
    DateTime? expiryDate,
    bool? isTrial,
    String? licenseKey,
    int? gstCreditsUsedThisMonth,
  }) {
    return LicenseState(
      tier: tier ?? this.tier,
      duration: duration ?? this.duration,
      startDate: startDate ?? this.startDate,
      expiryDate: expiryDate ?? this.expiryDate,
      isTrial: isTrial ?? this.isTrial,
      licenseKey: licenseKey ?? this.licenseKey,
      gstCreditsUsedThisMonth: gstCreditsUsedThisMonth ?? this.gstCreditsUsedThisMonth,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tier': tier.name,
      'duration': duration.name,
      'startDate': startDate.toIso8601String(),
      'expiryDate': expiryDate.toIso8601String(),
      'isTrial': isTrial,
      'licenseKey': licenseKey,
      'gstCreditsUsedThisMonth': gstCreditsUsedThisMonth,
    };
  }

  factory LicenseState.fromMap(Map<String, dynamic> map) {
    return LicenseState(
      tier: SubscriptionTier.values.firstWhere(
        (t) => t.name == map['tier'],
        orElse: () => SubscriptionTier.silver,
      ),
      duration: BillingDuration.values.firstWhere(
        (d) => d.name == map['duration'],
        orElse: () => BillingDuration.monthly,
      ),
      startDate: DateTime.tryParse(map['startDate'] ?? '') ?? DateTime.now(),
      expiryDate: DateTime.tryParse(map['expiryDate'] ?? '') ??
          DateTime.now().add(const Duration(days: 30)),
      isTrial: map['isTrial'] == true,
      licenseKey: map['licenseKey'],
      gstCreditsUsedThisMonth: map['gstCreditsUsedThisMonth'] ?? 0,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory LicenseState.fromJson(String source) => LicenseState.fromMap(jsonDecode(source));
}
