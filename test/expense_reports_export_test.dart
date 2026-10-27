import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/constants/mode_strings.dart';
import 'package:ledger_pulse/core/services/widget_sync_service.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/data/reporting/expense_report_engine.dart';
import 'package:ledger_pulse/data/reporting/report_export_service.dart';
import 'package:ledger_pulse/data/services/expense_csv_import_service.dart';
import 'package:ledger_pulse/domain/exceptions/ledger_exceptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<Map<String, dynamic>> widgetSavedData = [];

  setUp(() {
    widgetSavedData.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), (MethodCall call) async {
      if (call.method == 'saveWidgetData') {
        widgetSavedData.add(Map<String, dynamic>.from(call.arguments as Map));
        return true;
      }
      if (call.method == 'updateWidget') {
        return true;
      }
      if (call.method == 'setAppGroupId') {
        return true;
      }
      return null;
    });
  });

  // -------------------------------------------------------------
  // Fixed dataset for deterministic reporting tests
  // -------------------------------------------------------------
  final company = Company(
    id: 'cmp_test_expense',
    name: 'Personal Expenses',
    legalName: 'Personal Expenses Inc',
    currencyCode: 'INR',
    mode: CompanyMode.expenseTracker,
    enabledModules: {AppModule.dataImport, AppModule.budgets},
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final wCash = AccountModel(
    id: 'w_cash',
    companyId: company.id,
    code: '1001',
    name: 'Cash Wallet',
    type: AccountType.asset,
    currentBalanceInCents: 100000, // 1000.00
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final wBank = AccountModel(
    id: 'w_bank',
    companyId: company.id,
    code: '1002',
    name: 'Bank Account',
    type: AccountType.asset,
    currentBalanceInCents: 250000, // 2500.00
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final cGroceries = AccountModel(
    id: 'c_groceries',
    companyId: company.id,
    code: '5100',
    name: 'Groceries',
    type: AccountType.expense,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final cOrganic = AccountModel(
    id: 'c_organic',
    companyId: company.id,
    code: '5110',
    name: 'Organic Food',
    type: AccountType.expense,
    parentAccountId: 'c_groceries',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final cUtilities = AccountModel(
    id: 'c_utilities',
    companyId: company.id,
    code: '5200',
    name: 'Utilities',
    type: AccountType.expense,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final cSalary = AccountModel(
    id: 'c_salary',
    companyId: company.id,
    code: '4100',
    name: 'Salary',
    type: AccountType.income,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final testCategories = [cGroceries, cOrganic, cUtilities, cSalary];
  final testWallets = [wCash, wBank];

  final testVouchers = [
    // Month 1: October 2026
    VoucherModel(
      id: 'v_exp_1',
      companyId: company.id,
      voucherNumber: 'EXP-001',
      type: VoucherType.expense,
      date: DateTime(2026, 10, 5),
      status: VoucherStatus.posted,
      totalAmountInCents: 5000, // 50.00 groceries
      categoryAccountId: 'c_groceries',
      walletAccountId: 'w_cash',
      narration: 'Supermarket weekly run',
      createdAt: DateTime(2026, 10, 5),
      updatedAt: DateTime(2026, 10, 5),
    ),
    VoucherModel(
      id: 'v_exp_2',
      companyId: company.id,
      voucherNumber: 'EXP-002',
      type: VoucherType.expense,
      date: DateTime(2026, 10, 12),
      status: VoucherStatus.posted,
      totalAmountInCents: 3000, // 30.00 organic (sub of groceries)
      categoryAccountId: 'c_organic',
      walletAccountId: 'w_cash',
      narration: 'Farmer market fresh veg',
      createdAt: DateTime(2026, 10, 12),
      updatedAt: DateTime(2026, 10, 12),
    ),
    VoucherModel(
      id: 'v_exp_3',
      companyId: company.id,
      voucherNumber: 'EXP-003',
      type: VoucherType.expense,
      date: DateTime(2026, 10, 15),
      status: VoucherStatus.posted,
      totalAmountInCents: 12000, // 120.00 utilities
      categoryAccountId: 'c_utilities',
      walletAccountId: 'w_bank',
      narration: 'Electricity and water bills',
      createdAt: DateTime(2026, 10, 15),
      updatedAt: DateTime(2026, 10, 15),
    ),
    VoucherModel(
      id: 'v_inc_1',
      companyId: company.id,
      voucherNumber: 'INC-001',
      type: VoucherType.income,
      date: DateTime(2026, 10, 1),
      status: VoucherStatus.posted,
      totalAmountInCents: 50000, // 500.00 salary
      categoryAccountId: 'c_salary',
      walletAccountId: 'w_bank',
      narration: 'Monthly pay',
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
    ),
    VoucherModel(
      id: 'v_trf_1',
      companyId: company.id,
      voucherNumber: 'TRF-001',
      type: VoucherType.transfer,
      date: DateTime(2026, 10, 10),
      status: VoucherStatus.posted,
      totalAmountInCents: 10000, // 100.00 bank to cash
      walletAccountId: 'w_bank',
      toWalletAccountId: 'w_cash',
      narration: 'ATM withdrawal',
      createdAt: DateTime(2026, 10, 10),
      updatedAt: DateTime(2026, 10, 10),
    ),

    // Month 2: September 2026
    VoucherModel(
      id: 'v_exp_4',
      companyId: company.id,
      voucherNumber: 'EXP-004',
      type: VoucherType.expense,
      date: DateTime(2026, 9, 8),
      status: VoucherStatus.posted,
      totalAmountInCents: 7000, // 70.00 groceries
      categoryAccountId: 'c_groceries',
      walletAccountId: 'w_cash',
      narration: 'Groceries September',
      createdAt: DateTime(2026, 9, 8),
      updatedAt: DateTime(2026, 9, 8),
    ),
    VoucherModel(
      id: 'v_inc_2',
      companyId: company.id,
      voucherNumber: 'INC-002',
      type: VoucherType.income,
      date: DateTime(2026, 9, 1),
      status: VoucherStatus.posted,
      totalAmountInCents: 50000, // 500.00 salary
      categoryAccountId: 'c_salary',
      walletAccountId: 'w_bank',
      narration: 'Monthly pay September',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    ),

    // Month 3: August 2026
    VoucherModel(
      id: 'v_exp_5',
      companyId: company.id,
      voucherNumber: 'EXP-005',
      type: VoucherType.expense,
      date: DateTime(2026, 8, 10),
      status: VoucherStatus.posted,
      totalAmountInCents: 15000, // 150.00 utilities
      categoryAccountId: 'c_utilities',
      walletAccountId: 'w_bank',
      narration: 'Annual utility catch-up',
      createdAt: DateTime(2026, 8, 10),
      updatedAt: DateTime(2026, 8, 10),
    ),
    VoucherModel(
      id: 'v_inc_3',
      companyId: company.id,
      voucherNumber: 'INC-003',
      type: VoucherType.income,
      date: DateTime(2026, 8, 1),
      status: VoucherStatus.posted,
      totalAmountInCents: 45000, // 450.00 salary
      categoryAccountId: 'c_salary',
      walletAccountId: 'w_bank',
      narration: 'August pay',
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
    ),

    // Voided voucher (must be ignored in reports)
    VoucherModel(
      id: 'v_exp_void',
      companyId: company.id,
      voucherNumber: 'EXP-VOID',
      type: VoucherType.expense,
      date: DateTime(2026, 10, 20),
      status: VoucherStatus.voided,
      totalAmountInCents: 99999,
      categoryAccountId: 'c_groceries',
      walletAccountId: 'w_cash',
      createdAt: DateTime(2026, 10, 20),
      updatedAt: DateTime(2026, 10, 20),
    ),
  ];

  group('ExpenseReportEngine Numbers on Fixed Dataset', () {
    test('calculateSpendingByCategory computes sub-category rollups and percentages', () {
      final report = ExpenseReportEngine.calculateSpendingByCategory(
        vouchers: testVouchers,
        categories: testCategories,
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31, 23, 59, 59),
      );

      // Total spent in October = 5000 + 3000 + 12000 = 20000 cents
      expect(report.totalSpentInCents, 20000);
      expect(report.totalSpent, 200.0);
      expect(report.categories.length, 2); // Utilities and Groceries

      // Top category is Utilities (12000 > 8000)
      final utilities = report.categories.firstWhere((c) => c.categoryId == 'c_utilities');
      expect(utilities.totalSpentInCents, 12000);
      expect(utilities.percentage, 60.0); // 12000 / 20000 = 60%
      expect(utilities.transactionCount, 1);

      // Groceries rolls up own spend (5000) + sub-category organic (3000) = 8000
      final groceries = report.categories.firstWhere((c) => c.categoryId == 'c_groceries');
      expect(groceries.totalSpentInCents, 8000);
      expect(groceries.percentage, 40.0); // 8000 / 20000 = 40%
      expect(groceries.transactionCount, 2);
      expect(groceries.subCategories.length, 1);

      final organic = groceries.subCategories.first;
      expect(organic.categoryId, 'c_organic');
      expect(organic.totalSpentInCents, 3000);
      expect(organic.percentage, 15.0); // 3000 / 20000 = 15%
    });

    test('calculateMonthlyTrend computes trends over last 3 months', () {
      final report = ExpenseReportEngine.calculateMonthlyTrend(
        vouchers: testVouchers,
        referenceDate: DateTime(2026, 10, 31),
        months: 3,
      );

      expect(report.months.length, 3);
      // Chronological: August, September, October
      final aug = report.months[0];
      expect(aug.month.month, 8);
      expect(aug.totalIncomeInCents, 45000);
      expect(aug.totalExpenseInCents, 15000);
      expect(aug.netSavingsInCents, 30000);
      expect(aug.savingsRate, closeTo(66.66, 0.1));

      final sep = report.months[1];
      expect(sep.month.month, 9);
      expect(sep.totalIncomeInCents, 50000);
      expect(sep.totalExpenseInCents, 7000);
      expect(sep.netSavingsInCents, 43000);
      expect(sep.savingsRate, closeTo(86.0, 0.1));

      final oct = report.months[2];
      expect(oct.month.month, 10);
      expect(oct.totalIncomeInCents, 50000);
      expect(oct.totalExpenseInCents, 20000);
      expect(oct.netSavingsInCents, 30000);
      expect(oct.savingsRate, closeTo(60.0, 0.1));

      // Grand totals: Income 45000+50000+50000 = 145000, Expense 15000+7000+20000 = 42000
      expect(report.totalIncomeInCents, 145000);
      expect(report.totalExpenseInCents, 42000);
      expect(report.totalNetSavingsInCents, 103000);
      expect(report.averageMonthlyExpenseInCents, closeTo(14000.0, 0.1));
    });

    test('calculateIncomeVsExpense computes savings rate and transaction counts', () {
      final report = ExpenseReportEngine.calculateIncomeVsExpense(
        vouchers: testVouchers,
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31, 23, 59, 59),
      );

      expect(report.totalIncomeInCents, 50000);
      expect(report.totalExpenseInCents, 20000);
      expect(report.netSavingsInCents, 30000);
      expect(report.savingsRate, 60.0);
      expect(report.incomeTransactionCount, 1);
      expect(report.expenseTransactionCount, 3);
      expect(report.transferTransactionCount, 1);
    });

    test('calculateWalletBalanceHistory computes wallet inflows and outflows', () {
      final report = ExpenseReportEngine.calculateWalletBalanceHistory(
        wallets: testWallets,
        vouchers: testVouchers,
        asOfDate: DateTime(2026, 10, 31, 23, 59, 59),
      );

      expect(report.wallets.length, 2);
      final cashWallet = report.wallets.firstWhere((w) => w.walletId == 'w_cash');
      // Inflow into cash: ATM withdrawal transfer = 10000
      expect(cashWallet.totalInInCents, 10000);
      // Outflows from cash: groceries (5000), organic (3000), sept groceries (7000) = 15000
      expect(cashWallet.totalOutInCents, 15000);

      final bankWallet = report.wallets.firstWhere((w) => w.walletId == 'w_bank');
      // Inflow into bank: 3 salary deposits (50000 + 50000 + 45000) = 145000
      expect(bankWallet.totalInInCents, 145000);
      // Outflows from bank: utilities Oct (12000), utilities Aug (15000), transfer out (10000) = 37000
      expect(bankWallet.totalOutInCents, 37000);
    });

    test('generateProfitAndLoss reuses FinancialStatementEngine for P&L data', () {
      final pnl = ExpenseReportEngine.generateProfitAndLoss(
        company: company,
        vouchers: testVouchers,
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31, 23, 59, 59),
      );

      expect(pnl.metadata.id, 'rpt_pnl');
      expect(pnl.rows.isNotEmpty, isTrue);
    });
  });

  group('CSV Export Content & Round Trip', () {
    test('exportTransactionsCsv produces UTF-8 BOM, valid header and summary', () async {
      final octVouchers = testVouchers
          .where((v) => v.date.month == 10 && v.status != VoucherStatus.voided)
          .toList();

      final catNames = {for (final c in testCategories) c.id: c.name};
      final walNames = {for (final w in testWallets) w.id: w.name};

      final file = await ReportExportService.exportTransactionsCsv(
        transactions: octVouchers,
        company: company,
        categoryNames: catNames,
        walletNames: walNames,
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31),
        outputDirectory: Directory.systemTemp,
      );

      expect(file.existsSync(), isTrue);
      final bytes = await file.readAsBytes();
      // Must start with UTF-8 BOM (0xEF, 0xBB, 0xBF)
      expect(bytes[0], 0xEF);
      expect(bytes[1], 0xBB);
      expect(bytes[2], 0xBF);

      final content = await file.readAsString();

      // Must contain header row
      expect(content.contains('"Date","Voucher No","Type","Category","Wallet / Account","To Wallet","Amount","Narration","Reference","Status"'), isTrue);

      // Must contain row data
      expect(content.contains('"EXP-001"'), isTrue);
      expect(content.contains('"Groceries"'), isTrue);
      expect(content.contains('"Cash Wallet"'), isTrue);
      expect(content.contains('"50.00"'), isTrue);
      expect(content.contains('"500.00"'), isTrue); // salary

      // Must contain summary
      expect(content.contains('"Total Income","500.00"'), isTrue);
      expect(content.contains('"Total Expense","200.00"'), isTrue);
      expect(content.contains('"Net Savings","300.00"'), isTrue);

      // Clean up
      try {
        file.deleteSync();
      } catch (_) {}
    });

    test('CSV import round trip: parseTransactionsCsv correctly parses exported CSV', () async {
      final octVouchers = testVouchers
          .where((v) => v.date.month == 10 && v.status != VoucherStatus.voided)
          .toList();

      final catNames = {for (final c in testCategories) c.id: c.name};
      final walNames = {for (final w in testWallets) w.id: w.name};

      final file = await ReportExportService.exportTransactionsCsv(
        transactions: octVouchers,
        company: company,
        categoryNames: catNames,
        walletNames: walNames,
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31),
        outputDirectory: Directory.systemTemp,
      );

      final csvContent = await file.readAsString();

      // Parse with ExpenseCsvImportService
      final parseResult = ExpenseCsvImportService.parseTransactionsCsv(
        csvContent: csvContent,
        company: company,
      );

      // All 5 transactions should be parsed and valid
      expect(parseResult.totalCount, 5);
      expect(parseResult.validCount, 5);
      expect(parseResult.invalidCount, 0);

      // Check first expense
      final exp1 = parseResult.rows.firstWhere((r) => r.categoryName == 'Groceries' && r.amountInCents == 5000);
      expect(exp1.type, VoucherType.expense);
      expect(exp1.walletName, 'Cash Wallet');

      // Check salary income
      final inc1 = parseResult.rows.firstWhere((r) => r.amountInCents == 50000);
      expect(inc1.type, VoucherType.income);
      expect(inc1.walletName, 'Bank Account');

      // Check transfer
      final trf1 = parseResult.rows.firstWhere((r) => r.type == VoucherType.transfer);
      expect(trf1.amountInCents, 10000);
      expect(trf1.walletName, 'Bank Account');
      expect(trf1.toWalletName, 'Cash Wallet');

      // Clean up
      try {
        file.deleteSync();
      } catch (_) {}
    });

    test('ExpenseCsvImportService throws ModuleDisabledException when dataImport is disabled', () {
      final disabledCompany = company.copyWith(
        enabledModules: {AppModule.budgets}, // no dataImport
      );

      expect(
        () => ExpenseCsvImportService.parseTransactionsCsv(
          csvContent: 'Date,Amount\n2026-10-01,100',
          company: disabledCompany,
        ),
        throwsA(isA<ModuleDisabledException>()),
      );
    });
  });

  group('Widget Payload for Expense Mode', () {
    test('syncWidgetData saves expense month spend and income with company_id deep link', () async {
      // In test environment, HomeWidget channel calls are mocked by TestWidgetsFlutterBinding
      final ok = await WidgetSyncService.syncWidgetData(
        company: company,
        monthSpendCents: 20000, // 200.00
        monthIncomeCents: 50000, // 500.00
      );

      expect(ok, isTrue);

      final Map<String, dynamic> mergedData = {};
      for (final call in widgetSavedData) {
        final id = call['id'] as String?;
        final data = call['data'];
        if (id != null) mergedData[id] = data;
      }

      expect(mergedData['company_name'], 'Personal Expenses');
      expect(mergedData['company_id'], 'cmp_test_expense');
      expect(mergedData['mode'], 'expenseTracker');
      expect(mergedData['cash_in_label'], "This Month's Income");
      expect(mergedData['cash_out_label'], "This Month's Spend");
      expect(mergedData['cash_in_raw'], 500.0);
      expect(mergedData['cash_out_raw'], 200.0);
      expect(mergedData['deep_link_uri'], 'ledgerpulse://dashboard?company_id=cmp_test_expense');
    });
  });

  group('ModeStrings Helper Completeness', () {
    test('All ModeStrings adapt accurately based on CompanyMode', () {
      final expenseStrings = ModeStrings.of(CompanyMode.expenseTracker);
      final ledgerStrings = ModeStrings.of(CompanyMode.ledger);

      // App and titles
      expect(expenseStrings.appTitle, 'ExpensePulse');
      expect(ledgerStrings.appTitle, 'LedgerPulse');
      expect(expenseStrings.modeBadge, 'EXPENSE');
      expect(ledgerStrings.modeBadge, 'LEDGER');

      // Metrics
      expect(expenseStrings.primaryMetricLabel, 'Total Spent');
      expect(ledgerStrings.primaryMetricLabel, "You'll Get");
      expect(expenseStrings.secondaryMetricLabel, 'Total Income');
      expect(ledgerStrings.secondaryMetricLabel, "You'll Give");
      expect(expenseStrings.netLabel, 'Net Savings');
      expect(ledgerStrings.netLabel, 'Net Profit');

      // Tabs & Actions
      expect(expenseStrings.transactionsTab, 'Transactions');
      expect(ledgerStrings.transactionsTab, 'Daybook');
      expect(expenseStrings.reportsTab, 'Reports');
      expect(ledgerStrings.reportsTab, 'Analytics');
      expect(expenseStrings.addTransaction, 'Add Transaction');
      expect(ledgerStrings.addTransaction, 'Add Voucher');
      expect(expenseStrings.categoriesLabel, 'Categories');
      expect(ledgerStrings.categoriesLabel, 'Ledger Accounts');
      expect(expenseStrings.walletsLabel, 'Wallets & Accounts');
      expect(ledgerStrings.walletsLabel, 'Cash & Bank Accounts');
    });
  });
}
