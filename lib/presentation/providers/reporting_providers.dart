import '../../data/local/ledger_entry_balance.dart';
import 'package:drift/drift.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/transaction_model.dart';
import '../../data/models/voucher_model.dart';
import '../../data/reporting/financial_statement_engine.dart';
import '../../data/reporting/inventory_report_engine.dart';
import '../../data/reporting/report_catalog.dart';
import '../../data/reporting/report_models.dart';
import 'company_providers.dart';
import 'inventory_providers.dart';
import 'ledger_providers.dart';
import 'voucher_providers.dart';

const ledgerReports = [
  ReportMetadata(
    id: 'rpt_party_balances',
    title: 'Outstanding balances',
    category: ReportCategory.financial,
    description: 'Amounts to receive or pay, by party.',
  ),
  ReportMetadata(
    id: 'rpt_day_book',
    title: 'Transaction register',
    category: ReportCategory.financial,
    description: 'Ledger transaction history by date, including voids.',
  ),
  ReportMetadata(
    id: 'rpt_payments',
    title: 'Payment summary',
    category: ReportCategory.financial,
    description: 'Payments received and paid, based on posted cash or bank movements.',
  ),
];

final reportCatalogProvider = Provider<List<ReportMetadata>>((ref) {
  return ref.watch(activeCompanyProvider).isLedger
      ? ledgerReports
      : ReportCatalog.allReports;
});

class SelectedReportCategoryNotifier extends Notifier<ReportCategory?> {
  @override
  ReportCategory? build() => null;

  void selectCategory(ReportCategory? category) {
    state = category;
  }
}

final selectedReportCategoryProvider =
    NotifierProvider<SelectedReportCategoryNotifier, ReportCategory?>(
  SelectedReportCategoryNotifier.new,
);

