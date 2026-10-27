import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/domain/exceptions/ledger_exceptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late AuditService auditService;
  late VoucherPostingEngine postingEngine;
  late DriftVoucherRepository voucherRepo;
  late DriftLedgerRepository ledgerRepo;

  const companyId = 'cmp_expense_1';
  const otherCompanyId = 'cmp_other_2';
  const userId = 'usr_tester_1';

  final expenseCompany = Company(
    id: companyId,
    name: 'Personal Wallet',
    legalName: 'Personal Household Expenses',
    mode: CompanyMode.expenseTracker,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final otherCompany = Company(
    id: otherCompanyId,
    name: 'Other Company',
    legalName: 'Other Company Ltd',
    mode: CompanyMode.expenseTracker,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auditService = AuditService(db);
    postingEngine = VoucherPostingEngine(db, auditService);
    voucherRepo = DriftVoucherRepository(
      db: db,
      auditService: auditService,
      postingEngine: postingEngine,
      currentCompanyId: companyId,
      currentUserId: userId,
    );
    ledgerRepo = DriftLedgerRepository(
      db: db,
      postingEngine: postingEngine,
      currentCompanyId: companyId,
      currentUserId: userId,
    );

    // Insert companies into database
    await db.into(db.companies).insert(
          CompaniesCompanion.insert(
            id: expenseCompany.id,
            name: expenseCompany.name,
            legalName: expenseCompany.legalName,
            mode: Value(expenseCompany.mode.name),
            createdAt: Value(expenseCompany.createdAt),
            updatedAt: Value(expenseCompany.updatedAt),
          ),
        );
    await db.into(db.companies).insert(
          CompaniesCompanion.insert(
            id: otherCompany.id,
            name: otherCompany.name,
            legalName: otherCompany.legalName,
            mode: Value(otherCompany.mode.name),
            createdAt: Value(otherCompany.createdAt),
            updatedAt: Value(otherCompany.updatedAt),
          ),
        );

    // Seed default expense tracker accounts
    await postingEngine.seedAccountsFor(expenseCompany, initialWalletBalancesInCents: {
      ExpenseTrackerDefaults.walletCashId: 100000, // ₹1,000.00
      ExpenseTrackerDefaults.walletBankId: 500000, // ₹5,000.00
    });
    await postingEngine.seedAccountsFor(otherCompany);

    // Add a credit-card wallet (liability) to expenseCompany
    final ccWallet = AccountModel(
      id: '${companyId}_wallet_cc',
      companyId: companyId,
      code: '2100',
      name: 'Credit Card Wallet',
      type: AccountType.liability,
      currentBalanceInCents: 0,
      description: 'HDFC Millennia Credit Card',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            id: ccWallet.id,
            companyId: Value(ccWallet.companyId),
            code: ccWallet.code,
            name: ccWallet.name,
            type: ccWallet.type.name,
            currentBalanceInCents: const Value(0),
            description: Value(ccWallet.description),
            createdAt: Value(ccWallet.createdAt),
            updatedAt: Value(ccWallet.updatedAt),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('Prompt 8 - VoucherType Enum & Prefixes', () {
    test('income and transfer voucher types have correct displayName and prefixes', () {
      expect(VoucherType.expense.displayName, equals('Expense Voucher'));
      expect(VoucherType.expense.prefix, equals('EXP'));

      expect(VoucherType.income.displayName, equals('Income Voucher'));
      expect(VoucherType.income.prefix, equals('INC'));

      expect(VoucherType.transfer.displayName, equals('Transfer Voucher'));
      expect(VoucherType.transfer.prefix, equals('TRF'));

      expect(VoucherType.income.isFinancialPosting, isTrue);
      expect(VoucherType.transfer.isFinancialPosting, isTrue);
    });
  });

  group('Prompt 8 - Balanced Double-Entry Journal Posting', () {
    test('expense voucher posts Dr Category and Cr Wallet', () async {
      final cashWalletId = '${companyId}_${ExpenseTrackerDefaults.walletCashId}';
      final groceriesCatId = '${companyId}_${ExpenseTrackerDefaults.groceriesId}';

      final expVoucher = VoucherModel(
        id: 'vch_exp_test_1',
        companyId: companyId,
        voucherNumber: 'EXP-0001',
        type: VoucherType.expense,
        date: DateTime(2026, 1, 15),
        totalAmountInCents: 25000, // ₹250.00
        categoryAccountId: groceriesCatId,
        walletAccountId: cashWalletId,
        narration: 'Weekly vegetables',
        createdAt: DateTime(2026, 1, 15),
        updatedAt: DateTime(2026, 1, 15),
      );

      final posted = await voucherRepo.createVoucher(expVoucher);
      expect(posted.id, equals(expVoucher.id));

      final journals = await ledgerRepo.getJournals();
      final journal = journals.firstWhere((j) => j.voucherId == expVoucher.id);
      expect(journal.isBalanced, isTrue);
      expect(journal.totalAmountInCents, equals(25000));

      final drLine = journal.lines.firstWhere((l) => l.debitInCents > 0);
      final crLine = journal.lines.firstWhere((l) => l.creditInCents > 0);

      expect(drLine.accountId, equals(groceriesCatId));
      expect(drLine.debitInCents, equals(25000));
      expect(crLine.accountId, equals(cashWalletId));
      expect(crLine.creditInCents, equals(25000));

      // Check updated balances
      final cashAccount = await ledgerRepo.getAccountById(cashWalletId);
      final groceriesAccount = await ledgerRepo.getAccountById(groceriesCatId);

      // Cash asset: started with 100,000, spent 25,000 -> 75,000 cents
      expect(cashAccount.currentBalanceInCents, equals(75000));
      // Groceries expense: debit 25,000
      expect(groceriesAccount.currentBalanceInCents, equals(25000));
    });

    test('income voucher posts Dr Wallet and Cr Category', () async {
      final bankWalletId = '${companyId}_${ExpenseTrackerDefaults.walletBankId}';
      final salaryCatId = '${companyId}_${ExpenseTrackerDefaults.salaryId}';

      final incVoucher = VoucherModel(
        id: 'vch_inc_test_1',
        companyId: companyId,
        voucherNumber: 'INC-0001',
        type: VoucherType.income,
        date: DateTime(2026, 1, 20),
        totalAmountInCents: 1500000, // ₹15,000.00
        categoryAccountId: salaryCatId,
        walletAccountId: bankWalletId,
        narration: 'Consulting milestone payout',
        createdAt: DateTime(2026, 1, 20),
        updatedAt: DateTime(2026, 1, 20),
      );

      await voucherRepo.createVoucher(incVoucher);

      final journals = await ledgerRepo.getJournals();
      final journal = journals.firstWhere((j) => j.voucherId == incVoucher.id);
      expect(journal.isBalanced, isTrue);

      final drLine = journal.lines.firstWhere((l) => l.debitInCents > 0);
      final crLine = journal.lines.firstWhere((l) => l.creditInCents > 0);

      expect(drLine.accountId, equals(bankWalletId));
      expect(drLine.debitInCents, equals(1500000));
      expect(crLine.accountId, equals(salaryCatId));
      expect(crLine.creditInCents, equals(1500000));

      // Bank asset: started with 500,000, received 1,500,000 -> 2,000,000 cents
      final bankAccount = await ledgerRepo.getAccountById(bankWalletId);
      final salaryAccount = await ledgerRepo.getAccountById(salaryCatId);

      expect(bankAccount.currentBalanceInCents, equals(2000000));
      // Salary income: credit 1,500,000 (credit normal for income)
      expect(salaryAccount.currentBalanceInCents, equals(1500000));
    });

    test('transfer voucher posts Dr ToWallet and Cr Wallet', () async {
      final bankWalletId = '${companyId}_${ExpenseTrackerDefaults.walletBankId}';
      final cashWalletId = '${companyId}_${ExpenseTrackerDefaults.walletCashId}';

      final trfVoucher = VoucherModel(
        id: 'vch_trf_test_1',
        companyId: companyId,
        voucherNumber: 'TRF-0001',
        type: VoucherType.transfer,
        date: DateTime(2026, 1, 22),
        totalAmountInCents: 50000, // ₹500.00 ATM withdrawal
        walletAccountId: bankWalletId, // Source
        toWalletAccountId: cashWalletId, // Destination
        narration: 'ATM cash withdrawal from Bank',
        createdAt: DateTime(2026, 1, 22),
        updatedAt: DateTime(2026, 1, 22),
      );

      await voucherRepo.createVoucher(trfVoucher);

      final journals = await ledgerRepo.getJournals();
      final journal = journals.firstWhere((j) => j.voucherId == trfVoucher.id);
      expect(journal.isBalanced, isTrue);

      final drLine = journal.lines.firstWhere((l) => l.debitInCents > 0);
      final crLine = journal.lines.firstWhere((l) => l.creditInCents > 0);

      expect(drLine.accountId, equals(cashWalletId)); // ToWallet
      expect(drLine.debitInCents, equals(50000));
      expect(crLine.accountId, equals(bankWalletId)); // Wallet
      expect(crLine.creditInCents, equals(50000));

      final bankAccount = await ledgerRepo.getAccountById(bankWalletId);
      final cashAccount = await ledgerRepo.getAccountById(cashWalletId);

      // Bank: started with 500,000 - 50,000 = 450,000 cents
      expect(bankAccount.currentBalanceInCents, equals(450000));
      // Cash: started with 100,000 + 50,000 = 150,000 cents
      expect(cashAccount.currentBalanceInCents, equals(150000));
    });
  });

  group('Prompt 8 - Credit Card Wallet (Liability)', () {
    test('spending with credit-card wallet increases liability balance (what is owed)', () async {
      final ccWalletId = '${companyId}_wallet_cc';
      final shoppingCatId = '${companyId}_${ExpenseTrackerDefaults.shoppingId}';
      final bankWalletId = '${companyId}_${ExpenseTrackerDefaults.walletBankId}';

      // Verify starting balance of credit card is 0
      final initialCC = await ledgerRepo.getAccountById(ccWalletId);
      expect(initialCC.type, equals(AccountType.liability));
      expect(initialCC.currentBalanceInCents, equals(0));

      // 1. Spend ₹2,000 (200,000 cents) on shopping with Credit Card
      final expVoucher = VoucherModel(
        id: 'vch_exp_cc_1',
        companyId: companyId,
        voucherNumber: 'EXP-0002',
        type: VoucherType.expense,
        date: DateTime(2026, 1, 25),
        totalAmountInCents: 200000,
        categoryAccountId: shoppingCatId,
        walletAccountId: ccWalletId,
        narration: 'Shopping on Amazon via Credit Card',
        createdAt: DateTime(2026, 1, 25),
        updatedAt: DateTime(2026, 1, 25),
      );

      await voucherRepo.createVoucher(expVoucher);

      // Credit card liability balance must INCREASE by ₹2,000 (spending increases what is owed)
      final afterSpendCC = await ledgerRepo.getAccountById(ccWalletId);
      expect(afterSpendCC.currentBalanceInCents, equals(200000));

      // 2. Pay off Credit Card bill of ₹2,000 via Transfer from Bank
      final billPayVoucher = VoucherModel(
        id: 'vch_trf_cc_pay_1',
        companyId: companyId,
        voucherNumber: 'TRF-0002',
        type: VoucherType.transfer,
        date: DateTime(2026, 1, 28),
        totalAmountInCents: 200000,
        walletAccountId: bankWalletId, // Source: Bank asset
        toWalletAccountId: ccWalletId, // Destination: Credit card liability
        narration: 'Credit Card Bill Repayment',
        createdAt: DateTime(2026, 1, 28),
        updatedAt: DateTime(2026, 1, 28),
      );

      await voucherRepo.createVoucher(billPayVoucher);

      // Credit card liability balance must be reduced back to 0
      final afterPayCC = await ledgerRepo.getAccountById(ccWalletId);
      expect(afterPayCC.currentBalanceInCents, equals(0));

      // Bank asset was reduced by 200,000 cents (500,000 - 200,000 = 300,000)
      final afterPayBank = await ledgerRepo.getAccountById(bankWalletId);
      expect(afterPayBank.currentBalanceInCents, equals(300000));
    });
  });

  group('Prompt 8 - Void and Edit', () {
    test('voiding an expense voucher reverses journals and recalculates balances', () async {
      final cashWalletId = '${companyId}_${ExpenseTrackerDefaults.walletCashId}';
      final foodCatId = '${companyId}_${ExpenseTrackerDefaults.foodDiningId}';

      final expVoucher = VoucherModel(
        id: 'vch_exp_void_test',
        companyId: companyId,
        voucherNumber: 'EXP-0003',
        type: VoucherType.expense,
        date: DateTime(2026, 2, 1),
        totalAmountInCents: 30000, // ₹300.00
        categoryAccountId: foodCatId,
        walletAccountId: cashWalletId,
        narration: 'Dinner with friends',
        createdAt: DateTime(2026, 2, 1),
        updatedAt: DateTime(2026, 2, 1),
      );

      await voucherRepo.createVoucher(expVoucher);

      // Pre-void check: Cash balance is 100,000 - 30,000 = 70,000
      var cashAcc = await ledgerRepo.getAccountById(cashWalletId);
      expect(cashAcc.currentBalanceInCents, equals(70000));

      // Void the voucher
      await voucherRepo.voidVoucher(expVoucher.id);

      final voidedVoucher = await voucherRepo.getVoucherById(expVoucher.id);
      expect(voidedVoucher.status, equals(VoucherStatus.voided));

      final journals = await ledgerRepo.getJournals();
      final journal = journals.firstWhere((j) => j.voucherId == expVoucher.id);
      expect(journal.status, equals('voided'));

      // Cash balance restored to 100,000 cents
      cashAcc = await ledgerRepo.getAccountById(cashWalletId);
      expect(cashAcc.currentBalanceInCents, equals(100000));

      // Food category restored to 0 cents
      final foodAcc = await ledgerRepo.getAccountById(foodCatId);
      expect(foodAcc.currentBalanceInCents, equals(0));
    });

    test('editing a voucher replaces journals and updates wallet balances correctly', () async {
      final cashWalletId = '${companyId}_${ExpenseTrackerDefaults.walletCashId}';
      final bankWalletId = '${companyId}_${ExpenseTrackerDefaults.walletBankId}';
      final travelCatId = '${companyId}_${ExpenseTrackerDefaults.travelId}';

      final originalVoucher = VoucherModel(
        id: 'vch_exp_edit_test',
        companyId: companyId,
        voucherNumber: 'EXP-0004',
        type: VoucherType.expense,
        date: DateTime(2026, 2, 5),
        totalAmountInCents: 40000, // ₹400.00 from Cash
        categoryAccountId: travelCatId,
        walletAccountId: cashWalletId,
        narration: 'Fuel from Cash',
        createdAt: DateTime(2026, 2, 5),
        updatedAt: DateTime(2026, 2, 5),
      );

      await voucherRepo.createVoucher(originalVoucher);

      // Verify initial cash balance: 100,000 - 40,000 = 60,000 cents
      var cashAcc = await ledgerRepo.getAccountById(cashWalletId);
      expect(cashAcc.currentBalanceInCents, equals(60000));

      // Edit voucher: Change wallet to Bank, and change amount to ₹600 (60,000 cents)
      final updatedVoucher = originalVoucher.copyWith(
        walletAccountId: bankWalletId,
        totalAmountInCents: 60000,
        narration: 'Fuel paid via Bank Card',
      );

      await voucherRepo.editVoucher(updatedVoucher);

      // Cash wallet balance should be restored to 100,000 cents
      cashAcc = await ledgerRepo.getAccountById(cashWalletId);
      expect(cashAcc.currentBalanceInCents, equals(100000));

      // Bank wallet balance should reflect 60,000 deduction: 500,000 - 60,000 = 440,000 cents
      final bankAcc = await ledgerRepo.getAccountById(bankWalletId);
      expect(bankAcc.currentBalanceInCents, equals(440000));

      // Travel category should reflect 60,000 cents
      final travelAcc = await ledgerRepo.getAccountById(travelCatId);
      expect(travelAcc.currentBalanceInCents, equals(60000));
    });
  });

  group('Prompt 8 - Legacy Expense Voucher Fallbacks', () {
    test('legacy expense voucher with null ids posts exactly as before (operating expense and cash by payment mode)', () async {
      const ledgerCompanyId = 'cmp_ledger_legacy';
      final ledgerCompany = Company(
        id: ledgerCompanyId,
        name: 'Legacy Ledger Co',
        legalName: 'Legacy Ledger Co Pvt Ltd',
        mode: CompanyMode.ledger,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      await db.into(db.companies).insert(
            CompaniesCompanion.insert(
              id: ledgerCompany.id,
              name: ledgerCompany.name,
              legalName: ledgerCompany.legalName,
              mode: Value(ledgerCompany.mode.name),
              createdAt: Value(ledgerCompany.createdAt),
              updatedAt: Value(ledgerCompany.updatedAt),
            ),
          );
      await postingEngine.seedAccountsFor(ledgerCompany);

      final now = DateTime(2026, 2, 10);
      final legacyVoucher = VoucherModel(
        id: 'vch_legacy_exp_1',
        companyId: ledgerCompanyId,
        voucherNumber: 'EXP-LEGACY-01',
        type: VoucherType.expense,
        paymentMode: PaymentMode.cash,
        date: now,
        totalAmountInCents: 35000, // ₹350.00
        categoryAccountId: null,
        walletAccountId: null,
        narration: 'Office snacks (legacy)',
        createdAt: now,
        updatedAt: now,
      );

      await postingEngine.postVoucher(voucher: legacyVoucher, userId: userId);

      final ledgerRepoLegacy = DriftLedgerRepository(
        db: db,
        postingEngine: postingEngine,
        currentCompanyId: ledgerCompanyId,
        currentUserId: userId,
      );
      final journals = await ledgerRepoLegacy.getJournals();
      final journal = journals.firstWhere((j) => j.voucherId == legacyVoucher.id);
      expect(journal.isBalanced, isTrue);

      final drLine = journal.lines.firstWhere((l) => l.debitInCents > 0);
      final crLine = journal.lines.firstWhere((l) => l.creditInCents > 0);

      // Fallback: operatingExpenseAccountId (indirectExpensesId) and cashAccountId (cashId)
      expect(drLine.accountId, equals('${ledgerCompanyId}_${DefaultAccounts.indirectExpensesId}'));
      expect(crLine.accountId, equals('${ledgerCompanyId}_${DefaultAccounts.cashId}'));
      expect(drLine.debitInCents, equals(35000));
      expect(crLine.creditInCents, equals(35000));
    });
  });

  group('Prompt 8 - Party Ledger & Stock Untouched', () {
    test('party and stock are untouched for expense, income, and transfer vouchers', () async {
      // 1. Create a dummy party
      await ledgerRepo.addParty(Party(
        id: 'pty_test_1',
        name: 'John Merchant',
        phoneNumber: '9876543210',
        type: PartyType.customer,
        netBalanceInCents: 0,
        lastUpdated: DateTime(2026, 1, 1),
      ));

      // 2. Post an expense with partyId and items
      final cashWalletId = '${companyId}_${ExpenseTrackerDefaults.walletCashId}';
      final foodCatId = '${companyId}_${ExpenseTrackerDefaults.foodDiningId}';

      final voucher = VoucherModel(
        id: 'vch_party_test_1',
        companyId: companyId,
        voucherNumber: 'EXP-PARTY-01',
        type: VoucherType.expense,
        date: DateTime(2026, 2, 12),
        totalAmountInCents: 50000,
        partyId: 'pty_test_1',
        categoryAccountId: foodCatId,
        walletAccountId: cashWalletId,
        items: const [
          VoucherItemModel(
            itemId: 'itm_food_1',
            itemName: 'Buffet',
            sku: 'SKU-01',
            quantity: 2,
            unitPriceInCents: 25000,
            totalInCents: 50000,
          ),
        ],
        createdAt: DateTime(2026, 2, 12),
        updatedAt: DateTime(2026, 2, 12),
      );

      await voucherRepo.createVoucher(voucher);

      // Verify ledgerEntries table has NO entries for this voucher
      final partyLedgerEntries = await (db.select(db.ledgerEntries)
            ..where((t) => t.partyId.equals('pty_test_1')))
          .get();
      expect(partyLedgerEntries, isEmpty);

      // Party net balance remains 0
      final party = await (db.select(db.parties)..where((t) => t.id.equals('pty_test_1'))).getSingle();
      expect(party.netBalanceInCents, equals(0));

      // Stock ledger remains untouched (0 entries)
      final stockEntries = await (db.select(db.stockLedger)
            ..where((t) => t.voucherId.equals(voucher.id)))
          .get();
      expect(stockEntries, isEmpty);
    });
  });

  group('Prompt 8 - Validation Rules (All Rule Violations Throw)', () {
    test('amount <= 0 throws VoucherValidationException', () async {
      final cashWalletId = '${companyId}_${ExpenseTrackerDefaults.walletCashId}';
      final foodCatId = '${companyId}_${ExpenseTrackerDefaults.foodDiningId}';

      final invalidVoucher = VoucherModel(
        id: 'vch_val_amt_0',
        companyId: companyId,
        voucherNumber: 'EXP-INV-01',
        type: VoucherType.expense,
        date: DateTime(2026, 2, 14),
        totalAmountInCents: 0,
        categoryAccountId: foodCatId,
        walletAccountId: cashWalletId,
        createdAt: DateTime(2026, 2, 14),
        updatedAt: DateTime(2026, 2, 14),
      );

      expect(
        () async => await voucherRepo.createVoucher(invalidVoucher),
        throwsA(isA<VoucherValidationException>()),
      );
    });

    test('wallet from another company throws VoucherValidationException', () async {
      final otherCashWalletId = '${otherCompanyId}_${ExpenseTrackerDefaults.walletCashId}';
      final foodCatId = '${companyId}_${ExpenseTrackerDefaults.foodDiningId}';

      final invalidVoucher = VoucherModel(
        id: 'vch_val_cmp_wallet',
        companyId: companyId,
        voucherNumber: 'EXP-INV-02',
        type: VoucherType.expense,
        date: DateTime(2026, 2, 14),
        totalAmountInCents: 10000,
        categoryAccountId: foodCatId,
        walletAccountId: otherCashWalletId, // Belongs to otherCompanyId
        createdAt: DateTime(2026, 2, 14),
        updatedAt: DateTime(2026, 2, 14),
      );

      expect(
        () async => await voucherRepo.createVoucher(invalidVoucher),
        throwsA(isA<VoucherValidationException>()),
      );
    });

    test('category from another company throws VoucherValidationException', () async {
      final cashWalletId = '${companyId}_${ExpenseTrackerDefaults.walletCashId}';
      final otherFoodCatId = '${otherCompanyId}_${ExpenseTrackerDefaults.foodDiningId}';

      final invalidVoucher = VoucherModel(
        id: 'vch_val_cmp_cat',
        companyId: companyId,
        voucherNumber: 'EXP-INV-03',
        type: VoucherType.expense,
        date: DateTime(2026, 2, 14),
        totalAmountInCents: 10000,
        categoryAccountId: otherFoodCatId, // Belongs to otherCompanyId
        walletAccountId: cashWalletId,
        createdAt: DateTime(2026, 2, 14),
        updatedAt: DateTime(2026, 2, 14),
      );

      expect(
        () async => await voucherRepo.createVoucher(invalidVoucher),
        throwsA(isA<VoucherValidationException>()),
      );
    });

    test('expense voucher with income category throws VoucherValidationException', () async {
      final cashWalletId = '${companyId}_${ExpenseTrackerDefaults.walletCashId}';
      final salaryIncomeId = '${companyId}_${ExpenseTrackerDefaults.salaryId}'; // Type: income

      final invalidVoucher = VoucherModel(
        id: 'vch_val_cat_type_mismatch',
        companyId: companyId,
        voucherNumber: 'EXP-INV-04',
        type: VoucherType.expense,
        date: DateTime(2026, 2, 14),
        totalAmountInCents: 10000,
        categoryAccountId: salaryIncomeId, // Mismatched category type
        walletAccountId: cashWalletId,
        createdAt: DateTime(2026, 2, 14),
        updatedAt: DateTime(2026, 2, 14),
      );

      expect(
        () async => await voucherRepo.createVoucher(invalidVoucher),
        throwsA(isA<VoucherValidationException>()),
      );
    });

    test('income voucher with expense category throws VoucherValidationException', () async {
      final bankWalletId = '${companyId}_${ExpenseTrackerDefaults.walletBankId}';
      final groceriesExpenseId = '${companyId}_${ExpenseTrackerDefaults.groceriesId}'; // Type: expense

      final invalidVoucher = VoucherModel(
        id: 'vch_val_inc_type_mismatch',
        companyId: companyId,
        voucherNumber: 'INC-INV-01',
        type: VoucherType.income,
        date: DateTime(2026, 2, 14),
        totalAmountInCents: 10000,
        categoryAccountId: groceriesExpenseId, // Mismatched category type
        walletAccountId: bankWalletId,
        createdAt: DateTime(2026, 2, 14),
        updatedAt: DateTime(2026, 2, 14),
      );

      expect(
        () async => await voucherRepo.createVoucher(invalidVoucher),
        throwsA(isA<VoucherValidationException>()),
      );
    });

    test('transfer voucher with identical source and destination throws VoucherValidationException', () async {
      final bankWalletId = '${companyId}_${ExpenseTrackerDefaults.walletBankId}';

      final invalidVoucher = VoucherModel(
        id: 'vch_val_trf_same_wallet',
        companyId: companyId,
        voucherNumber: 'TRF-INV-01',
        type: VoucherType.transfer,
        date: DateTime(2026, 2, 14),
        totalAmountInCents: 10000,
        walletAccountId: bankWalletId,
        toWalletAccountId: bankWalletId, // Same wallet!
        createdAt: DateTime(2026, 2, 14),
        updatedAt: DateTime(2026, 2, 14),
      );

      expect(
        () async => await voucherRepo.createVoucher(invalidVoucher),
        throwsA(isA<VoucherValidationException>()),
      );
    });
  });
}
