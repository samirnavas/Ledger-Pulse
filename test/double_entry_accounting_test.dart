import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/utils/currency_formatter.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/journal_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/data/reporting/financial_statement_engine.dart';
import 'package:ledger_pulse/domain/exceptions/ledger_exceptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late AuditService auditService;
  late VoucherPostingEngine postingEngine;
  late DriftLedgerRepository ledgerRepo1;
  late DriftLedgerRepository ledgerRepo2;
  late DriftVoucherRepository voucherRepo1;

  const company1 = 'cmp_company_1';
  const company2 = 'cmp_company_2';
  const userId = 'usr_test_admin';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auditService = AuditService(db);
    postingEngine = VoucherPostingEngine(db, auditService);

    ledgerRepo1 = DriftLedgerRepository(
      db: db,
      postingEngine: postingEngine,
      currentCompanyId: company1,
      currentUserId: userId,
    );

    ledgerRepo2 = DriftLedgerRepository(
      db: db,
      postingEngine: postingEngine,
      currentCompanyId: company2,
      currentUserId: userId,
    );

    voucherRepo1 = DriftVoucherRepository(
      db: db,
      auditService: auditService,
      postingEngine: postingEngine,
      currentCompanyId: company1,
      currentUserId: userId,
    );

    // Add customer & supplier for company 1
    await ledgerRepo1.addParty(Party(
      id: 'party_c1',
      name: 'Customer One',
      phoneNumber: '9876543210',
      type: PartyType.customer,
      netBalanceInCents: 0,
      lastUpdated: DateTime.now(),
    ));

    await ledgerRepo1.addParty(Party(
      id: 'party_s1',
      name: 'Supplier One',
      phoneNumber: '9123456780',
      type: PartyType.supplier,
      netBalanceInCents: 0,
      lastUpdated: DateTime.now(),
    ));

    // Ensure company accounts initialized
    await postingEngine.ensureCompanyAccounts(company1);
    await postingEngine.ensureCompanyAccounts(company2);
  });

  tearDown(() async {
    ledgerRepo1.dispose();
    ledgerRepo2.dispose();
    await db.close();
  });

  group('LedgerPulse Double-Entry Accounting Core Tests', () {
    test('1. SALE Posting creates balanced AR Dr = total, Sales Cr = taxable, Output GST Cr = tax', () async {
      final now = DateTime(2026, 9, 1);
      final saleVoucher = VoucherModel(
        id: 'vch_sale_001',
        companyId: company1,
        voucherNumber: 'INV-2026-001',
        type: VoucherType.sales,
        partyId: 'party_c1',
        partyName: 'Customer One',
        date: now,
        subtotalInCents: 100000, // ₹1,000.00 taxable
        taxInCents: 18000,       // ₹180.00 GST (18%)
        totalAmountInCents: 118000, // ₹1,180.00 total
        status: VoucherStatus.posted,
        createdAt: now,
        updatedAt: now,
      );

      await voucherRepo1.createVoucher(saleVoucher);

      // Verify Journal Header
      final journals = await ledgerRepo1.getJournals();
      expect(journals.length, equals(1));
      final journal = journals.first;
      expect(journal.voucherId, equals('vch_sale_001'));
      expect(journal.totalAmountInCents, equals(118000));
      expect(journal.isBalanced, isTrue);

      // Verify Journal Lines
      final lines = journal.lines;
      expect(lines.length, equals(3));

      // AR Debit line
      final arLine = lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.arId));
      expect(arLine.debitInCents, equals(118000));
      expect(arLine.creditInCents, equals(0));
      expect(arLine.partyId, equals('party_c1'));

      // Sales Credit line
      final salesLine = lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.salesId));
      expect(salesLine.debitInCents, equals(0));
      expect(salesLine.creditInCents, equals(100000));

      // Output GST Credit line
      final gstLine = lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.outputGstId));
      expect(gstLine.debitInCents, equals(0));
      expect(gstLine.creditInCents, equals(18000));

      // Verify Accounts Balances
      final arAcc = await ledgerRepo1.getAccountById('${company1}_${DefaultAccounts.arId}');
      expect(arAcc.currentBalanceInCents, equals(118000)); // Asset debit balance

      final salesAcc = await ledgerRepo1.getAccountById('${company1}_${DefaultAccounts.salesId}');
      expect(salesAcc.currentBalanceInCents, equals(100000)); // Revenue credit balance

      final gstAcc = await ledgerRepo1.getAccountById('${company1}_${DefaultAccounts.outputGstId}');
      expect(gstAcc.currentBalanceInCents, equals(18000)); // Liability credit balance
    });

    test('2. PURCHASE Posting creates Purchases Dr = taxable, Input GST Dr = tax, AP Cr = total', () async {
      final now = DateTime(2026, 9, 2);
      final purVoucher = VoucherModel(
        id: 'vch_pur_001',
        companyId: company1,
        voucherNumber: 'PUR-2026-001',
        type: VoucherType.purchase,
        partyId: 'party_s1',
        partyName: 'Supplier One',
        date: now,
        subtotalInCents: 50000, // ₹500.00 taxable
        taxInCents: 9000,       // ₹90.00 GST (18%)
        totalAmountInCents: 59000, // ₹590.00 total
        status: VoucherStatus.posted,
        createdAt: now,
        updatedAt: now,
      );

      await voucherRepo1.createVoucher(purVoucher);

      final journals = await ledgerRepo1.getJournals();
      final journal = journals.first;
      expect(journal.isBalanced, isTrue);

      final lines = journal.lines;
      expect(lines.length, equals(3));

      // Purchases / COGS Dr line
      final purLine = lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.purchasesCogsId));
      expect(purLine.debitInCents, equals(50000));
      expect(purLine.creditInCents, equals(0));

      // Input GST Dr line
      final gstLine = lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.inputGstId));
      expect(gstLine.debitInCents, equals(9000));
      expect(gstLine.creditInCents, equals(0));

      // AP Cr line
      final apLine = lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.apId));
      expect(apLine.debitInCents, equals(0));
      expect(apLine.creditInCents, equals(59000));
      expect(apLine.partyId, equals('party_s1'));

      // Verify Supplier Party net balance
      final supplier = await ledgerRepo1.getPartyById('party_s1');
      expect(supplier.netBalanceInCents, equals(-59000)); // Payable
    });

    test('3. RECEIPT Posting creates Cash/Bank Dr and AR Cr', () async {
      final now = DateTime(2026, 9, 3);
      final receiptVoucher = VoucherModel(
        id: 'vch_rcpt_001',
        companyId: company1,
        voucherNumber: 'RCPT-001',
        type: VoucherType.receipt,
        partyId: 'party_c1',
        partyName: 'Customer One',
        paymentMode: PaymentMode.bank,
        date: now,
        subtotalInCents: 50000,
        taxInCents: 0,
        totalAmountInCents: 50000, // ₹500.00
        status: VoucherStatus.posted,
        createdAt: now,
        updatedAt: now,
      );

      await voucherRepo1.createVoucher(receiptVoucher);

      final journals = await ledgerRepo1.getJournals();
      final journal = journals.first;
      expect(journal.isBalanced, isTrue);

      final lines = journal.lines;
      final bankLine = lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.bankId));
      expect(bankLine.debitInCents, equals(50000));
      expect(bankLine.creditInCents, equals(0));

      final arLine = lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.arId));
      expect(arLine.debitInCents, equals(0));
      expect(arLine.creditInCents, equals(50000));
    });

    test('4. PAYMENT Posting creates AP Dr and Cash/Bank Cr', () async {
      final now = DateTime(2026, 9, 4);
      final paymentVoucher = VoucherModel(
        id: 'vch_pmt_001',
        companyId: company1,
        voucherNumber: 'PMT-001',
        type: VoucherType.payment,
        partyId: 'party_s1',
        partyName: 'Supplier One',
        paymentMode: PaymentMode.cash,
        date: now,
        subtotalInCents: 30000,
        taxInCents: 0,
        totalAmountInCents: 30000, // ₹300.00
        status: VoucherStatus.posted,
        createdAt: now,
        updatedAt: now,
      );

      await voucherRepo1.createVoucher(paymentVoucher);

      final journals = await ledgerRepo1.getJournals();
      final journal = journals.first;
      expect(journal.isBalanced, isTrue);

      final lines = journal.lines;
      final apLine = lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.apId));
      expect(apLine.debitInCents, equals(30000));
      expect(apLine.creditInCents, equals(0));

      final cashLine = lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.cashId));
      expect(cashLine.debitInCents, equals(0));
      expect(cashLine.creditInCents, equals(30000));
    });

    test('5. EXPENSE Posting creates Expense Dr and Cash/Bank Cr', () async {
      final now = DateTime(2026, 9, 5);
      final expVoucher = VoucherModel(
        id: 'vch_exp_001',
        companyId: company1,
        voucherNumber: 'EXP-001',
        type: VoucherType.expense,
        paymentMode: PaymentMode.cash,
        date: now,
        subtotalInCents: 15000,
        taxInCents: 0,
        totalAmountInCents: 15000, // ₹150.00
        narration: 'Office Electricity Bill',
        status: VoucherStatus.posted,
        createdAt: now,
        updatedAt: now,
      );

      await voucherRepo1.createVoucher(expVoucher);

      final journals = await ledgerRepo1.getJournals();
      final journal = journals.first;
      expect(journal.isBalanced, isTrue);

      final lines = journal.lines;
      final expLine = lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.indirectExpensesId));
      expect(expLine.debitInCents, equals(15000));
      expect(expLine.creditInCents, equals(0));

      final cashLine = lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.cashId));
      expect(cashLine.debitInCents, equals(0));
      expect(cashLine.creditInCents, equals(15000));
    });

    test('6. OPENING BALANCES creates real accounting entries and remains balanced', () async {
      final openingJournal = await ledgerRepo1.postOpeningBalances(
        date: DateTime(2026, 4, 1),
        cashInCents: 100000,     // ₹1,000 Cash
        bankInCents: 500000,     // ₹5,000 Bank
        inventoryInCents: 200000,// ₹2,000 Inventory
        receivablesByParty: {'party_c1': 300000}, // ₹3,000 AR
        payablesByParty: {'party_s1': 400000},    // ₹4,000 AP
      );

      expect(openingJournal.isBalanced, isTrue);

      // Total Assets Dr = 1000 + 5000 + 2000 + 3000 = ₹11,000 (1,100,000 cents)
      // Total Liab Cr = ₹4,000 (400,000 cents)
      // Capital Cr = ₹7,000 (700,000 cents)
      expect(openingJournal.totalDebit, equals(1100000));
      expect(openingJournal.totalCredit, equals(1100000));

      final capitalLine = openingJournal.lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.capitalId));
      expect(capitalLine.creditInCents, equals(700000));

      // Check customer & supplier party balances
      final cust = await ledgerRepo1.getPartyById('party_c1');
      expect(cust.netBalanceInCents, equals(300000));

      final supp = await ledgerRepo1.getPartyById('party_s1');
      expect(supp.netBalanceInCents, equals(-400000));
    });

    test('7. UNBALANCED journal transaction is rejected with UnbalancedJournalException', () async {
      expect(
        () async => await postingEngine.postJournalEntry(
          journal: JournalModel(
            id: 'jnl_bad_1',
            companyId: company1,
            journalNumber: 'JNL-BAD-1',
            date: DateTime.now(),
            lines: [
              JournalLineModel(
                id: 'l1',
                companyId: company1,
                journalId: 'jnl_bad_1',
                accountId: '${company1}_${DefaultAccounts.cashId}',
                debitInCents: 10000,
                creditInCents: 0,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
              JournalLineModel(
                id: 'l2',
                companyId: company1,
                journalId: 'jnl_bad_1',
                accountId: '${company1}_${DefaultAccounts.salesId}',
                debitInCents: 0,
                creditInCents: 8000, // Unbalanced: 10000 != 8000
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            ],
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          userId: userId,
        ),
        throwsA(isA<UnbalancedJournalException>()),
      );
    });

    test('8. TRIAL BALANCE maintains mathematical Total Debit == Total Credit from journals', () async {
      // Post Sale of ₹2,000 (200,000 cents)
      await voucherRepo1.createVoucher(VoucherModel(
        id: 'v_s1',
        companyId: company1,
        voucherNumber: 'S-01',
        type: VoucherType.sales,
        partyId: 'party_c1',
        date: DateTime(2026, 9, 10),
        subtotalInCents: 200000,
        taxInCents: 0,
        totalAmountInCents: 200000,
        status: VoucherStatus.posted,
        createdAt: DateTime(2026, 9, 10),
        updatedAt: DateTime(2026, 9, 10),
      ));

      // Post Purchase of ₹1,200 (120,000 cents)
      await voucherRepo1.createVoucher(VoucherModel(
        id: 'v_p1',
        companyId: company1,
        voucherNumber: 'P-01',
        type: VoucherType.purchase,
        partyId: 'party_s1',
        date: DateTime(2026, 9, 11),
        subtotalInCents: 120000,
        taxInCents: 0,
        totalAmountInCents: 120000,
        status: VoucherStatus.posted,
        createdAt: DateTime(2026, 9, 11),
        updatedAt: DateTime(2026, 9, 11),
      ));

      // Post Expense of ₹300 (30,000 cents)
      await voucherRepo1.createVoucher(VoucherModel(
        id: 'v_e1',
        companyId: company1,
        voucherNumber: 'E-01',
        type: VoucherType.expense,
        paymentMode: PaymentMode.cash,
        date: DateTime(2026, 9, 12),
        subtotalInCents: 30000,
        taxInCents: 0,
        totalAmountInCents: 30000,
        status: VoucherStatus.posted,
        createdAt: DateTime(2026, 9, 12),
        updatedAt: DateTime(2026, 9, 12),
      ));

      final accounts = await ledgerRepo1.getAccounts();
      final journals = await ledgerRepo1.getJournals();
      final allLines = journals.expand((j) => j.lines).toList();

      final tb = FinancialStatementEngine.generateTrialBalance(
        accounts: accounts,
        journalLines: allLines,
        companyId: company1,
      );

      expect(tb.summary['isBalanced'], isTrue);
      // Total Debits = AR (200000) + Purchases (120000) + Expense (30000) = 350000
      // Total Credits = Sales (200000) + AP (120000) + Cash (30000) = 350000
      expect(tb.summary['totalDebit'], equals(CurrencyFormatter.format(350000)));
      expect(tb.summary['totalCredit'], equals(CurrencyFormatter.format(350000)));
    });

    test('9. PROFIT & LOSS computes Revenue, COGS, Operating Expenses and Net Profit accurately', () async {
      // Sale: ₹2,000.00
      await voucherRepo1.createVoucher(VoucherModel(
        id: 'v_s1',
        companyId: company1,
        voucherNumber: 'S-01',
        type: VoucherType.sales,
        partyId: 'party_c1',
        date: DateTime(2026, 9, 10),
        subtotalInCents: 200000,
        taxInCents: 0,
        totalAmountInCents: 200000,
        status: VoucherStatus.posted,
        createdAt: DateTime(2026, 9, 10),
        updatedAt: DateTime(2026, 9, 10),
      ));

      // Purchase/COGS: ₹1,200.00
      await voucherRepo1.createVoucher(VoucherModel(
        id: 'v_p1',
        companyId: company1,
        voucherNumber: 'P-01',
        type: VoucherType.purchase,
        partyId: 'party_s1',
        date: DateTime(2026, 9, 11),
        subtotalInCents: 120000,
        taxInCents: 0,
        totalAmountInCents: 120000,
        status: VoucherStatus.posted,
        createdAt: DateTime(2026, 9, 11),
        updatedAt: DateTime(2026, 9, 11),
      ));

      // Operating Expense: ₹300.00
      await voucherRepo1.createVoucher(VoucherModel(
        id: 'v_e1',
        companyId: company1,
        voucherNumber: 'E-01',
        type: VoucherType.expense,
        paymentMode: PaymentMode.cash,
        date: DateTime(2026, 9, 12),
        subtotalInCents: 30000,
        taxInCents: 0,
        totalAmountInCents: 30000,
        status: VoucherStatus.posted,
        createdAt: DateTime(2026, 9, 12),
        updatedAt: DateTime(2026, 9, 12),
      ));

      final testCompany = Company(
        id: company1,
        name: 'Company 1',
        legalName: 'Company 1 Ltd',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final accounts = await ledgerRepo1.getAccounts();
      final journals = await ledgerRepo1.getJournals();
      final allLines = journals.expand((j) => j.lines).toList();

      final pnl = FinancialStatementEngine.generateProfitAndLoss(
        company: testCompany,
        accounts: accounts,
        journalLines: allLines,
      );

      // Revenue = 2000.00, COGS = 1200.00, Gross Profit = 800.00, Expenses = 300.00, Net Profit = 500.00
      expect(pnl.summary['netProfit'], equals(CurrencyFormatter.format(50000)));
      expect(pnl.summary['grossMargin'], equals('40.0%'));
    });

    test('10. BALANCE SHEET enforces Assets == Liabilities + Equity with period profit', () async {
      final testCompany = Company(
        id: company1,
        name: 'Company 1',
        legalName: 'Company 1 Ltd',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      // 1. Opening Balance: Cash ₹10,000, Capital ₹10,000
      await ledgerRepo1.postOpeningBalances(
        date: DateTime(2026, 4, 1),
        cashInCents: 1000000,
      );

      // 2. Sale: ₹2,000
      await voucherRepo1.createVoucher(VoucherModel(
        id: 'v_s1',
        companyId: company1,
        voucherNumber: 'S-01',
        type: VoucherType.sales,
        partyId: 'party_c1',
        date: DateTime(2026, 9, 10),
        subtotalInCents: 200000,
        taxInCents: 0,
        totalAmountInCents: 200000,
        status: VoucherStatus.posted,
        createdAt: DateTime(2026, 9, 10),
        updatedAt: DateTime(2026, 9, 10),
      ));

      // 3. Purchase: ₹1,200
      await voucherRepo1.createVoucher(VoucherModel(
        id: 'v_p1',
        companyId: company1,
        voucherNumber: 'P-01',
        type: VoucherType.purchase,
        partyId: 'party_s1',
        date: DateTime(2026, 9, 11),
        subtotalInCents: 120000,
        taxInCents: 0,
        totalAmountInCents: 120000,
        status: VoucherStatus.posted,
        createdAt: DateTime(2026, 9, 11),
        updatedAt: DateTime(2026, 9, 11),
      ));

      final accounts = await ledgerRepo1.getAccounts();
      final journals = await ledgerRepo1.getJournals();
      final allLines = journals.expand((j) => j.lines).toList();

      final bs = FinancialStatementEngine.generateBalanceSheet(
        company: testCompany,
        accounts: accounts,
        journalLines: allLines,
      );

      // Assets: Cash (10000) + AR (2000) = ₹12,000
      // Liabilities: AP (1200) = ₹1,200
      // Equity: Capital (10000) + Net Profit (800) = ₹10,800
      // Liabilities + Equity = 1200 + 10800 = ₹12,000 == Assets
      expect(bs.summary['isBalanced'], isTrue);
      expect(bs.summary['totalAssets'], equals(CurrencyFormatter.format(1200000)));
      expect(bs.summary['totalLiabilities'], equals(CurrencyFormatter.format(1200000)));
    });

    test('11. MULTI-COMPANY isolation prevents data leaking across companies', () async {
      // Post transaction in Company 1
      await voucherRepo1.createVoucher(VoucherModel(
        id: 'v_cmp1_sale',
        companyId: company1,
        voucherNumber: 'INV-CMP1-001',
        type: VoucherType.sales,
        partyId: 'party_c1',
        date: DateTime(2026, 9, 1),
        subtotalInCents: 500000,
        taxInCents: 0,
        totalAmountInCents: 500000,
        status: VoucherStatus.posted,
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      ));

      // Query Company 2 journals and accounts
      final cmp2Journals = await ledgerRepo2.getJournals();
      expect(cmp2Journals.isEmpty, isTrue);

      final cmp2Accounts = await ledgerRepo2.getAccounts();
      for (final acc in cmp2Accounts) {
        expect(acc.currentBalanceInCents, equals(0));
      }

      // Query Company 1 journals
      final cmp1Journals = await ledgerRepo1.getJournals();
      expect(cmp1Journals.length, equals(1));
      expect(cmp1Journals.first.voucherId, equals('v_cmp1_sale'));
    });

    test('12. VOUCHER VOID / REVERSAL updates status and restores account balances', () async {
      final now = DateTime(2026, 9, 1);
      final voucher = VoucherModel(
        id: 'vch_void_me',
        companyId: company1,
        voucherNumber: 'INV-VOID-01',
        type: VoucherType.sales,
        partyId: 'party_c1',
        partyName: 'Customer One',
        date: now,
        subtotalInCents: 100000,
        taxInCents: 0,
        totalAmountInCents: 100000,
        status: VoucherStatus.posted,
        createdAt: now,
        updatedAt: now,
      );

      await voucherRepo1.createVoucher(voucher);

      // Verify AR and party balance is 100000
      var party = await ledgerRepo1.getPartyById('party_c1');
      expect(party.netBalanceInCents, equals(100000));

      var arAcc = await ledgerRepo1.getAccountById('${company1}_${DefaultAccounts.arId}');
      expect(arAcc.currentBalanceInCents, equals(100000));

      // Void the voucher
      await voucherRepo1.voidVoucher('vch_void_me');

      // Verify voucher status voided
      final voidedVoucher = await voucherRepo1.getVoucherById('vch_void_me');
      expect(voidedVoucher.status, equals(VoucherStatus.voided));

      // Verify party balance restored to 0
      party = await ledgerRepo1.getPartyById('party_c1');
      expect(party.netBalanceInCents, equals(0));

      // Verify AR account balance restored to 0
      arAcc = await ledgerRepo1.getAccountById('${company1}_${DefaultAccounts.arId}');
      expect(arAcc.currentBalanceInCents, equals(0));
    });
  });
}
