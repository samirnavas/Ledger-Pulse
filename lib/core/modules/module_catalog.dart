import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../data/models/company_mode.dart';
import '../../data/models/subscription_tier_model.dart';
import '../theme/adaptive_theme.dart';

/// Predefined presets for module bundles.
class ModulePresets {
  static const simpleKhata = 'Simple Khata';
  static const billingAndGst = 'Billing & GST';
  static const fullErp = 'Full ERP';
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

/// Central registry and catalog of all application modules with their rules,
/// dependencies, subscription tiers, and preset configurations.
class ModuleCatalog {
  static const Map<AppModule, ModuleMetadata> _catalog = {
    AppModule.parties: ModuleMetadata(
      module: AppModule.parties,
      label: 'Parties & Contacts',
      description: 'Customer & vendor directories, ledgers, and contact balances.',
      materialIcon: Icons.people_outline,
      cupertinoIcon: CupertinoIcons.person_2,
      allowedModes: {CompanyMode.ledger},
      dependencies: {},
      minTier: SubscriptionTier.silver,
    ),
    AppModule.vouchers: ModuleMetadata(
      module: AppModule.vouchers,
      label: 'Vouchers & Transactions',
      description: 'Sales, purchases, payments, receipts, and journal entries.',
      materialIcon: Icons.receipt_long_outlined,
      cupertinoIcon: CupertinoIcons.doc_plaintext,
      allowedModes: {CompanyMode.ledger},
      dependencies: {},
      minTier: SubscriptionTier.silver,
    ),
    AppModule.inventory: ModuleMetadata(
      module: AppModule.inventory,
      label: 'Inventory & Stock',
      description: 'Item masters, stock levels, warehouse tracking, and valuation.',
      materialIcon: Icons.inventory_2_outlined,
      cupertinoIcon: CupertinoIcons.cube_box,
      allowedModes: {CompanyMode.ledger},
      dependencies: {AppModule.vouchers},
      minTier: SubscriptionTier.silver,
    ),
    AppModule.gst: ModuleMetadata(
      module: AppModule.gst,
      label: 'GST & Compliance',
      description: 'GSTR-1, GSTR-3B, e-Invoicing, e-Way bills, and tax reports.',
      materialIcon: Icons.account_balance_outlined,
      cupertinoIcon: CupertinoIcons.building_2_fill,
      allowedModes: {CompanyMode.ledger},
      dependencies: {AppModule.vouchers},
      minTier: SubscriptionTier.silver,
    ),
    AppModule.payroll: ModuleMetadata(
      module: AppModule.payroll,
      label: 'Payroll & HR',
      description: 'Employee salaries, attendance, payslips, PF, and ESI processing.',
      materialIcon: Icons.badge_outlined,
      cupertinoIcon: CupertinoIcons.person_badge_plus,
      allowedModes: {CompanyMode.ledger},
      dependencies: {AppModule.vouchers},
      minTier: SubscriptionTier.diamond,
    ),
    AppModule.manufacturing: ModuleMetadata(
      module: AppModule.manufacturing,
      label: 'Manufacturing & BOM',
      description: 'Bill of materials, production orders, scrap, and finished goods.',
      materialIcon: Icons.precision_manufacturing_outlined,
      cupertinoIcon: CupertinoIcons.gear_alt,
      allowedModes: {CompanyMode.ledger},
      dependencies: {AppModule.inventory},
      minTier: SubscriptionTier.diamond,
    ),
    AppModule.ecommerceSync: ModuleMetadata(
      module: AppModule.ecommerceSync,
      label: 'E-Commerce Sync',
      description: 'Multi-channel sales sync for Shopify, Amazon, and WooCommerce.',
      materialIcon: Icons.storefront_outlined,
      cupertinoIcon: CupertinoIcons.cart,
      allowedModes: {CompanyMode.ledger},
      dependencies: {AppModule.vouchers, AppModule.inventory},
      minTier: SubscriptionTier.diamond,
    ),
    AppModule.chequePrinting: ModuleMetadata(
      module: AppModule.chequePrinting,
      label: 'Cheque Printing',
      description: 'Custom bank cheque layouts, CTS-2010 alignment, and printing.',
      materialIcon: Icons.print_outlined,
      cupertinoIcon: CupertinoIcons.printer,
      allowedModes: {CompanyMode.ledger},
      dependencies: {},
      minTier: SubscriptionTier.diamond,
    ),
    AppModule.advancedReports: ModuleMetadata(
      module: AppModule.advancedReports,
      label: 'Advanced Reports',
      description: 'Financial balance sheet, P&L, cash flow, ageing, and ratios.',
      materialIcon: Icons.analytics_outlined,
      cupertinoIcon: CupertinoIcons.chart_bar_square,
      allowedModes: {CompanyMode.ledger},
      dependencies: {},
      minTier: SubscriptionTier.gold,
    ),
    AppModule.sqlStudio: ModuleMetadata(
      module: AppModule.sqlStudio,
      label: 'SQL Studio',
      description: 'Embedded SQLite query editor, schema browser, and CSV export.',
      materialIcon: Icons.terminal_outlined,
      cupertinoIcon: CupertinoIcons.chevron_left_slash_chevron_right,
      allowedModes: {CompanyMode.ledger},
      dependencies: {},
      minTier: SubscriptionTier.gold,
    ),
    AppModule.dataImport: ModuleMetadata(
      module: AppModule.dataImport,
      label: 'Data Import / Export',
      description: 'Bulk CSV, Excel, and Tally XML import and backup data export.',
      materialIcon: Icons.import_export_outlined,
      cupertinoIcon: CupertinoIcons.arrow_right_arrow_left,
      allowedModes: {CompanyMode.ledger},
      dependencies: {},
      minTier: SubscriptionTier.silver,
    ),
    AppModule.budgets: ModuleMetadata(
      module: AppModule.budgets,
      label: 'Budgets & Limits',
      description: 'Category-wise spending limits, budget alerts, and period rollover.',
      materialIcon: Icons.pie_chart_outline,
      cupertinoIcon: CupertinoIcons.chart_pie,
      allowedModes: {CompanyMode.expenseTracker},
      dependencies: {},
      minTier: SubscriptionTier.silver,
    ),
    AppModule.recurring: ModuleMetadata(
      module: AppModule.recurring,
      label: 'Recurring Rules',
      description: 'Scheduled recurring expenses, subscriptions, and auto-entry.',
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
  static String labelFor(AppModule module) => _catalog[module]?.label ?? module.name;

  /// Returns the human-readable description for [module].
  static String descriptionFor(AppModule module) => _catalog[module]?.description ?? '';

  /// Returns all modules allowed in Ledger mode.
  static List<AppModule> get ledgerModules => _catalog.values
      .where((m) => m.allowedModes.contains(CompanyMode.ledger))
      .map((m) => m.module)
      .toList();

  /// Returns the icon for [module].
  static IconData iconFor(AppModule module) => _catalog[module]?.icon ?? Icons.extension_outlined;

  /// Returns minimum subscription tier for a module.
  static SubscriptionTier minTierFor(AppModule module) => _catalog[module]!.minTier;

  /// Returns dependencies required by [module].
  static Set<AppModule> dependenciesFor(AppModule module) => _catalog[module]!.dependencies;

  /// Checks if a module is allowed for a company mode.

  static bool isModeAllowed(CompanyMode mode, AppModule module) {
    return _catalog[module]?.allowedModes.contains(mode) ?? false;
  }

  /// Returns all modules that depend on [module].
  ///
  /// If [transitive] is false (default), returns direct dependents.
  /// If [transitive] is true, includes indirect downstream dependents.
  static Set<AppModule> dependentsOf(AppModule module, {bool transitive = false}) {
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

  /// Returns default modules for a given [mode] and optional [preset].
  ///
  /// Presets:
  /// - `Simple Khata`: parties
  /// - `Billing & GST`: parties, vouchers, gst, advancedReports
  /// - `Full ERP`: every ledger-allowed module
  /// - `expense tracker defaults`: budgets, recurring
  static Set<AppModule> defaultsFor(CompanyMode mode, {String? preset}) {
    if (mode == CompanyMode.expenseTracker) {
      return {AppModule.budgets, AppModule.recurring};
    }

    final normalized = preset?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return {
        AppModule.parties,
        AppModule.vouchers,
        AppModule.gst,
        AppModule.advancedReports,
      };
    }

    if (normalized.contains('simple')) {
      return {AppModule.parties};
    }

    if (normalized.contains('billing')) {
      return {
        AppModule.parties,
        AppModule.vouchers,
        AppModule.gst,
        AppModule.advancedReports,
      };
    }

    if (normalized.contains('erp') || normalized.contains('full')) {
      return _catalog.values
          .where((m) => m.allowedModes.contains(CompanyMode.ledger))
          .map((m) => m.module)
          .toSet();
    }

    if (normalized.contains('expense')) {
      return {AppModule.budgets, AppModule.recurring};
    }

    // Default fallback for ledger mode
    return {
      AppModule.parties,
      AppModule.vouchers,
      AppModule.gst,
      AppModule.advancedReports,
    };
  }
}
