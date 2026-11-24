import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/core/theme/android_theme.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/domain/models/workspace_profile_header.dart';
import 'package:ledger_pulse/presentation/auth/app_root_gate.dart';
import 'package:ledger_pulse/presentation/auth/first_use_setup_screen.dart';
import 'package:ledger_pulse/presentation/auth/phone_input_screen.dart';
import 'package:ledger_pulse/presentation/home/home_shell.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';
import 'package:ledger_pulse/presentation/providers/budget_providers.dart';
import 'package:ledger_pulse/presentation/providers/database_providers.dart';
import 'package:ledger_pulse/presentation/providers/expense_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _user = '01aa0000-0000-4000-8000-000000000001';
const _otherUser = '01aa0000-0000-4000-8000-000000000002';
const _captureKey = Key('onboarding_capture');
final _previewFont = Platform.environment['LEDGER_ONBOARDING_FONT'];
bool _loadedPreviewFont = false;

class _TestAuth extends AuthController {
  _TestAuth(this.authenticated);
  final bool authenticated;

  @override
  AuthState build() => authenticated
      ? const AuthState(
          userId: _user,
          isAuthenticated: true,
          userName: 'LedgerPulse Tester',
        )
      : const AuthState();
}

class _LocalSync extends SyncEngine {
  _LocalSync({required super.db});

  @override
  void triggerBackgroundSync({
    String? companyId,
    Duration debounceDelay = Duration.zero,
  }) {}

  @override
  Future<SyncResult> syncAll({String? companyId}) async =>
      SyncResult(status: SyncEngineStatus.error, errorMessage: 'Offline test');
}

class _SetupRepo extends DriftProfileRepository {
  _SetupRepo({required super.db, required super.syncEngine});
  bool offline = false;
  bool failWorkspaceOnce = false;

  @override
  Future<List<WorkspaceProfileHeader>> getAccessibleProfiles(String accountId) {
    if (failWorkspaceOnce) {
      failWorkspaceOnce = false;
      throw StateError('Local storage temporarily unavailable');
    }
    return super.getAccessibleProfiles(accountId);
  }

