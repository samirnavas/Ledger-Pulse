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

  int get maxCompanies => 999;
  int get monthlyGstCreditLimit => 999999;

  bool get supportsCustomBranding => true;
  bool get supportsPayroll => true;
  bool get supportsManufacturing => true;
  bool get supportsEcommerceSync => true;
  bool get supportsChequePrinting => true;
  bool get supportsCustomSqlStudio => true;
  bool get supportsAdvancedReports => true;
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

  bool get isExpired => false;
  int get daysRemaining => 99999;
  int get remainingGstCredits => 999999;
  bool get canCreateCompany => true;
  bool canAccessTemplate(String templateTypeId) => true;

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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LicenseState &&
        other.tier == tier &&
        other.duration == duration &&
        other.startDate == startDate &&
        other.expiryDate == expiryDate &&
        other.isTrial == isTrial &&
        other.licenseKey == licenseKey &&
        other.gstCreditsUsedThisMonth == gstCreditsUsedThisMonth;
  }

  @override
  int get hashCode => Object.hash(
        tier,
        duration,
        startDate,
        expiryDate,
        isTrial,
        licenseKey,
        gstCreditsUsedThisMonth,
      );
}
