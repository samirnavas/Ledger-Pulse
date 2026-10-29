import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/company_mode.dart';
import '../providers/company_providers.dart';
import '../providers/module_providers.dart';

class ModulesScreen extends ConsumerWidget {
  const ModulesScreen({super.key});

  Future<void> _handleToggle({
    required BuildContext context,
    required WidgetRef ref,
    required String companyId,
    required AppModule module,
    required bool newValue,
    required Set<AppModule> enabledModules,
  }) async {
    HapticFeedback.selectionClick();
    final controller = ref.read(companyControllerProvider.notifier);

    if (newValue) {
      // Check missing dependencies
      final missing = ModuleCatalog.missingDependencies(module, enabledModules);
      if (missing.isNotEmpty) {
        final missingLabels = missing.map((m) => ModuleCatalog.labelFor(m)).join(', ');

        final shouldEnableBoth = await showAdaptiveConfirmDialog(
          context: context,
          title: 'Dependencies Required',
          message:
              '${ModuleCatalog.labelFor(module)} requires $missingLabels to function. Would you like to enable the required dependencies?',
          confirmLabel: 'Enable All',
          cancelLabel: 'Cancel',
        );

        if (shouldEnableBoth != true) return;

        try {
          for (final dep in missing) {
            await controller.setModuleEnabled(companyId, dep, true);
          }
          await controller.setModuleEnabled(companyId, module, true);
        } catch (e) {
          if (context.mounted) {
            _showErrorSnackbar(context, e.toString());
          }
        }
        return;
      }

      try {
        await controller.setModuleEnabled(companyId, module, true);
      } catch (e) {
        if (context.mounted) {
          _showErrorSnackbar(context, e.toString());
        }
      }
    } else {
      // Check active dependents
      final dependents = ModuleCatalog.dependentsOf(module);
      final activeDependents = dependents.intersection(enabledModules);
      if (activeDependents.isNotEmpty) {
        final dependentLabels = activeDependents.map((m) => ModuleCatalog.labelFor(m)).join(', ');

        await showAdaptiveInfoDialog(
          context: context,
          title: 'Cannot Disable Module',
          message:
              'The following active modules depend on ${ModuleCatalog.labelFor(module)}: $dependentLabels.\n\nPlease disable dependent modules first.',
          buttonLabel: 'OK',
        );
        return;
      }

      try {
        await controller.setModuleEnabled(companyId, module, false);
      } catch (e) {
        if (context.mounted) {
          _showErrorSnackbar(context, e.toString());
        }
      }
    }
  }

