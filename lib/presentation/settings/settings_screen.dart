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
                          color: (isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isIos
                              ? CupertinoIcons.building_2_fill
                              : Icons.corporate_fare_rounded,
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
                        backgroundColor: (isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary).withValues(alpha: 0.15),
                        child: Text(
                          profile.name.isNotEmpty
                              ? profile.name[0].toUpperCase()
                              : 'U',
                          style: TextStyle(
                            color: isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary,
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
                        isIos ? CupertinoIcons.chevron_forward : Icons.chevron_right_rounded,
                        size: isIos ? 14 : 20,
                        color: isIos ? CupertinoColors.tertiaryLabel : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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
