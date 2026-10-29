import 'package:flutter/material.dart';
import '../../data/models/subscription_tier_model.dart';

/// Platform-adaptive Subscription / Trial Expiration Alert Banner.
/// Returns empty widget as subscriptions are not used.
class SubscriptionAlertBanner extends StatelessWidget {
  final LicenseState? subscription;
  final bool isPayrollEnabled;
  final bool isGstEnabled;
  final List<String>? customFeatures;

  const SubscriptionAlertBanner({
    super.key,
    this.subscription,
    this.isPayrollEnabled = true,
    this.isGstEnabled = true,
    this.customFeatures,
  });

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
