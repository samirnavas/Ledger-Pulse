import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/constants/strings.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../data/models/company_mode.dart';
import '../integrations/ecommerce_sync_screen.dart';
import '../integrations/third_party_import_screen.dart';
import '../inventory/inventory_screen.dart';
import '../inventory/manufacturing_journal_screen.dart';
import '../payments/cts2010_cheque_preview_screen.dart';
import '../payroll/employee_list_screen.dart';
import '../providers/company_providers.dart';
import '../providers/module_providers.dart';
import '../reports/desktop_custom_report_studio.dart';
import '../reports/receivables_payables_screen.dart';
import '../reports/reporting_hub_screen.dart';
import '../settings/settings_screen.dart';
import 'company_switcher_sheet.dart';
import 'sync_settings_sheet.dart';

class DashboardSidebarDrawer extends ConsumerWidget {
  final VoidCallback onOpenErpModules;
  final VoidCallback onOpenBiHub;

  const DashboardSidebarDrawer({
    super.key,
    required this.onOpenErpModules,
    required this.onOpenBiHub,
  });

  static Widget? _routeForModule(AppModule module) {
    switch (module) {
      case AppModule.vouchers:
        return const ReceivablesPayablesScreen();
      case AppModule.payroll:
        return const EmployeeListScreen();
      case AppModule.manufacturing:
        return const ManufacturingJournalScreen();
      case AppModule.dataImport:
        return const ThirdPartyImportScreen();
      case AppModule.ecommerceSync:
        return const EcommerceSyncScreen();
      case AppModule.chequePrinting:
        return const Cts2010ChequePreviewScreen();
      case AppModule.advancedReports:
        return const ReportingHubScreen();
      case AppModule.sqlStudio:
        return const DesktopCustomReportStudio();
      case AppModule.inventory:
        return const InventoryScreen();
      case AppModule.gst:
        return const ReportingHubScreen();
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final activeCompany = ref.watch(activeCompanyProvider);
    final isExpense = activeCompany.mode == CompanyMode.expenseTracker;
    final isAdvancedReportsEnabled = ref.watch(moduleEnabledProvider(AppModule.advancedReports));
    final enabledCatalogModules = ModuleCatalog.all.values.where((meta) {
      if (meta.module == AppModule.parties) return false;
      return ref.watch(moduleEnabledProvider(meta.module));
    }).toList();

    final drawerBg = isIos
        ? (isDark ? const Color(0xEE0F172A) : const Color(0xEEF8FAFC))
        : colorScheme.surfaceContainerLow;

    /* Temporarily commented out profile badge definition
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
                  color: isIos
                      ? CupertinoColors.secondaryLabel
                      : colorScheme.onSurfaceVariant,
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
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isIos
                    ? (subscription.isExpired
                          ? CupertinoIcons.exclamationmark_triangle_fill
                          : CupertinoIcons.checkmark_seal_fill)
                    : (subscription.isExpired
                          ? Icons.warning_rounded
                          : Icons.verified_rounded),
                size: 12,
                color: subscription.isExpired
                    ? AppColors.payableRed
                    : AppColors.receivableGreen,
              ),
              const SizedBox(width: 4),
              Text(
                subscription.tier.displayName,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: subscription.isExpired
                      ? AppColors.payableRed
                      : AppColors.receivableGreen,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    */

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
                          ? const Color(0x881E293B)
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              (isIos
                                      ? CupertinoColors.activeBlue
                                      : colorScheme.primary)
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isIos
                              ? CupertinoIcons.building_2_fill
                              : Icons.corporate_fare_rounded,
                          size: 24,
                          color: isIos
                              ? CupertinoColors.activeBlue
                              : colorScheme.primary,
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
                  /* Temporarily commented out profile badge
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
                  */
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
                        color:
                            (isIos
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
                    title: const Text(
                      'Switch Company',
                      style: TextStyle(
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

                  // 2. Sync & Backup Center
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            (isIos
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
                      'Sync & Backup Center',
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

                  // 3. Export (Visible in Expense Mode)
                  if (isExpense)
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

                  // Ledger-only Navigation Items
                  if (!isExpense) ...[
                    // 3. Business Intelligence & Cash Flow (gated by advancedReports)
                    if (isAdvancedReportsEnabled)
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                (isIos
                                        ? CupertinoColors.activeBlue
                                        : colorScheme.primary)
                                    .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(isIos ? 10 : 14),
                          ),
                          child: Icon(
                            isIos
                                ? CupertinoIcons.chart_bar_alt_fill
                                : Icons.insights_rounded,
                            color: isIos
                                ? CupertinoColors.activeBlue
                                : colorScheme.primary,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Cash Flow & Intelligence',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          'Telemetry, margins & working capital breakdown',
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
                          onOpenBiHub();
                        },
                      ),

                    // 4. Reports & Analytics Hub (gated by advancedReports)
                    if (isAdvancedReportsEnabled)
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                (isIos
                                        ? CupertinoColors.systemPurple
                                        : colorScheme.tertiary)
                                    .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(isIos ? 10 : 14),
                          ),
                          child: Icon(
                            isIos
                                ? CupertinoIcons.chart_pie_fill
                                : Icons.analytics_rounded,
                            color: isIos
                                ? CupertinoColors.systemPurple
                                : colorScheme.tertiary,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Reports & Analytics Hub',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          'Daybook, P&L, GST & Party analytics',
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

                    // 5. Enabled ERP Modules from catalog
                    ...enabledCatalogModules.map((meta) {
                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (isIos
                                    ? CupertinoColors.activeBlue
                                    : colorScheme.primary)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(isIos ? 10 : 14),
                          ),
                          child: meta.buildAdaptiveIcon(
                            context,
                            size: 20,
                            color: isIos
                                ? CupertinoColors.activeBlue
                                : colorScheme.primary,
                          ),
                        ),
                        title: Text(
                          meta.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          meta.description,
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
                          final route = _routeForModule(meta.module);
                          if (route != null) {
                            Navigator.of(context).push(
                              createAdaptivePageRoute(builder: (_) => route),
                            );
                          }
                        },
                      );
                    }),

                    // 6. All ERP Modules & Paywall
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              (isIos
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
                        'ERP Modules & Licensing',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        'Payroll, Importers, Cheque printing & Paywall',
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
                            ? CupertinoColors.activeBlue
                            : colorScheme.primary,
                      ),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                        onOpenErpModules();
                      },
                    ),
                  ],

                  // 5. Settings & Preferences
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            (isIos
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
                      'Settings & Preferences',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Color theme, profile, cloud sync & system settings',
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
