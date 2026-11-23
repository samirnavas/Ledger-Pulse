import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../data/models/company_mode.dart';
import '../../data/models/subscription_tier_model.dart';
import '../theme/adaptive_theme.dart';

/// Configuration preset used by the expense tracker.
class ModulePresets {
  static const expenseTrackerDefaults = 'expense tracker defaults';
}

/// Metadata descriptor for an application module.
class ModuleMetadata {
  final AppModule module;
  final String label;
  final String description;
  final IconData materialIcon;
  final IconData cupertinoIcon;
  final Set<CompanyMode> allowedModes;
  final Set<AppModule> dependencies;
  final SubscriptionTier minTier;
  final Widget Function(BuildContext)? routeBuilder;

  const ModuleMetadata({
    required this.module,
    required this.label,
    required this.description,
    required this.materialIcon,
    required this.cupertinoIcon,
    required this.allowedModes,
    this.dependencies = const {},
    this.minTier = SubscriptionTier.silver,
    this.routeBuilder,
  });

  /// Default icon fallback (Material).
  IconData get icon => materialIcon;

  /// Returns iOS Cupertino icon on iOS/macOS and Material icon on Android/other.
  IconData adaptiveIcon(BuildContext context) {
    return AdaptiveThemeHelper.isIos(context) ? cupertinoIcon : materialIcon;
  }

  /// Builds an adaptive Icon widget.
  Widget buildAdaptiveIcon(BuildContext context, {double? size, Color? color}) {
    return Icon(adaptiveIcon(context), size: size, color: color);
  }
}

/// Modules available in the current release.
class ModuleCatalog {
  static const Map<AppModule, ModuleMetadata> _catalog = {
    AppModule.parties: ModuleMetadata(
      module: AppModule.parties,
      label: 'Parties & Contacts',
      description:
          'Customer & vendor directories, ledgers, and contact balances.',
      materialIcon: Icons.people_outline,
      cupertinoIcon: CupertinoIcons.person_2,
      allowedModes: {CompanyMode.ledger},
      dependencies: {},
      minTier: SubscriptionTier.silver,
    ),
    AppModule.vouchers: ModuleMetadata(
      module: AppModule.vouchers,
      label: 'Ledger transactions',
      description: 'Record money given and received.',
      materialIcon: Icons.receipt_long_outlined,
      cupertinoIcon: CupertinoIcons.doc_plaintext,
      allowedModes: {CompanyMode.ledger},
      dependencies: {},
      minTier: SubscriptionTier.silver,
    ),
    AppModule.dataImport: ModuleMetadata(
      module: AppModule.dataImport,
      label: 'Data Import / Export',
      description:
          'Bulk CSV, Excel, and Tally XML import and backup data export.',
      materialIcon: Icons.import_export_outlined,
      cupertinoIcon: CupertinoIcons.arrow_right_arrow_left,
      allowedModes: {CompanyMode.ledger},
      dependencies: {},
      minTier: SubscriptionTier.silver,
    ),
    AppModule.budgets: ModuleMetadata(
      module: AppModule.budgets,
      label: 'Budgets & Limits',
      description:
          'Category-wise spending limits, budget alerts, and period rollover.',
      materialIcon: Icons.pie_chart_outline,
      cupertinoIcon: CupertinoIcons.chart_pie,
      allowedModes: {CompanyMode.expenseTracker},
      dependencies: {},
      minTier: SubscriptionTier.silver,
    ),
    AppModule.recurring: ModuleMetadata(
      module: AppModule.recurring,
      label: 'Automation',
      description:
          'Automatically record repeating bills, subscriptions, and income.',
      materialIcon: Icons.update_outlined,
      cupertinoIcon: CupertinoIcons.repeat,
      allowedModes: {CompanyMode.expenseTracker},
      dependencies: {},
      minTier: SubscriptionTier.silver,
    ),
  };

  /// Returns metadata for all modules.
  static Map<AppModule, ModuleMetadata> get all => _catalog;

  /// Returns metadata for a specific module.
  static ModuleMetadata metadataFor(AppModule module) => _catalog[module]!;

  /// Returns the human-readable label for [module].
  static String labelFor(AppModule module) =>
      _catalog[module]?.label ?? module.name;

  /// Returns the human-readable description for [module].
  static String descriptionFor(AppModule module) =>
      _catalog[module]?.description ?? '';

  /// Returns all modules allowed in Ledger mode.
  static List<AppModule> get ledgerModules => _catalog.values
      .where((m) => m.allowedModes.contains(CompanyMode.ledger))
      .map((m) => m.module)
      .toList();

  /// Returns the icon for [module].
  static IconData iconFor(AppModule module) =>
      _catalog[module]?.icon ?? Icons.extension_outlined;

  /// Returns minimum subscription tier for a module.
  static SubscriptionTier minTierFor(AppModule module) =>
      _catalog[module]?.minTier ?? SubscriptionTier.silver;

  /// Returns dependencies required by [module].
  static Set<AppModule> dependenciesFor(AppModule module) =>
      _catalog[module]?.dependencies ?? const {};

  /// Checks if a module is allowed for a company mode.

  static bool isModeAllowed(CompanyMode mode, AppModule module) {
    return _catalog[module]?.allowedModes.contains(mode) ?? false;
  }

  /// Returns all modules that depend on [module].
  ///
  /// If [transitive] is false (default), returns direct dependents.
  /// If [transitive] is true, includes indirect downstream dependents.
  static Set<AppModule> dependentsOf(
    AppModule module, {
    bool transitive = false,
  }) {
    final direct = _catalog.values
        .where((m) => m.dependencies.contains(module))
        .map((m) => m.module)
        .toSet();

    if (!transitive) return direct;

    final all = Set<AppModule>.from(direct);
    for (final dep in direct) {
      all.addAll(dependentsOf(dep, transitive: true));
    }
    return all;
  }

  /// Returns the missing dependencies for [module] given an [enabled] set.
  static Set<AppModule> missingDependencies(
    AppModule module,
    Iterable<AppModule> enabled,
  ) {
    final meta = _catalog[module];
    if (meta == null) return const {};
    final enabledSet = enabled.toSet();
    return meta.dependencies.difference(enabledSet);
  }

  /// Legacy preset names are accepted for compatibility.
  static Set<AppModule> defaultsFor(CompanyMode mode, {String? preset}) {
    return mode == CompanyMode.expenseTracker
        ? {AppModule.budgets, AppModule.recurring}
        : AppModule.ledgerEssentials;
  }
}
