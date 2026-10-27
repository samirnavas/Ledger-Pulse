import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/subscription_tier_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/domain/exceptions/ledger_exceptions.dart';
import 'package:ledger_pulse/presentation/home/create_company_flow.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';
import 'package:ledger_pulse/presentation/providers/subscription_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Prompt 6 - Mode-Aware Account Seeding Tests', () {
    late AppDatabase db;
    late DriftLedgerRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftLedgerRepository(db: db, postingEngine: null);
    });

    tearDown(() async {
      await db.close();
    });

    test('expense company has only wallets and categories (no GST, AR, AP)', () async {
      final expenseCompany = Company(
        id: 'cmp_expense_1',
        name: 'Personal Vault',
        legalName: 'Personal Vault',
        currencyCode: 'INR',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.budgets, AppModule.recurring},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Create company with initial wallet balances: Cash = ₹5,000, Bank = ₹25,000
      await repo.createCompany(
        expenseCompany,
        initialWalletBalancesInCents: {
          ExpenseTrackerDefaults.walletCashId: 500000,
          ExpenseTrackerDefaults.walletBankId: 2500000,
        },
      );

      final accounts = await (db.select(db.accounts)
            ..where((t) => t.companyId.equals('cmp_expense_1') & t.isDeleted.equals(false)))
          .get();

      // Check wallets
      final cashAccount = accounts.firstWhere((a) => a.id == 'cmp_expense_1_${ExpenseTrackerDefaults.walletCashId}');
      expect(cashAccount.name, equals('Cash'));
      expect(cashAccount.type, equals(AccountType.asset.name));
      expect(cashAccount.currentBalanceInCents, equals(500000));

      final bankAccount = accounts.firstWhere((a) => a.id == 'cmp_expense_1_${ExpenseTrackerDefaults.walletBankId}');
      expect(bankAccount.name, equals('Bank Account'));
      expect(bankAccount.type, equals(AccountType.asset.name));
      expect(bankAccount.currentBalanceInCents, equals(2500000));

      // Check opening balance equity balances the assets
      final equityAccount = accounts.firstWhere((a) => a.id == 'cmp_expense_1_${ExpenseTrackerDefaults.openingBalanceEquityId}');
      expect(equityAccount.currentBalanceInCents, equals(3000000)); // 500000 + 2500000

      // Check retained earnings exists
      final retainedEarnings = accounts.firstWhere((a) => a.id == 'cmp_expense_1_${ExpenseTrackerDefaults.retainedEarningsId}');
      expect(retainedEarnings.type, equals(AccountType.equity.name));

      // Check income categories (Salary, Other Income)
      final incomeAccounts = accounts.where((a) => a.type == AccountType.income.name).toList();
      expect(incomeAccounts.length, equals(2));
      expect(incomeAccounts.any((a) => a.name == 'Salary'), isTrue);
      expect(incomeAccounts.any((a) => a.name == 'Other Income'), isTrue);

      // Check expense categories (11 categories)
      final expenseAccounts = accounts.where((a) => a.type == AccountType.expense.name).toList();
      expect(expenseAccounts.length, equals(11));
      expect(expenseAccounts.any((a) => a.name == 'Food & Dining'), isTrue);
      expect(expenseAccounts.any((a) => a.name == 'Groceries'), isTrue);
      expect(expenseAccounts.any((a) => a.name == 'Transport'), isTrue);
      expect(expenseAccounts.any((a) => a.name == 'Housing/Rent'), isTrue);
      expect(expenseAccounts.any((a) => a.name == 'Utilities'), isTrue);
      expect(expenseAccounts.any((a) => a.name == 'Shopping'), isTrue);
      expect(expenseAccounts.any((a) => a.name == 'Health'), isTrue);
      expect(expenseAccounts.any((a) => a.name == 'Entertainment'), isTrue);
      expect(expenseAccounts.any((a) => a.name == 'Education'), isTrue);
      expect(expenseAccounts.any((a) => a.name == 'Travel'), isTrue);
      expect(expenseAccounts.any((a) => a.name == 'Other Expenses'), isTrue);

      // Verify NO GST accounts
      expect(accounts.any((a) => a.id.toLowerCase().contains('gst') || a.name.toLowerCase().contains('gst')), isFalse);

      // Verify NO AR (Sundry Debtors) or AP (Sundry Creditors) accounts
      expect(accounts.any((a) => a.id.contains(DefaultAccounts.arId) || a.name.contains('Debtors')), isFalse);
      expect(accounts.any((a) => a.id.contains(DefaultAccounts.apId) || a.name.contains('Creditors')), isFalse);

      // Verify NO Inventory accounts
      expect(accounts.any((a) => a.id.contains(DefaultAccounts.inventoryId) || a.name.contains('Inventory')), isFalse);

      // Total count: 2 wallets + 2 equity + 2 income + 11 expense = 17 accounts
      expect(accounts.length, equals(17));
    });

    test('ledger company gets the existing chart and chosen modules', () async {
      final chosenModules = {
        AppModule.parties,
        AppModule.vouchers,
        AppModule.gst,
        AppModule.advancedReports,
      };

      final ledgerCompany = Company(
        id: 'cmp_ledger_1',
        name: 'Apex Traders',
        legalName: 'Apex Traders LLP',
        currencyCode: 'INR',
        mode: CompanyMode.ledger,
        enabledModules: chosenModules,
        gstin: '29ABCDE1234F1ZH',
        stateCode: '29',
        dealerType: 'regular',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repo.createCompany(ledgerCompany);

      final accounts = await (db.select(db.accounts)
            ..where((t) => t.companyId.equals('cmp_ledger_1') & t.isDeleted.equals(false)))
          .get();

      // Check standard double-entry chart accounts exist
      expect(accounts.any((a) => a.id == 'cmp_ledger_1_${DefaultAccounts.arId}'), isTrue);
      expect(accounts.any((a) => a.id == 'cmp_ledger_1_${DefaultAccounts.apId}'), isTrue);
      expect(accounts.any((a) => a.id == 'cmp_ledger_1_${DefaultAccounts.inventoryId}'), isTrue);
      expect(accounts.any((a) => a.id == 'cmp_ledger_1_${DefaultAccounts.inputGstId}'), isTrue);
      expect(accounts.any((a) => a.id == 'cmp_ledger_1_${DefaultAccounts.outputGstId}'), isTrue);
      expect(accounts.any((a) => a.id == 'cmp_ledger_1_${DefaultAccounts.salesId}'), isTrue);
      expect(accounts.any((a) => a.id == 'cmp_ledger_1_${DefaultAccounts.purchasesCogsId}'), isTrue);

      final expectedDefaultCount = DefaultAccounts.getDefaultAccounts('cmp_ledger_1').length;
      expect(accounts.length, equals(expectedDefaultCount));

      // Verify company in DB has chosen modules
      final companyRow = await (db.select(db.companies)..where((t) => t.id.equals('cmp_ledger_1'))).getSingle();
      final decodedModules = (jsonDecode(companyRow.enabledModulesJson!) as List)
          .map((e) => AppModule.fromName(e.toString()))
          .toSet();

      expect(decodedModules, equals(chosenModules));
      expect(companyRow.mode, equals('ledger'));
    });
  });

  group('Prompt 6 - Company Limit Enforcement Tests', () {
    late AppDatabase db;
    late DriftLedgerRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftLedgerRepository(db: db, postingEngine: null);
    });

    tearDown(() async {
      await db.close();
    });

    test('SubscriptionTier.silver enforces maxCompanies limit of 1', () async {
      final silverLicense = LicenseState(
        tier: SubscriptionTier.silver,
        duration: BillingDuration.monthly,
        startDate: DateTime.now(),
        expiryDate: DateTime.now().add(const Duration(days: 30)),
      );

      final container = ProviderContainer(
        overrides: [
          driftLedgerRepositoryProvider.overrideWithValue(repo),
          subscriptionStateProvider.overrideWith(() => _StaticSubscriptionNotifier(silverLicense)),
          userProfileProvider.overrideWith(() => _TestProfileNotifier()),
        ],
      );

      final controller = container.read(companyControllerProvider.notifier);

      final firstCompany = Company(
        id: 'cmp_first',
        name: 'Single Company',
        legalName: 'Single Company',
        mode: CompanyMode.ledger,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // First company succeeds (0 -> 1)
      await controller.addCompany(firstCompany);

      final secondCompany = Company(
        id: 'cmp_second',
        name: 'Second Company (Blocked)',
        legalName: 'Second Company',
        mode: CompanyMode.ledger,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Second company must throw CompanyLimitExceededException
      expect(
        () => controller.addCompany(secondCompany),
        throwsA(isA<CompanyLimitExceededException>().having(
          (e) => e.maxCompanies,
          'maxCompanies',
          equals(1),
        )),
      );

      container.dispose();
    });
  });

  group('Prompt 6 - First-Run Onboarding Flow Widget Tests', () {
    late AppDatabase db;
    late DriftLedgerRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftLedgerRepository(db: db, postingEngine: null);
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('first-run flow creates an expense company from onboarding', (tester) async {
      final container = ProviderContainer(
        overrides: [
          driftLedgerRepositoryProvider.overrideWithValue(repo),
          userProfileProvider.overrideWith(() => _TestProfileNotifier()),
        ],
      );

      bool companyCreated = false;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: CreateCompanyFlow(
              isOnboarding: true,
              onCompanyCreated: () {
                companyCreated = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Step 0: Profile
      expect(find.text("Let's set up your entity"), findsOneWidget);
      expect(find.text('Company Name *'), findsOneWidget);

      // Enter company name
      await tester.enterText(find.byType(TextField).first, 'Family Budget');
      await tester.pumpAndSettle();

      // Tap Continue
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 1: Mode Picker
      expect(find.text('Choose your organization mode'), findsOneWidget);
      expect(find.text('Business Ledger'), findsOneWidget);
      expect(find.text('Expense Tracker'), findsOneWidget);

      // Select Expense Tracker
      await tester.tap(find.text('Expense Tracker'));
      await tester.pumpAndSettle();

      // Tap Continue
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 2: Wallets & Opening Balances
      expect(find.text('Wallet Setup & Opening Balances'), findsOneWidget);
      expect(find.text('Cash in Wallet Opening Balance'), findsOneWidget);
      expect(find.text('Bank Account Opening Balance'), findsOneWidget);

      // Enter wallet balances
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), '1200.00'); // Cash: ₹1200
      await tester.enterText(textFields.at(1), '45000.00'); // Bank: ₹45000
      await tester.pumpAndSettle();

      // Tap Create Company
      await tester.tap(find.text('Create Company'));
      await tester.pumpAndSettle();

      expect(companyCreated, isTrue);

      // Verify in DB
      final companies = await repo.getCompanies();
      expect(companies.length, equals(1));
      expect(companies.first.name, equals('Family Budget'));
      expect(companies.first.mode, equals(CompanyMode.expenseTracker));

      // Verify accounts seeded
      final accounts = await (db.select(db.accounts)
            ..where((t) => t.companyId.equals(companies.first.id)))
          .get();

      final cashAcc = accounts.firstWhere((a) => a.id == '${companies.first.id}_${ExpenseTrackerDefaults.walletCashId}');
      expect(cashAcc.currentBalanceInCents, equals(120000));

      final bankAcc = accounts.firstWhere((a) => a.id == '${companies.first.id}_${ExpenseTrackerDefaults.walletBankId}');
      expect(bankAcc.currentBalanceInCents, equals(4500000));

      container.dispose();
    });
  });
}

class _StaticSubscriptionNotifier extends SubscriptionNotifier {
  final LicenseState _initial;
  _StaticSubscriptionNotifier(this._initial);

  @override
  LicenseState build() => _initial;
}

class _TestProfileNotifier extends UserProfileNotifier {
  @override
  UserProfile build() {
    return UserProfile(
      id: 'usr_test',
      name: 'Test Admin',
      phoneNumber: '9876543210',
      email: 'admin@test.com',
      activeCompanyId: '',
      companies: [],
    );
  }

  @override
  void updateProfile(UserProfile profile) {
    state = profile;
  }
}
