import '../../data/models/company_mode.dart';

/// Centralized strings that adapt based on whether the active company is in
/// [CompanyMode.ledger] (business B2B/B2C ledger) or [CompanyMode.expenseTracker] (personal/family expense tracking).
class ModeStrings {
  final CompanyMode mode;

  const ModeStrings(this.mode);

  bool get isExpense => mode == CompanyMode.expenseTracker;
  bool get isLedger => mode == CompanyMode.ledger;

  static ModeStrings of(CompanyMode mode) => ModeStrings(mode);

  // App & Shell Titles
  String get appTitle => isExpense ? 'ExpensePulse' : 'LedgerPulse';
  String get modeBadge => isExpense ? 'EXPENSE' : 'LEDGER';
  String get modeDisplayName => isExpense ? 'Expense Tracker' : 'Business Ledger';
  String get homeTitle => isExpense ? 'Expense Tracker' : 'Dashboard';

  // Company / Entity Labeling
  String get entityLabel => isExpense ? 'Account' : 'Company';
  String get entityLabelPlural => isExpense ? 'Accounts' : 'Companies';
  String get switchEntity => isExpense ? 'Switch Account' : 'Switch Company';
  String get addEntity => isExpense ? 'Add New Account' : 'Add New Company';
  String get entitySubtitlePlaceholder =>
      isExpense ? 'Personal Expense Tracker' : 'Personal / Sole Trader';

  // Metrics & Totals
  String get balanceTitle => isExpense ? 'Total Balance' : 'Net Outstanding';
  String get primaryMetricLabel => isExpense ? 'Total Spent' : "You'll Get";
  String get secondaryMetricLabel => isExpense ? 'Total Income' : "You'll Give";
  String get primaryBalanceTag => isExpense ? 'SPENT' : 'RECEIVABLE';
  String get secondaryBalanceTag => isExpense ? 'INCOME' : 'PAYABLE';
  String get spentThisMonth => isExpense ? 'Spent this month' : 'Purchases this month';
  String get incomeThisMonth => isExpense ? 'Income this month' : 'Sales this month';
  String get netLabel => isExpense ? 'Net Savings' : 'Net Profit';
  String get savingsRateLabel => isExpense ? 'Savings Rate' : 'Gross Margin';

  // Navigation & Tabs
  String get homeTab => isExpense ? 'Home' : 'Dashboard';
  String get transactionsTab => isExpense ? 'Transactions' : 'Daybook';
  String get reportsTab => isExpense ? 'Reports' : 'Analytics';
  String get accountsTab => isExpense ? 'My Profile' : 'Chart of Accounts';
  String get budgetsTab => isExpense ? 'Budgets' : 'Inventory';
  String get allExpensesTab => isExpense ? 'All Expenses' : 'All Vouchers';
  String get dailyTab => isExpense ? 'Daily' : 'Daily Daybook';
  String get weeklyTab => isExpense ? 'Weekly' : 'Weekly Summary';
  String get monthlyTab => isExpense ? 'Monthly' : 'Monthly Summary';
  String get categoriesTab => isExpense ? 'Categories' : 'Account Groups';
  String get recurringTab => isExpense ? 'Recurring' : 'Recurring Vouchers';
  String get budgetsTabTitle => isExpense ? 'Monthly Budgets' : 'Budget Allocations';

  // Records / Items
  String get recordsLabel => isExpense ? 'Expenses & Transfers' : 'Customers & Suppliers';
  String get transactionLabel => isExpense ? 'Transaction' : 'Voucher';
  String get transactionLabelPlural => isExpense ? 'Transactions' : 'Vouchers';
  String get searchHint =>
      isExpense ? 'Search expenses, categories & notes...' : 'Search by name or number...';
  String get emptyRecordsTitle =>
      isExpense ? 'No expenses recorded yet' : 'No parties found';
  String get emptyRecordsSubtitle => isExpense
      ? 'Tap + to record your first expense or income transaction'
      : 'Add your first customer or supplier to get started';
  String get emptyTransactionsTitle =>
      isExpense ? 'No transactions found' : 'No vouchers recorded';
  String get emptyTransactionsSubtitle => isExpense
      ? 'Record your first expense, income, or transfer'
      : 'Create your first invoice, payment, or receipt';
  String get emptyBudgetsTitle =>
      isExpense ? 'No budgets set' : 'No budgets configured';
  String get emptyBudgetsSubtitle => isExpense
      ? 'Set monthly spending limits to keep track of expenses'
      : 'Configure department or project budgets';
  String get emptyRecurringTitle =>
      isExpense ? 'No recurring transactions' : 'No recurring vouchers';
  String get emptyRecurringSubtitle => isExpense
      ? 'Schedule subscriptions, bills, or regular income'
      : 'Automate regular invoices, bills, or recurring salaries';
  String get emptyCategoriesTitle =>
      isExpense ? 'No categories found' : 'No ledger accounts found';
  String get emptyCategoriesSubtitle => isExpense
      ? 'Add categories to organize your expenses'
      : 'Add accounts to chart of accounts';
  String get emptyWalletsTitle =>
      isExpense ? 'No wallets or bank accounts' : 'No cash or bank accounts';
  String get emptyWalletsSubtitle => isExpense
      ? 'Add your cash wallets, bank accounts, or cards'
      : 'Add cash and bank ledgers to track balances';

