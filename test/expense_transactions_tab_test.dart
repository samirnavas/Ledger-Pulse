import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paypr/data/models/voucher_model.dart';
import 'package:paypr/core/network/sync_engine.dart';
import 'package:paypr/core/widgets/adaptive_chip.dart';
import 'package:paypr/core/widgets/spring_morphing_fab.dart';
import 'package:paypr/core/widgets/adaptive_icon_surface_button.dart';
import 'package:paypr/core/widgets/adaptive_list_row.dart';
import 'package:paypr/core/widgets/adaptive_search_field.dart';
import 'package:paypr/core/widgets/adaptive_section_header.dart';
import 'package:paypr/data/accounting/voucher_posting_engine.dart';
import 'package:paypr/data/local/audit_service.dart';
import 'package:paypr/data/local/database.dart';
import 'package:paypr/data/local/drift_expense_repository.dart';
import 'package:paypr/data/local/drift_voucher_repository.dart';
import 'package:paypr/data/models/account_model.dart';
import 'package:paypr/data/models/company_model.dart';
import 'package:paypr/data/models/user_profile_model.dart';
import 'package:paypr/presentation/expense/quick_add_transaction_sheet.dart';
import 'package:paypr/presentation/expense/transactions_screen.dart';
import 'package:paypr/presentation/expense/transaction_details_screen.dart';
import 'package:paypr/presentation/providers/company_providers.dart';
import 'package:paypr/presentation/providers/database_providers.dart';
import 'package:paypr/presentation/providers/expense_providers.dart';
import 'package:paypr/presentation/providers/profile_provider.dart';

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

    await db
        .into(db.companies)
        .insert(
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
      theme: ThemeData(platform: platform, useMaterial3: true),
      home: const Scaffold(body: ExpenseTransactionsScreen()),
    );

    if (container != null) {
      return UncontrolledProviderScope(container: container, child: app);
    }

    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        syncEngineProvider.overrideWithValue(_FakeSyncEngineTxn(db: db)),
        activeCompanyProvider.overrideWithValue(testCompany),
        userProfileProvider.overrideWith(
          () => _TestProfileNotifierTxn(testProfile),
        ),
        expenseRepositoryProvider.overrideWithValue(expenseRepo),
      ],
      child: app,
    );
  }

  group('Prompt UI-4 – Transactions Tab Matches Party List', () {
    for (final receipt in <String?>[null, '/missing/invoice.png']) {
      testWidgets('history opens details with invoice state: $receipt', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final txn = await expenseRepo.addExpense(
          categoryAccountId:
              '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}',
          walletAccountId:
              '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}',
          amountInCents: 12500,
          narration: 'Dinner receipt',
          date: DateTime.now(),
          receiptPhotoUrl: receipt,
        );
        await tester.pumpWidget(buildApp(platform: TargetPlatform.android));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(AdaptiveListRow).first);
        await tester.pumpAndSettle();
        expect(find.byType(TransactionDetailsScreen), findsOneWidget);
        final modal = find.byType(TransactionDetailsScreen);
        final sheetHeight = tester.getSize(modal).height;
        expect(find.text('Transaction Details'), findsOneWidget);
        expect(find.byType(QuickAddTransactionSheet), findsNothing);
        expect(
          find.descendant(of: modal, matching: find.text('Dinner receipt')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: modal, matching: find.text(txn.voucherNumber)),
          findsNothing,
        );
        expect(
          find.descendant(of: modal, matching: find.text('Food & Dining')),
          findsOneWidget,
        );
        final invoiceSection = find.byKey(
          const Key('transaction_invoice_section'),
        );
        if (receipt != null) {
          expect(sheetHeight, 1400);
          expect(invoiceSection, findsOneWidget);
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await tester.pumpAndSettle();
          expect(
            find.text('Invoice unavailable on this device'),
            findsOneWidget,
          );
        } else {
          expect(sheetHeight, lessThan(700));
          expect(invoiceSection, findsNothing);
          expect(find.text('Invoice / receipt'), findsNothing);

          await tester.tap(find.text('Edit details'));
          await tester.pumpAndSettle();
          final editor = find.byType(QuickAddTransactionSheet);
          expect(editor, findsOneWidget);
          expect(
            tester.widget<QuickAddTransactionSheet>(editor).initialVoucher?.id,
            txn.id,
          );
          Navigator.of(tester.element(editor)).pop();
          await tester.pumpAndSettle();

          await tester.tap(find.byType(AdaptiveListRow).first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete'));
          await tester.pumpAndSettle();
          expect(await expenseRepo.getTransactions(), isEmpty);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('header scrolls away and returns on a small reverse scroll', (
      tester,
    ) async {
      for (var i = 0; i < 35; i++) {
        await expenseRepo.addExpense(
          categoryAccountId:
              '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}',
          walletAccountId:
              '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}',
          amountInCents: 100,
          date: now.subtract(Duration(days: i % 20)),
        );
      }
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(ExpenseTransactionsScreen))).push(
        MaterialPageRoute<void>(
          builder: (_) => const ExpenseTransactionsScreen(),
        ),
      );
      await tester.pumpAndSettle();
      final fab = find.byKey(const Key('transactions_quick_add_fab'));
      expect(tester.widget<SpringMorphingFab>(fab).isExtended, isTrue);
      final expandedWidth = tester.getSize(fab).width;
      final summary = find.byKey(const Key('transactions_summary'));
      expect(summary.hitTestable(), findsOneWidget);
      final scroll = find.byKey(const PageStorageKey('transactions_scroll'));
      final search = find.byKey(const Key('transaction_search_field'));
      expect(search.hitTestable(), findsOneWidget);
      await tester.drag(scroll, const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(search.hitTestable(), findsNothing);
      expect(summary.hitTestable(), findsNothing);
      expect(tester.widget<SpringMorphingFab>(fab).isExtended, isFalse);
      expect(tester.getSize(fab).width, lessThan(expandedWidth));
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(of: scroll, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      final offsetBefore = position.pixels;
      await tester.drag(scroll, const Offset(0, 65));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(position.pixels, lessThan(offsetBefore));
      expect(search.hitTestable(), findsOneWidget);
      expect(tester.widget<SpringMorphingFab>(fab).isExtended, isTrue);
      expect(tester.getSize(fab).width, expandedWidth);
      expect(summary.hitTestable(), findsNothing);
      tester
          .state<ScrollableState>(
            find
                .descendant(of: scroll, matching: find.byType(Scrollable))
                .first,
          )
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(summary.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'renders top row, search field and filter button on both platforms',
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
      },
    );

    testWidgets(
      'day grouped headers and rows use AdaptiveSectionHeader & AdaptiveListRow',
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
        final row = tester.widget<AdaptiveListRow>(
          find.byType(AdaptiveListRow),
        );
        expect(row.title, 'Dinner with Team');
        expect(row.subtitle, contains('Food & Dining'));
        expect(row.subtitle, isNot(contains('Dinner with Team')));
      },
    );

    testWidgets('parent category filter includes subcategory transactions', (
      tester,
    ) async {
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
          userProfileProvider.overrideWith(
            () => _TestProfileNotifierTxn(testProfile),
          ),
          expenseRepositoryProvider.overrideWithValue(expenseRepo),
        ],
      );
      addTearDown(container.dispose);

      final foodId = '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}';
      final child = await expenseRepo.createCategory(
        name: 'Chaya',
        type: AccountType.expense,
        parentAccountId: foodId,
      );
      await expenseRepo.addExpense(
        categoryAccountId: child.id,
        walletAccountId: '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}',
        amountInCents: 1200,
        narration: 'Afternoon tea',
        date: DateTime.now(),
      );

      await tester.pumpWidget(
        buildApp(platform: TargetPlatform.android, container: container),
      );
      await tester.pumpAndSettle();

      var filterButton = tester.widget<AdaptiveIconSurfaceButton>(
        find.byKey(const Key('transaction_filter_button')),
      );
      expect(filterButton.isActive, false);

      // Set category filter
      container
          .read(transactionFiltersProvider.notifier)
          .updateFilters(
            TransactionFilters(categoryIds: [foodId, child.id]),
          );
      await tester.pumpAndSettle();

      filterButton = tester.widget<AdaptiveIconSurfaceButton>(
        find.byKey(const Key('transaction_filter_button')),
      );
      expect(filterButton.isActive, true);
      expect(find.text('Afternoon tea'), findsOneWidget);

      container.read(transactionFiltersProvider.notifier).updateFilters(
        TransactionFilters(categoryIds: [foodId]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Afternoon tea'), findsOneWidget);
    });

    testWidgets('search filtering and PopScope predictive back clears search', (
      tester,
    ) async {
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

    testWidgets(
      'swipe right-to-left triggers void confirmation and voids transaction',
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
        final clip = find.ancestor(
          of: dismissibleFinder,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ClipRRect &&
                widget.clipBehavior == Clip.antiAlias &&
                widget.child is Column,
          ),
        );
        expect(clip, findsOneWidget);
        expect(
          tester.getRect(clip).left,
          tester.getRect(dismissibleFinder).left,
        );
        expect(
          tester.getRect(clip).right,
          tester.getRect(dismissibleFinder).right,
        );

        await tester.drag(dismissibleFinder, const Offset(-500, 0));
        await tester.pumpAndSettle();

        // Confirm dialog appears
        expect(find.text('Delete transaction?'), findsOneWidget);
        expect(find.textContaining('₹ 12 expense from'), findsOneWidget);
        expect(find.textContaining(txn.voucherNumber), findsNothing);
        final confirmBtn = find.widgetWithText(FilledButton, 'Delete');
        expect(confirmBtn, findsOneWidget);

        await tester.tap(confirmBtn);
        await tester.pumpAndSettle();

        // Transaction is voided and removed from active list
        expect(find.textContaining('Quick Snack'), findsNothing);
        expect(find.text('₹ 12 expense deleted'), findsOneWidget);
      },
    );

    testWidgets('swipe left-to-right opens quick add edit sheet', (
      tester,
    ) async {
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

      await tester.pump(const Duration(milliseconds: 600));
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
