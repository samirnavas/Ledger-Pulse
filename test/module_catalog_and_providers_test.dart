import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/modules/module_catalog.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';

import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/module_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';

class _EmptyProfileNotifier extends UserProfileNotifier {
  @override
  UserProfile build() =>
      UserProfile(id: 'test', name: '', phoneNumber: '', email: '');
}

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
    enabledModules:
        enabledModules ??
        (mode == CompanyMode.ledger
            ? ModuleCatalog.defaultsFor(CompanyMode.ledger)
            : ModuleCatalog.defaultsFor(CompanyMode.expenseTracker)),
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy flags and presets cannot change the ledger release catalog', () {
    const essentials = {
      AppModule.parties,
      AppModule.vouchers,
      AppModule.dataImport,
    };
    expect(ModuleCatalog.ledgerModules.toSet(), essentials);
    for (final preset in [null, 'Simple Khata', 'Billing & GST', 'Full ERP']) {
      expect(
        ModuleCatalog.defaultsFor(CompanyMode.ledger, preset: preset),
        essentials,
      );
    }
    for (final saved in [const <AppModule>{}, AppModule.allModules]) {
      final company = _createTestCompany(
        id: 'ledger',
        name: 'Ledger',
        enabledModules: saved,
      );
      final container = ProviderContainer(
        overrides: [activeCompanyProvider.overrideWithValue(company)],
      );
      addTearDown(container.dispose);
      for (final module in AppModule.values) {
        final expected = essentials.contains(module);
        expect(company.isModuleEnabled(module), expected, reason: module.name);
        expect(
          container.read(moduleEnabledProvider(module)),
          expected,
          reason: module.name,
        );
      }
      expect(company.enabledModules, saved);
    }
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
          appDatabaseProvider.overrideWithValue(db),
          userProfileProvider.overrideWith(_EmptyProfileNotifier.new),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      repo.dispose();
      await db.close();
    });

    test(
      'rejects ERP configuration changes without rewriting saved flags',
      () async {
        final company = _createTestCompany(
          id: 'legacy',
          name: 'Legacy',
          enabledModules: {AppModule.inventory},
        );
        await repo.createCompany(company);
        final controller = container.read(companyControllerProvider.notifier);
        await expectLater(
          controller.setModuleEnabled(company.id, AppModule.gst, true),
          throwsA(isA<ModuleDependencyException>()),
        );
        expect(
          await controller.setModuleEnabled(
            company.id,
            AppModule.parties,
            false,
            throwOnError: false,
          ),
          {AppModule.parties},
        );
        final stored = (await repo.getCompanies()).singleWhere(
          (c) => c.id == company.id,
        );
        expect(stored.enabledModules, company.enabledModules);
        expect(stored.isModuleEnabled(AppModule.inventory), isFalse);
      },
    );

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
        () => controller.setModuleEnabled(
          'comp_expense',
          AppModule.vouchers,
          true,
        ),
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

    test(
      'successfully toggles module: persists DB first, bumps updatedAt, writes audit and outbox',
      () async {
        final initialUpdatedAt = DateTime.now().subtract(
          const Duration(minutes: 5),
        );
        final company = _createTestCompany(
          id: 'comp_toggle',
          name: 'Toggle Co',
          mode: CompanyMode.expenseTracker,
          enabledModules: {AppModule.budgets},
          updatedAt: initialUpdatedAt,
        );
        await repo.createCompany(company);

        final controller = container.read(companyControllerProvider.notifier);

        final result = await controller.setModuleEnabled(
          'comp_toggle',
          AppModule.recurring,
          true,
        );
        expect(result, isEmpty);

        // Verify DB row updated first
        final companies = await repo.getCompanies();
        final updatedComp = companies.firstWhere((c) => c.id == 'comp_toggle');
        expect(
          updatedComp.enabledModules.contains(AppModule.recurring),
          isTrue,
        );
        expect(updatedComp.updatedAt.isAfter(initialUpdatedAt), isTrue);

        // Verify outbox has pending record
        final outboxRows = await db.select(db.syncOutbox).get();
        final companyOutbox = outboxRows.where(
          (r) => r.targetTable == 'companies' && r.recordId == 'comp_toggle',
        );
        expect(companyOutbox.isNotEmpty, isTrue);

        // Verify audit trail logged the update
        final auditRows = await db.select(db.auditLogs).get();
        final companyAudit = auditRows.where(
          (r) => r.entityId == 'comp_toggle',
        );
        expect(companyAudit.isNotEmpty, isTrue);

        final disableResult = await controller.setModuleEnabled(
          'comp_toggle',
          AppModule.recurring,
          false,
        );
        expect(disableResult, isEmpty);

        final disabledComp = (await repo.getCompanies()).firstWhere(
          (c) => c.id == 'comp_toggle',
        );
        expect(
          disabledComp.enabledModules.contains(AppModule.recurring),
          isFalse,
        );
      },
    );
  });
}