  @override
  Future<List<WorkspaceProfileHeader>> syncAndLoadRemoteWorkspaces(
    String accountId,
  ) async {
    if (offline) throw const SocketException('Network is unreachable');
    return getAccessibleProfiles(accountId);
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['LEDGER_ONBOARDING_SCREENSHOTS'];
  if (directory == null) return;
  final dashboardPrefix = Platform.environment['LEDGER_DASHBOARD_CAPTURE'];
  if (dashboardPrefix != null && !name.startsWith('${dashboardPrefix}_home_'))
    return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;
  late _LocalSync sync;
  late _SetupRepo repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    sync = _LocalSync(db: db);
    repo = _SetupRepo(db: db, syncEngine: sync);
  });

  tearDown(() async {
    sync.dispose();
    await db.close();
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    bool authenticated = true,
    Brightness brightness = Brightness.light,
    TargetPlatform platform = TargetPlatform.android,
    double textScale = 1,
    Future<({bool hasActivity, bool hasExpense})>? historyOverride,
    bool waitForHistory = true,
  }) async {
    final previewFont = _previewFont;
    if (previewFont != null && !_loadedPreviewFont) {
      await tester.runAsync(() async {
        final roboto = File(
          previewFont,
        ).readAsBytes().then(ByteData.sublistView);
        final loader = FontLoader('OnboardingPreview')..addFont(roboto);
        final materialIcons =
            Platform.environment['LEDGER_MATERIAL_ICONS_FONT'];
        final symbols =
            FontLoader(
              'packages/material_symbols_icons/MaterialSymbolsOutlined',
            )..addFont(
              rootBundle.load(
                'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf',
              ),
            );
        await Future.wait([
          loader.load(),
          (FontLoader('Roboto')..addFont(roboto)).load(),
          symbols.load(),
          if (materialIcons != null)
            (FontLoader('MaterialIcons')..addFont(
                  File(materialIcons).readAsBytes().then(ByteData.sublistView),
                ))
                .load(),
        ]);
      });
      _loadedPreviewFont = true;
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final base = brightness == Brightness.light
        ? AndroidTheme.getLight()
        : AndroidTheme.getDark();
    final theme = base.copyWith(
      platform: platform,
      textTheme: base.textTheme.apply(
        fontFamily: previewFont == null ? null : 'OnboardingPreview',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _TestAuth(authenticated)),
          activeUserIdProvider.overrideWithValue(
            authenticated ? _user : 'usr_default',
          ),
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          syncEngineProvider.overrideWithValue(sync),
          profileRepositoryProvider.overrideWithValue(repo),
          if (historyOverride != null)
            dashboardTransactionHistoryProvider.overrideWith(
              (ref) => historyOverride,
            ),
        ],
        child: RepaintBoundary(
          key: _captureKey,
          child: MaterialApp(
            theme: theme,
            debugShowCheckedModeBanner: false,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const AppRootGate(),
          ),
        ),
      ),
    );
    if (waitForHistory) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  void viewport(WidgetTester tester, {Size? size}) {
    tester.view.physicalSize =
        size ??
        (_previewFont == null ? const Size(650, 1000) : const Size(430, 880));
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'en',
      'GB',
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final target = find.text(label).last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'First-use journey saves a real expense in ${brightness.name} mode',
      (tester) async {
        viewport(tester);
        await pumpApp(tester, authenticated: false, brightness: brightness);
        expect(find.text('Make sense of your money.'), findsOneWidget);
        await _capture(tester, '01_welcome_${brightness.name}');
        if (brightness == Brightness.light) {
          await tap(tester, 'Sign in');
          expect(
            tester
                .widget<PhoneInputScreen>(find.byType(PhoneInputScreen))
                .initialMode,
            AuthMode.login,
          );
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.text('Make sense of your money.'), findsOneWidget);
        }

        await pumpApp(tester, brightness: brightness);
        expect(find.text('Make it yours.'), findsOneWidget);
        expect(find.text('GBP · British pound'), findsOneWidget);
        await _capture(tester, '02_workspace_${brightness.name}');
        final create = find.text('Create workspace');
        await tester.tap(create);
        await tester.tap(create, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.text('Your first wallet.'), findsOneWidget);
        expect((await repo.getAccessibleProfiles(_user)).length, 1);
        expect(await db.select(db.expenseWallets).get(), isEmpty);
        await _capture(tester, '03_wallet_${brightness.name}');

        final opening = find.widgetWithText(TextField, 'Opening balance (GBP)');
        if (brightness == Brightness.light) {
          await tester.enterText(opening, '250');
        }
        await tap(tester, 'Create wallet');
        expect(find.text('Start tracking.'), findsOneWidget);
        expect(find.text('Wallet: Cash'), findsOneWidget);
        final pendingKey = prefs.getKeys().singleWhere(
          (key) => key.startsWith('first_use_workspace_'),
        );
        final wallet = (await db.select(db.expenseWallets).get()).single;
        expect(wallet.currencyCode, 'GBP');
        expect(
          wallet.startingBalanceInCents,
          brightness == Brightness.light ? 25000 : 0,
        );
        expect(await db.select(db.expenseTransactions).get(), isEmpty);
        await _capture(tester, '04_first_expense_${brightness.name}');

        await tester.enterText(
          find.byKey(const Key('quick_add_amount_field')),
          '5.25',
        );
        final category = (await db.select(db.expenseCategories).get())
            .firstWhere((row) => row.categoryType == 'expense');
        final chip = find.byKey(Key('cat_chip_${category.id}'));
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('quick_add_note_field')),
          'Lunch',
        );
        await tap(tester, 'Save Expense');
        final expense = (await db.select(db.expenseTransactions).get()).single;
        expect(expense.transactionType, 'expense');
        expect(expense.walletId, wallet.id);
        expect(expense.amountInCents, 525);
        expect(expense.note, 'Lunch');
        final outbox = await db.select(db.syncOutbox).get();
        final queuedTables = outbox.map((row) => row.targetTable).join(', ');
        expect(
          outbox.any(
            (row) =>
                row.targetTable == 'exp_wallets' && row.recordId == wallet.id,
          ),
          isTrue,
          reason: queuedTables,
        );
        expect(
          outbox.any(
            (row) =>
                row.targetTable == 'exp_transactions' &&
                row.recordId == expense.id,
          ),
          isTrue,
        );
        expect(
          (await db.select(db.expenseWallets).get())
              .single
              .currentBalanceInCents,
          wallet.startingBalanceInCents - 525,
        );
        expect(find.byType(HomeShell), findsOneWidget);
        expect(
          Navigator.of(tester.element(find.byType(HomeShell))).canPop(),
          isFalse,
        );
        if (brightness == Brightness.light) {
          // Simulate termination after saving the expense but before clearing setup.
          await prefs.setString(pendingKey, expense.profileId);
          await pumpApp(tester, brightness: brightness);
          expect(find.byType(HomeShell), findsOneWidget);
          expect((await db.select(db.expenseTransactions).get()).length, 1);
        }
      },
    );
  }

  testWidgets(
    'Wallet and expense setup resume offline after a fresh app instance',
    (tester) async {
      viewport(tester);
      await pumpApp(tester);
      repo.failWorkspaceOnce = true;
      await tap(tester, 'Create workspace');
      expect(
        find.text('Could not open your workspace. Try again.'),
        findsOneWidget,
      );
      await tap(tester, 'Create workspace');
      expect(find.text('Your first wallet.'), findsOneWidget);
      repo.offline = true;
      await pumpApp(tester);
      expect(find.text('Your first wallet.'), findsOneWidget);
      await tap(tester, 'Create wallet');
      await pumpApp(tester);
      expect(find.text('Start tracking.'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(FirstUseSetupScreen)),
        listen: false,
      );
      final expenseRepo = container.read(expenseRepositoryProvider);
      final wallet = (await expenseRepo.getWallets()).single;
      await expenseRepo.createWallet(
        name: 'Changed request',
        type: AccountType.asset,
        customId: wallet.id,
        openingBalanceInCents: 1000,
      );
      expect((await expenseRepo.getWallets()).single.name, 'Cash');
      expect((await expenseRepo.getWallets()).single.currentBalanceInCents, 0);
      await tap(tester, 'Skip for now');
      expect(find.byType(HomeShell), findsOneWidget);
      expect(await db.select(db.expenseTransactions).get(), isEmpty);
      expect(await repo.getAccessibleProfiles(_otherUser), isEmpty);
    },
  );

  testWidgets(
    'Skipping the wallet opens the dashboard with no wallet or expense',
    (tester) async {
      viewport(tester);
      await pumpApp(tester);
      await tap(tester, 'Create workspace');
      await tap(tester, 'Skip for now');
      await pumpApp(tester);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(FirstUseSetupScreen), findsNothing);
      expect(await db.select(db.expenseWallets).get(), isEmpty);
      expect(await db.select(db.expenseTransactions).get(), isEmpty);
      final inline = find.byKey(const Key('home_first_expense_action'));
      expect(
        find.descendant(of: inline, matching: find.text('Set up a wallet')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: inline, matching: find.text('Set up a wallet')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wallet_name_input')), findsOneWidget);
    },
  );

  testWidgets('An existing workspace bypasses setup', (tester) async {
    viewport(tester);
    await repo.createProfile(
      name: 'Existing expenses',
      type: ProfileType.expense,
      accountId: _user,
    );
    await pumpApp(tester);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(FirstUseSetupScreen), findsNothing);
    expect(
      (await db.select(db.expenseWallets).get()).single.name,
      'Cash in Hand',
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('Captures the new workspace dashboard in ${brightness.name}', (
      tester,
    ) async {
      viewport(tester, size: const Size(430, 880));
      await pumpApp(tester, brightness: brightness);
      await tap(tester, 'Create workspace');
      await tap(tester, 'Create wallet');
      await tap(tester, 'Skip for now');
      expect(find.byType(HomeShell), findsOneWidget);
      final prefix = Platform.environment['LEDGER_DASHBOARD_CAPTURE'];
      if (prefix != 'before') {
        expect(find.text('Welcome!'), findsOneWidget);
        expect(find.text('Your first expense'), findsOneWidget);
        expect(find.text('See all'), findsNothing);
        expect(find.text('Category Breakdown'), findsNothing);
        expect(find.textContaining('Daily average:'), findsNothing);
        expect(find.byKey(const Key('expense_quick_add_fab')), findsNothing);
      }
      if (prefix != null) {
        await _capture(tester, '${prefix}_home_${brightness.name}');
      }
    });
  }

  testWidgets('Cupertino setup supports a small viewport and large text', (
    tester,
  ) async {
    viewport(tester, size: const Size(340, 620));
    await pumpApp(
      tester,
      platform: TargetPlatform.iOS,
      brightness: Brightness.dark,
      textScale: 1.6,
    );
    expect(find.byType(CupertinoTextField), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Create workspace'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Dashboard records the first expense offline and restores the FAB reactively',
    (tester) async {
      viewport(tester);
      tester.view.padding = const FakeViewPadding(bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await pumpApp(tester);
      await tap(tester, 'Create workspace');
      await tap(tester, 'Create wallet');
      await tap(tester, 'Skip for now');
      repo.offline = true;
      await pumpApp(tester);
      expect(find.textContaining('Offline'), findsOneWidget);
      expect(find.byKey(const Key('home_first_expense')), findsOneWidget);
      expect(find.byKey(const Key('expense_quick_add_fab')), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('home_first_expense_action')),
          matching: find.text('Add transaction'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('quick_add_amount_field')),
        '6.50',
      );
      final category = (await db.select(db.expenseCategories).get()).firstWhere(
        (row) => row.categoryType == 'expense',
      );
      final chip = find.byKey(Key('cat_chip_${category.id}'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await tap(tester, 'Save Expense');

      expect(find.byKey(const Key('home_first_expense')), findsNothing);
      expect(find.text('Category Breakdown'), findsOneWidget);
      expect(find.byKey(const Key('expense_quick_add_fab')), findsOneWidget);
      final row = (await db.select(db.expenseTransactions).get()).single;
      expect(row.amountInCents, 650);
      expect(
        (await db.select(db.syncOutbox).get()).any(
          (entry) =>
              entry.targetTable == 'exp_transactions' &&
              entry.recordId == row.id,
        ),
        isTrue,
      );

      final home = find.byKey(const PageStorageKey('expense_tab_home')).first;
      final list = find
          .descendant(of: home, matching: find.byType(Scrollable))
          .first;
      final fab = find.byKey(const Key('expense_quick_add_fab'));
      await tester.scrollUntilVisible(
        find.text('Create a budget'),
        230,
        scrollable: list,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(list).bottom,
        lessThanOrEqualTo(tester.getRect(fab).top),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeShell)),
        listen: false,
      );
      await container
          .read(budgetRepositoryProvider)
          .createBudget(categoryId: 'all', amountInCents: 20000);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home_get_started')), findsNothing);
    },
  );

  for (final transferOnly in [false, true]) {
    testWidgets(
      'Dashboard distinguishes ${transferOnly ? 'transfer' : 'income'}-only activity',
      (tester) async {
        viewport(tester);
        await repo.createProfile(
          name: 'Existing',
          type: ProfileType.expense,
          accountId: _user,
        );
        await pumpApp(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeShell)),
          listen: false,
        );
        final expenses = container.read(expenseRepositoryProvider);
        final wallet = (await expenses.getWallets()).single;
        if (transferOnly) {
          final destination = await expenses.createWallet(
            name: 'Savings',
            type: AccountType.asset,
          );
          await expenses.addTransfer(
            walletAccountId: wallet.id,
            toWalletAccountId: destination.id,
            amountInCents: 530,
          );
        } else {
          final income = (await expenses.getCategories()).firstWhere(
            (category) => category.type == AccountType.income,
          );
          await expenses.addIncome(
            walletAccountId: wallet.id,
            categoryAccountId: income.id,
            amountInCents: 530,
            narration: 'Income deposit',
          );
        }
        await tester.pumpAndSettle();
        expect(find.text('Welcome!'), findsNothing);
        expect(
          find.text(transferOnly ? 'Transfer' : 'Income deposit'),
          findsOneWidget,
        );
        expect(find.text('See all'), findsOneWidget);
        expect(find.text('Category Breakdown'), findsNothing);
        expect(find.textContaining('Daily average:'), findsNothing);
        expect(find.text('Record your first expense'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'Empty months and switching workspaces do not reclassify history or share dismissal',
    (tester) async {
      viewport(tester);
      final first = await repo.createProfile(
        name: 'Existing',
        type: ProfileType.expense,
        accountId: _user,
      );
      await pumpApp(tester);
      var container = ProviderScope.containerOf(
        tester.element(find.byType(HomeShell)),
        listen: false,
      );
      await tester.tap(find.byTooltip('Dismiss Get started'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home_get_started')), findsNothing);
      await pumpApp(tester);
      expect(find.byKey(const Key('home_get_started')), findsNothing);
      container = ProviderScope.containerOf(
        tester.element(find.byType(HomeShell)),
        listen: false,
      );
      final expenses = container.read(expenseRepositoryProvider);
      final wallet = (await expenses.getWallets()).single;
      final category = (await expenses.getCategories()).firstWhere(
        (category) => category.type == AccountType.expense,
      );
      final now = DateTime.now();
      await expenses.addExpense(
        walletAccountId: wallet.id,
        categoryAccountId: category.id,
        amountInCents: 650,
        date: DateTime(now.year, now.month - 1, 10),
      );
      await tester.pumpAndSettle();
      expect(find.text('No transactions in this month.'), findsOneWidget);
      expect(find.text('Your first expense'), findsNothing);
      expect(find.text('See all'), findsNothing);
      expect(find.byKey(const Key('expense_quick_add_fab')), findsOneWidget);
      final second = await repo.createProfile(
        name: 'New workspace',
        type: ProfileType.expense,
        accountId: _user,
      );
      await container
          .read(profileSessionProvider.notifier)
          .switchProfile(second);
      await tester.pumpAndSettle();
      expect(find.text('Your first expense'), findsOneWidget);
      expect(find.byKey(const Key('home_get_started')), findsOneWidget);
      expect(find.byKey(const Key('expense_quick_add_fab')), findsNothing);
      await container
          .read(profileSessionProvider.notifier)
          .switchProfile(first);
      await tester.pumpAndSettle();
      expect(find.text('Your first expense'), findsNothing);
      expect(find.byKey(const Key('home_get_started')), findsNothing);
    },
  );

  testWidgets(
    'Dashboard distinguishes unknown history from an empty workspace',
    (tester) async {
      viewport(tester);
      await repo.createProfile(
        name: 'Existing',
        type: ProfileType.expense,
        accountId: _user,
      );
      final pending = Completer<({bool hasActivity, bool hasExpense})>();
      await pumpApp(
        tester,
        historyOverride: pending.future,
        waitForHistory: false,
      );
      expect(find.text('Recent Transactions'), findsOneWidget);
      expect(find.text('Your first expense'), findsNothing);
      expect(find.text('No transactions in this month.'), findsNothing);
      expect(find.byKey(const Key('expense_quick_add_fab')), findsNothing);
      pending.completeError(StateError('History unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load workspace activity.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Your first expense'), findsNothing);
    },
  );

  testWidgets('The compact Cupertino dashboard stays usable with large text', (
    tester,
  ) async {
    viewport(tester, size: const Size(340, 670));
    await repo.createProfile(
      name: 'Existing',
      type: ProfileType.expense,
      accountId: _user,
    );
    await pumpApp(
      tester,
      platform: TargetPlatform.iOS,
      brightness: Brightness.dark,
      textScale: 1.6,
    );
    expect(find.text('Your first expense'), findsOneWidget);
    expect(find.byKey(const Key('expense_ios_add_button')), findsNothing);
    expect(find.byType(CupertinoTabBar), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(CupertinoTabBar),
        matching: find.text('Reports'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your first expense'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Your first expense'), findsOneWidget);
  });
}
