import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/modules/module_catalog.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';

import 'package:ledger_pulse/data/models/subscription_tier_model.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/module_providers.dart';
import 'package:ledger_pulse/presentation/providers/subscription_providers.dart';

Company _createTestCompany({
  required String id,
  required String name,
  CompanyMode mode = CompanyMode.ledger,
  Set<AppModule>? enabledModules,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final now = DateTime.now();
  return Company(
    id: id,
    name: name,
    legalName: '$name Ltd',
    mode: mode,
    enabledModules: enabledModules ?? (mode == CompanyMode.ledger
        ? ModuleCatalog.defaultsFor(CompanyMode.ledger)
        : ModuleCatalog.defaultsFor(CompanyMode.expenseTracker)),
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModuleCatalog Dependency Rules and Presets', () {
    test('defines all 13 AppModules with non-empty label and description', () {
      expect(ModuleCatalog.all.length, equals(13));
      for (final module in AppModule.values) {
        final meta = ModuleCatalog.metadataFor(module);
        expect(meta.label.isNotEmpty, isTrue);
        expect(meta.description.isNotEmpty, isTrue);
        expect(meta.materialIcon, isNotNull);
        expect(meta.cupertinoIcon, isNotNull);
      }
    });

    test('verifies explicit dependency rules', () {
      // gst needs vouchers
      expect(ModuleCatalog.dependenciesFor(AppModule.gst), equals({AppModule.vouchers}));

      // inventory needs vouchers
      expect(ModuleCatalog.dependenciesFor(AppModule.inventory), equals({AppModule.vouchers}));

      // manufacturing needs inventory
      expect(ModuleCatalog.dependenciesFor(AppModule.manufacturing), equals({AppModule.inventory}));

      // payroll needs vouchers
      expect(ModuleCatalog.dependenciesFor(AppModule.payroll), equals({AppModule.vouchers}));

      // ecommerceSync needs vouchers and inventory
      expect(
        ModuleCatalog.dependenciesFor(AppModule.ecommerceSync),
        equals({AppModule.vouchers, AppModule.inventory}),
      );

      // independent modules have empty dependencies
      expect(ModuleCatalog.dependenciesFor(AppModule.parties), isEmpty);
      expect(ModuleCatalog.dependenciesFor(AppModule.vouchers), isEmpty);
      expect(ModuleCatalog.dependenciesFor(AppModule.chequePrinting), isEmpty);
      expect(ModuleCatalog.dependenciesFor(AppModule.advancedReports), isEmpty);
      expect(ModuleCatalog.dependenciesFor(AppModule.sqlStudio), isEmpty);
      expect(ModuleCatalog.dependenciesFor(AppModule.dataImport), isEmpty);
      expect(ModuleCatalog.dependenciesFor(AppModule.budgets), isEmpty);
      expect(ModuleCatalog.dependenciesFor(AppModule.recurring), isEmpty);
    });

    test('verifies allowed modes for all modules', () {
      // budgets and recurring are expenseTracker-only
      expect(
        ModuleCatalog.metadataFor(AppModule.budgets).allowedModes,
        equals({CompanyMode.expenseTracker}),
      );
      expect(
        ModuleCatalog.metadataFor(AppModule.recurring).allowedModes,
        equals({CompanyMode.expenseTracker}),
      );

      // All others are ledger-only
      final ledgerOnlyModules = AppModule.values.where(
        (m) => m != AppModule.budgets && m != AppModule.recurring,
      );
      for (final module in ledgerOnlyModules) {
        expect(
          ModuleCatalog.metadataFor(module).allowedModes,
          equals({CompanyMode.ledger}),
          reason: '$module should only be allowed in ledger mode',
        );
      }
    });

    test('verifies minimum subscription tier rules', () {
      // diamond tiers: payroll, manufacturing, ecommerceSync, chequePrinting
      expect(ModuleCatalog.minTierFor(AppModule.payroll), equals(SubscriptionTier.diamond));
      expect(ModuleCatalog.minTierFor(AppModule.manufacturing), equals(SubscriptionTier.diamond));
      expect(ModuleCatalog.minTierFor(AppModule.ecommerceSync), equals(SubscriptionTier.diamond));
      expect(ModuleCatalog.minTierFor(AppModule.chequePrinting), equals(SubscriptionTier.diamond));

      // gold tiers: sqlStudio, advancedReports
      expect(ModuleCatalog.minTierFor(AppModule.sqlStudio), equals(SubscriptionTier.gold));
      expect(ModuleCatalog.minTierFor(AppModule.advancedReports), equals(SubscriptionTier.gold));

      // silver tiers (all others)
      expect(ModuleCatalog.minTierFor(AppModule.parties), equals(SubscriptionTier.silver));
      expect(ModuleCatalog.minTierFor(AppModule.vouchers), equals(SubscriptionTier.silver));
      expect(ModuleCatalog.minTierFor(AppModule.inventory), equals(SubscriptionTier.silver));
      expect(ModuleCatalog.minTierFor(AppModule.gst), equals(SubscriptionTier.silver));
      expect(ModuleCatalog.minTierFor(AppModule.dataImport), equals(SubscriptionTier.silver));
      expect(ModuleCatalog.minTierFor(AppModule.budgets), equals(SubscriptionTier.silver));
      expect(ModuleCatalog.minTierFor(AppModule.recurring), equals(SubscriptionTier.silver));
    });

    test('verifies presets in defaultsFor(mode, {preset})', () {
      // Simple Khata = parties
      final simpleKhata = ModuleCatalog.defaultsFor(
        CompanyMode.ledger,
        preset: 'Simple Khata',
      );
      expect(simpleKhata, equals({AppModule.parties}));

      // Billing & GST = parties, vouchers, gst, advancedReports
      final billingGst = ModuleCatalog.defaultsFor(
        CompanyMode.ledger,
        preset: 'Billing & GST',
      );
      expect(
        billingGst,
        equals({
          AppModule.parties,
          AppModule.vouchers,
          AppModule.gst,
          AppModule.advancedReports,
        }),
      );

      // Full ERP = every ledger-allowed module (11 modules)
      final fullErp = ModuleCatalog.defaultsFor(
        CompanyMode.ledger,
        preset: 'Full ERP',
      );
      expect(fullErp.length, equals(11));
      expect(fullErp.contains(AppModule.budgets), isFalse);
      expect(fullErp.contains(AppModule.recurring), isFalse);
      expect(
        fullErp,
        containsAll([
          AppModule.parties,
          AppModule.vouchers,
          AppModule.inventory,
          AppModule.gst,
          AppModule.payroll,
          AppModule.manufacturing,
          AppModule.ecommerceSync,
          AppModule.chequePrinting,
          AppModule.advancedReports,
          AppModule.sqlStudio,
          AppModule.dataImport,
        ]),
      );

      // expense tracker defaults = budgets, recurring
      final expenseDefaults = ModuleCatalog.defaultsFor(CompanyMode.expenseTracker);
      expect(expenseDefaults, equals({AppModule.budgets, AppModule.recurring}));

      final expenseWithPreset = ModuleCatalog.defaultsFor(
        CompanyMode.expenseTracker,
        preset: 'expense tracker defaults',
      );
      expect(expenseWithPreset, equals({AppModule.budgets, AppModule.recurring}));
    });

    test('verifies dependentsOf calculation', () {
      // Direct dependents of vouchers: gst, inventory, payroll, ecommerceSync
      final voucherDependents = ModuleCatalog.dependentsOf(AppModule.vouchers);
      expect(
        voucherDependents,
        equals({
          AppModule.gst,
          AppModule.inventory,
          AppModule.payroll,
          AppModule.ecommerceSync,
        }),
      );

      // Direct dependents of inventory: manufacturing, ecommerceSync
      final inventoryDependents = ModuleCatalog.dependentsOf(AppModule.inventory);
      expect(
        inventoryDependents,
        equals({AppModule.manufacturing, AppModule.ecommerceSync}),
      );

      // Transitive dependents of vouchers includes manufacturing
      final transitiveVoucherDependents = ModuleCatalog.dependentsOf(
        AppModule.vouchers,
        transitive: true,
      );
      expect(
        transitiveVoucherDependents,
        containsAll([
          AppModule.gst,
          AppModule.inventory,
          AppModule.payroll,
          AppModule.ecommerceSync,
          AppModule.manufacturing,
        ]),
      );

      // Independent leaf modules have no dependents
      expect(ModuleCatalog.dependentsOf(AppModule.parties), isEmpty);
      expect(ModuleCatalog.dependentsOf(AppModule.chequePrinting), isEmpty);
      expect(ModuleCatalog.dependentsOf(AppModule.budgets), isEmpty);
    });

    test('verifies missingDependencies calculation', () {
      // ecommerceSync requires vouchers and inventory
      expect(
        ModuleCatalog.missingDependencies(AppModule.ecommerceSync, {AppModule.vouchers}),
        equals({AppModule.inventory}),
      );
      expect(
        ModuleCatalog.missingDependencies(AppModule.ecommerceSync, {}),
        equals({AppModule.vouchers, AppModule.inventory}),
      );
      expect(
        ModuleCatalog.missingDependencies(
          AppModule.ecommerceSync,
          {AppModule.vouchers, AppModule.inventory},
        ),
        isEmpty,
      );

      // gst requires vouchers
      expect(
        ModuleCatalog.missingDependencies(AppModule.gst, {AppModule.parties}),
        equals({AppModule.vouchers}),
      );
      expect(
        ModuleCatalog.missingDependencies(AppModule.gst, {AppModule.vouchers}),
        isEmpty,
      );

      // module with no dependencies
      expect(ModuleCatalog.missingDependencies(AppModule.parties, {}), isEmpty);
    });
  });

  group('Provider Truth Table (mode x enabled x tier)', () {
    late AppDatabase db;
    late DriftLedgerRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftLedgerRepository(db: db, autoSync: false);
    });

    tearDown(() async {
      repo.dispose();
      await db.close();
    });

    ProviderContainer createContainer({
      required Company company,
      required LicenseState license,
    }) {
      final container = ProviderContainer(
        overrides: [
          driftLedgerRepositoryProvider.overrideWithValue(repo),
          activeCompanyProvider.overrideWithValue(company),
          userCompaniesProvider.overrideWithValue([company]),
          subscriptionStateProvider.overrideWith(
            () => _FakeSubscriptionNotifier(license),
          ),
        ],
      );
      return container;
    }

    test('tierAllowsProvider correctly reflects tier rules and expiry', () {
      final silverLicense = LicenseState(
        tier: SubscriptionTier.silver,
        duration: BillingDuration.monthly,
        startDate: DateTime.now().subtract(const Duration(days: 1)),
        expiryDate: DateTime.now().add(const Duration(days: 29)),
      );
      final goldLicense = silverLicense.copyWith(tier: SubscriptionTier.gold);
      final diamondLicense = silverLicense.copyWith(tier: SubscriptionTier.diamond);
      final expiredLicense = diamondLicense.copyWith(
        expiryDate: DateTime.now().subtract(const Duration(days: 1)),
      );

      final cSilver = createContainer(
        company: _createTestCompany(id: 'c1', name: 'C1'),
        license: silverLicense,
      );
      final cGold = createContainer(
        company: _createTestCompany(id: 'c1', name: 'C1'),
        license: goldLicense,
      );
      final cDiamond = createContainer(
        company: _createTestCompany(id: 'c1', name: 'C1'),
        license: diamondLicense,
      );
      final cExpired = createContainer(
        company: _createTestCompany(id: 'c1', name: 'C1'),
        license: expiredLicense,
      );

      // Silver tier checks
      expect(cSilver.read(tierAllowsProvider(AppModule.parties)), isTrue);
      expect(cSilver.read(tierAllowsProvider(AppModule.vouchers)), isTrue);
      expect(cSilver.read(tierAllowsProvider(AppModule.advancedReports)), isFalse);
      expect(cSilver.read(tierAllowsProvider(AppModule.sqlStudio)), isFalse);
      expect(cSilver.read(tierAllowsProvider(AppModule.payroll)), isFalse);
      expect(cSilver.read(tierAllowsProvider(AppModule.chequePrinting)), isFalse);

      // Gold tier checks
      expect(cGold.read(tierAllowsProvider(AppModule.parties)), isTrue);
      expect(cGold.read(tierAllowsProvider(AppModule.advancedReports)), isTrue);
      expect(cGold.read(tierAllowsProvider(AppModule.sqlStudio)), isTrue);
      expect(cGold.read(tierAllowsProvider(AppModule.payroll)), isFalse);

      // Diamond tier checks
      expect(cDiamond.read(tierAllowsProvider(AppModule.payroll)), isTrue);
      expect(cDiamond.read(tierAllowsProvider(AppModule.manufacturing)), isTrue);
      expect(cDiamond.read(tierAllowsProvider(AppModule.ecommerceSync)), isTrue);
      expect(cDiamond.read(tierAllowsProvider(AppModule.chequePrinting)), isTrue);

      // Expired license blocks all modules
      expect(cExpired.read(tierAllowsProvider(AppModule.parties)), isFalse);
      expect(cExpired.read(tierAllowsProvider(AppModule.payroll)), isFalse);
    });

    test('truth table evaluations for moduleEnabledProvider & moduleLockReasonProvider', () {
      final diamondLicense = LicenseState(
        tier: SubscriptionTier.diamond,
        duration: BillingDuration.monthly,
        startDate: DateTime.now().subtract(const Duration(days: 1)),
        expiryDate: DateTime.now().add(const Duration(days: 29)),
      );
      final silverLicense = diamondLicense.copyWith(tier: SubscriptionTier.silver);

      // Case 1: Mode does not allow module (vouchers in expenseTracker mode)
      final expenseCompany = _createTestCompany(
        id: 'c1',
        name: 'Expense Co',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.vouchers, AppModule.budgets},
      );
      final cModeMismatch = createContainer(
        company: expenseCompany,
        license: diamondLicense,
      );
      expect(cModeMismatch.read(moduleEnabledProvider(AppModule.vouchers)), isFalse);
      expect(
        cModeMismatch.read(moduleLockReasonProvider(AppModule.vouchers)),
        equals(ModuleLockReason.modeNotAllowed),
      );

      // Case 2: Mode allowed, but Tier too low (payroll on silver tier)
      final ledgerCompanyWithPayroll = _createTestCompany(
        id: 'c2',
        name: 'Ledger Co',
        mode: CompanyMode.ledger,
        enabledModules: {AppModule.vouchers, AppModule.payroll},
      );
      final cTierTooLow = createContainer(
        company: ledgerCompanyWithPayroll,
        license: silverLicense,
      );
      expect(cTierTooLow.read(moduleEnabledProvider(AppModule.payroll)), isFalse);
      expect(
        cTierTooLow.read(moduleLockReasonProvider(AppModule.payroll)),
        equals(ModuleLockReason.tierTooLow),
      );

      // Case 3: Mode allowed, Tier entitles, but Company has NOT enabled it
      final ledgerCompanyNoPayroll = _createTestCompany(
        id: 'c3',
        name: 'Ledger Co',
        mode: CompanyMode.ledger,
        enabledModules: {AppModule.vouchers}, // payroll not enabled
      );
      final cNotEnabled = createContainer(
        company: ledgerCompanyNoPayroll,
        license: diamondLicense,
      );
      expect(cNotEnabled.read(moduleEnabledProvider(AppModule.payroll)), isFalse);
      expect(
        cNotEnabled.read(moduleLockReasonProvider(AppModule.payroll)),
        equals(ModuleLockReason.notEnabled),
      );

      // Case 4: Mode allowed, Tier entitles, Company enabled, but missing dependency (gst without vouchers)
      final ledgerCompanyGstNoVouchers = _createTestCompany(
        id: 'c4',
        name: 'Ledger Co',
        mode: CompanyMode.ledger,
        enabledModules: {AppModule.gst}, // vouchers missing!
      );
      final cMissingDep = createContainer(
        company: ledgerCompanyGstNoVouchers,
        license: diamondLicense,
      );
      expect(cMissingDep.read(moduleEnabledProvider(AppModule.gst)), isFalse);
      expect(
        cMissingDep.read(moduleLockReasonProvider(AppModule.gst)),
        equals(ModuleLockReason.missingDependency),
      );

      // Case 5: Mode allows AND Tier entitles AND Company enabled AND dependencies satisfied -> true / null
      final fullActiveCompany = _createTestCompany(
        id: 'c5',
        name: 'Ledger Co',
        mode: CompanyMode.ledger,
        enabledModules: {AppModule.vouchers, AppModule.gst, AppModule.payroll},
      );
      final cActive = createContainer(
        company: fullActiveCompany,
        license: diamondLicense,
      );
      expect(cActive.read(moduleEnabledProvider(AppModule.gst)), isTrue);
      expect(cActive.read(moduleLockReasonProvider(AppModule.gst)), isNull);
      expect(cActive.read(moduleEnabledProvider(AppModule.payroll)), isTrue);
      expect(cActive.read(moduleLockReasonProvider(AppModule.payroll)), isNull);
    });
  });

  group('Toggle Refusal Cases in CompanyController.setModuleEnabled', () {
    late AppDatabase db;
    late DriftLedgerRepository repo;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftLedgerRepository(db: db, autoSync: false);

      container = ProviderContainer(
        overrides: [
          driftLedgerRepositoryProvider.overrideWithValue(repo),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      repo.dispose();
      await db.close();
    });

    test('refuses to enable when dependencies are off (throwOnError: true & false)', () async {
      final company = _createTestCompany(
        id: 'comp_test',
        name: 'Test Co',
        mode: CompanyMode.ledger,
        enabledModules: {AppModule.parties}, // vouchers is disabled!
      );
      await repo.createCompany(company);

      final controller = container.read(companyControllerProvider.notifier);

      // Attempting to enable gst without vouchers should throw ModuleDependencyException
      expect(
        () => controller.setModuleEnabled('comp_test', AppModule.gst, true),
        throwsA(
          isA<ModuleDependencyException>().having(
            (e) => e.missingDependencies,
            'missingDependencies',
            contains(AppModule.vouchers),
          ),
        ),
      );

      // Attempting to enable with throwOnError: false returns missing dependencies
      final missing = await controller.setModuleEnabled(
        'comp_test',
        AppModule.gst,
        true,
        throwOnError: false,
      );
      expect(missing, equals({AppModule.vouchers}));

      // Verify DB was NOT modified and gst is still not enabled
      final reloaded = (await repo.getCompanies()).firstWhere((c) => c.id == 'comp_test');
      expect(reloaded.enabledModules.contains(AppModule.gst), isFalse);
    });

    test('refuses to enable module not allowed by mode', () async {
      final expenseCompany = _createTestCompany(
        id: 'comp_expense',
        name: 'Expense Co',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.budgets, AppModule.recurring},
      );
      await repo.createCompany(expenseCompany);

      final controller = container.read(companyControllerProvider.notifier);

      // Attempting to enable vouchers in expenseTracker mode
      expect(
        () => controller.setModuleEnabled('comp_expense', AppModule.vouchers, true),
        throwsA(isA<ModuleDependencyException>()),
      );

      final returned = await controller.setModuleEnabled(
        'comp_expense',
        AppModule.vouchers,
        true,
        throwOnError: false,
      );
      expect(returned, equals({AppModule.vouchers}));
    });

    test('refuses to disable when an enabled module depends on it', () async {
      final company = _createTestCompany(
        id: 'comp_with_gst',
        name: 'GST Co',
        mode: CompanyMode.ledger,
        enabledModules: {AppModule.vouchers, AppModule.gst},
      );
      await repo.createCompany(company);

      final controller = container.read(companyControllerProvider.notifier);

      // Attempting to disable vouchers while gst is enabled
      expect(
        () => controller.setModuleEnabled('comp_with_gst', AppModule.vouchers, false),
        throwsA(
          isA<ModuleDependencyException>().having(
            (e) => e.activeDependents,
            'activeDependents',
            contains(AppModule.gst),
          ),
        ),
      );

      final dependents = await controller.setModuleEnabled(
        'comp_with_gst',
        AppModule.vouchers,
        false,
        throwOnError: false,
      );
      expect(dependents, contains(AppModule.gst));

      // Verify vouchers is STILL enabled in DB
      final reloaded = (await repo.getCompanies()).firstWhere((c) => c.id == 'comp_with_gst');
      expect(reloaded.enabledModules.contains(AppModule.vouchers), isTrue);
    });

    test('successfully toggles module: persists DB first, bumps updatedAt, writes audit and outbox', () async {
      final initialUpdatedAt = DateTime.now().subtract(const Duration(minutes: 5));
      final company = _createTestCompany(
        id: 'comp_toggle',
        name: 'Toggle Co',
        mode: CompanyMode.ledger,
        enabledModules: {AppModule.parties, AppModule.vouchers},
        updatedAt: initialUpdatedAt,
      );
      await repo.createCompany(company);

      final controller = container.read(companyControllerProvider.notifier);

      // Enable gst (dependencies are met since vouchers is enabled)
      final result = await controller.setModuleEnabled('comp_toggle', AppModule.gst, true);
      expect(result, isEmpty);

      // Verify DB row updated first
      final companies = await repo.getCompanies();
      final updatedComp = companies.firstWhere((c) => c.id == 'comp_toggle');
      expect(updatedComp.enabledModules.contains(AppModule.gst), isTrue);
      expect(updatedComp.updatedAt.isAfter(initialUpdatedAt), isTrue);

      // Verify outbox has pending record
      final outboxRows = await db.select(db.syncOutbox).get();
      final companyOutbox = outboxRows.where(
        (r) => r.targetTable == 'companies' && r.recordId == 'comp_toggle',
      );
      expect(companyOutbox.isNotEmpty, isTrue);

      // Verify audit trail logged the update
      final auditRows = await db.select(db.auditLogs).get();
      final companyAudit = auditRows.where((r) => r.entityId == 'comp_toggle');
      expect(companyAudit.isNotEmpty, isTrue);

      // Disable gst (nothing depends on gst)
      final disableResult = await controller.setModuleEnabled('comp_toggle', AppModule.gst, false);
      expect(disableResult, isEmpty);

      final disabledComp = (await repo.getCompanies()).firstWhere((c) => c.id == 'comp_toggle');
      expect(disabledComp.enabledModules.contains(AppModule.gst), isFalse);
    });
  });
}

class _FakeSubscriptionNotifier extends SubscriptionNotifier {
  final LicenseState _initial;
  _FakeSubscriptionNotifier(this._initial);

  @override
  LicenseState build() => _initial;
}
