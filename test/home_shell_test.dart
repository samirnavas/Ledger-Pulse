import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/constants/mode_strings.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/core/widgets/adaptive_bottom_nav.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/presentation/expense/expense_home_screen.dart';
import 'package:ledger_pulse/presentation/home/dashboard_screen.dart';
import 'package:ledger_pulse/presentation/home/dashboard_sidebar_drawer.dart';
import 'package:ledger_pulse/presentation/home/home_shell.dart';
import 'package:ledger_pulse/presentation/home/party_list_tab.dart';
import 'package:ledger_pulse/presentation/profile/profile_screen.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';
import 'package:ledger_pulse/presentation/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  final ledgerCompany = Company(
    id: 'cmp_ledger_1',
    name: 'Acme Traders',
    legalName: 'Acme Traders Pvt Ltd',
    gstin: '29ABCDE1234F1Z5',
    mode: CompanyMode.ledger,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  final expenseCompany = Company(
    id: 'cmp_expense_1',
    name: 'Personal Expenses',
    legalName: 'Personal Household',
    mode: CompanyMode.expenseTracker,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('ModeStrings Unit Tests', () {
    test('ModeStrings returns correct labels for ledger mode', () {
      final strings = ModeStrings.of(CompanyMode.ledger);
      expect(strings.isLedger, isTrue);
      expect(strings.isExpense, isFalse);
      expect(strings.modeDisplayName, equals('Business Ledger'));
      expect(strings.homeTitle, equals('Dashboard'));
      expect(strings.primaryMetricLabel, equals("You'll Get"));
      expect(strings.secondaryMetricLabel, equals("You'll Give"));
    });

    test('ModeStrings returns correct labels for expense mode', () {
      final strings = ModeStrings.of(CompanyMode.expenseTracker);
      expect(strings.isExpense, isTrue);
      expect(strings.isLedger, isFalse);
      expect(strings.modeDisplayName, equals('Expense Tracker'));
      expect(strings.homeTitle, equals('Expense Tracker'));
      expect(strings.primaryMetricLabel, equals('Total Spent'));
      expect(strings.secondaryMetricLabel, equals('Total Income'));
    });
  });

  group('Ledger-only Providers in Expense Mode', () {
    test('businessSummaryProvider and partyListProvider are not querying repo in expense mode', () async {
      final profile = UserProfile(
        id: 'usr_test',
        name: 'John Doe',
        phoneNumber: '+91 99999 00000',
        email: 'john@example.com',
        companies: [expenseCompany],
        activeCompanyId: expenseCompany.id,
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          userProfileProvider.overrideWith(() => _TestUserProfileNotifier(profile)),
        ],
      );
      addTearDown(container.dispose);

      // Verify active company is in expense mode
      final activeCmp = container.read(activeCompanyProvider);
      expect(activeCmp.mode, equals(CompanyMode.expenseTracker));

      // Reading businessSummaryProvider in expense mode returns (0, 0) without calling repo
      final summary = await container.read(businessSummaryProvider.future);
      expect(summary, equals((0, 0)));

      // Reading partyListProvider in expense mode returns empty list without calling repo
      final parties = await container.read(partyListProvider.future);
      expect(parties, isEmpty);
    });
  });

  group('HomeShell Routing & Company Switch Widget Tests', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('ledger opens Parties with balances and a scroll-aware FAB', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(400, 600);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final profile = UserProfile(
          id: 'usr_test',
          name: 'Business user',
          phoneNumber: '',
          email: '',
          companies: [ledgerCompany],
          activeCompanyId: ledgerCompany.id,
        );
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
            userProfileProvider.overrideWith(() => _TestUserProfileNotifier(profile)),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(platform: platform),
            home: const HomeShell(),
          ),
        ));
        await tester.pumpAndSettle();

        final fab = find.byKey(const Key('ledger_add_party_fab'));
        final partyList = find.descendant(
          of: find.byType(PartyListTab),
          matching: find.byType(ListView),
        );
        expect(find.text('Home'), findsNothing);
        expect(find.text('To receive'), findsOneWidget);
        expect(find.text('To pay'), findsOneWidget);
        expect(tester.getBottomLeft(find.text('To pay')).dy,
            lessThan(tester.getTopLeft(find.text('All')).dy));
        expect(find.text('Add Party'), findsOneWidget);
        final expandedWidth = tester.getSize(fab).width;

        await tester.drag(partyList, const Offset(0, -100));
        await tester.pumpAndSettle();
        expect(tester.getSize(fab).width, lessThan(expandedWidth));

        await tester.drag(partyList, const Offset(0, 100));
        await tester.pumpAndSettle();
        expect(tester.getSize(fab).width, expandedWidth);

        await tester.tap(find.text('Transactions'));
        await tester.pumpAndSettle();
        expect(find.text('Add Transaction'), findsOneWidget);
        expect(find.text('Add Party'), findsNothing);

        await tester.tap(find.byTooltip('My Account'));
        await tester.pumpAndSettle();
        expect(find.byType(ProfileScreen), findsOneWidget);
        expect(find.text('Manage Workspaces & Members'), findsNothing);
        expect(find.text('Sync Account & Workspace'), findsNothing);
        expect(find.text('Audit log'), findsNothing);
        final editDetails = find.text('Edit business and bank details');
        await tester.ensureVisible(editDetails);
        await tester.tap(editDetails);
        await tester.pumpAndSettle();
        expect(find.text('Account number (optional)'), findsOneWidget);
        Navigator.of(tester.element(find.text('Edit Workspace'))).pop();
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.byType(ProfileScreen))).pop();
        await tester.pumpAndSettle();
        expect(find.text('Add Transaction'), findsOneWidget);

        expect(find.text('Archived parties'), findsNothing);
        final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
        scaffold.openDrawer();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archived parties'));
        await tester.pumpAndSettle();
        expect(scaffold.isDrawerOpen, isFalse);
        expect(find.text('No archived parties'), findsOneWidget);
      }, variant: TargetPlatformVariant({platform}));

      testWidgets('ledger tabs and report links work on ${platform.name}', (tester) async {
        final profile = UserProfile(
          id: 'usr_test',
          name: 'Business user',
          phoneNumber: '',
          email: '',
          companies: [ledgerCompany],
          activeCompanyId: ledgerCompany.id,
        );
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
            userProfileProvider.overrideWith(() => _TestUserProfileNotifier(profile)),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(platform: platform,
              brightness: platform == TargetPlatform.iOS ? Brightness.dark : Brightness.light),
            home: const HomeShell(),
          ),
        ));
        await tester.pumpAndSettle();
        Finder tab(String label) => find.descendant(
          of: find.byType(AdaptiveBottomNav), matching: find.text(label),
        );
        expect(find.text('To receive'), findsOneWidget);
        for (final label in ['Parties', 'Transactions', 'Reports']) {
          expect(tab(label), findsOneWidget);
        }
        await tester.tap(tab('Parties'));
        await tester.pumpAndSettle();
        expect(find.text('All'), findsOneWidget);
        await tester.tap(find.text('Suppliers'));
        await tester.pumpAndSettle();
        expect(container.read(selectedPartyTypeFilterProvider), PartyType.supplier);
        await tester.tap(tab('Transactions'));
        await tester.pumpAndSettle();
        expect(find.text('No transactions yet'), findsOneWidget);
        await tester.tap(find.text('Dates'));
        await tester.pumpAndSettle();
        if (platform == TargetPlatform.iOS) {
          expect(find.byType(CupertinoDatePicker), findsOneWidget);
          await tester.tap(find.text('Apply'));
        } else {
          expect(find.byType(DateRangePickerDialog), findsOneWidget);
          Navigator.of(tester.element(find.byType(DateRangePickerDialog))).pop();
        }
        await tester.pumpAndSettle();
        await tester.tap(tab('Reports'));
        await tester.pumpAndSettle();
        expect(find.text('Payment summary'), findsOneWidget);
        expect(find.text('Party statements'), findsOneWidget);
        expect(find.text('Import parties from CSV'), findsOneWidget);
        await tester.ensureVisible(find.text('Import parties from CSV'));
        await tester.tap(find.text('Import parties from CSV'));
        await tester.pumpAndSettle();
        final csvField = platform == TargetPlatform.iOS
            ? find.byType(CupertinoTextField) : find.byType(TextField);
        await tester.enterText(csvField, 'Wrong,Type,Phone,Opening Balance');
        await tester.pumpAndSettle();
        expect(find.text('Use the header Name,Type,Phone,Opening Balance'), findsOneWidget);
        await tester.enterText(
          csvField,
          'Name,Type,Phone,Opening Balance\nNorth,Customer,,25.25',
        );
        await tester.pumpAndSettle();
        expect(find.text('North (Customer)'), findsOneWidget);
      }, variant: TargetPlatformVariant({platform}));
    }

    testWidgets('HomeShell renders DashboardScreen in ledger mode', (tester) async {
      final profile = UserProfile(
        id: 'usr_test',
        name: 'John Doe',
        phoneNumber: '+91 99999 00000',
        email: 'john@example.com',
        companies: [ledgerCompany],
        activeCompanyId: ledgerCompany.id,
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          userProfileProvider.overrideWith(() => _TestUserProfileNotifier(profile)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: HomeShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ledger mode shows DashboardScreen
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(ExpenseHomeScreen), findsNothing);
      expect(find.text('Acme Traders'), findsOneWidget);

      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pumpAndSettle();
      expect(find.text('Switch Workspace'), findsOneWidget);
      expect(find.text('Settings & Preferences'), findsOneWidget);
      expect(find.text('Cash Flow & Intelligence'), findsNothing);
      expect(find.text('ERP Modules & Licensing'), findsNothing);

      tester.state<ScaffoldState>(find.byType(Scaffold).first).closeDrawer();
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AdaptiveBottomNav), matching: find.text('Reports')));
      await tester.pumpAndSettle();
      expect(find.text('Outstanding balances'), findsOneWidget);
      expect(find.text('Transaction register'), findsOneWidget);
      expect(find.text('Custom SQL Studio'), findsNothing);
    });

    testWidgets('HomeShell renders ExpenseHomeScreen in expense mode', (tester) async {
      final profile = UserProfile(
        id: 'usr_test',
        name: 'John Doe',
        phoneNumber: '+91 99999 00000',
        email: 'john@example.com',
        companies: [expenseCompany],
        activeCompanyId: expenseCompany.id,
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          userProfileProvider.overrideWith(() => _TestUserProfileNotifier(profile)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: HomeShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expense mode shows ExpenseHomeScreen
      expect(find.byType(ExpenseHomeScreen), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);
      expect(find.text('Personal Expenses'), findsWidgets);
      expect(find.byKey(const Key('expense_balance_card')), findsNothing);
      expect(find.byKey(const Key('active_profile_indicator_pill')), findsOneWidget);
    });

    testWidgets('Switching company immediately swaps home screen and resets mode-specific state', (tester) async {
      final profileNotifier = _TestUserProfileNotifier(
        UserProfile(
          id: 'usr_test',
          name: 'John Doe',
          phoneNumber: '+91 99999 00000',
          email: 'john@example.com',
          companies: [ledgerCompany, expenseCompany],
          activeCompanyId: ledgerCompany.id,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          userProfileProvider.overrideWith(() => profileNotifier),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: HomeShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Initial State: Ledger Mode
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(ExpenseHomeScreen), findsNothing);

      // Modify mode-specific state: search query, filter, tab
      container.read(partySearchQueryProvider.notifier).setQuery('Searching Supplier');
      container.read(isPartySearchActiveProvider.notifier).setActive(true);
      container.read(selectedPartyTypeFilterProvider.notifier).setFilter(PartyType.supplier);
      expect(container.read(partySearchQueryProvider), equals('Searching Supplier'));
      expect(container.read(isPartySearchActiveProvider), isTrue);
      expect(container.read(selectedPartyTypeFilterProvider), equals(PartyType.supplier));

      // 2. Switch to Expense company
      container.read(companyControllerProvider.notifier).selectCompany(expenseCompany.id);
      await tester.pumpAndSettle();

      // 3. Verify immediate screen swap to ExpenseHomeScreen
      expect(find.byType(ExpenseHomeScreen), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);

      // 4. Verify mode-specific state was reset
      expect(container.read(partySearchQueryProvider), isEmpty);
      expect(container.read(isPartySearchActiveProvider), isFalse);
      expect(container.read(selectedPartyTypeFilterProvider), isNull);

      // 5. Switch back to Ledger company
      container.read(companyControllerProvider.notifier).selectCompany(ledgerCompany.id);
      await tester.pumpAndSettle();

      // 6. Verify immediate screen swap back to DashboardScreen
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(ExpenseHomeScreen), findsNothing);
    });
  });

  group('Hiding Ledger Concepts in Expense Mode', () {
    testWidgets('DashboardSidebarDrawer shows only Settings, Export, Sync, Switch Workspace in expense mode', (tester) async {
      final profile = UserProfile(
        id: 'usr_test',
        name: 'John Doe',
        phoneNumber: '+91 99999 00000',
        email: 'john@example.com',
        companies: [expenseCompany],
        activeCompanyId: expenseCompany.id,
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          userProfileProvider.overrideWith(() => _TestUserProfileNotifier(profile)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              drawer: const DashboardSidebarDrawer(),
              body: const Text('Main Body'),
            ),
          ),
        ),
      );

      // Open drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Verify ONLY the 4 permitted items are visible
      expect(find.text('Switch Workspace'), findsOneWidget);
      expect(find.text('Sync & Backup Center'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('Settings & Preferences'), findsOneWidget);

      // Verify ledger concepts are NOT shown
      expect(find.text('Cash Flow & Intelligence'), findsNothing);
      expect(find.text('ERP Modules & Licensing'), findsNothing);
    });

    testWidgets('ProfileScreen hides GSTIN, dealer type, and bank/UPI in expense mode', (tester) async {
      final profile = UserProfile(
        id: 'usr_test',
        name: 'John Doe',
        phoneNumber: '+91 99999 00000',
        email: 'john@example.com',
        businessName: 'Personal Wallet',
        gstin: '29ABCDE1234F1Z5',
        businessType: 'Regular',
        bankName: 'HDFC Bank',
        bankAccountNumber: '1234567890',
        bankIfsc: 'HDFC0001234',
        upiId: 'john@okhdfcbank',
        companies: [expenseCompany],
        activeCompanyId: expenseCompany.id,
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          userProfileProvider.overrideWith(() => _TestUserProfileNotifier(profile)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ProfileScreen(isStandalone: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify GSTIN, dealer type (business type), and banking remittance details are HIDDEN
      expect(find.text('GSTIN / Tax ID'), findsNothing);
      expect(find.text('Business Type'), findsNothing);
      expect(find.text('Banking & Remittance (Invoice Payment)'), findsNothing);
      expect(find.text('Item Master & Inventory'), findsNothing);
      expect(find.text('Statutory Audit Trail'), findsNothing);

      // Personal & account information is shown
      expect(find.text('Full Name'), findsWidgets);
      expect(find.text('Phone Number'), findsWidgets);
      expect(find.text('Account Name'), findsWidgets);
    });

    testWidgets('SettingsScreen hides GSTIN, cheque printing, signature, and e-invoice in expense mode', (tester) async {
      final profile = UserProfile(
        id: 'usr_test',
        name: 'John Doe',
        phoneNumber: '+91 99999 00000',
        email: 'john@example.com',
        companies: [expenseCompany],
        activeCompanyId: expenseCompany.id,
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          userProfileProvider.overrideWith(() => _TestUserProfileNotifier(profile)),
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

      // Verify GSTIN is hidden in subtitle
      expect(find.textContaining('GSTIN:'), findsNothing);
      expect(find.text('Personal Expense Tracker'), findsOneWidget);

      // Verify Invoicing & Statutory section is hidden
      expect(find.text('INVOICING, BRANDING & STATUTORY'), findsNothing);
      expect(find.text('CTS-2010 Cheque Printing'), findsNothing);
      expect(find.text('Signature & Company Branding'), findsNothing);
      expect(find.text('e-Invoice & GST Compliance'), findsNothing);

      // Verify Business Ledger Workspace, Security & Audit Logs, Master Reporting Hub and PRO badge are hidden in Expense Mode
      expect(find.text('Business Ledger Workspace'), findsNothing);
      expect(find.text('Security & Audit Logs'), findsNothing);
      expect(find.text('Master Reporting Hub'), findsNothing);
      expect(find.text('REPORTING & COMPLIANCE'), findsNothing);
      expect(find.text('PRO'), findsNothing);
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
