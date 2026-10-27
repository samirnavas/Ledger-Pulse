import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/core/utils/currency_formatter.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/sync_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/presentation/expense/accounts_screen.dart';
import 'package:ledger_pulse/presentation/expense/expense_home_screen.dart';
import 'package:ledger_pulse/presentation/expense/quick_add_transaction_sheet.dart';
import 'package:ledger_pulse/presentation/expense/transactions_screen.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/database_providers.dart';
import 'package:ledger_pulse/presentation/providers/expense_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuditService auditService;
  late VoucherPostingEngine postingEngine;
  late DriftVoucherRepository voucherRepo;
  late DriftExpenseRepository expenseRepo;

  const expenseCompanyId = 'cmp_expense_ui_test';
  final now = DateTime(2026, 10, 15, 12, 0);

  final testCompany = Company(
    id: expenseCompanyId,
    name: 'Smart Spender',
    legalName: 'Smart Spender LLC',
    currencyCode: 'INR',
    mode: CompanyMode.expenseTracker,
    enabledModules: const {AppModule.vouchers, AppModule.budgets},
    createdAt: now,
    updatedAt: now,
  );

  final testProfile = UserProfile(
    id: 'usr_ui_tester',
    name: 'UI Tester',
    phoneNumber: '+91 99999 22222',
    email: 'tester@example.com',
    companies: [testCompany],
    activeCompanyId: testCompany.id,
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auditService = AuditService(db);
    postingEngine = VoucherPostingEngine(db, auditService);
    voucherRepo = DriftVoucherRepository(
      db: db,
      auditService: auditService,
      postingEngine: postingEngine,
      currentCompanyId: expenseCompanyId,
    );

    // Insert company into DB
    await db.into(db.companies).insert(
          CompaniesCompanion.insert(
            id: expenseCompanyId,
            name: testCompany.name,
            legalName: testCompany.legalName,
            currencyCode: Value(testCompany.currencyCode),
            mode: Value(testCompany.mode.name),
            enabledModulesJson: const Value('["vouchers","budgets"]'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    // Seed default chart of accounts with cash & bank balances
    await postingEngine.seedAccountsFor(
      testCompany,
      initialWalletBalancesInCents: {
        ExpenseTrackerDefaults.walletCashId: 40000, // 400.00
        ExpenseTrackerDefaults.walletBankId: 90000, // 900.00
      },
    );

    expenseRepo = DriftExpenseRepository(
      db: db,
      postingEngine: postingEngine,
      voucherRepo: voucherRepo,
      auditService: auditService,
      currentCompanyId: expenseCompanyId,
      currentUserId: testProfile.id,
      company: testCompany,
    );
  });

  tearDown(() async {
    expenseRepo.dispose();
    await db.close();
  });

  Widget buildTestApp({
    required Widget child,
    Company? companyOverride,
  }) {
    final activeComp = companyOverride ?? testCompany;
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        syncEngineProvider.overrideWithValue(_FakeSyncEngineForScreens(db: db)),
        activeCompanyProvider.overrideWithValue(activeComp),
        userProfileProvider.overrideWith(
          () => _TestScreensProfileNotifier(
            testProfile.copyWith(
              companies: [activeComp],
              activeCompanyId: activeComp.id,
            ),
          ),
        ),
        expenseRepositoryProvider.overrideWithValue(expenseRepo),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('Prompt 10 - Quick Add Transaction Sheet', () {
    testWidgets('Validation: shows error when submitting empty amount',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: const Scaffold(
            body: QuickAddTransactionSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap submit with empty amount
      final submitBtn = find.byKey(const Key('quick_add_submit_button'));
      expect(submitBtn, findsOneWidget);

      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(
        find.text('Please enter an amount greater than 0.'),
        findsOneWidget,
      );
    });

    testWidgets('Quick Add Expense: enters amount, taps category chip, saves expense in 3 taps',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: const Scaffold(
            body: QuickAddTransactionSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Enter amount
      final amountField = find.byKey(const Key('quick_add_amount_field'));
      expect(amountField, findsOneWidget);
      await tester.enterText(amountField, '120.50');
      await tester.pumpAndSettle();

      // 2. Tap Food & Dining category chip (Tap 1)
      final foodChip = find.text('Food & Dining');
      expect(foodChip, findsOneWidget);
      await tester.tap(foodChip);
      await tester.pumpAndSettle();

      // 3. Tap Save Expense button (Tap 2 - typical expense takes at most 3 taps)
      final submitBtn = find.byKey(const Key('quick_add_submit_button'));
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Verify transaction saved to repository
      final txns = await expenseRepo.getTransactions(type: VoucherType.expense);
      expect(txns.length, equals(1));
      expect(txns.first.totalAmountInCents, equals(12050));
    });

    testWidgets('Quick Add Income: selects income type, enters amount, saves income',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: const Scaffold(
            body: QuickAddTransactionSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Income
      final incomeSegment = find.text('Income');
      expect(incomeSegment, findsOneWidget);
      await tester.tap(incomeSegment);
      await tester.pumpAndSettle();

      // Enter amount
      final amountField = find.byKey(const Key('quick_add_amount_field'));
      await tester.enterText(amountField, '5000');
      await tester.pumpAndSettle();

      // Tap Salary category
      final salaryChip = find.text('Salary');
      expect(salaryChip, findsOneWidget);
      await tester.tap(salaryChip);
      await tester.pumpAndSettle();

      // Save
      final submitBtn = find.byKey(const Key('quick_add_submit_button'));
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Verify transaction saved as income
      final txns = await expenseRepo.getTransactions(type: VoucherType.income);
      expect(txns.length, equals(1));
      expect(txns.first.totalAmountInCents, equals(500000));
    });

    testWidgets('Quick Add Transfer: switches to transfer, selects source & destination wallets, saves transfer',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: const Scaffold(
            body: QuickAddTransactionSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Transfer
      final transferSegment = find.text('Transfer');
      await tester.tap(transferSegment);
      await tester.pumpAndSettle();

      // Enter amount
      await tester.enterText(
          find.byKey(const Key('quick_add_amount_field')), '150');
      await tester.pumpAndSettle();

      // Destination wallet chips should show available second wallet (e.g. Bank Account)
      final destBankChip = find.text('Bank Account');
      expect(destBankChip, findsAtLeastNWidgets(1));
      await tester.tap(destBankChip.last);
      await tester.pumpAndSettle();

      // Save Transfer
      await tester.tap(find.byKey(const Key('quick_add_submit_button')));
      await tester.pumpAndSettle();

      final txns = await expenseRepo.getTransactions(type: VoucherType.transfer);
      expect(txns.length, equals(1));
      expect(txns.first.totalAmountInCents, equals(15000));
    });
  });

  group('Prompt 10 - Transactions Screen & Filtering', () {
    testWidgets('TransactionsScreen renders grouped by day, filters by text and type',
        (tester) async {
      final cashWalletId =
          '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}';
      final foodCatId =
          '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}';
      final salaryCatId =
          '${expenseCompanyId}_${ExpenseTrackerDefaults.salaryId}';

      // Seed 2 transactions
      await expenseRepo.addExpense(
        categoryAccountId: foodCatId,
        walletAccountId: cashWalletId,
        amountInCents: 2400,
        narration: 'Italian Pasta',
        date: DateTime.now(),
      );

      await expenseRepo.addIncome(
        categoryAccountId: salaryCatId,
        walletAccountId: cashWalletId,
        amountInCents: 80000,
        narration: 'Freelance Design',
        date: DateTime.now(),
      );

      await tester.pumpWidget(
        buildTestApp(
          child: const ExpenseTransactionsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Day header and transactions present
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Italian Pasta'), findsOneWidget);
      expect(find.text('Freelance Design'), findsOneWidget);

      // Search filtering
      final searchField = find.byKey(const Key('transaction_search_field'));
      await tester.enterText(searchField, 'Pasta');
      await tester.pumpAndSettle();

      expect(find.text('Italian Pasta'), findsOneWidget);
      expect(find.text('Freelance Design'), findsNothing);

      // Clear search
      await tester.enterText(searchField, '');
      await tester.pumpAndSettle();

      // Filter by Type: Income
      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();

      expect(find.text('Freelance Design'), findsOneWidget);
      expect(find.text('Italian Pasta'), findsNothing);
    });

    testWidgets('TransactionsScreen displays EmptyStateView when no transactions match',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: const ExpenseTransactionsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('empty_transactions_view')), findsOneWidget);
      expect(find.text('No Transactions'), findsOneWidget);
    });
  });

  group('Prompt 10 - Accounts & Wallets Screen Basics', () {
    testWidgets('AccountsScreen shows wallets list, net balance, and opening balance editor',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: const ExpenseAccountsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Shows initial wallets
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Bank Account'), findsOneWidget);
      expect(find.text('Total Liquid Assets'), findsOneWidget);

      // Tap Set Opening Balance on Cash
      final cashWalletId =
          '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}';
      final editOpeningBtn =
          find.byKey(Key('edit_opening_btn_$cashWalletId'));
      expect(editOpeningBtn, findsOneWidget);

      await tester.tap(editOpeningBtn);
      await tester.pumpAndSettle();

      // Opening balance dialog is visible
      expect(find.text('Opening Balance: Cash'), findsOneWidget);
      final field = find.byKey(const Key('edit_opening_balance_field'));
      expect(field, findsOneWidget);

      await tester.enterText(field, '750.00');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('save_opening_balance_button')));
      await tester.pumpAndSettle();

      // Verified updated balance in repository
      final updatedCash = await expenseRepo.getWalletById(cashWalletId);
      expect(updatedCash.currentBalanceInCents, equals(75000));
    });

    testWidgets('AccountsScreen switches to Categories tab and shows Expense & Income categories',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: const ExpenseAccountsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Categories tab
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();

      // Default to Expense categories
      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);

      // Switch to Income Categories
      await tester.tap(find.text('Income Categories'));
      await tester.pumpAndSettle();

      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Other Income'), findsOneWidget);
    });
  });

  group('Prompt 10 - Non-INR Currencies End-to-End', () {
    testWidgets('CurrencyFormatter and screens format amounts with USD currency symbol and grouping',
        (tester) async {
      final usdCompany = testCompany.copyWith(
        currencyCode: 'USD',
      );

      // Verify CurrencyFormatter with USD
      final formatted = CurrencyFormatter.format(150000, currencyCode: 'USD');
      expect(formatted, contains('\$'));
      expect(formatted, contains('1,500.00'));

      final compact =
          CurrencyFormatter.formatCompact(250000000, currencyCode: 'USD');
      expect(compact, contains('2.5M'));

      // Render ExpenseHomeScreen with USD company
      await tester.pumpWidget(
        buildTestApp(
          child: const ExpenseHomeScreen(),
          companyOverride: usdCompany,
        ),
      );
      await tester.pumpAndSettle();

      // Verify total balance uses $ symbol
      expect(find.textContaining('\$'), findsAtLeastNWidgets(1));
    });
  });
}

class _FakeSyncEngineForScreens extends SyncEngine {
  _FakeSyncEngineForScreens({required super.db});

  @override
  Future<SyncResult> syncAll({String? companyId}) async {
    return SyncResult(
      success: true,
      itemsPushed: 0,
      itemsPulled: 0,
      timestamp: DateTime.now(),
    );
  }
}

class _TestScreensProfileNotifier extends UserProfileNotifier {
  final UserProfile _initial;
  _TestScreensProfileNotifier(this._initial);

  @override
  UserProfile build() => _initial;

  @override
  void updateProfile(UserProfile updated) {
    state = updated;
  }
}
