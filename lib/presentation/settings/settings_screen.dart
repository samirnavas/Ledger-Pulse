import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/strings.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/sync_model.dart';
import '../home/company_switcher_sheet.dart';
import '../home/sync_settings_sheet.dart';
import '../profile/profile_screen.dart';
import '../providers/company_providers.dart';
import '../providers/profile_provider.dart';
import '../providers/sync_providers.dart';
import '../providers/theme_provider.dart';
import '../reports/audit_log_screen.dart';
import '../reports/reporting_hub_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final themeMode = ref.watch(appThemeModeProvider);
    final activeCompany = ref.watch(activeCompanyProvider);
    final profile = ref.watch(userProfileProvider);
    final syncStatus = ref.watch(syncControllerProvider);
    final isSyncing = syncStatus == SyncStatus.syncing;

    return AdaptiveScaffold(
      title: 'Settings & Preferences',
      body: Align(
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

                const SizedBox(height: 24),

                // 2. ACTIVE COMPANY & PROFILE
                _buildSectionHeader(context, 'ACTIVE COMPANY & PROFILE'),
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
                          color: Colors.indigo.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isIos
                              ? CupertinoIcons.building_2_fill
                              : Icons.business_rounded,
                          color: Colors.indigo,
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
                        activeCompany.gstin?.isNotEmpty == true
                            ? 'GSTIN: ${activeCompany.gstin}'
                            : 'Personal / Sole Trader',
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
                        backgroundColor:
                            AppColors.primaryBlue.withValues(alpha: 0.2),
                        child: Text(
                          profile.name.isNotEmpty
                              ? profile.name[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      title: Text(
                        profile.name.isNotEmpty ? profile.name : 'Owner Profile',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        profile.phoneNumber,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                      trailing: Icon(
                        isIos ? CupertinoIcons.chevron_forward : Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Colors.grey,
                      ),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).push(
                          createAdaptivePageRoute(
                            builder: (ctx) => const ProfileScreen(),
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
                          color: AppColors.primaryBlue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isIos
                              ? CupertinoIcons.cloud_upload_fill
                              : Icons.sync_rounded,
                          color: AppColors.primaryBlue,
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
                        isIos ? CupertinoIcons.chevron_forward : Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Colors.grey,
                      ),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        SyncSettingsSheet.show(context);
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isIos
                              ? CupertinoIcons.doc_text_search
                              : Icons.history_edu_rounded,
                          color: Colors.purple,
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
                      subtitle: const Text(
                        'Immutable activity ledger and transaction trails',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: Icon(
                        isIos ? CupertinoIcons.chevron_forward : Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Colors.grey,
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
                ),

                const SizedBox(height: 24),

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
                          color: AppColors.receivableGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isIos
                              ? CupertinoIcons.chart_pie_fill
                              : Icons.analytics_rounded,
                          color: AppColors.receivableGreen,
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
                      subtitle: const Text(
                        '36 comprehensive reports, Daybook, P&L & GSTR JSON',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: Icon(
                        isIos ? CupertinoIcons.chevron_forward : Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Colors.grey,
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

                const SizedBox(height: 24),

                // 5. APP INFO & BUILD
                _buildSectionHeader(context, 'ABOUT LEDGER PULSE'),
                const SizedBox(height: 8),
                _buildCard(
                  context,
                  isDark,
                  isIos,
                  children: [
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/icons/app_icon.png',
                          width: 36,
                          height: 36,
                          errorBuilder: (context, error, stackTrace) =>
                              Icon(
                            isIos
                                ? CupertinoIcons.money_dollar_circle_fill
                                : Icons.account_balance_wallet_rounded,
                            color: AppColors.primaryBlue,
                            size: 32,
                          ),
                        ),
                      ),
                      title: const Text(
                        AppStrings.appName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: const Text(
                        'Version 1.0.0 (Build 2026.09)',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'PRO',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
    );
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
        child: Column(
          children: children,
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
    final cardBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                currentMode == ThemeMode.dark
                    ? (isIos ? CupertinoIcons.moon_fill : Icons.dark_mode_rounded)
                    : (currentMode == ThemeMode.light
                        ? (isIos ? CupertinoIcons.sun_max_fill : Icons.light_mode_rounded)
                        : (isIos ? CupertinoIcons.device_phone_portrait : Icons.brightness_auto_rounded)),
                color: AppColors.primaryBlue,
                size: 20,
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 3-Segment Theme Selector: Light, Dark, Auto
        Row(
          children: [
            _buildThemeOptionTile(
              context: context,
              ref: ref,
              mode: ThemeMode.light,
              label: 'Light',
              icon: isIos ? CupertinoIcons.sun_max_fill : Icons.light_mode_rounded,
              isSelected: currentMode == ThemeMode.light,
              isDark: isDark,
              isIos: isIos,
            ),
            const SizedBox(width: 8),
            _buildThemeOptionTile(
              context: context,
              ref: ref,
              mode: ThemeMode.dark,
              label: 'Dark',
              icon: isIos ? CupertinoIcons.moon_fill : Icons.dark_mode_rounded,
              isSelected: currentMode == ThemeMode.dark,
              isDark: isDark,
              isIos: isIos,
            ),
            const SizedBox(width: 8),
            _buildThemeOptionTile(
              context: context,
              ref: ref,
              mode: ThemeMode.system,
              label: 'Auto / System',
              icon: isIos ? CupertinoIcons.device_phone_portrait : Icons.brightness_auto_rounded,
              isSelected: currentMode == ThemeMode.system,
              isDark: isDark,
              isIos: isIos,
            ),
          ],
        ),
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

  Widget _buildThemeOptionTile({
    required BuildContext context,
    required WidgetRef ref,
    required ThemeMode mode,
    required String label,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required bool isIos,
  }) {
    final theme = Theme.of(context);
    final activeColor = isIos ? CupertinoColors.activeBlue : theme.colorScheme.primary;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          ref.read(appThemeModeProvider.notifier).setThemeMode(mode);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: isDark ? 0.25 : 0.15)
                : (isDark
                    ? const Color(0xFF1E293B).withValues(alpha: 0.5)
                    : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(isIos ? 14 : 20),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : theme.colorScheme.outlineVariant.withValues(
                      alpha: isDark ? 0.2 : 0.35,
                    ),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? activeColor
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected
                      ? activeColor
                      : theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
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
