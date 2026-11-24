import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ledger_pulse/core/widgets/app_pull_to_refresh.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/core/widgets/adaptive_bottom_nav.dart';
import 'package:ledger_pulse/core/widgets/adaptive_scaffold.dart';
import 'package:ledger_pulse/core/widgets/adaptive_segmented_control.dart';
import 'package:ledger_pulse/core/widgets/spring_morphing_fab.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/presentation/expense/expense_home_screen.dart';
import 'package:ledger_pulse/presentation/expense/accounts_screen.dart';
import 'package:ledger_pulse/presentation/expense/transaction_details_screen.dart';
import 'package:ledger_pulse/presentation/expense/transactions_screen.dart';
import 'package:ledger_pulse/core/widgets/adaptive_section_header.dart';
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
      expect(find.byKey(const Key('active_profile_indicator_pill')), findsOneWidget);
      expect(find.byTooltip('My Account'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byTooltip('My Account'),
          matching: find.byType(CircleAvatar),
        ),
        findsOneWidget,
      );

      // 2. iOS
      await tester.pumpWidget(buildExpenseShellApp(platform: TargetPlatform.iOS));
      await tester.pumpAndSettle();

      expect(find.byType(AdaptiveScaffold), findsOneWidget);
      expect(find.byKey(const Key('active_profile_indicator_pill')), findsOneWidget);
      expect(find.byTooltip('My Account'), findsOneWidget);
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('swipes and taps select the same tab on ${platform.name}', (
        tester,
      ) async {
        await tester.pumpWidget(buildExpenseShellApp(platform: platform));
        await tester.pumpAndSettle();

        final pages = find.byType(PageView);
        final nav = find.byType(AdaptiveBottomNav);
        final bounds = tester.getRect(pages);
        final swipeStart = Offset(
          bounds.left + bounds.width * 0.8,
          bounds.top + 30,
        );
        final swipeEnd = Offset(
          bounds.left + bounds.width * 0.2,
          bounds.top + 30,
        );

        for (var index = 1; index <= 3; index++) {
          await tester.dragFrom(swipeStart, swipeEnd - swipeStart);
          await tester.pumpAndSettle();
          expect(tester.widget<AdaptiveBottomNav>(nav).currentIndex, index);
          expect(find.byKey(const Key('active_profile_indicator_pill')), findsOneWidget);
        }
        expect(find.byType(ExpenseTransactionsScreen), findsOneWidget);

        // Start below the transaction search and filter controls.
        await tester.dragFrom(
          Offset(swipeEnd.dx, bounds.bottom - 60),
          Offset(swipeStart.dx - swipeEnd.dx, 0),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<AdaptiveBottomNav>(nav).currentIndex, 2);

        await tester.tap(find.descendant(of: nav, matching: find.text('Home')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.widget<AdaptiveBottomNav>(nav).currentIndex, 0);
        expect(
          tester.widget<PageView>(pages).controller!.page,
          inExclusiveRange(0, 2),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<AdaptiveBottomNav>(nav).currentIndex, 0);
        expect(tester.widget<PageView>(pages).controller!.page, 0);
      });

      testWidgets('profile sections swipe and slide on ${platform.name}', (
        tester,
      ) async {
        await tester.pumpWidget(buildExpenseShellApp(platform: platform));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('My Account'));
        await tester.pumpAndSettle();

        final sections = find.byType(AdaptiveSegmentedControl<int>);
        final pages = find.byType(PageView);
        final bounds = tester.getRect(pages);
        final start = Offset(
          bounds.left + bounds.width * 0.8,
          bounds.top + 40,
        );

        for (var index = 1; index <= 2; index++) {
          await tester.dragFrom(start, Offset(-bounds.width * 0.6, 0));
          await tester.pumpAndSettle();
          expect(
            tester.widget<AdaptiveSegmentedControl<int>>(sections).groupValue,
            index,
          );
        }

        await tester.tap(
          find.descendant(of: sections, matching: find.text('Account')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          tester.widget<PageView>(pages).controller!.page,
          inExclusiveRange(0, 2),
        );
        expect(
          tester.widget<AdaptiveSegmentedControl<int>>(sections).groupValue,
          0,
        );
        await tester.pumpAndSettle();
        expect(tester.widget<PageView>(pages).controller!.page, 0);
      });
    }

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
      for (int i = 0; i < 4; i++) {
        container.read(expenseTabControllerProvider.notifier).setTab(i);
        await tester.pumpAndSettle();
        expect(find.byType(Scaffold), findsOneWidget);
      }
    });

    testWidgets('FAB on Android and nav "+" button on iOS', (tester) async {
      await expenseRepo.addExpense(
        categoryAccountId: '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}',
        walletAccountId: '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}',
        amountInCents: 4500,
      );
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

    testWidgets('per-tab FAB follows profile, wallet and category sections', (tester) async {
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

      // Tab 1 (Budgets): 'Add budget'
      container.read(expenseTabControllerProvider.notifier).setTab(1);
      await tester.pumpAndSettle();
      expect(find.text('Add budget'), findsOneWidget);

      // Tab 2 (Reports): FAB hidden
      container.read(expenseTabControllerProvider.notifier).setTab(2);
      await tester.pumpAndSettle();
      expect(find.byType(SpringMorphingFab), findsNothing);

      // Transactions replaces My Account in the bottom navigation.
      await tester.tap(find.text('Transactions'));
      await tester.pumpAndSettle();
      expect(find.byType(ExpenseTransactionsScreen), findsOneWidget);
      expect(find.text('Add transaction'), findsOneWidget);
      expect(find.byTooltip('Sync & Backup'), findsNothing);

      // The header opens My Account above the current tab.
      await tester.tap(find.byTooltip('My Account'));
      await tester.pumpAndSettle();
      expect(find.text('Add workspace'), findsOneWidget);
      await tester.tap(find.text('Wallet').first);
      await tester.pumpAndSettle();
      expect(find.text('Add wallet'), findsOneWidget);
      await tester.tap(find.text('Add wallet'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wallet_name_input')), findsOneWidget);
      Navigator.of(tester.element(find.byKey(const Key('wallet_name_input')))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Category').first);
      await tester.pumpAndSettle();
      expect(find.text('Add category'), findsOneWidget);
      await tester.tap(find.text('Add category'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('category_name_input')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ExpenseTransactionsScreen), findsOneWidget);
    });

    testWidgets('back navigation from tab 2 goes to tab 0', (tester) async {
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

      // Switch to Tab 2 (Reports)
      container.read(expenseTabControllerProvider.notifier).setTab(2);
      await tester.pumpAndSettle();
      expect(container.read(expenseTabControllerProvider).currentIndex, equals(2));

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

      // Rebuild the shell while the drawer is open. Closing it must not leave
      // a stale PopScope veto that disables future native back gestures.
      container.read(expenseTabControllerProvider.notifier).setTab(0);
      await tester.pumpAndSettle();

      // Simulate back
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      // Verify drawer closed
      expect(scaffoldState.isDrawerOpen, isFalse);
      expect(tester.widget<PopScope>(
        find.byWidgetPredicate((widget) => widget is PopScope).first,
      ).canPop, isTrue);
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('Settings is reachable from the expense drawer on ${platform.name}', (tester) async {
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
            activeCompanyProvider.overrideWithValue(testCompany),
            userProfileProvider.overrideWith(
              () => _TestProfileNotifier(
                testProfile.copyWith(phoneNumber: '', email: ''),
              ),
            ),
            expenseRepositoryProvider.overrideWithValue(expenseRepo),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(buildExpenseShellApp(
          platform: platform,
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
        final settings = find.byType(SettingsScreen);
        expect(settings, findsOneWidget);
        final settingsList = find.descendant(
          of: settings,
          matching: find.byType(Scrollable),
        );
        final profile = find.widgetWithText(ListTile, 'Personal details, wallets and categories');
        await tester.scrollUntilVisible(profile, 200, scrollable: settingsList);
        await tester.ensureVisible(profile);
        await tester.pumpAndSettle();
        await tester.tap(profile);
        await tester.pumpAndSettle();
        expect(find.byType(ExpenseAccountsScreen), findsOneWidget);
        expect(find.text('Wallet'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Help'),
          240,
          scrollable: settingsList,
        );
        await tester.pumpAndSettle();
        expect(find.text('Load sample data'), findsNothing);
        expect(find.text('DEVELOPER & DEBUG'), findsNothing);

        await tester.tap(find.text('Help'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('How do I add or find a transaction?'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Expense, Income, or Transfer'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        const appInfo = MethodChannel('com.ledgerpulse.ledger_pulse/app_info');
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(appInfo, (_) async => '2.4.1 (27)');
        addTearDown(() => messenger.setMockMethodCallHandler(appInfo, null));
        await tester.ensureVisible(find.text('About'));
        await tester.tap(find.text('About'));
        await tester.pumpAndSettle();
        expect(find.text('Version 2.4.1 (27)'), findsOneWidget);
        await tester.tap(find.text('Open-source licenses'));
        await tester.pumpAndSettle();
        expect(find.byType(LicensePage), findsOneWidget);
      });
    }

    testWidgets('Expense drawer does not offer an in-place Ledger upgrade', (tester) async {
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

      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text('Upgrade to Business Ledger'), findsNothing);
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
      expect(find.text('Income this month'), findsNothing);
      expect(find.byKey(const Key('expense_balance_card')), findsNothing);
      expect(find.byType(CategoryBreakdownCard), findsOneWidget);
      expect(find.byType(AdaptiveSectionHeader), findsNWidgets(2));
      expect(find.text('Recent Transactions'), findsOneWidget);
      expect(find.text('Lunch at Cafe'), findsOneWidget);

      await tester.tap(find.text('Lunch at Cafe'));
      await tester.pumpAndSettle();
      final transactionsPage = find.byType(ExpenseTransactionsScreen);
      final details = find.byType(TransactionDetailsScreen);
      expect(transactionsPage, findsOneWidget);
      expect(details, findsOneWidget);
      expect(
        find.descendant(of: details, matching: find.text('Lunch at Cafe')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(details, findsNothing);
      expect(transactionsPage, findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ExpenseHomeScreen), findsOneWidget);
      expect(transactionsPage, findsNothing);

      // 2. iOS
      await tester.pumpWidget(buildExpenseShellApp(platform: TargetPlatform.iOS));
      await tester.pumpAndSettle();

      expect(find.byType(ExpenseHomeScreen), findsOneWidget);
      expect(find.text('Spent this month'), findsOneWidget);
      expect(find.text('Income this month'), findsNothing);
      expect(find.byKey(const Key('expense_balance_card')), findsNothing);
      expect(find.byType(CategoryBreakdownCard), findsOneWidget);
      expect(find.byType(AdaptiveSectionHeader), findsNWidgets(2));
      expect(find.text('RECENT TRANSACTIONS'), findsOneWidget);
      expect(find.byTooltip('My Account'), findsOneWidget);
      await tester.tap(find.text('Transactions'));
      await tester.pumpAndSettle();
      expect(find.byType(ExpenseTransactionsScreen), findsOneWidget);
      expect(find.byKey(const Key('expense_ios_add_button')), findsOneWidget);
    });

    testWidgets('displays expanded spent card with daily average', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await expenseRepo.addExpense(
        categoryAccountId: '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}',
        walletAccountId: '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}',
        amountInCents: 4500,
      );

      await tester.pumpWidget(buildExpenseShellApp(platform: TargetPlatform.android));
      await tester.pumpAndSettle();

      expect(find.text('Spent this month'), findsOneWidget);
      expect(find.textContaining('Daily average:'), findsOneWidget);
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

      expect(find.text('Your first expense'), findsOneWidget);
      expect(find.text('Welcome!'), findsOneWidget);
      expect(find.text('Spent this month'), findsOneWidget);
      expect(find.byKey(const Key('expense_prev_month_btn')), findsNothing);
      expect(find.byType(CategoryBreakdownCard), findsNothing);
      expect(find.text('Recent Transactions'), findsNothing);
      expect(find.byKey(const Key('home_first_expense_action')), findsOneWidget);
      expect(find.byKey(const Key('expense_quick_add_fab')), findsNothing);
      expect(find.text('See all'), findsNothing);
    });

    testWidgets('month change updates cards and month switcher', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await expenseRepo.addExpense(
        categoryAccountId: '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}',
        walletAccountId: '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}',
        amountInCents: 4500,
      );
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

      final refreshFinder = find.byType(AppPullToRefresh);
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

      // Verify that expenseTabController switched to tab 2 (ExpenseReportsScreen)
      expect(container.read(expenseTabControllerProvider).currentIndex, 2);
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