  void _showErrorSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.payableRed,
      ),
    );
  }

  Future<void> _applyPreset({
    required BuildContext context,
    required WidgetRef ref,
    required String companyId,
    required CompanyMode mode,
    required String presetName,
  }) async {
    HapticFeedback.mediumImpact();
    final defaultModules = ModuleCatalog.defaultsFor(mode, preset: presetName);
    final controller = ref.read(companyControllerProvider.notifier);

    try {
      // First enable all desired modules
      for (final mod in defaultModules) {
        await controller.setModuleEnabled(companyId, mod, true, throwOnError: false);
      }
      // Then disable any modules not in preset, sorted by dependents first
      final allAllowed = AppModule.values.where((m) => ModuleCatalog.isModeAllowed(mode, m));
      for (final mod in allAllowed) {
        if (!defaultModules.contains(mod)) {
          await controller.setModuleEnabled(companyId, mod, false, throwOnError: false);
        }
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Applied preset: $presetName'),
            backgroundColor: AppColors.receivableGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackbar(context, 'Failed to apply preset: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    final activeCompany = ref.watch(activeCompanyProvider);

    // Filter to only modules allowed by the company's mode
    final allowedModules = AppModule.values
        .where((m) => ModuleCatalog.isModeAllowed(activeCompany.mode, m))
        .toList();

    return AdaptiveScaffold(
      title: 'Company Modules & Features',
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              // 1. Company Mode & Status Header Card
              _buildHeaderCard(context, activeCompany, isIos, isDark),

              const SizedBox(height: 20),

              // 2. Preset Quick Selectors
              _buildSectionHeader(context, 'CONFIGURED PRESETS'),
              const SizedBox(height: 8),
              _buildPresetsBar(context, ref, activeCompany, isIos, isDark),

              const SizedBox(height: 24),

              // 3. Module List
              _buildSectionHeader(context, 'AVAILABLE MODULES (${allowedModules.length})'),
              const SizedBox(height: 8),
              _buildCard(
                context,
                isDark,
                isIos,
                children: [
                  for (int i = 0; i < allowedModules.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _buildModuleTile(
                      context: context,
                      ref: ref,
                      module: allowedModules[i],
                      companyId: activeCompany.id,
                      enabledModules: activeCompany.enabledModules,
                      isIos: isIos,
                      isDark: isDark,
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    BuildContext context,
    dynamic company,
    bool isIos,
    bool isDark,
  ) {
    final modeLabel = company.mode == CompanyMode.expenseTracker
        ? 'Expense Tracker Mode'
        : 'Full Double-Entry Ledger Mode';

    final modeColor = company.mode == CompanyMode.expenseTracker
        ? (isIos ? CupertinoColors.systemOrange : Colors.orange.shade700)
        : (isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary);

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: modeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              company.mode == CompanyMode.expenseTracker
                  ? (isIos ? CupertinoIcons.chart_pie_fill : Icons.pie_chart_rounded)
                  : (isIos ? CupertinoIcons.building_2_fill : Icons.business_center_rounded),
              color: modeColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  company.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  modeLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: modeColor,
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
        borderRadius: 20,
        padding: EdgeInsets.zero,
        child: content,
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(
                alpha: isDark ? 0.35 : 0.5,
              ),
        ),
      ),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: content,
    );
  }

  Widget _buildPresetsBar(
    BuildContext context,
    WidgetRef ref,
    dynamic company,
    bool isIos,
    bool isDark,
  ) {
    final isExpense = company.mode == CompanyMode.expenseTracker;
    final presets = isExpense
        ? [ModulePresets.expenseTrackerDefaults]
        : [
            ModulePresets.simpleKhata,
            ModulePresets.billingAndGst,
            ModulePresets.fullErp,
          ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: presets.map((preset) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: Icon(
                isIos ? CupertinoIcons.wand_stars : Icons.auto_fix_high_rounded,
                size: 16,
                color: isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary,
              ),
              label: Text(preset),
              shape: const StadiumBorder(),
              onPressed: () => _applyPreset(
                context: context,
                ref: ref,
                companyId: company.id,
                mode: company.mode,
                presetName: preset,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildModuleTile({
    required BuildContext context,
    required WidgetRef ref,
    required AppModule module,
    required String companyId,
    required Set<AppModule> enabledModules,
    required bool isIos,
    required bool isDark,
  }) {
    final meta = ModuleCatalog.metadataFor(module);
    final isEnabled = enabledModules.contains(module);
    final missingDeps = ModuleCatalog.missingDependencies(module, enabledModules);

    final Color iconColor = isEnabled
        ? (isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary)
        : (isDark ? Colors.grey.shade400 : Colors.grey.shade600);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          meta.adaptiveIcon(context),
          color: iconColor,
          size: 22,
        ),
      ),
      title: Text(
        meta.label,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              meta.description,
              style: TextStyle(
                fontSize: 12,
                color: isIos
                    ? (isDark ? CupertinoColors.systemGrey : CupertinoColors.secondaryLabel)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (meta.dependencies.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    isIos ? CupertinoIcons.link : Icons.link_rounded,
                    size: 12,
                    color: missingDeps.isNotEmpty
                        ? AppColors.payableRed
                        : (isIos ? CupertinoColors.systemGrey2 : Colors.grey),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      missingDeps.isNotEmpty
                          ? 'Requires: ${meta.dependencies.map((d) => ModuleCatalog.labelFor(d)).join(', ')} (Missing)'
                          : 'Requires: ${meta.dependencies.map((d) => ModuleCatalog.labelFor(d)).join(', ')}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: missingDeps.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                        color: missingDeps.isNotEmpty
                            ? AppColors.payableRed
                            : (isIos ? CupertinoColors.systemGrey2 : Colors.grey.shade600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      trailing: Switch.adaptive(
        value: isEnabled,
        activeTrackColor: isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary,
        onChanged: (val) => _handleToggle(
          context: context,
          ref: ref,
          companyId: companyId,
          module: module,
          newValue: val,
          enabledModules: enabledModules,
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
}
