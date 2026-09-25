import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/strings.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../providers/company_providers.dart';
import '../providers/profile_provider.dart';
import '../providers/subscription_providers.dart';
import '../reports/reporting_hub_screen.dart';
import '../settings/settings_screen.dart';
import 'company_switcher_sheet.dart';
import 'sync_settings_sheet.dart';

class DashboardSidebarDrawer extends ConsumerWidget {
  final VoidCallback onOpenErpModules;

  const DashboardSidebarDrawer({
    super.key,
    required this.onOpenErpModules,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final profile = ref.watch(userProfileProvider);
    final activeCompany = ref.watch(activeCompanyProvider);
    final subscription = ref.watch(subscriptionStateProvider);

    final drawerBg = isIos
        ? (isDark ? const Color(0xEE0F172A) : const Color(0xEEF8FAFC))
        : colorScheme.surfaceContainerLow;

    final profileBadge = Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.2),
          child: Text(
            profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'U',
            style: const TextStyle(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                profile.phoneNumber,
                style: TextStyle(
                  fontSize: 11,
                  color: isIos ? CupertinoColors.secondaryLabel : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: subscription.isExpired
                ? AppColors.payableRed.withValues(alpha: 0.15)
                : AppColors.receivableGreen.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            subscription.tier.displayName,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: subscription.isExpired
                  ? AppColors.payableRed
                  : AppColors.receivableGreen,
            ),
          ),
        ),
      ],
    );

    return Drawer(
      backgroundColor: drawerBg,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header with App & Active Company Info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isIos
                    ? (isDark ? const Color(0x881E293B) : Colors.white.withValues(alpha: 0.8))
                    : colorScheme.surfaceContainer,
                border: Border(
                  bottom: BorderSide(
                    color: isIos
                        ? (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08))
                        : colorScheme.outlineVariant.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (isIos ? CupertinoColors.activeBlue : colorScheme.primary).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isIos ? CupertinoIcons.building_2_fill : Icons.business_rounded,
                          size: 24,
                          color: isIos ? CupertinoColors.activeBlue : colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          activeCompany.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  isIos
                      ? LiquidGlassCard(
                          borderRadius: 14,
                          padding: const EdgeInsets.all(12),
                          child: profileBadge,
                        )
                      : Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: profileBadge,
                        ),
                ],
              ),
            ),

            // Navigation Items List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'QUICK ACTIONS & TOOLS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),

                  // 1. Company Switcher
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isIos ? CupertinoIcons.building_2_fill : Icons.business_rounded,
                        color: Colors.indigo,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Switch Company',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Text(
                      activeCompany.name,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      CompanySwitcherSheet.show(context);
                    },
                  ),

                  // 2. Sync & Backup Center
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isIos ? CupertinoIcons.cloud_upload : Icons.sync_rounded,
                        color: Colors.blue,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Sync & Backup Center',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Cloud synchronization status & settings',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      SyncSettingsSheet.show(context);
                    },
                  ),

                  // 3. Reports & Analytics Hub
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isIos ? CupertinoIcons.chart_pie : Icons.insights_rounded,
                        color: Colors.purple,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Reports & Analytics Hub',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Daybook, P&L, GST & Party analytics',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        createAdaptivePageRoute(builder: (context) => const ReportingHubScreen()),
                      );
                    },
                  ),

                  // 4. ERP Modules & Paywall
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade800.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isIos ? CupertinoIcons.square_grid_2x2 : Icons.apps_rounded,
                        color: Colors.amber.shade800,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'ERP Modules & Licensing',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Payroll, Importers, Cheque printing & Paywall',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      onOpenErpModules();
                    },
                  ),

                  // 5. Settings & Preferences
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isIos ? CupertinoIcons.gear_alt_fill : Icons.settings_rounded,
                        color: Colors.blueGrey,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Settings & Preferences',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Color theme, profile, cloud sync & system settings',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        createAdaptivePageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Footer with App Logo
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.asset(
                      'assets/icons/app_icon.png',
                      height: 16,
                      width: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    AppStrings.appName,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