/// Generates ReportData for a selected report ID
final dynamicReportDataProvider = FutureProvider.family<ReportData, String>((ref, reportId) async {
  final company = ref.watch(activeCompanyProvider);
  if (company.isLedger) {
    final metadata = ledgerReports.where((report) => report.id == reportId).firstOrNull;
    if (metadata == null) throw ArgumentError.value(reportId, 'reportId');

    ref.watch(ledgerUpdatesStreamProvider);
    final db = ref.watch(appDatabaseProvider);
    final parties = await (db.select(db.parties)
          ..where((t) => t.companyId.equals(company.id))
          ..orderBy([(t) => OrderingTerm.asc(t.name), (t) => OrderingTerm.asc(t.id)]))
        .get();

    if (reportId == 'rpt_party_balances') {
      final balances = await readLedgerPartyBalances(db, company.id);
      final outstanding = {
        for (final party in parties) party.id: balances[party.id] ?? party.netBalanceInCents,
      };
      return ReportData(
        metadata: metadata,
        columns: const [
          ReportColumn(key: 'party', label: 'Party'),
          ReportColumn(key: 'receive', label: 'To receive', isCurrency: true),
          ReportColumn(key: 'pay', label: 'To pay', isCurrency: true),
        ],
        rows: [
          for (final party in parties.where((party) => !party.isDeleted && outstanding[party.id] != 0))
            ReportRow({
              'party': party.name,
              'receive': outstanding[party.id]! > 0
                  ? CurrencyFormatter.format(outstanding[party.id]!, currencyCode: company.currencyCode)
                  : '',
              'pay': outstanding[party.id]! < 0
                  ? CurrencyFormatter.format(-outstanding[party.id]!, currencyCode: company.currencyCode)
                  : '',
            }),
        ],
        generatedAt: DateTime.now(),
      );
    }

    final names = {for (final party in parties) party.id: party.name};
    final entries = await (db.select(db.ledgerEntries)
          ..where((t) => t.companyId.equals(company.id))
          ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.createdAt), (t) => OrderingTerm.asc(t.id)]))
        .get();
    final balance = LedgerEntryBalance(entries);
    if (reportId == 'rpt_payments') {
      final journals = db.journals;
      final lines = db.journalLines;
      final vouchers = db.vouchers;
      final posted = journals.companyId.equals(company.id) &
          journals.status.equals('posted') & journals.isDeleted.equals(false);
      final movements = await (db.select(lines).join([
        innerJoin(journals, journals.id.equalsExp(lines.journalId)),
        leftOuterJoin(vouchers, vouchers.id.equalsExp(journals.voucherId) &
            vouchers.companyId.equals(company.id) & vouchers.isDeleted.equals(false) &
            vouchers.status.equals('posted') & vouchers.type.isIn(['receipt', 'payment'])),
      ])..where(posted & lines.companyId.equals(company.id) &
          lines.isDeleted.equals(false) & lines.accountId.isIn([
        '${company.id}_${DefaultAccounts.cashId}',
        '${company.id}_${DefaultAccounts.bankId}',
      ]))).get();
      final amounts = <String, int>{};
      final voucherMethods = <String, String>{};
      for (final movement in movements) {
        final journal = movement.readTable(journals);
        final voucher = movement.readTableOrNull(vouchers);
        final id = voucher != null
            ? 'vch_entry_${voucher.id}'
            : journal.id.startsWith('jnl_entry_')
                ? journal.id.substring('jnl_entry_'.length)
                : null;
        if (id == null) continue;
        final line = movement.readTable(lines);
        amounts.update(id, (value) => value + line.debitInCents - line.creditInCents,
            ifAbsent: () => line.debitInCents - line.creditInCents);
        if (voucher != null) {
          voucherMethods[id] = PaymentMode.values
              .where((mode) => mode.name == voucher.paymentMode).firstOrNull?.displayName ?? '';
        }
      }
      final payments = entries.where((entry) => (amounts[entry.id] ?? 0) != 0 &&
          !entry.isVoided && !entry.isDeleted && !balance.isLegacyOffset(entry)).toList();
      int received = 0;
      int paid = 0;
      for (final payment in payments) {
        final movement = amounts[payment.id]!;
        if (movement > 0) {
          received += movement;
        } else {
          paid -= movement;
        }
      }
      String amount(int cents) => CurrencyFormatter.format(cents, currencyCode: company.currencyCode);
      return ReportData(
        metadata: metadata,
        columns: const [
          ReportColumn(key: 'date', label: 'Date'),
          ReportColumn(key: 'party', label: 'Party'),
          ReportColumn(key: 'type', label: 'Movement'),
          ReportColumn(key: 'method', label: 'Method'),
          ReportColumn(key: 'amount', label: 'Amount', isCurrency: true),
        ],
        rows: [
          for (final payment in payments)
            ReportRow({
              'date': DateFormatter.formatShortDate(payment.date),
              'party': names[payment.partyId] ?? 'Archived party',
              'type': amounts[payment.id]! > 0 ? 'Payment received' : 'Payment paid',
              'method': (LedgerPaymentMethod.fromName(payment.paymentMethod) ??
                  LedgerPaymentMethod.read(payment.note))?.label ?? voucherMethods[payment.id] ?? '',
              'amount': amount(amounts[payment.id]!.abs()),
            }),
        ],
        summary: {'Received': amount(received), 'Paid': amount(paid)},
        generatedAt: DateTime.now(),
      );
    }
    return ReportData(
      metadata: metadata,
      columns: const [
        ReportColumn(key: 'date', label: 'Date'),
        ReportColumn(key: 'party', label: 'Party'),
        ReportColumn(key: 'direction', label: 'Transaction'),
        ReportColumn(key: 'amount', label: 'Amount', isCurrency: true),
        ReportColumn(key: 'note', label: 'Note'),
        ReportColumn(key: 'status', label: 'Status'),
      ],
      rows: [
        for (final entry in entries.where((entry) => !entry.isDeleted && !balance.isLegacyOffset(entry) && names.containsKey(entry.partyId)))
          ReportRow({
            'date': DateFormatter.formatShortDate(entry.date),
            'party': names[entry.partyId],
            'direction': entry.type == EntryType.gave ? 'You gave' : 'You got',
            'amount': CurrencyFormatter.format(entry.amountInCents, currencyCode: company.currencyCode),
            'note': LedgerPaymentMethod.strip(entry.note) ?? '',
            'status': entry.isVoided ? 'Voided' : 'Recorded',
          }),
      ],
      generatedAt: DateTime.now(),
    );
  }

  final parties = await ref.watch(partyListProvider.future);
  final vouchers = await ref.watch(vouchersListProvider(null).future);
  final items = await ref.watch(inventoryItemsListProvider.future);
  final db = ref.watch(appDatabaseProvider);

  // Fetch accounts and journal lines for the active company
  final accountRows = await (db.select(db.accounts)
        ..where((t) => t.companyId.equals(company.id) & t.isDeleted.equals(false)))
      .get();
  final convertedAccounts = accountRows
      .map((r) => AccountModel(
            id: r.id,
            companyId: r.companyId,
            code: r.code,
            name: r.name,
            type: AccountType.values.firstWhere(
              (e) => e.name.toLowerCase() == r.type.toLowerCase(),
              orElse: () => AccountType.asset,
            ),
            parentAccountId: r.parentAccountId,
            isSystem: r.isSystem,
            isActive: r.isActive,
            description: r.description,
            currentBalanceInCents: r.currentBalanceInCents,
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
          ))
      .toList();

  final journalLineRows = await (db.select(db.journalLines)
        ..where((t) => t.companyId.equals(company.id) & t.isDeleted.equals(false)))
      .get();
  final convertedJournalLines = journalLineRows
      .map((r) => JournalLineModel(
            id: r.id,
            companyId: r.companyId,
            journalId: r.journalId,
            accountId: r.accountId,
            partyId: r.partyId,
            debitInCents: r.debitInCents,
            creditInCents: r.creditInCents,
            narration: r.narration,
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
          ))
      .toList();

  final entries = await (db.select(db.ledgerEntries)
        ..where((t) => t.companyId.equals(company.id) & t.isDeleted.equals(false)))
      .get();

  final convertedEntries = entries
      .map((row) => LedgerEntry(
            id: row.id,
            partyId: row.partyId,
            amountInCents: row.amountInCents,
            type: row.type,
            date: row.date,
            note: row.note,
            receiptPhotoUrl: row.receiptPhotoUrl,
            isVoided: row.isVoided,
          ))
      .toList();

  switch (reportId) {
    case 'rpt_balance_sheet':
      return FinancialStatementEngine.generateBalanceSheet(
        company: company,
        parties: parties,
        items: items,
        entries: convertedEntries,
        vouchers: vouchers,
        accounts: convertedAccounts,
        journalLines: convertedJournalLines,
      );

    case 'rpt_pnl':
      return FinancialStatementEngine.generateProfitAndLoss(
        company: company,
        vouchers: vouchers,
        items: items,
        entries: convertedEntries,
        accounts: convertedAccounts,
        journalLines: convertedJournalLines,
      );

    case 'rpt_trial_balance':
      return FinancialStatementEngine.generateTrialBalance(
        parties: parties,
        vouchers: vouchers,
        items: items,
        accounts: convertedAccounts,
        journalLines: convertedJournalLines,
        companyId: company.id,
      );

    case 'rpt_day_book':
      return FinancialStatementEngine.generateDayBook(
        vouchers: vouchers,
        entries: convertedEntries,
      );

    case 'rpt_cash_flow':
      return FinancialStatementEngine.generateCashFlowStatement(
        vouchers: vouchers,
        entries: convertedEntries,
      );

    case 'rpt_stock_summary':
      return InventoryReportEngine.generateStockSummary(items: items);

    case 'rpt_low_stock':
      return InventoryReportEngine.generateLowStockRegister(items: items);

    default:
      return FinancialStatementEngine.generateBalanceSheet(
        company: company,
        parties: parties,
        items: items,
        entries: convertedEntries,
        vouchers: vouchers,
        accounts: convertedAccounts,
        journalLines: convertedJournalLines,
      );
  }
});

