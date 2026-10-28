import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/core/widgets/adaptive_chip.dart';
import 'package:ledger_pulse/core/widgets/adaptive_icon_surface_button.dart';
import 'package:ledger_pulse/core/widgets/adaptive_list_row.dart';
import 'package:ledger_pulse/core/widgets/adaptive_search_field.dart';
import 'package:ledger_pulse/core/widgets/adaptive_section_header.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/sync_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
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

  const expenseCompanyId = 'cmp_transactions_tab_test';
  final now = DateTime.now();

  final testCompany = Company(
    id: expenseCompanyId,
    name: 'Spender Pro',
    legalName: 'Spender Pro LLC',
    currencyCode: 'INR',
    mode: CompanyMode.expenseTracker,
    enabledModules: const {AppModule.vouchers, AppModule.budgets},
    createdAt: now,
    updatedAt: now,
  );

  final testProfile = UserProfile(
    id: 'usr_txn_tester',
    name: 'Txn Tester',
    phoneNumber: '+91 98888 11111',
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
      currentCompanyId: expenseCompanyId,
      currentUserId: testProfile.id,
      company: testCompany,
    );
  });

  tearDown(() async {
    expenseRepo.dispose();
    await db.close();
  });

  Widget buildApp({
    TargetPlatform platform = TargetPlatform.android,
    ProviderContainer? container,
  }) {
    final app = MaterialApp(
      theme: ThemeData(
        platform: platform,
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: ExpenseTransactionsScreen(),
      ),
    );

    if (container != null) {
      return UncontrolledProviderScope(
        container: container,
        child: app,
      );
    }

    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        syncEngineProvider.overrideWithValue(_FakeSyncEngineTxn(db: db)),
        activeCompanyProvider.overrideWithValue(testCompany),
        userProfileProvider.overrideWith(() => _TestProfileNotifierTxn(testProfile)),
        expenseRepositoryProvider.overrideWithValue(expenseRepo),
      ],
      child: app,
    );
  }

  group('Prompt UI-4 – Transactions Tab Matches Party List', () {
    testWidgets('renders top row, search field and filter button on both platforms',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // 1. Android
      await tester.pumpWidget(buildApp(platform: TargetPlatform.android));
      await tester.pumpAndSettle();

      expect(find.byType(AdaptiveSearchField), findsOneWidget);
      expect(find.byType(AdaptiveIconSurfaceButton), findsOneWidget);
      expect(find.byType(AdaptiveChipRow<VoucherType?>), findsOneWidget);

      // 2. iOS
      await tester.pumpWidget(buildApp(platform: TargetPlatform.iOS));
      await tester.pumpAndSettle();

      expect(find.byType(AdaptiveSearchField), findsOneWidget);
      expect(find.byType(AdaptiveIconSurfaceButton), findsOneWidget);
      expect(find.byType(AdaptiveChipRow<VoucherType?>), findsOneWidget);
    });

    testWidgets('day grouped headers and rows use AdaptiveSectionHeader & AdaptiveListRow',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final cashWalletId =
          '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}';
      final foodCatId =
          '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}';

      await expenseRepo.addExpense(
        categoryAccountId: foodCatId,
        walletAccountId: cashWalletId,
        amountInCents: 3500,
        narration: 'Dinner with Team',
        date: DateTime.now(),
      );

      await tester.pumpWidget(buildApp(platform: TargetPlatform.android));
      await tester.pumpAndSettle();

      expect(find.byType(AdaptiveSectionHeader), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.byType(AdaptiveListRow), findsOneWidget);
      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.textContaining('Dinner with Team'), findsOneWidget);
    });

    testWidgets('filter button shows active tint when filters are set',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngineTxn(db: db)),
          activeCompanyProvider.overrideWithValue(testCompany),
          userProfileProvider.overrideWith(() => _TestProfileNotifierTxn(testProfile)),
          expenseRepositoryProvider.overrideWithValue(expenseRepo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildApp(
        platform: TargetPlatform.android,
        container: container,
      ));
      await tester.pumpAndSettle();

      var filterButton = tester.widget<AdaptiveIconSurfaceButton>(
        find.byKey(const Key('transaction_filter_button')),
      );
      expect(filterButton.isActive, false);

      // Set category filter
      container.read(transactionFiltersProvider.notifier).updateFilters(
            const TransactionFilters(categoryIds: ['some_cat_id']),
          );
      await tester.pumpAndSettle();

      filterButton = tester.widget<AdaptiveIconSurfaceButton>(
        find.byKey(const Key('transaction_filter_button')),
      );
      expect(filterButton.isActive, true);
    });

    testWidgets('search filtering and PopScope predictive back clears search',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final cashWalletId =
          '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}';
      final foodCatId =
          '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}';
      final salaryCatId =
          '${expenseCompanyId}_${ExpenseTrackerDefaults.salaryId}';

      await expenseRepo.addExpense(
        categoryAccountId: foodCatId,
        walletAccountId: cashWalletId,
        amountInCents: 1500,
        narration: 'Coffee and Croissant',
        date: DateTime.now(),
      );

      await expenseRepo.addIncome(
        categoryAccountId: salaryCatId,
        walletAccountId: cashWalletId,
        amountInCents: 50000,
        narration: 'App Project Freelance',
        date: DateTime.now(),
      );

      await tester.pumpWidget(buildApp(platform: TargetPlatform.android));
      await tester.pumpAndSettle();

      expect(find.textContaining('Coffee and Croissant'), findsOneWidget);
      expect(find.textContaining('App Project Freelance'), findsOneWidget);

      // Enter search query
      final searchFinder = find.byKey(const Key('transaction_search_field'));
      await tester.enterText(searchFinder, 'Croissant');
      await tester.pumpAndSettle();

      expect(find.textContaining('Coffee and Croissant'), findsOneWidget);
      expect(find.textContaining('App Project Freelance'), findsNothing);

      // Trigger back via PopScope
      final popScopeFinder = find.byWidgetPredicate((w) => w is PopScope);
      expect(popScopeFinder, findsOneWidget);
      final popScope = tester.widget<PopScope>(popScopeFinder);
      expect(popScope.canPop, false); // Search is active

      // Invoke pop callback
      popScope.onPopInvokedWithResult?.call(false, null);
      await tester.pumpAndSettle();

      // Search cleared and both transactions visible again
      expect(find.textContaining('Coffee and Croissant'), findsOneWidget);
      expect(find.textContaining('App Project Freelance'), findsOneWidget);
    });

    testWidgets('swipe right-to-left triggers void confirmation and voids transaction',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final cashWalletId =
          '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}';
      final foodCatId =
          '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}';

      final txn = await expenseRepo.addExpense(
        categoryAccountId: foodCatId,
        walletAccountId: cashWalletId,
        amountInCents: 1200,
        narration: 'Quick Snack',
        date: DateTime.now(),
      );

      await tester.pumpWidget(buildApp(platform: TargetPlatform.android));
      await tester.pumpAndSettle();

      expect(find.textContaining('Quick Snack'), findsOneWidget);

      // Swipe right to left (endToStart)
      final dismissibleFinder = find.byKey(ValueKey('txn_${txn.id}'));
      expect(dismissibleFinder, findsOneWidget);

      await tester.drag(dismissibleFinder, const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Confirm dialog appears
      expect(find.text('Void Transaction?'), findsOneWidget);
      final confirmBtn = find.widgetWithText(FilledButton, 'Void');
      expect(confirmBtn, findsOneWidget);

      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Transaction is voided and removed from active list
      expect(find.textContaining('Quick Snack'), findsNothing);
    });

    testWidgets('swipe left-to-right opens quick add edit sheet',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final cashWalletId =
          '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}';
      final foodCatId =
          '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}';

      final txn = await expenseRepo.addExpense(
        categoryAccountId: foodCatId,
        walletAccountId: cashWalletId,
        amountInCents: 1200,
        narration: 'Quick Lunch',
        date: DateTime.now(),
      );

      await tester.pumpWidget(buildApp(platform: TargetPlatform.android));
      await tester.pumpAndSettle();

      // Swipe left to right (startToEnd)
      final dismissibleFinder = find.byKey(ValueKey('txn_${txn.id}'));
      await tester.drag(dismissibleFinder, const Offset(500, 0));
      await tester.pumpAndSettle();

      // Quick add sheet opened in edit mode
      expect(find.byType(QuickAddTransactionSheet), findsOneWidget);
    });
  });
}

class _FakeSyncEngineTxn extends SyncEngine {
  _FakeSyncEngineTxn({required super.db});

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

class _TestProfileNotifierTxn extends UserProfileNotifier {
  final UserProfile _initial;
  _TestProfileNotifierTxn(this._initial);

  @override
  UserProfile build() => _initial;

  @override
  void updateProfile(UserProfile updated) {
    state = updated;
  }
}
