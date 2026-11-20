import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/constants/colors.dart';
import '../../core/services/widget_entry_service.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_page_entrance.dart';
import '../../core/widgets/adaptive_controls.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/sync_model.dart';
import '../auth/profile_onboarding_screen.dart';
import '../expense/accounts_screen.dart';
import '../home/company_switcher_sheet.dart';
import '../home/sync_settings_sheet.dart';
import '../profile/profile_screen.dart';
import '../providers/auth_providers.dart';
import '../providers/company_providers.dart';
import '../providers/profile_provider.dart';
import '../../data/models/company_model.dart';
import '../payments/cts2010_cheque_preview_screen.dart';
import '../providers/sync_providers.dart';
import '../providers/theme_provider.dart';
import '../providers/widget_sync_provider.dart';
import '../reports/audit_log_screen.dart';
import '../reports/reporting_hub_screen.dart';
import 'about_screen.dart';
import 'help_screen.dart';
import 'modules_screen.dart';

class SettingsScreen extends ConsumerWidget {

  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final themeMode = ref.watch(appThemeModeProvider);
    final activeCompany = ref.watch(activeCompanyProvider);
    final isExpense = activeCompany.mode == CompanyMode.expenseTracker;
    final profile = ref.watch(userProfileProvider);
    final profileName = profile.name.trim();
    final profileSubtitle = [
      profile.phoneNumber.trim(),
      profile.email.trim(),
    ].firstWhere(
      (value) => value.isNotEmpty,
      orElse: () => isExpense
          ? 'Personal details, wallets and categories'
          : 'Personal details',
    );
    final syncStatus = ref.watch(syncControllerProvider);
    final isSyncing = syncStatus == SyncStatus.syncing;
    final showWidgetSettings = !kIsWeb && Platform.isAndroid;
    final widgetKeypad = showWidgetSettings
        ? ref.watch(widgetKeypadEnabledProvider).value
        : null;

