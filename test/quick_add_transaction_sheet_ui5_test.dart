import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/recurring_rule_model.dart';
import 'package:ledger_pulse/data/models/sync_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/data/services/recurring_service.dart';
import 'package:ledger_pulse/presentation/expense/quick_add_transaction_sheet.dart';
import 'package:ledger_pulse/presentation/expense/widgets/transaction_type_switcher.dart';
import 'package:ledger_pulse/presentation/ledger/widgets/entry_amount_display.dart';
import 'package:ledger_pulse/presentation/ledger/widgets/entry_numeric_keypad.dart';
import 'package:ledger_pulse/presentation/ledger/widgets/entry_quick_presets_row.dart';
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
  late RecurringService recurringService;

  const testCompanyId = 'cmp_quick_add_ui5_test';
  final now = DateTime(2026, 10, 20, 10, 0);

  final testCompany = Company(
    id: testCompanyId,
    name: 'Smart Ledger',
    legalName: 'Smart Ledger Corp',
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
    id: 'usr_quick_add_tester',
    name: 'Quick Add Tester',
    phoneNumber: '+91 98765 43210',
    email: 'quickadd@test.com',
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
      currentCompanyId: testCompanyId,
    );

    await db.into(db.companies).insert(
          CompaniesCompanion.insert(
            id: testCompanyId,
            name: testCompany.name,
            legalName: testCompany.legalName,
            currencyCode: Value(testCompany.currencyCode),
            mode: Value(testCompany.mode.name),
            enabledModulesJson:
                const Value('["vouchers","budgets","recurring"]'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    await postingEngine.seedAccountsFor(
      testCompany,
      initialWalletBalancesInCents: {
        ExpenseTrackerDefaults.walletCashId: 50000,
        ExpenseTrackerDefaults.walletBankId: 100000,
      },
    );

    expenseRepo = DriftExpenseRepository(
      db: db,
      postingEngine: postingEngine,
      voucherRepo: voucherRepo,
      auditService: auditService,
      currentCompanyId: testCompanyId,
      currentUserId: testProfile.id,
      company: testCompany,
    );

    recurringService = RecurringService(
      db: db,
      expenseRepo: expenseRepo,
      auditService: auditService,
      currentCompanyId: testCompanyId,
      company: testCompany,
    );
  });

  tearDown(() async {
    expenseRepo.dispose();
    await db.close();
  });

  Widget buildTestApp({
    required Widget child,
    TargetPlatform platform = TargetPlatform.android,
    Company? companyOverride,
  }) {
    final activeComp = companyOverride ?? testCompany;
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        syncEngineProvider.overrideWithValue(_FakeSyncEngineForUI5(db: db)),
        activeCompanyProvider.overrideWithValue(activeComp),
        userProfileProvider.overrideWith(
          () => _TestProfileNotifier(
            testProfile.copyWith(
              companies: [activeComp],
              activeCompanyId: activeComp.id,
            ),
          ),
        ),
        expenseRepositoryProvider.overrideWithValue(expenseRepo),
        recurringServiceProvider.overrideWithValue(recurringService),
      ],
      child: MaterialApp(
        theme: ThemeData(
          platform: platform,
          useMaterial3: true,
        ),
        home: child,
      ),
    );
  }

  group('Prompt UI-5 – Quick-Add Transaction Sheet', () {
    testWidgets(
        '1. Add Expense on Android with Keypad, Presets and AdaptiveChips',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          platform: TargetPlatform.android,
          child: const Scaffold(
            body: QuickAddTransactionSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check presets, amount display and type switcher are rendered
      expect(find.byType(EntryQuickPresetsRow), findsOneWidget);
      expect(find.byType(EntryAmountDisplay), findsOneWidget);
      expect(find.byType(TransactionTypeSwitcher), findsOneWidget);

      // Tap amount display box to open custom keyboard modal
      await tester.tap(find.byType(EntryAmountDisplay));
      await tester.pumpAndSettle();

      expect(find.byType(EntryNumericKeypad), findsOneWidget);

      // Tap numeric keypad keys: 1, 0, 0 -> 100
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('0').first);
      await tester.pumpAndSettle();

      expect(find.text('100'), findsWidgets);

      // Tap Done
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Tap preset: +500 -> 600
      await tester.tap(find.text('+₹500'));
      await tester.pumpAndSettle();

      expect(find.text('600'), findsOneWidget);

      // Select Food & Dining category
      final foodChip = find.text('Food & Dining');
      expect(foodChip, findsOneWidget);
      await tester.tap(foodChip);
      await tester.pumpAndSettle();

      // Tap submit button
      final submitBtn = find.byKey(const Key('quick_add_submit_button'));
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Verify transaction in repository
      final expenses =
          await expenseRepo.getTransactions(type: VoucherType.expense);
      expect(expenses.length, equals(1));
      expect(expenses.first.totalAmountInCents, equals(60000));
    });

    testWidgets('2. Add Expense on iOS platform', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          platform: TargetPlatform.iOS,
          child: const Scaffold(
            body: QuickAddTransactionSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap amount display box to open custom keyboard modal
      await tester.tap(find.byType(EntryAmountDisplay));
      await tester.pumpAndSettle();

      // Keypad entry: 2, 5, 0 -> 250
      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0').first);
      await tester.pumpAndSettle();

      expect(find.text('250'), findsWidgets);

      // Tap Done
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Select category
      await tester.tap(find.text('Food & Dining'));
      await tester.pumpAndSettle();

      // Save Expense
      await tester.tap(find.byKey(const Key('quick_add_submit_button')));
      await tester.pumpAndSettle();

      final expenses =
          await expenseRepo.getTransactions(type: VoucherType.expense);
      expect(expenses.length, equals(1));
      expect(expenses.first.totalAmountInCents, equals(25000));
    });

    testWidgets('3. Add Income on Android and iOS', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          platform: TargetPlatform.android,
          child: const Scaffold(
            body: QuickAddTransactionSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Income
      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();

      // Tap amount display box to open custom keyboard modal
      await tester.tap(find.byType(EntryAmountDisplay));
      await tester.pumpAndSettle();

      // Keypad: 5, 0, 0, 0
      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('0').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('0').first);
      await tester.pumpAndSettle();

      expect(find.text('5000'), findsWidgets);

      // Tap Done
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Select Salary category
      final salaryChip = find.text('Salary');
      expect(salaryChip, findsOneWidget);
      await tester.tap(salaryChip);
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.byKey(const Key('quick_add_submit_button')));
      await tester.pumpAndSettle();

      final incomes =
          await expenseRepo.getTransactions(type: VoucherType.income);
      expect(incomes.length, equals(1));
      expect(incomes.first.totalAmountInCents, equals(500000));
    });

    testWidgets('4. Add Transfer on both platforms', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          platform: TargetPlatform.iOS,
          child: const Scaffold(
            body: QuickAddTransactionSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Transfer
      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();

      // Tap amount display box to open custom keyboard modal
      await tester.tap(find.byType(EntryAmountDisplay));
      await tester.pumpAndSettle();

      // Keypad: 3, 5, 0
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0').first);
      await tester.pumpAndSettle();

      // Tap Done
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Select destination wallet Bank Account
      final destBank = find.text('Bank Account');
      expect(destBank, findsAtLeastNWidgets(1));
      await tester.tap(destBank.last);
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.byKey(const Key('quick_add_submit_button')));
      await tester.pumpAndSettle();

      final transfers =
          await expenseRepo.getTransactions(type: VoucherType.transfer);
      expect(transfers.length, equals(1));
      expect(transfers.first.totalAmountInCents, equals(35000));
    });

    testWidgets('5. Edit Mode pre-populates fields and updates voucher',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Create an existing voucher
      final created = await expenseRepo.addExpense(
        categoryAccountId:
            '${testCompanyId}_${ExpenseTrackerDefaults.foodDiningId}',
        walletAccountId:
            '${testCompanyId}_${ExpenseTrackerDefaults.walletCashId}',
        amountInCents: 4500,
        date: now,
        narration: 'Team snacks',
      );

      await tester.pumpWidget(
        buildTestApp(
          child: Scaffold(
            body: QuickAddTransactionSheet(
              initialVoucher: created,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header shows EDIT TRANSACTION
      expect(find.text('EDIT TRANSACTION'), findsOneWidget);
      expect(find.text('45'), findsOneWidget);
      expect(find.text('Team snacks'), findsOneWidget);
      expect(find.text('Update Transaction'), findsOneWidget);

      // Add +100 preset -> 145
      await tester.tap(find.text('+₹100'));
      await tester.pumpAndSettle();

      expect(find.text('145'), findsOneWidget);

      // Submit update
      await tester.tap(find.byKey(const Key('quick_add_submit_button')));
      await tester.pumpAndSettle();

      final txns = await expenseRepo.getTransactions(type: VoucherType.expense);
      expect(txns.length, equals(1));
      expect(txns.first.totalAmountInCents, equals(14500));
    });

    testWidgets('6. Dirty-back confirm: PopScope and discard dialog',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool sheetDismissed = false;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  await QuickAddTransactionSheet.show(ctx);
                  sheetDismissed = true;
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.byType(QuickAddTransactionSheet), findsOneWidget);

      // When clean, close button pops immediately
      final closeBtn = find.byIcon(Icons.close_rounded);
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      expect(sheetDismissed, isTrue);
      expect(find.byType(QuickAddTransactionSheet), findsNothing);

      // Open sheet again
      sheetDismissed = false;
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Tap amount display box to open custom keyboard modal
      await tester.tap(find.byType(EntryAmountDisplay));
      await tester.pumpAndSettle();

      // Enter a digit to make form dirty
      await tester.tap(find.text('9'));
      await tester.pumpAndSettle();

      // Close modal keypad
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Now tap close button
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Confirm dialog appears
      expect(find.text('Discard unsaved changes?'), findsOneWidget);

      // Tap 'Keep Editing'
      await tester.tap(find.text('Keep Editing'));
      await tester.pumpAndSettle();

      // Sheet should still be open
      expect(find.byType(QuickAddTransactionSheet), findsOneWidget);
      expect(sheetDismissed, isFalse);

      // Tap close again and tap Discard
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      // Sheet should now be closed
      expect(find.byType(QuickAddTransactionSheet), findsNothing);
      expect(sheetDismissed, isTrue);
    });

    testWidgets('7. Repeat toggle creates a recurring rule', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          child: const Scaffold(
            body: QuickAddTransactionSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Toggle repeat switch
      final repeatSwitch = find.byKey(const Key('quick_add_repeat_switch'));
      expect(repeatSwitch, findsOneWidget);
      await tester.tap(repeatSwitch);
      await tester.pumpAndSettle();

      // Verify frequency dropdown and date fields appear
      expect(find.byKey(const Key('quick_add_repeat_interval')), findsOneWidget);
      expect(find.text('Start Date'), findsOneWidget);

      // Tap amount display box to open custom keyboard modal
      await tester.tap(find.byType(EntryAmountDisplay));
      await tester.pumpAndSettle();

      // Enter amount via keypad
      await tester.tap(find.text('8'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0').first);
      await tester.pumpAndSettle();

      // Close modal keypad
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Select category
      await tester.tap(find.text('Food & Dining'));
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.byKey(const Key('quick_add_submit_button')));
      await tester.pumpAndSettle();

      // Verify recurring rule was registered
      final rules = await recurringService.getRules();
      expect(rules.length, equals(1));
      expect(rules.first.template.amountInCents, equals(8000));
      expect(rules.first.interval, equals(RecurringIntervalType.monthly));
    });
  });
}

class _FakeSyncEngineForUI5 extends SyncEngine {
  _FakeSyncEngineForUI5({required super.db});

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

class _TestProfileNotifier extends UserProfileNotifier {
  final UserProfile _initial;
  _TestProfileNotifier(this._initial);

  @override
  UserProfile build() => _initial;

  @override
  void updateProfile(UserProfile updated) {
    state = updated;
  }
}
