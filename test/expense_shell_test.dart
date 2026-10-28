import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/core/widgets/adaptive_scaffold.dart';
import 'package:ledger_pulse/core/widgets/spring_morphing_fab.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/sync_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/presentation/expense/expense_home_screen.dart';
import 'package:ledger_pulse/core/constants/colors.dart';
import 'package:ledger_pulse/core/constants/mode_strings.dart';
import 'package:ledger_pulse/core/widgets/adaptive_metric_card.dart';
import 'package:ledger_pulse/core/widgets/adaptive_section_header.dart';
import 'package:ledger_pulse/core/widgets/empty_state_view.dart';
import 'package:ledger_pulse/presentation/expense/widgets/category_breakdown_card.dart';
import 'package:ledger_pulse/presentation/expense/providers/expense_tab_controller.dart';
import 'package:ledger_pulse/presentation/expense/widgets/expense_sidebar_drawer.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/database_providers.dart';
import 'package:ledger_pulse/presentation/providers/expense_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';
import 'package:ledger_pulse/presentation/settings/settings_screen.dart';
import 'package:intl/intl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuditService auditService;
  late VoucherPostingEngine postingEngine;
  late DriftVoucherRepository voucherRepo;
  late DriftExpenseRepository expenseRepo;

  const expenseCompanyId = 'cmp_expense_shell_test';
  final now = DateTime(2026, 10, 15, 12, 0);

  final testCompany = Company(
    id: expenseCompanyId,
    name: 'Smart Spender',
    legalName: 'Smart Spender LLC',
    currencyCode: 'INR',
    mode: CompanyMode.expenseTracker,
    enabledModules: const {AppModule.vouchers, AppModule.budgets, AppModule.recurring},
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

    await db.into(db.companies).insert(
          CompaniesCompanion.insert(
            id: expenseCompanyId,
            name: testCompany.name,
            legalName: testCompany.legalName,
            currencyCode: Value(testCompany.currencyCode),
            mode: Value(testCompany.mode.name),
            enabledModulesJson: const Value('["vouchers","budgets","recurring"]'),
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

  Widget buildExpenseShellApp({
    TargetPlatform platform = TargetPlatform.android,
    ProviderContainer? container,
  }) {
    final overrides = [
      appDatabaseProvider.overrideWithValue(db),
      syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
      activeCompanyProvider.overrideWithValue(testCompany),
      userProfileProvider.overrideWith(
        () => _TestProfileNotifier(testProfile),
      ),
      expenseRepositoryProvider.overrideWithValue(expenseRepo),
    ];

    final app = MaterialApp(
      theme: ThemeData(
        platform: platform,
        useMaterial3: true,
      ),
      home: const ExpenseHomeScreen(),
    );

    if (container != null) {
      return UncontrolledProviderScope(
        container: container,
        child: app,
      );
    }

    return ProviderScope(
      overrides: overrides,
      child: app,
    );
  }

  group('Prompt UI-2 – Expense Shell Tests', () {
    testWidgets('shell shows AdaptiveScaffold on Android and iOS platforms', (tester) async {
      // 1. Android
      await tester.pumpWidget(buildExpenseShellApp(platform: TargetPlatform.android));
      await tester.pumpAndSettle();

      expect(find.byType(AdaptiveScaffold), findsOneWidget);
      expect(find.byKey(const Key('expense_company_switcher_button')), findsOneWidget);

      // 2. iOS
      await tester.pumpWidget(buildExpenseShellApp(platform: TargetPlatform.iOS));
      await tester.pumpAndSettle();

      expect(find.byType(AdaptiveScaffold), findsOneWidget);
      expect(find.byKey(const Key('expense_company_switcher_button')), findsOneWidget);
    });

    testWidgets('no nested Scaffold under tab bodies (count equals 1 for shell)', (tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          activeCompanyProvider.overrideWithValue(testCompany),
          userProfileProvider.overrideWith(() => _TestProfileNotifier(testProfile)),
          expenseRepositoryProvider.overrideWithValue(expenseRepo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildExpenseShellApp(
        platform: TargetPlatform.android,
        container: container,
      ));
      await tester.pumpAndSettle();

      // Exactly 1 Scaffold (the outer AdaptiveScaffold shell)
      expect(find.byType(Scaffold), findsOneWidget);

      // Switch through all tabs and assert only 1 Scaffold remains
      for (int i = 0; i < 5; i++) {
        container.read(expenseTabControllerProvider.notifier).setTab(i);
        await tester.pumpAndSettle();
        expect(find.byType(Scaffold), findsOneWidget);
      }
    });

    testWidgets('FAB on Android and nav "+" button on iOS', (tester) async {
      // 1. Android shows SpringMorphingFab
      await tester.pumpWidget(buildExpenseShellApp(platform: TargetPlatform.android));
      await tester.pumpAndSettle();

      expect(find.byType(SpringMorphingFab), findsOneWidget);
      expect(find.text('Add transaction'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.add), findsNothing);

      // 2. iOS shows CupertinoIcons.add in nav actions, NO FAB
      await tester.pumpWidget(buildExpenseShellApp(platform: TargetPlatform.iOS));
      await tester.pumpAndSettle();

      expect(find.byType(SpringMorphingFab), findsNothing);
      expect(find.byIcon(CupertinoIcons.add), findsOneWidget);
    });

    testWidgets('per-tab FAB labels on Android: Home/Txn -> Add transaction, Budgets -> Add budget, Accounts -> Add wallet/category', (tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          activeCompanyProvider.overrideWithValue(testCompany),
          userProfileProvider.overrideWith(() => _TestProfileNotifier(testProfile)),
          expenseRepositoryProvider.overrideWithValue(expenseRepo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildExpenseShellApp(
        platform: TargetPlatform.android,
        container: container,
      ));
      await tester.pumpAndSettle();

      // Tab 0 (Home): 'Add transaction'
      expect(find.text('Add transaction'), findsOneWidget);

      // Tab 1 (Transactions): 'Add transaction'
      container.read(expenseTabControllerProvider.notifier).setTab(1);
      await tester.pumpAndSettle();
      expect(find.text('Add transaction'), findsOneWidget);

      // Tab 2 (Budgets): 'Add budget'
      container.read(expenseTabControllerProvider.notifier).setTab(2);
      await tester.pumpAndSettle();
      expect(find.text('Add budget'), findsOneWidget);

      // Tab 3 (Reports): FAB hidden
      container.read(expenseTabControllerProvider.notifier).setTab(3);
      await tester.pumpAndSettle();
      expect(find.byType(SpringMorphingFab), findsNothing);

      // Tab 4 (Accounts): 'Add wallet/category'
      container.read(expenseTabControllerProvider.notifier).setTab(4);
      await tester.pumpAndSettle();
      expect(find.text('Add wallet/category'), findsOneWidget);
    });

    testWidgets('back navigation from tab 3 goes to tab 0', (tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          activeCompanyProvider.overrideWithValue(testCompany),
          userProfileProvider.overrideWith(() => _TestProfileNotifier(testProfile)),
          expenseRepositoryProvider.overrideWithValue(expenseRepo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildExpenseShellApp(
        platform: TargetPlatform.android,
        container: container,
      ));
      await tester.pumpAndSettle();

      // Switch to Tab 3 (Reports)
      container.read(expenseTabControllerProvider.notifier).setTab(3);
      await tester.pumpAndSettle();
      expect(container.read(expenseTabControllerProvider).currentIndex, equals(3));

      // Simulate system back button / pop request
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      // Verify returned to tab 0
      expect(container.read(expenseTabControllerProvider).currentIndex, equals(0));
    });

    testWidgets('back navigation closes drawer first if open', (tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          activeCompanyProvider.overrideWithValue(testCompany),
          userProfileProvider.overrideWith(() => _TestProfileNotifier(testProfile)),
          expenseRepositoryProvider.overrideWithValue(expenseRepo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildExpenseShellApp(
        platform: TargetPlatform.android,
        container: container,
      ));
      await tester.pumpAndSettle();

      // Open drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(scaffoldState.isDrawerOpen, isTrue);

      // Simulate back
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      // Verify drawer closed
      expect(scaffoldState.isDrawerOpen, isFalse);
    });

    testWidgets('Settings is reachable from the expense drawer', (tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          activeCompanyProvider.overrideWithValue(testCompany),
          userProfileProvider.overrideWith(() => _TestProfileNotifier(testProfile)),
          expenseRepositoryProvider.overrideWithValue(expenseRepo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildExpenseShellApp(
        platform: TargetPlatform.android,
        container: container,
      ));
      await tester.pumpAndSettle();

      // Open drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(find.byType(ExpenseSidebarDrawer), findsOneWidget);

      // Tap Settings
      final settingsTile = find.widgetWithText(ListTile, 'Settings');
      expect(settingsTile, findsOneWidget);
      await tester.tap(settingsTile);
      await tester.pumpAndSettle();

      // SettingsScreen is displayed
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('Upgrade to Business Ledger is reachable from the expense drawer', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          activeCompanyProvider.overrideWithValue(testCompany),
          userProfileProvider.overrideWith(() => _TestProfileNotifier(testProfile)),
          expenseRepositoryProvider.overrideWithValue(expenseRepo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildExpenseShellApp(
        platform: TargetPlatform.android,
        container: container,
      ));
      await tester.pumpAndSettle();

      // Open drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Find and tap 'Upgrade to Business Ledger'
      final upgradeTile = find.widgetWithText(ListTile, 'Upgrade to Business Ledger');
      expect(upgradeTile, findsOneWidget);
      await tester.tap(upgradeTile);
      await tester.pumpAndSettle();

      // Upgrade dialog is visible
      expect(find.byKey(const Key('confirm_upgrade_button')), findsOneWidget);
      expect(find.textContaining('Upgrading to Business Ledger'), findsOneWidget);
    });
  });

  group('Prompt UI-3 – Expense Home Tab matches Dashboard', () {
    testWidgets('Home pumps with seeded data on both Android and iOS platforms', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final currentMonth = DateTime.now();
      await expenseRepo.addExpense(
        categoryAccountId: '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}',
        walletAccountId: '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}',
        amountInCents: 4500,
        date: currentMonth,
        narration: 'Lunch at Cafe',
      );

      // 1. Android
      await tester.pumpWidget(buildExpenseShellApp(platform: TargetPlatform.android));
      await tester.pumpAndSettle();

      expect(find.byType(ExpenseHomeScreen), findsOneWidget);
      expect(find.text('Spent this month'), findsOneWidget);
      expect(find.text('Income this month'), findsOneWidget);
      expect(find.byKey(const Key('expense_balance_card')), findsOneWidget);
      expect(find.byType(CategoryBreakdownCard), findsOneWidget);
      expect(find.byType(AdaptiveSectionHeader), findsOneWidget);
      expect(find.text('Recent Transactions'), findsOneWidget);
      expect(find.text('Lunch at Cafe'), findsOneWidget);

      // 2. iOS
      await tester.pumpWidget(buildExpenseShellApp(platform: TargetPlatform.iOS));
      await tester.pumpAndSettle();

      expect(find.byType(ExpenseHomeScreen), findsOneWidget);
      expect(find.text('Spent this month'), findsOneWidget);
      expect(find.text('Income this month'), findsOneWidget);
      expect(find.byKey(const Key('expense_balance_card')), findsOneWidget);
      expect(find.byType(CategoryBreakdownCard), findsOneWidget);
      expect(find.byType(AdaptiveSectionHeader), findsOneWidget);
      expect(find.text('RECENT TRANSACTIONS'), findsOneWidget);
    });

    testWidgets('correct colours via AppColors for Spent and Income metric cards', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildExpenseShellApp(platform: TargetPlatform.android));
      await tester.pumpAndSettle();

      final metricCards = tester.widgetList<AdaptiveMetricCard>(find.byType(AdaptiveMetricCard)).toList();
      expect(metricCards.length, greaterThanOrEqualTo(2));
      final spentCard = metricCards.firstWhere((c) => c.label == 'Spent this month');
      final incomeCard = metricCards.firstWhere((c) => c.label == 'Income this month');

      expect(spentCard.accentColor, AppColors.payableRed);
      expect(incomeCard.accentColor, AppColors.receivableGreen);
    });

    testWidgets('empty state shows with no transactions', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // No transactions added
      await tester.pumpWidget(buildExpenseShellApp(platform: TargetPlatform.android));
      await tester.pumpAndSettle();

      expect(find.byType(EmptyStateView), findsOneWidget);
      expect(find.text(ModeStrings.of(CompanyMode.expenseTracker).emptyRecordsTitle), findsOneWidget);
    });

    testWidgets('month change updates cards and month switcher', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildExpenseShellApp(platform: TargetPlatform.android));
      await tester.pumpAndSettle();

      final currentNow = DateTime.now();
      final currentMonthStr = DateFormat('MMMM yyyy').format(currentNow);
      expect(find.text(currentMonthStr), findsOneWidget);

      // Tap previous month button
      final prevBtn = find.byKey(const Key('expense_prev_month_btn'));
      expect(prevBtn, findsOneWidget);
      await tester.tap(prevBtn);
      await tester.pumpAndSettle();

      final prevMonthDate = DateTime(currentNow.year, currentNow.month - 1, 1);
      final prevMonthStr = DateFormat('MMMM yyyy').format(prevMonthDate);
      expect(find.text(prevMonthStr), findsOneWidget);
    });

    testWidgets('pull-to-refresh triggers', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildExpenseShellApp(platform: TargetPlatform.android));
      await tester.pumpAndSettle();

      final refreshFinder = find.byType(RefreshIndicator);
      expect(refreshFinder, findsOneWidget);

      // Trigger pull to refresh gesture
      await tester.fling(refreshFinder, const Offset(0.0, 300.0), 1000.0);
      await tester.pumpAndSettle();
    });

    testWidgets('category breakdown tap filters Transactions tab', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final currentMonth = DateTime.now();
      await expenseRepo.addExpense(
        categoryAccountId: '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}',
        walletAccountId: '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}',
        amountInCents: 4500,
        date: currentMonth,
        narration: 'Lunch at Cafe',
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          activeCompanyProvider.overrideWithValue(testCompany),
          userProfileProvider.overrideWith(() => _TestProfileNotifier(testProfile)),
          expenseRepositoryProvider.overrideWithValue(expenseRepo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildExpenseShellApp(
        platform: TargetPlatform.android,
        container: container,
      ));
      await tester.pumpAndSettle();

      // Find Food category row or tap target in CategoryBreakdownCard
      final foodTile = find.text('Food & Dining');
      expect(foodTile, findsOneWidget);
      await tester.tap(foodTile);
      await tester.pumpAndSettle();

      // Verify that expenseTabController switched to tab 1 (Transactions)
      expect(container.read(expenseTabControllerProvider).currentIndex, 1);
      // Verify filter category is set
      final activeFilters = container.read(transactionFiltersProvider);
      expect(activeFilters.categoryIds, contains('${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}'));
    });
  });
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
