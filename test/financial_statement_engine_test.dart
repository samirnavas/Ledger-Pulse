import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/inventory_item_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/data/reporting/financial_statement_engine.dart';

void main() {
  group('Financial Statement Engine Tests (FR-RPT-01, FR-RPT-03)', () {
    late Company testCompany;
    late List<Party> sampleParties;
    late List<InventoryItem> sampleItems;
    late List<LedgerEntry> sampleEntries;
    late List<VoucherModel> sampleVouchers;

    setUp(() {
      testCompany = Company(
        id: 'cmp_1',
        name: 'Acme Enterprises',
        legalName: 'Acme Enterprises Ltd',
        gstin: '29ABCDE1234F1ZH',
        stateCode: '29',
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 1),
      );

      sampleParties = [
        Party(
          id: 'p1',
          name: 'Customer Alpha',
          phoneNumber: '+919999911111',
          type: PartyType.customer,
          netBalanceInCents: 150000, // 1500.00 Receivable
          lastUpdated: DateTime(2026, 1, 1),
        ),
        Party(
          id: 'p2',
          name: 'Supplier Beta',
          phoneNumber: '+919999922222',
          type: PartyType.supplier,
          netBalanceInCents: -80000, // 800.00 Payable
          lastUpdated: DateTime(2026, 1, 1),
        ),
      ];

      sampleItems = [
        InventoryItem(
          id: 'item_1',
          companyId: 'cmp_1',
          sku: 'SKU-BOLT-1',
          name: 'Steel Bolts',
          unit: 'KG',
          purchasePriceInCents: 5000,
          sellingPriceInCents: 8000,
          currentStockQuantity: 100, // 100 * 5000 = 500,000 cents (₹5000)
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ];

      sampleEntries = [
        LedgerEntry(
          id: 'entry_1',
          partyId: 'p1',
          amountInCents: 100000,
          type: EntryType.got,
          date: DateTime(2026, 9, 20),
        ),
      ];

      sampleVouchers = [
        VoucherModel(
          id: 'vch_s1',
          companyId: 'cmp_1',
          voucherNumber: 'INV-101',
          type: VoucherType.sales,
          partyId: 'p1',
          partyName: 'Customer Alpha',
          date: DateTime(2026, 9, 20),
          subtotalInCents: 200000,
          taxInCents: 36000,
          totalAmountInCents: 236000,
          createdAt: DateTime(2026, 9, 20),
          updatedAt: DateTime(2026, 9, 20),
        ),
        VoucherModel(
          id: 'vch_p1',
          companyId: 'cmp_1',
          voucherNumber: 'PUR-201',
          type: VoucherType.purchase,
          partyId: 'p2',
          partyName: 'Supplier Beta',
          date: DateTime(2026, 9, 21),
          subtotalInCents: 100000,
          taxInCents: 18000,
          totalAmountInCents: 118000,
          createdAt: DateTime(2026, 9, 21),
          updatedAt: DateTime(2026, 9, 21),
        ),
      ];
    });

    test('generateBalanceSheet calculates balanced Assets, Liabilities, and Equity', () {
      final report = FinancialStatementEngine.generateBalanceSheet(
        company: testCompany,
        parties: sampleParties,
        items: sampleItems,
        entries: sampleEntries,
        vouchers: sampleVouchers,
      );

      expect(report.metadata.id, equals('rpt_balance_sheet'));
      expect(report.columns.length, equals(3));
      expect(report.rows.isNotEmpty, isTrue);

      // Verify Summary metrics
      expect(report.summary.containsKey('totalAssets'), isTrue);
      expect(report.summary.containsKey('totalLiabilities'), isTrue);
      expect(report.summary['isBalanced'], isTrue);
    });

    test('generateProfitAndLoss computes Operating Revenue, COGS, and Net Profit', () {
      final pnl = FinancialStatementEngine.generateProfitAndLoss(
        company: testCompany,
        vouchers: sampleVouchers,
        items: sampleItems,
        entries: sampleEntries,
      );

      expect(pnl.metadata.id, equals('rpt_pnl'));
      expect(pnl.summary.containsKey('netProfit'), isTrue);
      expect(pnl.summary.containsKey('grossMargin'), isTrue);
      expect(pnl.rows.any((r) => r.get('particulars') == 'Gross Revenue from Operations (Sales)'), isTrue);
    });

    test('generateTrialBalance maintains mathematical Debit equals Credit equality', () {
      final tb = FinancialStatementEngine.generateTrialBalance(
        parties: sampleParties,
        vouchers: sampleVouchers,
        items: sampleItems,
      );

      expect(tb.metadata.id, equals('rpt_trial_balance'));
      expect(tb.summary.containsKey('totalDebit'), isTrue);
      expect(tb.summary.containsKey('totalCredit'), isTrue);
      expect(tb.summary['isBalanced'], isTrue);
    });

    test('generateDayBook aggregates all transactions sequentially', () {
      final dayBook = FinancialStatementEngine.generateDayBook(
        vouchers: sampleVouchers,
        entries: sampleEntries,
        targetDate: DateTime(2026, 9, 20),
      );

      expect(dayBook.metadata.id, equals('rpt_day_book'));
      expect(dayBook.rows.isNotEmpty, isTrue);
      expect(dayBook.rows.first.get('voucherNo'), equals('INV-101'));
    });

    test('generateCashFlowStatement computes operating inflows, outflows, and net liquidity', () {
      final cashFlow = FinancialStatementEngine.generateCashFlowStatement(
        vouchers: sampleVouchers,
        entries: sampleEntries,
      );

      expect(cashFlow.metadata.id, equals('rpt_cash_flow'));
      expect(cashFlow.summary.containsKey('netCashMovement'), isTrue);
      expect(cashFlow.rows.length, equals(4));
    });
  });
}
