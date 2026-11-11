import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/modules/module_catalog.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';
import 'package:ledger_pulse/presentation/settings/settings_screen.dart';

class _TestUserProfileNotifier extends UserProfileNotifier {
  final UserProfile _initial;
  _TestUserProfileNotifier(this._initial);

  @override
  UserProfile build() => _initial;

  @override
  void updateProfile(UserProfile updated) {
    state = updated;
  }
}

class _FakeSyncEngine extends SyncEngine {
  _FakeSyncEngine({required super.db});

  @override
  Future<SyncResult> syncAll({String? companyId}) async {
    return SyncResult(
      success: true,
      itemsPushed: 0,
      itemsPulled: 0,
      timestamp: DateTime.now(),
    );
  }

  @override
  void triggerBackgroundSync({
    String? companyId,
    Duration debounceDelay = const Duration(milliseconds: 1500),
  }) {
    // No-op for fake sync engine in unit tests
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Prompt 7 – Workspace Type Immutability & Rejection of Mutation Tests', () {
    late AppDatabase db;
    late AuditService auditService;
    late VoucherPostingEngine postingEngine;
    late DriftLedgerRepository repo;
    late DriftExpenseRepository expenseRepo;
    late DriftVoucherRepository voucherRepo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      auditService = AuditService(db);
      postingEngine = VoucherPostingEngine(db, auditService);
      repo = DriftLedgerRepository(
        db: db,
        postingEngine: postingEngine,
        autoSync: false,
      );
      voucherRepo = DriftVoucherRepository(
        db: db,
        postingEngine: postingEngine,
        auditService: auditService,
      );
      expenseRepo = DriftExpenseRepository(
        db: db,
        postingEngine: postingEngine,
        voucherRepo: voucherRepo,
        auditService: auditService,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('Company.copyWith rejects changing mode', () {
      final expenseCompany = Company(
        id: 'cmp_1',
        name: 'Personal Expenses',
        legalName: 'Personal Expenses',
        currencyCode: 'INR',
        mode: CompanyMode.expenseTracker,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(
        () => expenseCompany.copyWith(mode: CompanyMode.ledger),
        throwsStateError,
      );
    });

    test('updateCompany rejects converting Expense workspace to Ledger workspace', () async {
      const companyId = 'cmp_expense_immutable';

      final expenseCompany = Company(
        id: companyId,
        name: 'Personal Expenses',
        legalName: 'Personal Expenses',
        currencyCode: 'INR',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.budgets, AppModule.recurring},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repo.createCompany(
        expenseCompany,
        initialWalletBalancesInCents: {
          ExpenseTrackerDefaults.walletCashId: 1000000,
        },
      );

      // Attempt to update with a new Company instance having mode = ledger
      final attemptMutateToLedger = Company(
        id: companyId,
        name: 'Personal Expenses',
        legalName: 'Personal Expenses',
        currencyCode: 'INR',
        mode: CompanyMode.ledger,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(
        () => repo.updateCompany(attemptMutateToLedger),
        throwsUnsupportedError,
        reason: 'Workspace type is immutable and must not change from expense to ledger.',
      );

      final persisted = (await repo.getCompanies()).firstWhere((c) => c.id == companyId);
      expect(persisted.mode, equals(CompanyMode.expenseTracker));
    });

    test('updateCompany rejects converting Ledger workspace to Expense workspace', () async {
      const companyId = 'cmp_ledger_immutable';

      final ledgerCompany = Company(
        id: companyId,
        name: 'Enterprise Trading',
        legalName: 'Enterprise Trading Ltd',
        currencyCode: 'INR',
        mode: CompanyMode.ledger,
        enabledModules: ModuleCatalog.defaultsFor(CompanyMode.ledger),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repo.createCompany(ledgerCompany);

      // Attempt to update with a new Company instance having mode = expenseTracker
      final attemptMutateToExpense = Company(
        id: companyId,
        name: 'Enterprise Trading',
        legalName: 'Enterprise Trading Ltd',
        currencyCode: 'INR',
        mode: CompanyMode.expenseTracker,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(
        () => repo.updateCompany(attemptMutateToExpense),
        throwsUnsupportedError,
        reason: 'Workspace type is immutable and must not change from ledger to expense.',
      );

      final persisted = (await repo.getCompanies()).firstWhere((c) => c.id == companyId);
      expect(persisted.mode, equals(CompanyMode.ledger));
    });

    test('creating a new Ledger workspace leaves existing Expense workspace untouched', () async {
      const expenseId = 'cmp_user_expense';
      const ledgerId = 'cmp_user_ledger';

      final expenseCompany = Company(
        id: expenseId,
        name: 'My Personal Vault',
        legalName: 'My Personal Vault',
        currencyCode: 'INR',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.budgets, AppModule.recurring},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repo.createCompany(
        expenseCompany,
        initialWalletBalancesInCents: {
          ExpenseTrackerDefaults.walletCashId: 750000,
        },
      );

      expenseRepo.setContext(companyId: expenseId);
      await expenseRepo.addExpense(
        categoryAccountId: '${expenseId}_${ExpenseTrackerDefaults.foodDiningId}',
        walletAccountId: '${expenseId}_${ExpenseTrackerDefaults.walletCashId}',
        amountInCents: 50000,
        narration: 'Groceries',
      );

      final expenseAccountsBefore = await (db.select(db.accounts)
            ..where((t) => t.companyId.equals(expenseId) & t.isDeleted.equals(false)))
          .get();
      final cashAccountBefore = expenseAccountsBefore.firstWhere((a) => a.id == '${expenseId}_${ExpenseTrackerDefaults.walletCashId}');
      expect(cashAccountBefore.currentBalanceInCents, equals(700000));

      // Now create a separate Ledger workspace for the user
      final ledgerCompany = Company(
        id: ledgerId,
        name: 'My Business Ledger',
        legalName: 'My Business Ledger Ltd',
        currencyCode: 'INR',
        mode: CompanyMode.ledger,
        enabledModules: ModuleCatalog.defaultsFor(CompanyMode.ledger),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await repo.createCompany(ledgerCompany);

      // Verify Expense company is completely untouched
      final companies = await repo.getCompanies();
      expect(companies.length, equals(2));

      final persistedExpense = companies.firstWhere((c) => c.id == expenseId);
      expect(persistedExpense.mode, equals(CompanyMode.expenseTracker));

      final persistedLedger = companies.firstWhere((c) => c.id == ledgerId);
      expect(persistedLedger.mode, equals(CompanyMode.ledger));

      // Balance in original expense workspace is completely identical
      final expenseAccountsAfter = await (db.select(db.accounts)
            ..where((t) => t.companyId.equals(expenseId) & t.isDeleted.equals(false)))
          .get();
      final cashAccountAfter = expenseAccountsAfter.firstWhere((a) => a.id == '${expenseId}_${ExpenseTrackerDefaults.walletCashId}');
      expect(cashAccountAfter.currentBalanceInCents, equals(700000));
    });

    testWidgets('Settings in expense mode explains workspace immutability and offers separate workspace', (tester) async {
      const companyId = 'cmp_ui_test';

      final expenseCompany = Company(
        id: companyId,
        name: 'My Personal Workspace',
        legalName: 'My Personal Workspace',
        currencyCode: 'INR',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.budgets, AppModule.recurring},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repo.createCompany(
        expenseCompany,
        initialWalletBalancesInCents: {
          ExpenseTrackerDefaults.walletCashId: 500000,
        },
      );

      final userProfile = UserProfile(
        id: 'usr_default',
        name: 'Owner',
        email: 'owner@example.com',
        phoneNumber: '+919999999999',
        activeCompanyId: companyId,
        companies: [expenseCompany],
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          driftLedgerRepositoryProvider.overrideWithValue(repo),
          userProfileProvider.overrideWith(
            () => _TestUserProfileNotifier(userProfile),
          ),
        ],
      );

      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify 'Business Ledger Workspace' tile is displayed
      final upgradeTile = find.byKey(const Key('upgrade_to_business_ledger_tile'));
      expect(upgradeTile, findsOneWidget);
      expect(find.text('Business Ledger Workspace'), findsOneWidget);
      expect(find.textContaining('Workspace types are immutable'), findsOneWidget);

      // 2. Tap tile
      await tester.tap(upgradeTile);
      await tester.pumpAndSettle();

      // 3. Verify explanation dialog appears explaining immutability
      expect(find.textContaining('enforces immutable workspace types'), findsOneWidget);
      expect(find.textContaining('cannot be converted into a Business Ledger'), findsOneWidget);
      expect(find.textContaining('remain completely intact'), findsOneWidget);
      expect(find.byKey(const Key('cancel_upgrade_button')), findsOneWidget);
      expect(find.byKey(const Key('confirm_upgrade_button')), findsOneWidget);

      // 4. Cancel dismisses without changing anything
      await tester.tap(find.byKey(const Key('cancel_upgrade_button')));
      await tester.pumpAndSettle();

      final activeComp = container.read(activeCompanyProvider);
      expect(activeComp.mode, equals(CompanyMode.expenseTracker));
    });
  });
}
