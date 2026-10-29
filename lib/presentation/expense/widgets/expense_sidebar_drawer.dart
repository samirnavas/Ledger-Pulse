import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/mode_strings.dart';
import '../../../core/constants/strings.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../core/utils/adaptive_page_route.dart';
import '../../../data/models/company_model.dart';
import '../../home/company_switcher_sheet.dart';
import '../../home/sync_settings_sheet.dart';
import '../../providers/company_providers.dart';
import '../../reports/reporting_hub_screen.dart';
import '../../settings/modules_screen.dart';
import '../../settings/settings_screen.dart';
import '../../subscription/subscription_paywall_screen.dart';
import '../recurring_screen.dart';

/// Platform-adaptive drawer for Expense Tracker mode.
/// Hides all ledger-only items (ERP modules, BI hub, GST, payroll).
/// Exposes company header, Settings, Modules, Sync & Backup, Subscription,
/// Recurring rules (if module on), Export, and 'Upgrade to Business Ledger'.
class ExpenseSidebarDrawer extends ConsumerWidget {
  const ExpenseSidebarDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final activeCompany = ref.watch(activeCompanyProvider);
    final modeStrings = ModeStrings.of(activeCompany.mode);
    final isRecurringEnabled = activeCompany.isModuleEnabled(AppModule.recurring);

