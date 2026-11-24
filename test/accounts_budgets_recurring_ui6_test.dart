import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/core/widgets/adaptive_chip.dart';
import 'package:ledger_pulse/core/widgets/adaptive_controls.dart';
import 'package:ledger_pulse/core/widgets/amount_text.dart';
import 'package:ledger_pulse/core/widgets/adaptive_list_row.dart';
import 'package:ledger_pulse/core/widgets/adaptive_surface_card.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_budget_repository.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/recurring_rule_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/data/services/recurring_service.dart';
import 'package:ledger_pulse/presentation/expense/accounts_screen.dart';
import 'package:ledger_pulse/presentation/expense/budgets_screen.dart';
import 'package:ledger_pulse/presentation/expense/quick_add_transaction_sheet.dart';
import 'package:ledger_pulse/presentation/expense/recurring_screen.dart';
import 'package:ledger_pulse/presentation/providers/budget_providers.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/database_providers.dart';
import 'package:ledger_pulse/presentation/providers/expense_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';
import 'package:ledger_pulse/presentation/providers/recurring_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuditService auditService;
  late VoucherPostingEngine postingEngine;
  late DriftVoucherRepository voucherRepo;
  late DriftExpenseRepository expenseRepo;
  late DriftBudgetRepository budgetRepo;
  late RecurringService recurringService;

  const testCompanyId = 'cmp_ui6_test';
  final now = DateTime(2026, 10, 15, 12, 0);

  final enabledCompany = Company(
    id: testCompanyId,
    name: 'Pulse Test Co',
    legalName: 'Pulse Test LLC',
    currencyCode: 'INR',
    mode: CompanyMode.expenseTracker,
    enabledModules: const {
      AppModule.vouchers,
      AppModule.budgets,
      AppModule.recurring,
    },
    createdAt: now,
    updatedAt: now,
  );

  final testProfile = UserProfile(
    id: 'usr_ui6_tester',
    name: 'UI6 Tester',
    phoneNumber: '+91 99999 33333',
    email: 'ui6@example.com',
    companies: [enabledCompany],
    activeCompanyId: enabledCompany.id,
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auditService = AuditService(db);
    postingEngine = VoucherPostingEngine(db, auditService);
    voucherRepo = DriftVoucherRepository(
      db: db,
      auditService: auditService,
      postingEngine: postingEngine,
      currentCompanyId: testCompanyId,
    );
    expenseRepo = DriftExpenseRepository(
      db: db,
      voucherRepo: voucherRepo,
      postingEngine: postingEngine,
      auditService: auditService,
      currentCompanyId: testCompanyId,
      company: enabledCompany,
    );
    budgetRepo = DriftBudgetRepository(
      db: db,
      auditService: auditService,
      currentCompanyId: testCompanyId,
      company: enabledCompany,
    );
    recurringService = RecurringService(
      db: db,
      expenseRepo: expenseRepo,
      auditService: auditService,
      currentCompanyId: testCompanyId,
      company: enabledCompany,
    );

    // Seed company in DB
    await db
        .into(db.companies)
        .insert(
          CompaniesCompanion.insert(
            id: enabledCompany.id,
            name: enabledCompany.name,
            legalName: enabledCompany.legalName,
            mode: Value(enabledCompany.mode.name),
            enabledModulesJson: const Value(
              '["vouchers","budgets","recurring"]',
            ),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    // Seed chart of accounts
    await postingEngine.seedAccountsFor(
      enabledCompany,
      initialWalletBalancesInCents: {
        ExpenseTrackerDefaults.walletCashId: 500000,
        ExpenseTrackerDefaults.walletBankId: 800000,
      },
    );
  });

  tearDown(() async {
    budgetRepo.dispose();
    recurringService.dispose();
    expenseRepo.dispose();
    await db.close();
  });

  Widget buildTestScope({
    required Widget child,
    TargetPlatform platform = TargetPlatform.android,
  }) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        syncEngineProvider.overrideWithValue(_FakeSyncEngineForUi6(db: db)),
        activeCompanyProvider.overrideWithValue(enabledCompany),
        userProfileProvider.overrideWith(
          () => _TestUi6ProfileNotifier(testProfile),
        ),
        expenseRepositoryProvider.overrideWithValue(expenseRepo),
        budgetRepositoryProvider.overrideWithValue(budgetRepo),
        recurringServiceProvider.overrideWithValue(recurringService),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        home: Scaffold(body: child),
      ),
    );
  }

  group('Prompt UI-6 - Accounts Screen (Wallets & Categories)', () {
    testWidgets('Wallet menu sets the default for a new transaction', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final wallet = await expenseRepo.createWallet(
        name: 'Preferred Wallet',
        type: AccountType.asset,
        openingBalanceInCents: 0,
      );
      await tester.pumpWidget(
        buildTestScope(child: const ExpenseAccountsScreen(initialTab: 1)),
      );
      await tester.pumpAndSettle();
      final menu = find.byKey(Key('wallet_menu_${wallet.id}'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set as default wallet'));
      await tester.pumpAndSettle();
      expect(find.text('Asset Wallet · Default'), findsOneWidget);

      final sheet = QuickAddTransactionSheet.show(
        tester.element(find.byType(ExpenseAccountsScreen)),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AdaptiveChip>(find.byKey(Key('wallet_chip_${wallet.id}')))
            .isSelected,
        isTrue,
      );
      Navigator.of(tester.element(find.byType(QuickAddTransactionSheet))).pop();
      await tester.pumpAndSettle();
      await sheet;
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear default wallet'));
      await tester.pumpAndSettle();
      expect(await expenseRepo.getDefaultWalletId(), isNull);
    });

    testWidgets('Saved category drag order appears in Quick Add', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final first = await expenseRepo.createCategory(
        name: 'A Priority Example',
        type: AccountType.expense,
      );
      final second = await expenseRepo.createCategory(
        name: 'B Priority Example',
        type: AccountType.expense,
      );
      await tester.pumpWidget(
        buildTestScope(child: const ExpenseAccountsScreen(initialTab: 2)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arrange'));
      await tester.pumpAndSettle();

      final handle = find.byTooltip('Reorder B Priority Example');
      final from = tester.getCenter(handle);
      final target = tester.getTopLeft(find.text('A Priority Example')).dy;
      final gesture = await tester.startGesture(from);
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      await gesture.moveTo(Offset(from.dx, target - 62));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text(second.name)).dy,
        lessThan(tester.getTopLeft(find.text(first.name)).dy),
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text(second.name)).dy,
        lessThan(tester.getTopLeft(find.text(first.name)).dy),
      );
      final transactionSheet = QuickAddTransactionSheet.show(
        tester.element(find.byType(ExpenseAccountsScreen)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(Key('cat_chip_${second.id}'))).dx,
        lessThan(tester.getTopLeft(find.byKey(Key('cat_chip_${first.id}'))).dx),
      );
      final more = find.byKey(const Key('cat_chip_more'));
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text(second.name).hitTestable()).dy,
        lessThan(tester.getTopLeft(find.text(first.name).hitTestable()).dy),
      );
      Navigator.of(tester.element(find.text('Select Category'))).pop();
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(QuickAddTransactionSheet))).pop();
      await tester.pumpAndSettle();
      await transactionSheet;
    });

    testWidgets(
      'Add wallet sheet with AdaptiveChip liability and opening balance',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          buildTestScope(
            child: Builder(
              builder: (context) => Consumer(
                builder: (ctx, ref, _) => ElevatedButton(
                  onPressed: () =>
                      ExpenseAccountsScreen.showAddAccountOrCategoryDialog(
                        context,
                        ref,
                      ),
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Tap 'Add Wallet'
        await tester.tap(find.text('Add Wallet'));
        await tester.pumpAndSettle();

        expect(find.text('Add Wallet'), findsOneWidget);
        expect(find.byKey(const Key('wallet_name_input')), findsOneWidget);
        expect(find.text('Asset (Cash/Bank)'), findsOneWidget);
        expect(find.text('Liability (Card)'), findsOneWidget);

        // Enter name
        await tester.enterText(
          find.byKey(const Key('wallet_name_input')),
          'HDFC Credit Card',
        );
        // Select Liability
        await tester.tap(find.text('Liability (Card)'));
        await tester.pumpAndSettle();

        // Enter opening balance
        await tester.enterText(
          find.byKey(const Key('wallet_opening_balance_input')),
          '15000.00',
        );
        await tester.pumpAndSettle();

        // Tap Save Wallet
        await tester.ensureVisible(find.byKey(const Key('save_wallet_button')));
        await tester.tap(
          find.byKey(const Key('save_wallet_button')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // Verify wallet was created in repo
        final wallets = await expenseRepo.getWallets();
        final hdfc = wallets.firstWhere((w) => w.name == 'HDFC Credit Card');
        expect(hdfc.type, equals(AccountType.liability));
        expect(hdfc.currentBalanceInCents, equals(1500000));
      },
    );

    testWidgets(
      'Add category sheet with parent selection via AdaptiveDropdownField',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // First create a top-level category
        final parentCat = await expenseRepo.createCategory(
          name: 'Auto & Transport',
          type: AccountType.expense,
        );

        await tester.pumpWidget(
          buildTestScope(
            child: Builder(
              builder: (context) => Consumer(
                builder: (ctx, ref, _) => ElevatedButton(
                  onPressed: () =>
                      ExpenseAccountsScreen.showAddAccountOrCategoryDialog(
                        context,
                        ref,
                      ),
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Add Category'));
        await tester.pumpAndSettle();

        expect(find.text('Add Expense Category'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('category_name_input')),
          'Fuel / Petrol',
        );
        await tester.pumpAndSettle();

        // Tap parent dropdown
        expect(find.text('Parent Category'), findsOneWidget);
        await tester.tap(find.text('Parent Category'));
        await tester.pumpAndSettle();

        // Select parent from picker
        await tester.tap(find.text('Auto & Transport').last);
        await tester.pumpAndSettle();

        // Save category
        await tester.ensureVisible(
          find.byKey(const Key('save_category_button')),
        );
        await tester.tap(
          find.byKey(const Key('save_category_button')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        final categories = await expenseRepo.getCategories();
        final fuelCat = categories.firstWhere((c) => c.name == 'Fuel / Petrol');
        expect(fuelCat.parentAccountId, equals(parentCat.id));
      },
    );

    testWidgets(
      'Wallets overview subtracts credit owed and can hide balances',
      (tester) async {
        tester.view.physicalSize = const Size(500, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        // Create liability card
        await expenseRepo.createWallet(
          name: 'SBI Credit Card',
          type: AccountType.liability,
          openingBalanceInCents: 250000, // 2,500.00
        );

        await tester.pumpWidget(
          buildTestScope(
            child: const ExpenseAccountsScreen(
              initialTab: 1,
              isStandalone: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final total = find.byKey(const Key('wallets_total_balance'));
        expect(tester.widget<AmountText>(total).amountInCents, 1050000);
        expect(find.text('SBI Credit Card'), findsOneWidget);
        expect(find.text('Credit card'), findsOneWidget);
        expect(find.text('Owed'), findsOneWidget);
        await tester.tap(find.byTooltip('Hide balances'));
        await tester.pumpAndSettle();
        expect(total, findsNothing);
        expect(find.text('Where your money is held'), findsNothing);
        expect(find.byTooltip('Show balances'), findsOneWidget);
      },
    );

    testWidgets(
      'Wallet balance comparison and archive preserve the recorded balance',
      (tester) async {
        tester.view.physicalSize = const Size(500, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final wallet = (await expenseRepo.getWallets()).first;
        await tester.pumpWidget(
          buildTestScope(child: const ExpenseAccountsScreen(initialTab: 1)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('wallet_card_${wallet.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Check balance'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Actual balance'),
          (wallet.currentBalanceInCents / 100).toStringAsFixed(2),
        );
        await tester.pumpAndSettle();
        expect(find.text('Your recorded balance matches.'), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('wallet_menu_${wallet.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archive'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archive'));
        await tester.pumpAndSettle();
        expect((await expenseRepo.getWalletById(wallet.id)).isActive, isFalse);
        expect(
          tester
              .widget<AmountText>(
                find.byKey(const Key('wallets_total_balance')),
              )
              .amountInCents,
          1300000 - wallet.currentBalanceInCents,
        );

        await tester.tap(find.text('Archived wallets'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(wallet.name));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restore'));
        await tester.pumpAndSettle();
        final restored = await expenseRepo.getWalletById(wallet.id);
        expect(restored.isActive, isTrue);
        expect(restored.currentBalanceInCents, wallet.currentBalanceInCents);
      },
    );

    testWidgets(
      'Wallet transfer previews both balances and records one transfer',
      (tester) async {
        tester.view.physicalSize = const Size(500, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final wallets = await expenseRepo.getWallets();
        final source = wallets.first;
        final destination = wallets.last;
        await tester.pumpWidget(
          buildTestScope(child: const ExpenseAccountsScreen(initialTab: 1)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Add wallet'), findsOneWidget);
        expect(find.text('Activity'), findsOneWidget);
        await tester.tap(find.text('Transfer'));
        await tester.pumpAndSettle();
        final amount = find.byKey(const Key('wallet_transfer_amount'));
        await tester.enterText(amount, '100');
        tester.testTextInput.hide();

        Future<void> choose(String label, String name) async {
          final field = find.widgetWithText(
            AdaptiveDropdownField<String>,
            label,
          );
          await tester.ensureVisible(field);
          await tester.tap(field);
          await tester.pumpAndSettle();
          await tester.tap(find.text(name).last);
          await tester.pumpAndSettle();
        }

        await choose('From wallet', source.name);
        await choose('To wallet', destination.name);
        expect(find.text('Balance after transfer'), findsOneWidget);
        expect(
          find.text('Total wallet balance stays the same.'),
          findsOneWidget,
        );
        final confirm = find.byKey(const Key('confirm_wallet_transfer'));
        await tester.ensureVisible(confirm);
        await tester.tap(find.text('Confirm transfer'));
        await tester.pumpAndSettle();

        final transfer = (await expenseRepo.getTransactions()).single;
        expect(transfer.type, VoucherType.transfer);
        expect(transfer.walletAccountId, source.id);
        expect(transfer.toWalletAccountId, destination.id);
        expect(
          (await expenseRepo.getWalletById(source.id)).currentBalanceInCents,
          source.currentBalanceInCents - 10000,
        );
        expect(
          (await expenseRepo.getWalletById(
            destination.id,
          )).currentBalanceInCents,
          destination.currentBalanceInCents + 10000,
        );
      },
    );

    testWidgets(
      'Categories tab renders AdaptiveListRow with parent/child and archive dialog',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final parent = await expenseRepo.createCategory(
          name: 'Live Concerts',
          type: AccountType.expense,
        );
        await expenseRepo.createCategory(
          name: 'Indie Music',
          type: AccountType.expense,
          parentAccountId: parent.id,
        );
        final retiredIncome = await expenseRepo.createCategory(
          name: 'Retired Income',
          type: AccountType.income,
        );
        await expenseRepo.updateCategory(id: retiredIncome.id, isActive: false);
        final removed = await expenseRepo.createCategory(
          name: 'Removed Category',
          type: AccountType.expense,
        );
        expect(await expenseRepo.deleteCategory(removed.id), isTrue);

        await tester.pumpWidget(
          buildTestScope(child: const ExpenseAccountsScreen()),
        );
        await tester.pumpAndSettle();

        // Switch to Category tab
        await tester.tap(find.text('Category'));
        await tester.pumpAndSettle();

        // Verify AdaptiveListRow is used
        expect(find.byType(AdaptiveListRow), findsWidgets);
        expect(find.text('Live Concerts'), findsOneWidget);
        expect(find.text('Indie Music'), findsOneWidget);

        // Open 3-dot menu on parent
        final menuBtn = find.descendant(
          of: find.byKey(Key('cat_dismiss_${parent.id}')),
          matching: find.byIcon(Icons.more_vert),
        );
        expect(menuBtn, findsOneWidget);
        await tester.tap(menuBtn);
        await tester.pumpAndSettle();

        // Tap delete button in menu
        final deleteBtn = find.byKey(Key('delete_cat_${parent.id}'));
        expect(deleteBtn, findsOneWidget);
        await tester.tap(deleteBtn);
        await tester.pumpAndSettle();

        // Confirmation dialog appears
        expect(find.text('Delete Category?'), findsOneWidget);
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        // Verify deleted from repo
        final remaining = await expenseRepo.getCategories();
        expect(remaining.any((c) => c.id == parent.id), isFalse);

        await tester.tap(find.text('View archive'));
        await tester.pumpAndSettle();

        expect(find.text('Archived Categories'), findsOneWidget);
        expect(find.text('Retired Income'), findsOneWidget);
        expect(find.text('Live Concerts'), findsOneWidget);
        expect(find.text('Indie Music'), findsNothing);
        expect(find.text('Removed Category'), findsNothing);

        await tester.tap(find.text('Retired Income'));
        await tester.pumpAndSettle();
        expect(find.text('Restore category?'), findsOneWidget);
        await tester.tap(find.text('Restore'));
        await tester.pumpAndSettle();
        expect(find.text('Retired Income'), findsNothing);
        expect(
          (await expenseRepo.getCategoryById(retiredIncome.id)).isActive,
          isTrue,
        );
      },
    );
  });

  group('Prompt UI-6 - Budgets Screen & Thresholds', () {
    testWidgets(
      'Add budget sheet with category picker, period segmented, and rollover switch',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final cat = await expenseRepo.createCategory(
          name: 'Dining Out',
          type: AccountType.expense,
        );

        await tester.pumpWidget(buildTestScope(child: const BudgetsScreen()));
        await tester.pumpAndSettle();

        // Tap 'Set First Budget'
        await tester.tap(find.text('Set First Budget'));
        await tester.pumpAndSettle();

        expect(find.text('Set Budget'), findsWidgets);
        expect(find.byKey(const Key('budget_category_field')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('budget_amount_field')),
            matching: find.text('\u20B9'),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('budget_period_selector')), findsOneWidget);
        expect(find.byKey(const Key('budget_rollover_switch')), findsOneWidget);

        // Select category
        await tester.tap(find.byKey(const Key('budget_category_field')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(cat.name).last);
        await tester.pumpAndSettle();

        // Enter amount
        await tester.enterText(
          find.byKey(const Key('budget_amount_field')),
          '8000.00',
        );
        await tester.pumpAndSettle();

        // Select Monthly
        await tester.tap(find.text('Monthly'));
        await tester.pumpAndSettle();

        // Toggle Rollover
        await tester.tap(find.byKey(const Key('budget_rollover_switch')));
        await tester.pumpAndSettle();

        // Save budget
        await tester.ensureVisible(find.byKey(const Key('save_budget_button')));
        await tester.tap(
          find.byKey(const Key('save_budget_button')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        final budgets = await budgetRepo.getBudgets();
        expect(budgets.length, 1);
        expect(budgets.first.allocatedInCents, 800000);
        expect(budgets.first.rolloverEnabled, isTrue);
      },
    );

    testWidgets('Budgets progress bar threshold colors on Android platform', (
      tester,
    ) async {
      final wallet = await expenseRepo.createWallet(
        name: 'Cash',
        type: AccountType.asset,
      );
      final catNormal = await expenseRepo.createCategory(
        name: 'Books',
        type: AccountType.expense,
      );
      final catWarning = await expenseRepo.createCategory(
        name: 'Electronics',
        type: AccountType.expense,
      );
      final catExceeded = await expenseRepo.createCategory(
        name: 'Travel',
        type: AccountType.expense,
      );

      // Books: spent 300 of 1000 (30% -> normal income color)
      await budgetRepo.createBudget(
        categoryId: catNormal.id,
        amountInCents: 100000,
      );
      await expenseRepo.addExpense(
        walletAccountId: wallet.id,
        categoryAccountId: catNormal.id,
        amountInCents: 30000,
        date: now,
      );

      // Electronics: spent 850 of 1000 (85% -> amber warning)
      await budgetRepo.createBudget(
        categoryId: catWarning.id,
        amountInCents: 100000,
      );
      await expenseRepo.addExpense(
        walletAccountId: wallet.id,
        categoryAccountId: catWarning.id,
        amountInCents: 85000,
        date: now,
      );

      // Travel: spent 1200 of 1000 (120% -> expense red)
      await budgetRepo.createBudget(
        categoryId: catExceeded.id,
        amountInCents: 100000,
      );
      await expenseRepo.addExpense(
        walletAccountId: wallet.id,
        categoryAccountId: catExceeded.id,
        amountInCents: 120000,
        date: now,
      );

      await tester.pumpWidget(
        buildTestScope(
          child: const BudgetsScreen(),
          platform: TargetPlatform.android,
        ),
      );
      await tester.pumpAndSettle();

      // On Android, LinearProgressIndicator is used
      final progressIndicators = find.byType(LinearProgressIndicator);
      expect(progressIndicators, findsWidgets);

      expect(
        find.byKey(const Key('overall_budget_card_monthly')),
        findsOneWidget,
      );
      expect(find.byType(AdaptiveSurfaceCard), findsWidgets);
    });

    testWidgets('Budgets progress bar threshold colors on iOS platform', (
      tester,
    ) async {
      final wallet = await expenseRepo.createWallet(
        name: 'Cash',
        type: AccountType.asset,
      );
      final cat = await expenseRepo.createCategory(
        name: 'Coffee',
        type: AccountType.expense,
      );

      await budgetRepo.createBudget(categoryId: cat.id, amountInCents: 50000);
      await expenseRepo.addExpense(
        walletAccountId: wallet.id,
        categoryAccountId: cat.id,
        amountInCents: 20000,
        date: now,
      );

      await tester.pumpWidget(
        buildTestScope(
          child: const BudgetsScreen(),
          platform: TargetPlatform.iOS,
        ),
      );
      await tester.pumpAndSettle();

      // On iOS, custom rounded capsule is used (not LinearProgressIndicator)
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.byKey(const Key('overall_budget_card_monthly')),
        findsOneWidget,
      );
    });
  });

  group('Prompt UI-6 - Recurring Transactions Screen', () {
    testWidgets('RecurringScreen saves category edits and supports pausing', (
      tester,
    ) async {
      final wallet = await expenseRepo.createWallet(
        name: 'Bank',
        type: AccountType.asset,
      );
      final cat = await expenseRepo.createCategory(
        name: 'Subscriptions',
        type: AccountType.expense,
      );
      final newCategory = await expenseRepo.createCategory(
        name: 'Software',
        type: AccountType.expense,
      );

      final rule = await recurringService.createRule(
        template: RecurringTemplate(
          type: VoucherType.expense,
          amountInCents: 99900,
          walletAccountId: wallet.id,
          categoryAccountId: cat.id,
          notes: 'Cloud Storage',
        ),
        interval: RecurringIntervalType.monthly,
        nextRunDate: DateTime(2026, 11, 1, 14, 30),
      );

      await tester.pumpWidget(buildTestScope(child: const RecurringScreen()));
      await tester.pumpAndSettle();

      // Rule card rendered
      expect(find.byKey(Key('recurring_rule_card_${rule.id}')), findsOneWidget);
      expect(find.text('Cloud Storage'), findsOneWidget);
      expect(find.textContaining('Next: Nov 1, 2026'), findsOneWidget);
      expect(find.textContaining('2:30'), findsOneWidget);
      expect(find.text('Category: Subscriptions'), findsOneWidget);
      expect(find.textContaining('Monthly'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('edit_rule_${rule.id}')));
      await tester.pumpAndSettle();
      final categoryField = find.byKey(const Key('recurring_category_field'));
      await tester.ensureVisible(categoryField);
      await tester.tap(categoryField);
      await tester.pumpAndSettle();
      final softwareOption = find.text('Software');
      await tester.ensureVisible(softwareOption);
      await tester.tap(softwareOption);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Category: Software'), findsOneWidget);
      expect(
        (await recurringService.getRuleById(
          rule.id,
        )).template.categoryAccountId,
        newCategory.id,
      );

      // Toggle active state
      final toggleSwitch = find.byKey(Key('toggle_rule_${rule.id}'));
      expect(toggleSwitch, findsOneWidget);

      await tester.tap(toggleSwitch);
      await tester.pumpAndSettle();

      final updatedRule = await recurringService.getRuleById(rule.id);
      expect(updatedRule.isActive, isFalse);
    });

    testWidgets('Recurring rule deletion via popup menu and confirm dialog', (
      tester,
    ) async {
      final wallet = await expenseRepo.createWallet(
        name: 'Bank',
        type: AccountType.asset,
      );
      final cat = await expenseRepo.createCategory(
        name: 'Gym',
        type: AccountType.expense,
      );

      final rule = await recurringService.createRule(
        template: RecurringTemplate(
          type: VoucherType.expense,
          amountInCents: 200000,
          walletAccountId: wallet.id,
          categoryAccountId: cat.id,
          notes: 'Gym Membership',
        ),
        interval: RecurringIntervalType.monthly,
        nextRunDate: DateTime(2026, 11, 1),
      );

      await tester.pumpWidget(buildTestScope(child: const RecurringScreen()));
      await tester.pumpAndSettle();

      // Open popup menu on the rule card
      final moreBtn = find.byIcon(Icons.more_vert);
      expect(moreBtn, findsOneWidget);
      await tester.tap(moreBtn);
      await tester.pumpAndSettle();

      // Tap Delete
      final deleteOption = find.byKey(Key('delete_rule_${rule.id}'));
      expect(deleteOption, findsOneWidget);
      await tester.tap(deleteOption);
      await tester.pumpAndSettle();

      // Confirmation dialog appears
      expect(find.text('Delete Automation'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Verify rule removed
      final rules = await recurringService.getRules();
      expect(rules.any((r) => r.id == rule.id), isFalse);
    });
  });
}

class _FakeSyncEngineForUi6 extends SyncEngine {
  _FakeSyncEngineForUi6({required super.db});

  @override
  Future<SyncResult> pushQueue({String? companyId}) async {
    return SyncResult(success: true, itemsPushed: 0, timestamp: DateTime.now());
  }
}

class _TestUi6ProfileNotifier extends UserProfileNotifier {
  final UserProfile _initial;
  _TestUi6ProfileNotifier(this._initial);

  @override
  UserProfile build() => _initial;

  @override
  void updateProfile(UserProfile updated) {
    state = updated;
  }
}