    return AdaptiveScaffold(
      title: 'Settings & Preferences',
      body: AdaptivePageEntrance(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
                // 1. APPEARANCE & THEME
                _buildSectionHeader(context, 'APPEARANCE & THEME'),
                const SizedBox(height: 8),
                _buildThemeSelectorCard(context, ref, themeMode, isDark, isIos),

                if (showWidgetSettings) ...[
                  const SizedBox(height: 24),
                  _buildSectionHeader(context, 'HOME SCREEN WIDGET'),
                  const SizedBox(height: 8),
                  _buildCard(
                    context,
                    isDark,
                    isIos,
                    children: [
                      SwitchListTile(
                        title: const Text('Add from home screen'),
                        subtitle: const Text(
                          'Show a keypad on the Expense widget. Turn off to open Quick Add in the app.',
                        ),
                        value: widgetKeypad ?? false,
                        onChanged: widgetKeypad == null ? null : (enabled) async {
                          try {
                            await HomeWidget.saveWidgetData(
                              WidgetEntryService.enabledKey,
                              enabled,
                            );
                            ref.invalidate(widgetKeypadEnabledProvider);
                            await WidgetEntryService.refresh();
                          } catch (_) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Could not update widget settings')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),

                // 2. ACTIVE WORKSPACE & PROFILE
                _buildSectionHeader(
                  context,
                  isExpense
                      ? 'ACTIVE WORKSPACE & PROFILE'
                      : 'ACTIVE COMPANY & PROFILE',
                ),
                const SizedBox(height: 8),
                _buildCard(
                  context,
                  isDark,
                  isIos,
                  children: [
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isExpense
                              ? (isIos
                                  ? CupertinoIcons.creditcard
                                  : Icons.account_balance_wallet_outlined)
                              : (isIos
                                  ? CupertinoIcons.building_2_fill
                                  : Icons.corporate_fare_rounded),
                          color: isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        activeCompany.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        isExpense
                            ? 'Personal Expense Tracker'
                            : (activeCompany.gstin?.isNotEmpty == true
                                ? 'GSTIN: ${activeCompany.gstin}'
                                : 'Personal / Sole Trader'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                      trailing: TextButton.icon(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          CompanySwitcherSheet.show(context);
                        },
                        icon: Icon(
                          isIos ? CupertinoIcons.arrow_2_circlepath : Icons.swap_horiz_rounded,
                          size: 18,
                        ),
                        label: const Text('Switch'),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: (isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary).withValues(alpha: 0.15),
                        child: Text(
                          profileName.isNotEmpty
                              ? profileName.characters.first.toUpperCase()
                              : 'U',
                          style: TextStyle(
                            color: isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      title: Text(
                        profileName.isNotEmpty ? profileName : 'My Profile',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        profileSubtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                      trailing: Icon(
                        isIos ? CupertinoIcons.chevron_forward : Icons.chevron_right_rounded,
                        size: isIos ? 14 : 20,
                        color: isIos ? CupertinoColors.tertiaryLabel : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).push(
                          createAdaptivePageRoute(
                            builder: (_) => isExpense
                                ? const ExpenseAccountsScreen(isStandalone: true)
                                : const ProfileScreen(isStandalone: true),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (isIos ? CupertinoColors.systemIndigo : Theme.of(context).colorScheme.tertiary).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isIos
                              ? CupertinoIcons.square_grid_2x2_fill
                              : Icons.extension_rounded,
                          color: isIos ? CupertinoColors.systemIndigo : Theme.of(context).colorScheme.tertiary,
                          size: 22,
                        ),
                      ),
                      title: const Text(
                        'Company Modules & Features',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        'Configure ${activeCompany.enabledModules.length} enabled modules & presets',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                      trailing: Icon(
                        isIos ? CupertinoIcons.chevron_forward : Icons.chevron_right_rounded,
                        size: isIos ? 14 : 20,
                        color: isIos ? CupertinoColors.tertiaryLabel : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).push(
                          createAdaptivePageRoute(
                            builder: (ctx) => const ModulesScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),


                const SizedBox(height: 24),

                // 3. CLOUD SYNC & BACKUP
                _buildSectionHeader(context, 'CLOUD SYNC & DATA INTEGRITY'),
                const SizedBox(height: 8),
                _buildCard(
                  context,
                  isDark,
                  isIos,
                  children: [
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (isIos ? CupertinoColors.systemTeal : Theme.of(context).colorScheme.secondary).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isIos
                              ? CupertinoIcons.cloud_upload_fill
                              : Icons.cloud_sync_rounded,
                          color: isIos ? CupertinoColors.systemTeal : Theme.of(context).colorScheme.secondary,
                          size: 22,
                        ),
                      ),
                      title: const Text(
                        'Cloud Sync & Backup Hub',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        isSyncing
                            ? 'Sync in progress...'
                            : 'Offline-first database with Supabase cloud replication',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                      trailing: Icon(
                        isIos ? CupertinoIcons.chevron_forward : Icons.chevron_right_rounded,
                        size: isIos ? 14 : 20,
                        color: isIos ? CupertinoColors.tertiaryLabel : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        SyncSettingsSheet.show(context);
                      },
                    ),
                    if (!isExpense) ...[
                      const Divider(height: 1),
                      ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (isIos ? CupertinoColors.systemPurple : Theme.of(context).colorScheme.tertiary).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isIos
                                ? CupertinoIcons.doc_text_search
                                : Icons.manage_search_rounded,
                            color: isIos ? CupertinoColors.systemPurple : Theme.of(context).colorScheme.tertiary,
                            size: 22,
                          ),
                        ),
                        title: const Text(
                          'Security & Audit Logs',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          'Immutable activity ledger and transaction trails',
                          style: TextStyle(
                            fontSize: 12,
                            color: isIos ? CupertinoColors.secondaryLabel : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Icon(
                          isIos ? CupertinoIcons.chevron_forward : Icons.chevron_right_rounded,
                          size: isIos ? 14 : 20,
                          color: isIos ? CupertinoColors.tertiaryLabel : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).push(
                            createAdaptivePageRoute(
                              builder: (ctx) => const AuditLogScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 24),

                if (!isExpense) ...[
                  // 4. REPORTS & EXPORTS
                  _buildSectionHeader(context, 'REPORTING & COMPLIANCE'),
                  const SizedBox(height: 8),
                  _buildCard(
                    context,
                    isDark,
                    isIos,
                    children: [
                      ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (isIos ? CupertinoColors.systemGreen : Theme.of(context).colorScheme.secondary).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isIos
                                ? CupertinoIcons.chart_pie_fill
                                : Icons.analytics_rounded,
                            color: isIos ? CupertinoColors.systemGreen : Theme.of(context).colorScheme.secondary,
                            size: 22,
                          ),
                        ),
                        title: const Text(
                          'Master Reporting Hub',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '36 comprehensive reports, Daybook, P&L & GSTR JSON',
                          style: TextStyle(
                            fontSize: 12,
                            color: isIos ? CupertinoColors.secondaryLabel : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Icon(
                          isIos ? CupertinoIcons.chevron_forward : Icons.chevron_right_rounded,
                          size: isIos ? 14 : 20,
                          color: isIos ? CupertinoColors.tertiaryLabel : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).push(
                            createAdaptivePageRoute(
                              builder: (ctx) => const ReportingHubScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],

                if (!isExpense) ...[
                  const SizedBox(height: 24),
                  _buildSectionHeader(context, 'INVOICING, BRANDING & STATUTORY'),
                  const SizedBox(height: 8),
                  _buildCard(
                    context,
                    isDark,
                    isIos,
                    children: [
                      ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isIos ? CupertinoIcons.printer_fill : Icons.print_rounded,
                            color: isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary,
                            size: 22,
                          ),
                        ),
                        title: const Text(
                          'CTS-2010 Cheque Printing',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          'Bank cheque layout calibration, payee formatting & CTS alignment',
                          style: TextStyle(
                            fontSize: 12,
                            color: isIos ? CupertinoColors.secondaryLabel : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Icon(
                          isIos ? CupertinoIcons.chevron_forward : Icons.chevron_right_rounded,
                          size: isIos ? 14 : 20,
                          color: isIos ? CupertinoColors.tertiaryLabel : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).push(
                            createAdaptivePageRoute(
                              builder: (ctx) => const Cts2010ChequePreviewScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (isIos ? CupertinoColors.systemIndigo : Theme.of(context).colorScheme.tertiary).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isIos ? CupertinoIcons.signature : Icons.draw_rounded,
                            color: isIos ? CupertinoColors.systemIndigo : Theme.of(context).colorScheme.tertiary,
                            size: 22,
                          ),
                        ),
                        title: const Text(
                          'Signature & Company Branding',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          'Business logo, authorized signatory signature & invoice headers',
                          style: TextStyle(
                            fontSize: 12,
                            color: isIos ? CupertinoColors.secondaryLabel : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Icon(
                          isIos ? CupertinoIcons.chevron_forward : Icons.chevron_right_rounded,
                          size: isIos ? 14 : 20,
                          color: isIos ? CupertinoColors.tertiaryLabel : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).push(
                            createAdaptivePageRoute(
                              builder: (ctx) => const ProfileScreen(isStandalone: true),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (isIos ? CupertinoColors.systemGreen : Theme.of(context).colorScheme.secondary).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isIos ? CupertinoIcons.doc_checkmark_fill : Icons.verified_rounded,
                            color: isIos ? CupertinoColors.systemGreen : Theme.of(context).colorScheme.secondary,
                            size: 22,
                          ),
                        ),
                        title: const Text(
                          'e-Invoice & GST Compliance',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          'IRP portal connection, e-Way bills & 2026 GSTN regulations',
                          style: TextStyle(
                            fontSize: 12,
                            color: isIos ? CupertinoColors.secondaryLabel : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Icon(
                          isIos ? CupertinoIcons.chevron_forward : Icons.chevron_right_rounded,
                          size: isIos ? 14 : 20,
                          color: isIos ? CupertinoColors.tertiaryLabel : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).push(
                            createAdaptivePageRoute(
                              builder: (ctx) => const ReportingHubScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 24),

                _buildSectionHeader(context, 'HELP & ABOUT'),
                const SizedBox(height: 8),
                _buildCard(
                  context,
                  isDark,
                  isIos,
                  children: [
                    _buildInfoLink(
                      context,
                      isIos: isIos,
                      icon: isIos
                          ? CupertinoIcons.question_circle
                          : Icons.help_outline_rounded,
                      title: 'Help',
                      subtitle: 'Getting started and common questions',
                      page: HelpScreen(isExpense: isExpense),
                    ),
                    const Divider(height: 1),
                    _buildInfoLink(
                      context,
                      isIos: isIos,
                      icon: isIos
                          ? CupertinoIcons.info_circle
                          : Icons.info_outline_rounded,
                      title: 'About',
                      subtitle: 'App version and open-source licenses',
                      page: const AboutScreen(),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoLink(
    BuildContext context, {
    required bool isIos,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget page,
  }) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: colors.onSecondaryContainer, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: Icon(
        isIos ? CupertinoIcons.chevron_forward : Icons.chevron_right_rounded,
        color: colors.onSurfaceVariant,
      ),
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          createAdaptivePageRoute(builder: (_) => page),
        );
      },
    );
  }

  static Future<void> showCreateBusinessLedgerDialog(
    BuildContext context,
    WidgetRef ref,
    Company company,
  ) async {
    final isIos = AdaptiveThemeHelper.isIos(context);

    final result = await showAdaptiveDialog<bool>(
      context: context,
      builder: (ctx) {
        const content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LedgerPulse enforces immutable workspace types:\n\n'
              '• A Personal Expense workspace cannot be converted into a Business Ledger.\n'
              '• Your existing expense wallets, categories, and transactions remain completely intact and untouched in this workspace.\n'
              '• To use double-entry bookkeeping, GST invoicing, parties, and inventory, create a separate Business Ledger workspace for your account.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        );

        if (isIos) {
          return CupertinoAlertDialog(
            title: const Text('Business Ledger Workspace'),
            content: const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: content,
            ),
            actions: [
              CupertinoDialogAction(
                key: const Key('cancel_upgrade_button'),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                key: const Key('confirm_upgrade_button'),
                isDefaultAction: true,
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Create Ledger Workspace'),
              ),
            ],
          );
        }

        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.business_rounded, color: AppColors.primaryBlue),
              SizedBox(width: 8),
              Text('Business Ledger Workspace'),
            ],
          ),
          content: content,
          actions: [
            TextButton(
              key: const Key('cancel_upgrade_button'),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm_upgrade_button'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create Ledger Workspace'),
            ),
          ],
        );
      },
    );

    if (result == true && context.mounted) {
      final authState = ref.read(authControllerProvider);
      final userId = authState.userId ?? ref.read(authRepositoryProvider).currentUserId;
      if (userId != null && userId.isNotEmpty) {
        Navigator.of(context).push(
          createAdaptivePageRoute(
            builder: (_) => ProfileOnboardingScreen(userId: userId),
          ),
        );
      } else {
        CompanySwitcherSheet.showAddCompanyDialog(context, ref);
      }
    }
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    bool isDark,
    bool isIos, {
    required List<Widget> children,
  }) {
    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 20,
        padding: EdgeInsets.zero,
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: children),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(
                alpha: isDark ? 0.35 : 0.5,
              ),
        ),
      ),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          children: children,
        ),
      ),
    );
  }

  Widget _buildThemeSelectorCard(
    BuildContext context,
    WidgetRef ref,
    ThemeMode currentMode,
    bool isDark,
    bool isIos,
  ) {
    final dynamicColorEnabled = ref.watch(dynamicColorEnabledProvider);
    final cardBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isIos
                    ? CupertinoColors.activeBlue.withValues(alpha: 0.15)
                    : Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                currentMode == ThemeMode.dark
                    ? (isIos ? CupertinoIcons.moon_fill : Icons.dark_mode_rounded)
                    : (currentMode == ThemeMode.light
                        ? (isIos ? CupertinoIcons.sun_max_fill : Icons.light_mode_rounded)
                        : (isIos ? CupertinoIcons.device_phone_portrait : Icons.brightness_auto_rounded)),
                color: isIos
                    ? CupertinoColors.activeBlue
                    : Theme.of(context).colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Color Theme',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    _getThemeDescription(currentMode),
                    style: TextStyle(
                      fontSize: 12,
                      color: isIos
                          ? (isDark ? CupertinoColors.systemGrey : CupertinoColors.secondaryLabel)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (!isIos) ...[
          AdaptiveSwitch(
            key: const Key('dynamic_color_switch'),
            label: 'Dynamic colors',
            subtitle: dynamicColorEnabled
                ? 'Use system colors when available'
                : 'Use the default app colors',
            value: dynamicColorEnabled,
            onChanged: (enabled) => ref.read(dynamicColorEnabledProvider.notifier).setEnabled(enabled),
          ),
          const SizedBox(height: 16),
        ],
        // iOS: Native Cupertino Sliding Segmented Control
        // Android / Material: M3 Expressive Morphing Button Group
        if (isIos)
          _buildIosSegmentedControl(context, ref, currentMode, isDark)
        else
          _buildM3ExpressiveMorphingButtonGroup(context, ref, currentMode, isDark),
      ],
    );

    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 20,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: cardBody,
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(
                alpha: isDark ? 0.35 : 0.5,
              ),
        ),
      ),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: cardBody,
      ),
    );
  }

  Widget _buildIosSegmentedControl(
    BuildContext context,
    WidgetRef ref,
    ThemeMode currentMode,
    bool isDark,
  ) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<ThemeMode>(
        groupValue: currentMode,
        backgroundColor: isDark
            ? CupertinoColors.systemGrey6.darkColor
            : CupertinoColors.systemGrey5,
        thumbColor: isDark
            ? const Color(0xFF334155)
            : CupertinoColors.white,
        children: {
          ThemeMode.light: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.sun_max_fill,
                  size: 16,
                  color: currentMode == ThemeMode.light
                      ? (isDark ? CupertinoColors.white : CupertinoColors.activeBlue)
                      : CupertinoColors.secondaryLabel,
                ),
                const SizedBox(width: 6),
                Text(
                  'Light',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: currentMode == ThemeMode.light
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: currentMode == ThemeMode.light
                        ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                        : CupertinoColors.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
          ThemeMode.dark: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.moon_fill,
                  size: 16,
                  color: currentMode == ThemeMode.dark
                      ? (isDark ? CupertinoColors.white : CupertinoColors.activeBlue)
                      : CupertinoColors.secondaryLabel,
                ),
                const SizedBox(width: 6),
                Text(
                  'Dark',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: currentMode == ThemeMode.dark
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: currentMode == ThemeMode.dark
                        ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                        : CupertinoColors.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
          ThemeMode.system: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.device_phone_portrait,
                  size: 16,
                  color: currentMode == ThemeMode.system
                      ? (isDark ? CupertinoColors.white : CupertinoColors.activeBlue)
                      : CupertinoColors.secondaryLabel,
                ),
                const SizedBox(width: 6),
                Text(
                  'System',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: currentMode == ThemeMode.system
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: currentMode == ThemeMode.system
                        ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                        : CupertinoColors.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
        },
        onValueChanged: (val) {
          if (val != null) {
            HapticFeedback.selectionClick();
            ref.read(appThemeModeProvider.notifier).setThemeMode(val);
          }
        },
      ),
    );
  }

  Widget _buildM3ExpressiveMorphingButtonGroup(
    BuildContext context,
    WidgetRef ref,
    ThemeMode currentMode,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final options = [
      (
        mode: ThemeMode.light,
        label: 'Light',
        selectedIcon: Icons.light_mode_rounded,
        unselectedIcon: Icons.light_mode_outlined,
      ),
      (
        mode: ThemeMode.dark,
        label: 'Dark',
        selectedIcon: Icons.dark_mode_rounded,
        unselectedIcon: Icons.dark_mode_outlined,
      ),
      (
        mode: ThemeMode.system,
        label: 'Auto',
        selectedIcon: Icons.brightness_auto_rounded,
        unselectedIcon: Icons.brightness_auto_outlined,
      ),
    ];

    final selectedIndex = options.indexWhere((opt) => opt.mode == currentMode);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Row(
        children: List.generate(options.length, (index) {
          final opt = options[index];
          final isSelected = index == selectedIndex;
          final borderRadius = _getM3ExpressiveCornerRadius(
            index,
            options.length,
            selectedIndex,
          );

          // In M3 Expressive: Selected button has high-emphasis solid fill; unselected has soft tonal container
          final containerBg = isSelected
              ? (isDark ? scheme.primary : scheme.onSurface)
              : (isDark
                  ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
                  : scheme.secondaryContainer.withValues(alpha: 0.7));

          final fgColor = isSelected
              ? (isDark ? scheme.onPrimary : scheme.surface)
              : (isDark ? scheme.onSurface : scheme.onSecondaryContainer);

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(appThemeModeProvider.notifier).setThemeMode(opt.mode);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  height: 48,
                  decoration: BoxDecoration(
                    color: containerBg,
                    borderRadius: borderRadius,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: scheme.shadow.withValues(alpha: 0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedScale(
                        scale: isSelected ? 1.15 : 1.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutBack,
                        child: Icon(
                          isSelected ? opt.selectedIcon : opt.unselectedIcon,
                          size: 18,
                          color: fgColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        style: TextStyle(
                          fontFamily: theme.textTheme.labelLarge?.fontFamily,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          letterSpacing: isSelected ? 0.1 : 0,
                          color: fgColor,
                        ),
                        child: Text(
                          opt.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  BorderRadius _getM3ExpressiveCornerRadius(int index, int total, int selectedIndex) {
    const double fullRadius = 9999.0;
    const double innerRadius = 4.0;
    const double neighborRadius = 8.0;

    // 1. Selected item morphs into a complete standalone pill (all 4 corners rounded)
    if (index == selectedIndex) {
      return BorderRadius.circular(fullRadius);
    }

    // 2. Determine left edge radius:
    final bool isFirstInGroup = (index == 0);
    final bool isLeftNeighborSelected = (selectedIndex == index - 1);
    final double leftRadius = isFirstInGroup
        ? fullRadius
        : (isLeftNeighborSelected ? neighborRadius : innerRadius);

    // 3. Determine right edge radius:
    final bool isLastInGroup = (index == total - 1);
    final bool isRightNeighborSelected = (selectedIndex == index + 1);
    final double rightRadius = isLastInGroup
        ? fullRadius
        : (isRightNeighborSelected ? neighborRadius : innerRadius);

    return BorderRadius.only(
      topLeft: Radius.circular(leftRadius),
      bottomLeft: Radius.circular(leftRadius),
      topRight: Radius.circular(rightRadius),
      bottomRight: Radius.circular(rightRadius),
    );
  }

  String _getThemeDescription(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Daylight light theme always active';
      case ThemeMode.dark:
        return 'Midnight OLED dark theme always active';
      case ThemeMode.system:
        return 'Dynamically follows device system settings';
    }
  }
}
