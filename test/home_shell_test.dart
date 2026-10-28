import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/constants/mode_strings.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/sync_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/presentation/expense/expense_home_screen.dart';
import 'package:ledger_pulse/presentation/home/dashboard_screen.dart';
import 'package:ledger_pulse/presentation/home/dashboard_sidebar_drawer.dart';
import 'package:ledger_pulse/presentation/home/home_shell.dart';
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
      expect(find.byKey(const Key('expense_balance_card')), findsOneWidget);
      expect(find.byKey(const Key('expense_company_switcher_button')), findsOneWidget);
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
      expect(container.read(selectedPartyTypeFilterProvider), equals(PartyType.customer));

      // 5. Switch back to Ledger company
      container.read(companyControllerProvider.notifier).selectCompany(ledgerCompany.id);
      await tester.pumpAndSettle();

      // 6. Verify immediate screen swap back to DashboardScreen
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(ExpenseHomeScreen), findsNothing);
    });
  });

  group('Hiding Ledger Concepts in Expense Mode', () {
    testWidgets('DashboardSidebarDrawer shows only Settings, Export, Sync, Switch company in expense mode', (tester) async {
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
              drawer: DashboardSidebarDrawer(
                onOpenBiHub: () {},
                onOpenErpModules: () {},
              ),
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
      expect(find.text('Switch Company'), findsOneWidget);
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