class DashboardBiMetrics {
  final int totalIncomeInCents;
  final int totalExpenseInCents;
  final int netProfitInCents;
  final int totalReceivableInCents;
  final int totalPayableInCents;
  final double salesVelocityPerDayInCents;
  final List<MonthlyTrendPoint> monthlyTrends;
  final List<CategoryShare> topExpenseCategories;

  const DashboardBiMetrics({
    required this.totalIncomeInCents,
    required this.totalExpenseInCents,
    required this.netProfitInCents,
    required this.totalReceivableInCents,
    required this.totalPayableInCents,
    required this.salesVelocityPerDayInCents,
    required this.monthlyTrends,
    required this.topExpenseCategories,
  });
}

class MonthlyTrendPoint {
  final String monthLabel;
  final int incomeInCents;
  final int expenseInCents;

  const MonthlyTrendPoint({
    required this.monthLabel,
    required this.incomeInCents,
    required this.expenseInCents,
  });
}

class CategoryShare {
  final String categoryName;
  final int amountInCents;
  final double percentage;

  const CategoryShare({
    required this.categoryName,
    required this.amountInCents,
    required this.percentage,
  });
}

final dashboardBiMetricsProvider = FutureProvider<DashboardBiMetrics>((ref) async {
  final (totalReceivable, totalPayable) = await ref.watch(businessSummaryProvider.future);
  final vouchers = await ref.watch(vouchersListProvider(null).future);

  int totalIncome = 0;
  int totalExpense = 0;

  final Map<String, int> monthlyIncome = {};
  final Map<String, int> monthlyExpense = {};
  final Map<String, int> expenseCategories = {};

  final now = DateTime.now();
  final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  // Seed last 4 months
  for (int i = 3; i >= 0; i--) {
    final d = DateTime(now.year, now.month - i, 1);
    final key = '${monthNames[d.month - 1]} ${d.year.toString().substring(2)}';
    monthlyIncome[key] = 0;
    monthlyExpense[key] = 0;
  }

  for (final v in vouchers) {
    final isIncome = v.type == VoucherType.sales || v.type == VoucherType.receipt || v.type == VoucherType.income;
    final isExpense = v.type == VoucherType.purchase || v.type == VoucherType.payment || v.type == VoucherType.expense;

    if (isIncome) {
      totalIncome += v.totalAmountInCents;
      final mKey = '${monthNames[v.date.month - 1]} ${v.date.year.toString().substring(2)}';
      if (monthlyIncome.containsKey(mKey)) {
        monthlyIncome[mKey] = (monthlyIncome[mKey] ?? 0) + v.totalAmountInCents;
      }
    } else if (isExpense) {
      totalExpense += v.totalAmountInCents;
      final mKey = '${monthNames[v.date.month - 1]} ${v.date.year.toString().substring(2)}';
      if (monthlyExpense.containsKey(mKey)) {
        monthlyExpense[mKey] = (monthlyExpense[mKey] ?? 0) + v.totalAmountInCents;
      }
      final cat = (v.narration != null && v.narration!.trim().isNotEmpty)
          ? v.narration!.trim()
          : (v.type == VoucherType.purchase ? 'Stock Purchases' : (v.type == VoucherType.expense ? 'Expenses' : 'Vendor Payments'));
      expenseCategories[cat] = (expenseCategories[cat] ?? 0) + v.totalAmountInCents;
    }
  }

  final trends = monthlyIncome.keys.map((k) {
    return MonthlyTrendPoint(
      monthLabel: k,
      incomeInCents: monthlyIncome[k] ?? 0,
      expenseInCents: monthlyExpense[k] ?? 0,
    );
  }).toList();

  final sortedCategories = expenseCategories.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top5 = sortedCategories.take(5).map((e) {
    final pct = totalExpense > 0 ? (e.value / totalExpense) * 100 : 0.0;
    return CategoryShare(categoryName: e.key, amountInCents: e.value, percentage: pct);
  }).toList();

  final salesVelocity = totalIncome > 0 ? (totalIncome / 30.0) : 0.0;

  return DashboardBiMetrics(
    totalIncomeInCents: totalIncome,
    totalExpenseInCents: totalExpense,
    netProfitInCents: totalIncome - totalExpense,
    totalReceivableInCents: totalReceivable,
    totalPayableInCents: totalPayable,
    salesVelocityPerDayInCents: salesVelocity,
    monthlyTrends: trends,
    topExpenseCategories: top5,
  );
});