    final drawerBg = isIos
        ? (isDark
            ? AppColors.surfaceDark.withValues(alpha: 0.93)
            : AppColors.surfaceLight.withValues(alpha: 0.93))
        : colorScheme.surfaceContainerLow;

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
                    ? (isDark
                        ? AppColors.surfaceCardDark.withValues(alpha: 0.55)
                        : Colors.white.withValues(alpha: 0.8))
                    : colorScheme.surfaceContainer,
                border: Border(
                  bottom: BorderSide(
                    color: isIos
                        ? (isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.08))
                        : colorScheme.outlineVariant.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isIos
                              ? CupertinoColors.activeBlue
                              : colorScheme.primary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isIos
                          ? CupertinoIcons.money_dollar_circle_fill
                          : Icons.account_balance_wallet_rounded,
                      size: 24,
                      color: isIos
                          ? CupertinoColors.activeBlue
                          : colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          activeCompany.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          modeStrings.entitySubtitlePlaceholder,
                          style: TextStyle(
                            fontSize: 12,
                            color: isIos
                                ? CupertinoColors.secondaryLabel
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
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
                        color: (isIos
                                ? CupertinoColors.activeBlue
                                : colorScheme.primary)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(isIos ? 10 : 14),
                      ),
                      child: Icon(
                        isIos
                            ? CupertinoIcons.arrow_2_squarepath
                            : Icons.swap_horizontal_circle_rounded,
                        color: isIos
                            ? CupertinoColors.activeBlue
                            : colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      modeStrings.switchEntity,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      activeCompany.name,
                      style: TextStyle(
                        fontSize: 11,
                        color: isIos
                            ? CupertinoColors.secondaryLabel
                            : colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Icon(
                      isIos
                          ? CupertinoIcons.chevron_forward
                          : Icons.chevron_right_rounded,
                      size: isIos ? 14 : 20,
                      color: isIos
                          ? CupertinoColors.tertiaryLabel
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      CompanySwitcherSheet.show(context);
                    },
                  ),

                  // 2. Settings
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isIos
                                ? CupertinoColors.systemPurple
                                : colorScheme.tertiary)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(isIos ? 10 : 14),
                      ),
                      child: Icon(
                        isIos
                            ? CupertinoIcons.gear_alt_fill
                            : Icons.settings_suggest_rounded,
                        color: isIos
                            ? CupertinoColors.activeBlue
                            : colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Settings',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Preferences, theme, profile & system',
                      style: TextStyle(
                        fontSize: 11,
                        color: isIos
                            ? CupertinoColors.secondaryLabel
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Icon(
                      isIos
                          ? CupertinoIcons.chevron_forward
                          : Icons.chevron_right_rounded,
                      size: isIos ? 14 : 20,
                      color: isIos
                          ? CupertinoColors.tertiaryLabel
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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

                  // 3. Modules
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isIos
                                ? CupertinoColors.activeBlue
                                : colorScheme.primary)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(isIos ? 10 : 14),
                      ),
                      child: Icon(
                        isIos
                            ? CupertinoIcons.square_grid_2x2_fill
                            : Icons.grid_view_rounded,
                        color: isIos
                            ? CupertinoColors.activeBlue
                            : colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Modules',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Budgets, recurring rules & active features',
                      style: TextStyle(
                        fontSize: 11,
                        color: isIos
                            ? CupertinoColors.secondaryLabel
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Icon(
                      isIos
                          ? CupertinoIcons.chevron_forward
                          : Icons.chevron_right_rounded,
                      size: isIos ? 14 : 20,
                      color: isIos
                          ? CupertinoColors.tertiaryLabel
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        createAdaptivePageRoute(
                          builder: (context) => const ModulesScreen(),
                        ),
                      );
                    },
                  ),

                  // 4. Sync & Backup
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isIos
                                ? CupertinoColors.systemTeal
                                : colorScheme.secondary)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(isIos ? 10 : 14),
                      ),
                      child: Icon(
                        isIos
                            ? CupertinoIcons.cloud_upload_fill
                            : Icons.cloud_sync_rounded,
                        color: isIos
                            ? CupertinoColors.systemTeal
                            : colorScheme.secondary,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Sync & Backup',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Cloud synchronization status & settings',
                      style: TextStyle(
                        fontSize: 11,
                        color: isIos
                            ? CupertinoColors.secondaryLabel
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Icon(
                      isIos
                          ? CupertinoIcons.chevron_forward
                          : Icons.chevron_right_rounded,
                      size: isIos ? 14 : 20,
                      color: isIos
                          ? CupertinoColors.tertiaryLabel
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      SyncSettingsSheet.show(context);
                    },
                  ),

                  // 5. Subscription / Plan
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isIos
                                ? CupertinoColors.systemIndigo
                                : colorScheme.primary)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(isIos ? 10 : 14),
                      ),
                      child: Icon(
                        isIos
                            ? CupertinoIcons.shield_fill
                            : Icons.workspace_premium_rounded,
                        color: isIos
                            ? CupertinoColors.systemIndigo
                            : colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Subscription',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Tier limits & upgrades',
                      style: TextStyle(
                        fontSize: 11,
                        color: isIos
                            ? CupertinoColors.secondaryLabel
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Icon(
                      isIos
                          ? CupertinoIcons.chevron_forward
                          : Icons.chevron_right_rounded,
                      size: isIos ? 14 : 20,
                      color: isIos
                          ? CupertinoColors.tertiaryLabel
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        createAdaptivePageRoute(
                          builder: (context) => const SubscriptionPaywallScreen(),
                        ),
                      );
                    },
                  ),

                  // 6. Recurring Rules (only if module enabled)
                  if (isRecurringEnabled)
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (isIos
                                  ? CupertinoColors.systemOrange
                                  : Colors.orange)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(isIos ? 10 : 14),
                        ),
                        child: Icon(
                          isIos
                              ? CupertinoIcons.repeat
                              : Icons.update_rounded,
                          color: isIos
                              ? CupertinoColors.systemOrange
                              : Colors.orange.shade800,
                          size: 20,
                        ),
                      ),
                      title: const Text(
                        'Recurring Rules',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        'Automated repeating transactions',
                        style: TextStyle(
                          fontSize: 11,
                          color: isIos
                               ? CupertinoColors.secondaryLabel
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Icon(
                        isIos
                            ? CupertinoIcons.chevron_forward
                            : Icons.chevron_right_rounded,
                        size: isIos ? 14 : 20,
                        color: isIos
                            ? CupertinoColors.tertiaryLabel
                            : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          createAdaptivePageRoute(
                            builder: (context) => const RecurringScreen(),
                          ),
                        );
                      },
                    ),

                  // 7. Export
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isIos
                                ? CupertinoColors.systemGreen
                                : colorScheme.secondary)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(isIos ? 10 : 14),
                      ),
                      child: Icon(
                        isIos
                            ? CupertinoIcons.square_arrow_up
                            : Icons.file_upload_outlined,
                        color: isIos
                            ? CupertinoColors.systemGreen
                            : colorScheme.secondary,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Export',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Export expense records, CSV & statements',
                      style: TextStyle(
                        fontSize: 11,
                        color: isIos
                            ? CupertinoColors.secondaryLabel
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Icon(
                      isIos
                          ? CupertinoIcons.chevron_forward
                          : Icons.chevron_right_rounded,
                      size: isIos ? 14 : 20,
                      color: isIos
                          ? CupertinoColors.tertiaryLabel
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        createAdaptivePageRoute(
                          builder: (context) => const ReportingHubScreen(),
                        ),
                      );
                    },
                  ),

                  // 8. Upgrade to Business Ledger
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade800.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(isIos ? 10 : 14),
                      ),
                      child: Icon(
                        isIos
                            ? CupertinoIcons.arrow_up_circle_fill
                            : Icons.upgrade_rounded,
                        color: Colors.amber.shade800,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Upgrade to Business Ledger',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.amber,
                      ),
                    ),
                    subtitle: Text(
                      'Convert to full double-entry ledger with GST & invoicing',
                      style: TextStyle(
                        fontSize: 11,
                        color: isIos
                            ? CupertinoColors.secondaryLabel
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Icon(
                      isIos
                          ? CupertinoIcons.chevron_forward
                          : Icons.chevron_right_rounded,
                      size: isIos ? 14 : 20,
                      color: isIos
                          ? CupertinoColors.tertiaryLabel
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      Navigator.pop(context);
                      SettingsScreen.showUpgradeDialog(
                        context,
                        ref,
                        activeCompany,
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
                  Text(
                    modeStrings.appTitle,
                    style: const TextStyle(
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