  // Section Headers
  String get recentTransactionsHeader =>
      isExpense ? 'Recent Transactions' : 'Recent Vouchers';
  String get spendingOverviewHeader =>
      isExpense ? 'Spending Overview' : 'Business Overview';
  String get budgetStatusHeader =>
      isExpense ? 'Budget Status' : 'Budget vs Actual';
  String get recurringBillsHeader =>
      isExpense ? 'Upcoming Bills & Subscriptions' : 'Upcoming Recurring Entries';
  String get topCategoriesHeader =>
      isExpense ? 'Top Spending Categories' : 'Top Expense Ledgers';
  String get accountsOverviewHeader =>
      isExpense ? 'Accounts & Wallets' : 'Cash & Bank Balances';
  String get analyticsHeader =>
      isExpense ? 'Spending Analytics' : 'Financial Analytics';
  String get breakdownHeader =>
      isExpense ? 'Expense Breakdown' : 'Cost Breakdown';

  // Budget & Recurring
  String get budgetLabel => isExpense ? 'Budget' : 'Budget Target';
  String get budgetsLabelPlural => isExpense ? 'Budgets' : 'Budget Allocations';
  String get createBudget => isExpense ? 'Create Budget' : 'Add Budget Target';
  String get editBudget => isExpense ? 'Edit Budget' : 'Edit Budget Target';
  String get budgetRemaining => isExpense ? 'Remaining Budget' : 'Available Budget';
  String get budgetOverspent => isExpense ? 'Over Budget' : 'Budget Exceeded';
  String get budgetProgress => isExpense ? 'Budget Spent' : 'Budget Utilized';
  String get totalBudgeted => isExpense ? 'Total Budgeted' : 'Total Budgeted';
  String get recurringLabel =>
      isExpense ? 'Recurring Transaction' : 'Recurring Voucher';
  String get recurringLabelPlural =>
      isExpense ? 'Recurring Transactions' : 'Recurring Vouchers';
  String get addRecurring =>
      isExpense ? 'Add Recurring' : 'Add Recurring Voucher';
  String get editRecurring =>
      isExpense ? 'Edit Recurring' : 'Edit Recurring Voucher';
  String get nextDueDate => isExpense ? 'Next Due Date' : 'Next Execution Date';
  String get repeatFrequency => isExpense ? 'Frequency' : 'Recurrence Interval';
  String get recurringActive => isExpense ? 'Active Schedules' : 'Active Schedules';
  String get recurringPaused => isExpense ? 'Paused Schedules' : 'Paused Schedules';

  // Transaction Actions
  String get addTransaction => isExpense ? 'Add Transaction' : 'Add Voucher';
  String get recordExpense => isExpense ? 'Record Expense' : 'Create Payment';
  String get recordIncome => isExpense ? 'Record Income' : 'Create Receipt';
  String get recordTransfer => isExpense ? 'Transfer Money' : 'Contra Entry';
  String get transactionHistory => isExpense ? 'Transaction History' : 'Voucher Register';
  String get filterTransactions => isExpense ? 'Filter Transactions' : 'Filter Vouchers';
  String get deleteTransactionPrompt =>
      isExpense ? 'Delete this transaction?' : 'Void this voucher?';

  // Accounts & Headings
  String get categoriesLabel => isExpense ? 'Categories' : 'Ledger Accounts';
  String get walletsLabel => isExpense ? 'Wallets & Accounts' : 'Cash & Bank Accounts';
  String get monthlyTrendTitle =>
      isExpense ? 'Monthly Spending Trend' : 'Monthly Financial Trend';

  // Import / Export
  String get exportActionLabel => isExpense ? 'Export' : 'Reports & Analytics Hub';
  String get exportActionSubtitle => isExpense
      ? 'Download expense history, CSV & PDF summary'
      : 'Daybook, P&L, GST & Party analytics';
  String get importTransactionsTitle =>
      isExpense ? 'Import Transactions (CSV)' : 'Import Ledgers & Items (XML/CSV)';
  String get exportTransactionsTitle =>
      isExpense ? 'Export Transactions (CSV / PDF)' : 'Export Statements & Daybook';
}
