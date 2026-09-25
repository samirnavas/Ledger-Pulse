import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';

import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/subscription_tier_model.dart';
import '../providers/subscription_providers.dart';

class SubscriptionPaywallScreen extends ConsumerStatefulWidget {
  const SubscriptionPaywallScreen({super.key});

  @override
  ConsumerState<SubscriptionPaywallScreen> createState() =>
      _SubscriptionPaywallScreenState();
}

class _SubscriptionPaywallScreenState
    extends ConsumerState<SubscriptionPaywallScreen> {
  BillingDuration _selectedDuration = BillingDuration.yearly;
  final TextEditingController _licenseKeyController = TextEditingController();
  // ignore: prefer_final_fields, unused_field
  bool _isActivating = false; // Reserved for async activation flow

  @override
  void dispose() {
    _licenseKeyController.dispose();
    super.dispose();
  }

  void _onSelectPlan(SubscriptionTier tier) {
    HapticFeedback.mediumImpact();
    ref.read(subscriptionStateProvider.notifier).upgradePlan(
          tier: tier,
          duration: _selectedDuration,
        );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Successfully upgraded to ${tier.displayName}!'),
        backgroundColor: AppColors.receivableGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showLicenseKeyDialog() {
    final isIos = AdaptiveThemeHelper.isIos(context);

    void onActivate(BuildContext ctx) {
      final key = _licenseKeyController.text.trim();
      if (key.isEmpty) return;
      Navigator.pop(ctx);
      final success = ref
          .read(subscriptionStateProvider.notifier)
          .activateLicenseKey(
            licenseKey: key,
            customerId: 'CUST-DEFAULT-01',
          );
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('License Key Activated Successfully!'),
            backgroundColor: AppColors.receivableGreen,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid License Key format. Please try again.'),
            backgroundColor: AppColors.payableRed,
          ),
        );
      }
    }

    if (isIos) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Redeem License Key'),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter your 16-character Ludgerpulse activation key:',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: _licenseKeyController,
                  textCapitalization: TextCapitalization.characters,
                  placeholder: 'LP-DIA-ABCD-EFGH-IJKL',
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(CupertinoIcons.ticket, size: 18),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => onActivate(ctx),
              child: const Text('Activate'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Redeem License Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter your 16-character Ludgerpulse activation key (e.g. LP-DIA-XXXX-XXXX-XXXX):',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _licenseKeyController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'LP-DIA-ABCD-EFGH-IJKL',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.vpn_key_rounded),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => onActivate(ctx),
              child: const Text('Activate'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentSub = ref.watch(subscriptionStateProvider);

    return AdaptiveScaffold(
      title: 'Ludgerpulse ERP Plans',
      actions: [
        IconButton(
          tooltip: 'Enter License Key',
          icon: Icon(isIos ? CupertinoIcons.ticket : Icons.vpn_key_rounded),
          onPressed: _showLicenseKeyDialog,
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Active Subscription / Trial Status Banner
            _buildStatusHeader(isIos, isDark, currentSub),
            const SizedBox(height: 16),

            // Billing Period Switcher
            Center(
              child: AdaptiveSegmentedControl<BillingDuration>(
                groupValue: _selectedDuration,
                children: const {
                  BillingDuration.monthly: Text('Monthly'),
                  BillingDuration.yearly: Text('Yearly (Save 20%)'),
                  BillingDuration.lifetime: Text('Lifetime'),
                },
                onValueChanged: (val) {
                  setState(() => _selectedDuration = val);
                },
              ),
            ),
            const SizedBox(height: 20),

            // 3 Tier Cards
            _buildTierCard(
              context: context,
              isIos: isIos,
              isDark: isDark,
              tier: SubscriptionTier.silver,
              price: _selectedDuration == BillingDuration.monthly
                  ? '₹499/mo'
                  : _selectedDuration == BillingDuration.yearly
                      ? '₹4,790/yr'
                      : '₹14,999 (10-Yr)',
              features: [
                '1 LPWeb Company',
                '20 e-Way Bills & e-Invoices / mo',
                'Standard Invoicing & POS',
                'Basic Double-Entry Ledger',
                'Local & Cloud Backup',
              ],
              isCurrent: currentSub.tier == SubscriptionTier.silver && !currentSub.isTrial,
              accentColor: Colors.blueGrey,
            ),
            const SizedBox(height: 14),

            _buildTierCard(
              context: context,
              isIos: isIos,
              isDark: isDark,
              tier: SubscriptionTier.gold,
              price: _selectedDuration == BillingDuration.monthly
                  ? '₹999/mo'
                  : _selectedDuration == BillingDuration.yearly
                      ? '₹9,590/yr'
                      : '₹29,999 (10-Yr)',
              features: [
                'Up to 5 Multi-GST Companies',
                '200 e-Way Bills & e-Invoices / mo',
                'GST Statutory Tax Invoices & POS',
                'Desktop Custom SQL Report Studio',
                'Audit Trail & MCA Compliance',
                'GSTR-1, 2A, 3B JSON Generation',
              ],
              isPopular: true,
              isCurrent: currentSub.tier == SubscriptionTier.gold && !currentSub.isTrial,
              accentColor: const Color(0xFFD97706),
            ),
            const SizedBox(height: 14),

            _buildTierCard(
              context: context,
              isIos: isIos,
              isDark: isDark,
              tier: SubscriptionTier.diamond,
              price: _selectedDuration == BillingDuration.monthly
                  ? '₹1,999/mo'
                  : _selectedDuration == BillingDuration.yearly
                      ? '₹19,190/yr'
                      : '₹49,999 (10-Yr)',
              features: [
                'Unlimited Companies & Users (50+)',
                '1,000 e-Way Bills & e-Invoices / mo',
                'Full Payroll & Salary Slips Module',
                'Manufacturing Journal & BOM Production',
                'Amazon & Flipkart Order Auto-Sync',
                'Indian CTS-2010 Cheque Printing',
                'All 36 Master Financial & Tax Reports',
                'Razorpay, Paytm, Cashfree & UPI Links',
              ],
              isCurrent: (currentSub.tier == SubscriptionTier.diamond && !currentSub.isTrial),
              accentColor: const Color(0xFF7C3AED),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader(bool isIos, bool isDark, LicenseState sub) {
    final statusContent = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: sub.isTrial
                  ? Colors.amber.withValues(alpha: 0.2)
                  : Colors.green.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              sub.isTrial
                  ? (isIos ? CupertinoIcons.timer : Icons.timer_rounded)
                  : (isIos ? CupertinoIcons.checkmark_seal_fill : Icons.verified_rounded),
              color: sub.isTrial ? Colors.amber.shade700 : AppColors.receivableGreen,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      sub.isTrial
                          ? '14-Day Full Diamond Trial'
                          : '${sub.tier.displayName} (${sub.duration.displayName})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  sub.isTrial
                      ? '${sub.daysRemaining} days remaining • All ERP features unlocked'
                      : 'Valid until ${sub.expiryDate.day}/${sub.expiryDate.month}/${sub.expiryDate.year} • ${sub.remainingGstCredits} GST credits remaining',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 16,
        padding: EdgeInsets.zero,
        child: statusContent,
      );
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: sub.isTrial ? Colors.amber.shade300 : AppColors.receivableGreen.withValues(alpha: 0.4),
        ),
      ),
      child: statusContent,
    );
  }

  Widget _buildTierCard({
    required BuildContext context,
    required bool isIos,
    required bool isDark,
    required SubscriptionTier tier,
    required String price,
    required List<String> features,
    required Color accentColor,
    bool isPopular = false,
    bool isCurrent = false,
  }) {
    final cardContent = Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    tier.displayName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                  if (isPopular) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: accentColor),
                      ),
                      child: Text(
                        'POPULAR',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                price,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          ...features.map((feat) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      isIos ? CupertinoIcons.checkmark_circle_fill : Icons.check_circle_rounded,
                      size: 16,
                      color: accentColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        feat,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: AdaptiveButton(
              type: isCurrent ? AdaptiveButtonType.secondary : AdaptiveButtonType.primary,
              onPressed: isCurrent ? () {} : () => _onSelectPlan(tier),
              child: Text(
                isCurrent ? 'Current Plan' : 'Select ${tier.displayName}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );

    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 20,
        padding: EdgeInsets.zero,
        child: cardContent,
      );
    }
    return Card(
      elevation: isPopular ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isPopular ? accentColor : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
          width: isPopular ? 2 : 1,
        ),
      ),
      child: cardContent,
    );
  }
}
