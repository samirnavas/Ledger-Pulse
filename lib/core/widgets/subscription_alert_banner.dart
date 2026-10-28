import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/subscription_tier_model.dart';
import '../constants/colors.dart';
import '../theme/adaptive_theme.dart';
import '../utils/adaptive_page_route.dart';
import 'liquid_glass_card.dart';
import '../../presentation/subscription/subscription_paywall_screen.dart';

/// Platform-adaptive Subscription / Trial Expiration Alert Banner.
/// Displayed at the top of Home dashboard in both Ledger and Expense Tracker modes.
class SubscriptionAlertBanner extends StatelessWidget {
  final LicenseState subscription;
  final bool isPayrollEnabled;
  final bool isGstEnabled;
  final List<String>? customFeatures;

  const SubscriptionAlertBanner({
    super.key,
    required this.subscription,
    this.isPayrollEnabled = true,
    this.isGstEnabled = true,
    this.customFeatures,
  });

  @override
  Widget build(BuildContext context) {
    if (!subscription.isExpired && (!subscription.isTrial || subscription.daysRemaining > 3)) {
      return const SizedBox.shrink();
    }

    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isExpired = subscription.isExpired;
    final title = isExpired
        ? 'Subscription Expired'
        : 'Trial Ending in ${subscription.daysRemaining} Days';

    final features = <String>[];
    if (customFeatures != null) {
      features.addAll(customFeatures!);
    } else {
      if (isPayrollEnabled) features.add('payroll');
      if (isGstEnabled) features.add('GST e-Way bills');
      features.add('unlimited companies');
    }

    final message = isExpired
        ? 'Your access to advanced modules and sync is paused. Tap to renew now.'
        : 'Upgrade to keep ${features.join(", ")}.';

    final content = InkWell(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.of(context).push(
          createAdaptivePageRoute(builder: (_) => const SubscriptionPaywallScreen()),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isExpired ? AppColors.payableRed : Colors.amber.shade700).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isIos
                    ? (isExpired ? CupertinoIcons.exclamationmark_triangle_fill : CupertinoIcons.timer)
                    : (isExpired ? Icons.warning_rounded : Icons.timer_rounded),
                color: isExpired ? AppColors.payableRed : Colors.amber.shade700,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isExpired ? AppColors.payableRed : Colors.amber.shade800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (isExpired ? AppColors.payableRed : AppColors.primaryBlue),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'UPGRADE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (isIos) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: LiquidGlassCard(
          borderRadius: 16,
          padding: EdgeInsets.zero,
          child: content,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: (isExpired ? AppColors.payableRed : Colors.amber.shade400).withValues(alpha: 0.6),
          ),
        ),
        color: (isExpired ? AppColors.payableRed : Colors.amber).withValues(alpha: isDark ? 0.12 : 0.06),
        child: content,
      ),
    );
  }
}
