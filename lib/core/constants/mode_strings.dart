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
  String get netLabel => isExpense ? 'Net Savings' : 'Net Profit';
  String get savingsRateLabel => isExpense ? 'Savings Rate' : 'Gross Margin';

  // Navigation & Tabs
  String get homeTab => isExpense ? 'Home' : 'Dashboard';
  String get transactionsTab => isExpense ? 'Transactions' : 'Daybook';
  String get reportsTab => isExpense ? 'Reports' : 'Analytics';
  String get accountsTab => isExpense ? 'Accounts' : 'Chart of Accounts';
  String get budgetsTab => isExpense ? 'Budgets' : 'Inventory';

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
