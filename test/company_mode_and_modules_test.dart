import 'dart:convert';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CompanyMode and AppModule parsing tests', () {
    test('CompanyMode name-based parsing parses valid names and ignores unknown values', () {
      expect(CompanyMode.fromName('ledger'), equals(CompanyMode.ledger));
      expect(CompanyMode.fromName('expenseTracker'), equals(CompanyMode.expenseTracker));
      expect(CompanyMode.fromName('EXPENSETRACKER'), equals(CompanyMode.expenseTracker));
      expect(CompanyMode.fromName('unknown_mode'), equals(CompanyMode.ledger));
      expect(CompanyMode.fromName(null), equals(CompanyMode.ledger));
      expect(CompanyMode.fromName(null, fallback: CompanyMode.expenseTracker), equals(CompanyMode.expenseTracker));
    });

    test('AppModule name-based parsing parses valid names and ignores unknown values', () {
      expect(AppModule.tryParse('parties'), equals(AppModule.parties));
      expect(AppModule.tryParse('VOUCHERS'), equals(AppModule.vouchers));
      expect(AppModule.tryParse('budgets'), equals(AppModule.budgets));
      expect(AppModule.tryParse('recurring'), equals(AppModule.recurring));
      expect(AppModule.tryParse('invalid_module'), isNull);
      expect(AppModule.tryParse(null), isNull);
    });

    test('AppModule.parseSet handles null, JSON strings, and lists, falling back to all modules for legacy rows', () {
      // Null or missing -> all modules enabled
      expect(AppModule.parseSet(null), equals(AppModule.allModules));
      expect(AppModule.parseSet(''), equals(AppModule.allModules));
      expect(AppModule.parseSet('null'), equals(AppModule.allModules));

      // Valid JSON list
      final jsonList = jsonEncode(['parties', 'budgets', 'unknown_something']);
      final parsedFromJson = AppModule.parseSet(jsonList);
      expect(parsedFromJson, containsAll([AppModule.parties, AppModule.budgets]));
      expect(parsedFromJson.length, equals(2));

      // Direct list
      final directList = ['vouchers', 'recurring', 'some_bogus'];
      final parsedFromList = AppModule.parseSet(directList);
      expect(parsedFromList, containsAll([AppModule.vouchers, AppModule.recurring]));
      expect(parsedFromList.length, equals(2));
    });
  });

  group('Company model mode & modules tests', () {
    test('Company defaults mode to ledger and enabledModules to all modules', () {
      final now = DateTime.now();
      final company = Company(
        id: 'comp_1',
        name: 'Tech Corp',
        legalName: 'Tech Corp Pvt Ltd',
        createdAt: now,
        updatedAt: now,
      );

      expect(company.mode, equals(CompanyMode.ledger));
      expect(company.enabledModules, equals(AppModule.allModules));
      expect(company.isModuleEnabled(AppModule.parties), isTrue);
      expect(company.isModuleEnabled(AppModule.budgets), isTrue);
    });

    test('Company isModuleEnabled reflects enabledModules subset', () {
      final now = DateTime.now();
      final company = Company(
        id: 'comp_exp',
        name: 'Expense Co',
        legalName: 'Expense Co',
        mode: CompanyMode.expenseTracker,
        enabledModules: const {AppModule.vouchers, AppModule.budgets},
        createdAt: now,
        updatedAt: now,
      );

      expect(company.mode, equals(CompanyMode.expenseTracker));
      expect(company.isModuleEnabled(AppModule.vouchers), isTrue);
      expect(company.isModuleEnabled(AppModule.budgets), isTrue);
      expect(company.isModuleEnabled(AppModule.parties), isFalse);
      expect(company.isModuleEnabled(AppModule.manufacturing), isFalse);
    });

    test('Company serialization and deserialization preserves mode and enabledModules', () {
      final now = DateTime.now();
      final company = Company(
        id: 'comp_2',
        name: 'Budget Master',
        legalName: 'Budget Master LLC',
        mode: CompanyMode.expenseTracker,
        enabledModules: const {AppModule.budgets, AppModule.recurring},
        createdAt: now,
        updatedAt: now,
      );

      final map = company.toMap();
      expect(map['mode'], equals('expenseTracker'));
      expect(map['enabledModules'], isA<String>());

      final restored = Company.fromMap(map);
      expect(restored.mode, equals(CompanyMode.expenseTracker));
      expect(restored.enabledModules, equals({AppModule.budgets, AppModule.recurring}));
      expect(restored, equals(company));
      expect(restored.hashCode, equals(company.hashCode));
    });

    test('Company.fromMap legacy row with missing modules gets all modules enabled', () {
      final now = DateTime.now();
      final legacyMap = {
        'id': 'legacy_comp',
        'name': 'Legacy Inc',
        'legalName': 'Legacy Inc',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };

      final company = Company.fromMap(legacyMap);
      expect(company.mode, equals(CompanyMode.ledger));
      expect(company.enabledModules, equals(AppModule.allModules));
    });
  });

  group('Database Schema v8 and Drift Repositories tests', () {
    late AppDatabase db;
    late DriftLedgerRepository ledgerRepo;
    late DriftVoucherRepository voucherRepo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      final audit = AuditService(db);
      final posting = VoucherPostingEngine(db, audit);
      ledgerRepo = DriftLedgerRepository(
        db: db,
        syncEngine: SyncEngine(db: db, simulateSyncForTesting: true),
        postingEngine: posting,
        autoSync: false,
      );
      voucherRepo = DriftVoucherRepository(
        db: db,
        auditService: audit,
        postingEngine: posting,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('AppDatabase schemaVersion is 8 and tables are created', () {
      expect(db.schemaVersion, equals(8));
      expect(db.budgets, isNotNull);
      expect(db.recurringRules, isNotNull);
    });

    test('createCompany and updateCompany persist mode and enabledModules to database', () async {
      final now = DateTime.now();
      final newComp = Company(
        id: 'c_test_modes',
        name: 'Mode Tester',
        legalName: 'Mode Tester Ltd',
        mode: CompanyMode.expenseTracker,
        enabledModules: const {AppModule.budgets, AppModule.vouchers, AppModule.recurring},
        createdAt: now,
        updatedAt: now,
      );

      await ledgerRepo.createCompany(newComp);

      final companies = await ledgerRepo.getCompanies();
      final fetched = companies.firstWhere((c) => c.id == 'c_test_modes');
      expect(fetched.mode, equals(CompanyMode.expenseTracker));
      expect(fetched.enabledModules, equals({AppModule.budgets, AppModule.vouchers, AppModule.recurring}));
      expect(fetched.isModuleEnabled(AppModule.budgets), isTrue);
      expect(fetched.isModuleEnabled(AppModule.parties), isFalse);

      // Update company mode and modules
      final updatedComp = fetched.copyWith(
        mode: CompanyMode.ledger,
        enabledModules: {AppModule.parties, AppModule.vouchers, AppModule.gst},
      );
      await ledgerRepo.updateCompany(updatedComp);

      final reFetchedList = await ledgerRepo.getCompanies();
      final reFetched = reFetchedList.firstWhere((c) => c.id == 'c_test_modes');
      expect(reFetched.mode, equals(CompanyMode.ledger));
      expect(reFetched.enabledModules, equals({AppModule.parties, AppModule.vouchers, AppModule.gst}));
    });

    test('VoucherModel and drift_voucher_repository persist categoryAccountId, walletAccountId, toWalletAccountId', () async {
      final now = DateTime.now();
      final defaultCompany = Company(
        id: 'cmp_default',
        name: 'Default Co',
        legalName: 'Default Co',
        mode: CompanyMode.expenseTracker,
        enabledModules: AppModule.allModules,
        createdAt: now,
        updatedAt: now,
      );
      await ledgerRepo.createCompany(defaultCompany);

      final catId = 'cmp_default_${ExpenseTrackerDefaults.foodDiningId}';
      final walletId = 'cmp_default_${ExpenseTrackerDefaults.walletCashId}';
      final toWalletId = 'cmp_default_${ExpenseTrackerDefaults.walletBankId}';

      final voucher = VoucherModel(
        id: 'v_wallet_test_1',
        companyId: 'cmp_default',
        voucherNumber: 'EXP-0001',
        type: VoucherType.expense,
        date: now,
        totalAmountInCents: 50000,
        categoryAccountId: catId,
        walletAccountId: walletId,
        toWalletAccountId: toWalletId,
        createdAt: now,
        updatedAt: now,
      );

      // Test VoucherModel copyWith, toMap, fromMap
      final vMap = voucher.toMap();
      expect(vMap['categoryAccountId'], equals(catId));
      expect(vMap['walletAccountId'], equals(walletId));
      expect(vMap['toWalletAccountId'], equals(toWalletId));

      final restoredVoucher = VoucherModel.fromMap(vMap);
      expect(restoredVoucher.categoryAccountId, equals(catId));
      expect(restoredVoucher.walletAccountId, equals(walletId));
      expect(restoredVoucher.toWalletAccountId, equals(toWalletId));

      // Persist via voucherRepo
      await voucherRepo.createVoucher(voucher);

      final fetchedVoucher = await voucherRepo.getVoucherById('v_wallet_test_1');
      expect(fetchedVoucher.categoryAccountId, equals(catId));
      expect(fetchedVoucher.walletAccountId, equals(walletId));
      expect(fetchedVoucher.toWalletAccountId, equals(toWalletId));

      final list = await voucherRepo.getVouchers();
      final itemInList = list.firstWhere((v) => v.id == 'v_wallet_test_1');
      expect(itemInList.categoryAccountId, equals(catId));
      expect(itemInList.walletAccountId, equals(walletId));
      expect(itemInList.toWalletAccountId, equals(toWalletId));
    });

    test('Budgets and RecurringRules tables allow insert and select operations', () async {
      final now = DateTime.now();
      // Insert into Budgets
      await db.into(db.budgets).insert(
        BudgetsCompanion.insert(
          id: 'b_1',
          companyId: const Value('cmp_default'),
          categoryAccountId: 'acc_cat_food',
          periodType: 'monthly',
          amountInCents: 100000,
          startDate: now,
          rolloverEnabled: const Value(true),
          isActive: const Value(true),
        ),
      );

      final budgets = await db.select(db.budgets).get();
      expect(budgets.length, equals(1));
      expect(budgets.first.categoryAccountId, equals('acc_cat_food'));
      expect(budgets.first.amountInCents, equals(100000));
      expect(budgets.first.rolloverEnabled, isTrue);

      // Insert into RecurringRules
      await db.into(db.recurringRules).insert(
        RecurringRulesCompanion.insert(
          id: 'r_1',
          companyId: const Value('cmp_default'),
          templateJson: '{"type":"expense","amountInCents":20000}',
          intervalType: 'weekly',
          intervalCount: const Value(2),
          nextRunDate: now.add(const Duration(days: 14)),
        ),
      );

      final rules = await db.select(db.recurringRules).get();
      expect(rules.length, equals(1));
      expect(rules.first.intervalType, equals('weekly'));
      expect(rules.first.intervalCount, equals(2));
    });
  });
}
