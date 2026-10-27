import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../domain/exceptions/ledger_exceptions.dart';
import '../local/audit_service.dart';
import '../local/database.dart';
import '../models/account_model.dart';
import '../models/audit_log_model.dart';
import '../models/company_model.dart';
import '../models/journal_model.dart';
import '../models/stock_ledger_model.dart';
import '../models/transaction_model.dart';
import '../models/voucher_model.dart';

class VoucherPostingEngine {
  final AppDatabase _db;
  final AuditService _auditService;
  final _uuid = const Uuid();

  VoucherPostingEngine(this._db, this._auditService);

  /// Seeds the initial Chart of Accounts for [company].
  /// Branches on [company.mode] to seed either standard double-entry ledger accounts
  /// or lightweight expense tracker wallets and categories.
  Future<void> seedAccountsFor(
    Company company, {
    Map<String, int>? initialWalletBalancesInCents,
  }) async {
    final existingCount = await (_db.select(_db.accounts)
          ..where((t) => t.companyId.equals(company.id) & t.isDeleted.equals(false)))
        .get();

    if (existingCount.isNotEmpty) return;

    final List<AccountModel> accountsToSeed;
    switch (company.mode) {
      case CompanyMode.expenseTracker:
        accountsToSeed = ExpenseTrackerDefaults.getDefaultAccounts(
          company.id,
          initialWalletBalancesInCents: initialWalletBalancesInCents,
        );
        break;
      case CompanyMode.ledger:
        accountsToSeed = DefaultAccounts.getDefaultAccounts(company.id);
        break;
    }

    for (final acc in accountsToSeed) {
      await _db.into(_db.accounts).insertOnConflictUpdate(
            AccountsCompanion.insert(
              id: acc.id,
              companyId: Value(company.id),
              code: acc.code,
              name: acc.name,
              type: acc.type.name,
              parentAccountId: Value(acc.parentAccountId),
              isSystem: Value(acc.isSystem),
              isActive: Value(acc.isActive),
              description: Value(acc.description),
              currentBalanceInCents: Value(acc.currentBalanceInCents),
              createdAt: Value(acc.createdAt),
              updatedAt: Value(acc.updatedAt),
              isDeleted: const Value(false),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );
    }

    // If expense tracker wallets have initial balances, post a balanced opening journal entry
    if (company.mode == CompanyMode.expenseTracker && initialWalletBalancesInCents != null) {
      final cashId = '${company.id}_${ExpenseTrackerDefaults.walletCashId}';
      final bankId = '${company.id}_${ExpenseTrackerDefaults.walletBankId}';
      final equityId = '${company.id}_${ExpenseTrackerDefaults.openingBalanceEquityId}';

      final cashBal = initialWalletBalancesInCents[ExpenseTrackerDefaults.walletCashId] ??
          initialWalletBalancesInCents[cashId] ??
          initialWalletBalancesInCents['cash'] ??
          0;
      final bankBal = initialWalletBalancesInCents[ExpenseTrackerDefaults.walletBankId] ??
          initialWalletBalancesInCents[bankId] ??
          initialWalletBalancesInCents['bank'] ??
          0;

      final totalEquity = cashBal + bankBal;
      if (totalEquity > 0) {
        final journalId = 'jnl_opening_${company.id}';
        final journalNumber = 'JNL-OPENING-${company.id}';
        final now = DateTime.now();
        final List<JournalLinesCompanion> lines = [];

        if (cashBal > 0) {
          lines.add(JournalLinesCompanion.insert(
            id: '${journalId}_cash',
            companyId: Value(company.id),
            journalId: journalId,
            accountId: cashId,
            debitInCents: Value(cashBal),
            creditInCents: const Value(0),
            narration: const Value('Opening Wallet Balance - Cash'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
        }

        if (bankBal > 0) {
          lines.add(JournalLinesCompanion.insert(
            id: '${journalId}_bank',
            companyId: Value(company.id),
            journalId: journalId,
            accountId: bankId,
            debitInCents: Value(bankBal),
            creditInCents: const Value(0),
            narration: const Value('Opening Wallet Balance - Bank'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
        }

        lines.add(JournalLinesCompanion.insert(
          id: '${journalId}_equity',
          companyId: Value(company.id),
          journalId: journalId,
          accountId: equityId,
          debitInCents: const Value(0),
          creditInCents: Value(totalEquity),
          narration: const Value('Opening Balance Equity'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));

        await _db.into(_db.journals).insertOnConflictUpdate(
              JournalsCompanion.insert(
                id: journalId,
                companyId: Value(company.id),
                journalNumber: journalNumber,
                voucherId: const Value(null),
                date: now,
                narration: const Value('Opening Wallet Balances'),
                totalAmountInCents: Value(totalEquity),
                status: const Value('posted'),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );

        for (final line in lines) {
          await _db.into(_db.journalLines).insertOnConflictUpdate(line);
        }

        for (final line in lines) {
          await _recalculateAccountBalance(line.accountId.value, company.id);
        }
      }
    }
  }

  /// Seeds missing standard double-entry ledger accounts (AR, AP, GST Input/Output,
  /// Sales, Purchases, Inventory, etc.) for [companyId] without modifying any
  /// existing accounts, wallets, categories, vouchers, or journals.
  ///
  /// Idempotent if called multiple times: only missing accounts are inserted.
  Future<List<AccountModel>> seedMissingLedgerAccountsFor(String companyId) async {
    final existingAccounts = await (_db.select(_db.accounts)
          ..where((t) => t.companyId.equals(companyId) & t.isDeleted.equals(false)))
        .get();
    final existingIds = existingAccounts.map((a) => a.id).toSet();

    final standardAccounts = DefaultAccounts.getDefaultAccounts(companyId);
    final missingAccounts = standardAccounts.where((a) => !existingIds.contains(a.id)).toList();

    for (final acc in missingAccounts) {
      await _db.into(_db.accounts).insertOnConflictUpdate(
            AccountsCompanion.insert(
              id: acc.id,
              companyId: Value(companyId),
              code: acc.code,
              name: acc.name,
              type: acc.type.name,
              parentAccountId: Value(acc.parentAccountId),
              isSystem: Value(acc.isSystem),
              isActive: Value(acc.isActive),
              description: Value(acc.description),
              currentBalanceInCents: const Value(0),
              createdAt: Value(acc.createdAt),
              updatedAt: Value(acc.updatedAt),
              isDeleted: const Value(false),
              syncStatus: const Value(SyncRecordStatus.synced),
            ),
          );
    }

    return missingAccounts;
  }

  /// Verifies that accounts exist for [companyId].
  /// If accounts are missing (for legacy companies created before transactional seeding),
  /// seeds them when first used for backwards compatibility.
  Future<void> ensureCompanyAccounts(String companyId) async {
    final existingAccounts = await (_db.select(_db.accounts)
          ..where((t) => t.companyId.equals(companyId) & t.isDeleted.equals(false)))
        .get();

    if (existingAccounts.isNotEmpty) return;

    // Backward-compatibility: companies created before transactional seeding get accounts when first used.
    final companyRow = await (_db.select(_db.companies)
          ..where((t) => t.id.equals(companyId)))
        .getSingleOrNull();

    final company = companyRow != null
        ? Company(
            id: companyRow.id,
            name: companyRow.name,
            legalName: companyRow.legalName,
            gstin: companyRow.gstin,
            stateCode: companyRow.stateCode,
            dealerType: companyRow.dealerType,
            currencyCode: companyRow.currencyCode,
            address: companyRow.address,
            email: companyRow.email,
            phoneNumber: companyRow.phoneNumber,
            mode: CompanyMode.fromName(companyRow.mode),
            createdAt: companyRow.createdAt,
            updatedAt: companyRow.updatedAt,
          )
        : Company(
            id: companyId,
            name: 'Company $companyId',
            legalName: 'Company $companyId',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );

    await seedAccountsFor(company);
  }

  /// Validates business and posting rules for a voucher.
  /// Throws [VoucherValidationException] if any rule is violated.
  Future<void> _validateVoucher(VoucherModel voucher) async {
    // 1. Amount must be greater than zero
    if (voucher.totalAmountInCents <= 0) {
      throw VoucherValidationException(
        'Transaction amount must be greater than zero. Received: ${voucher.totalAmountInCents}',
      );
    }

    // 2. Transfer source differs from destination
    if (voucher.type == VoucherType.transfer) {
      final source = voucher.walletAccountId;
      final dest = voucher.toWalletAccountId;
      if (source != null && dest != null && source == dest) {
        throw const VoucherValidationException(
          'Transfer source and destination wallet accounts must be different.',
        );
      }
    }

    // 3. Wallet and Category belong to the same company
    final companyId = voucher.companyId;

    if (voucher.walletAccountId != null) {
      final walletAcc = await (_db.select(_db.accounts)
            ..where((t) => t.id.equals(voucher.walletAccountId!) & t.isDeleted.equals(false)))
          .getSingleOrNull();
      if (walletAcc == null || walletAcc.companyId != companyId) {
        throw VoucherValidationException(
          'Wallet account ${voucher.walletAccountId} does not belong to company $companyId or does not exist.',
        );
      }
    }

    if (voucher.toWalletAccountId != null) {
      final toWalletAcc = await (_db.select(_db.accounts)
            ..where((t) => t.id.equals(voucher.toWalletAccountId!) & t.isDeleted.equals(false)))
          .getSingleOrNull();
      if (toWalletAcc == null || toWalletAcc.companyId != companyId) {
        throw VoucherValidationException(
          'Destination wallet account ${voucher.toWalletAccountId} does not belong to company $companyId or does not exist.',
        );
      }
    }

    if (voucher.categoryAccountId != null) {
      final categoryAcc = await (_db.select(_db.accounts)
            ..where((t) => t.id.equals(voucher.categoryAccountId!) & t.isDeleted.equals(false)))
          .getSingleOrNull();
      if (categoryAcc == null || categoryAcc.companyId != companyId) {
        throw VoucherValidationException(
          'Category account ${voucher.categoryAccountId} does not belong to company $companyId or does not exist.',
        );
      }

      // Category type matches the voucher type
      final catType = AccountType.values.firstWhere(
        (e) => e.name.toLowerCase() == categoryAcc.type.toLowerCase(),
        orElse: () => AccountType.expense,
      );

      if (voucher.type == VoucherType.expense && catType != AccountType.expense) {
        throw VoucherValidationException(
          'Category account ${categoryAcc.name} must be of type Expense for an expense voucher. Found: ${catType.name}',
        );
      }

      if (voucher.type == VoucherType.income && catType != AccountType.income) {
        throw VoucherValidationException(
          'Category account ${categoryAcc.name} must be of type Income for an income voucher. Found: ${catType.name}',
        );
      }
    }
  }

  /// Posts a voucher into the database, generating double-entry journal entries,
  /// party ledger records, and stock ledger movements atomically in a single transaction.
  Future<VoucherModel> postVoucher({
    required VoucherModel voucher,
    required String userId,
  }) async {
    return await _db.transaction(() async {
      final now = DateTime.now();

      // Ensure accounts exist for this company
      await ensureCompanyAccounts(voucher.companyId);

      // Validate voucher rules before writing
      await _validateVoucher(voucher);

      // 1. Insert or update the voucher record
      final itemsJsonString = jsonEncode(voucher.items.map((i) => i.toMap()).toList());
      await _db.into(_db.vouchers).insertOnConflictUpdate(
            VouchersCompanion.insert(
              id: voucher.id,
              companyId: Value(voucher.companyId),
              voucherNumber: voucher.voucherNumber,
              type: voucher.type.name,
              date: voucher.date,
              dueDate: Value(voucher.dueDate),
              partyId: Value(voucher.partyId),
              partyName: Value(voucher.partyName),
              status: Value(voucher.status.name),
              paymentMode: Value(voucher.paymentMode.name),
              subtotalInCents: Value(voucher.subtotalInCents),
              taxInCents: Value(voucher.taxInCents),
              discountInCents: Value(voucher.discountInCents),
              totalAmountInCents: Value(voucher.totalAmountInCents),
              narration: Value(voucher.narration),
              referenceNumber: Value(voucher.referenceNumber),
              sourceVoucherId: Value(voucher.sourceVoucherId),
              receiptPhotoUrl: Value(voucher.receiptPhotoUrl),
              itemsJson: Value(itemsJsonString),
              categoryAccountId: Value(voucher.categoryAccountId),
              walletAccountId: Value(voucher.walletAccountId),
              toWalletAccountId: Value(voucher.toWalletAccountId),
              createdAt: Value(voucher.createdAt),
              updatedAt: Value(now),
            ),
          );

      // 2. Double-Entry Posting for Financial Vouchers
      if (voucher.type.isFinancialPosting && voucher.status == VoucherStatus.posted) {
        // Post balanced Journal Header & Lines
        await _postDoubleEntryJournal(voucher);

        // Maintain party subledger entry for party statement compatibility
        await _postPartyLedgerEntry(voucher);

        // Maintain inventory stock movements
        await _postInventoryStockMovements(voucher);
      }

      // 3. If this voucher converted a source order or estimate, mark source as converted
      if (voucher.sourceVoucherId != null) {
        await (_db.update(_db.vouchers)..where((t) => t.id.equals(voucher.sourceVoucherId!))).write(
          const VouchersCompanion(
            status: Value('converted'),
          ),
        );
      }

      // 4. Audit Log
      await _auditService.recordLog(
        companyId: voucher.companyId,
        userId: userId,
        entityType: 'voucher',
        entityId: voucher.id,
        action: AuditAction.insert,
        newState: voucher.toMap(),
      );

      // 5. Sync Outbox
      await _db.into(_db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              id: _uuid.v4(),
              targetTable: 'vouchers',
              recordId: voucher.id,
              mutationType: 'INSERT',
              payload: jsonEncode({
                ...voucher.toMap(),
                'companyId': voucher.companyId,
              }),
            ),
          );

      return voucher;
    });
  }

  /// Posts a balanced Journal Header and Journal Lines for a Voucher.
  /// Enforces Total Debit == Total Credit.
  Future<JournalModel> _postDoubleEntryJournal(VoucherModel voucher) async {
    final companyId = voucher.companyId;
    final totalAmount = voucher.totalAmountInCents;
    if (totalAmount <= 0) {
      throw UnbalancedJournalException(
        totalDebit: 0,
        totalCredit: 0,
        message: 'Cannot post a transaction with zero or negative total amount.',
      );
    }

    final journalId = 'jnl_${voucher.id}';
    final journalNumber = 'JNL-${voucher.voucherNumber}';
    final now = DateTime.now();

    final List<JournalLinesCompanion> linesToInsert = [];

    // Account ID helpers
    final arAccountId = '${companyId}_${DefaultAccounts.arId}';
    final apAccountId = '${companyId}_${DefaultAccounts.apId}';
    final salesAccountId = '${companyId}_${DefaultAccounts.salesId}';
    final purchasesAccountId = '${companyId}_${DefaultAccounts.purchasesCogsId}';
    final outputGstAccountId = '${companyId}_${DefaultAccounts.outputGstId}';
    final inputGstAccountId = '${companyId}_${DefaultAccounts.inputGstId}';
    final companyRow = await (_db.select(_db.companies)..where((t) => t.id.equals(companyId))).getSingleOrNull();
    final isExpenseCompany = companyRow?.mode == CompanyMode.expenseTracker.name;

    final cashAccountId = isExpenseCompany
        ? '${companyId}_${ExpenseTrackerDefaults.walletCashId}'
        : '${companyId}_${DefaultAccounts.cashId}';
    final bankAccountId = isExpenseCompany
        ? '${companyId}_${ExpenseTrackerDefaults.walletBankId}'
        : '${companyId}_${DefaultAccounts.bankId}';
    final operatingExpenseAccountId = isExpenseCompany
        ? '${companyId}_${ExpenseTrackerDefaults.otherExpensesId}'
        : '${companyId}_${DefaultAccounts.indirectExpensesId}';
    final otherIncomeAccountId = '${companyId}_${DefaultAccounts.otherIncomeId}';

    final liquidAccountId = (voucher.paymentMode == PaymentMode.bank || voucher.paymentMode == PaymentMode.upi)
        ? bankAccountId
        : cashAccountId;

    switch (voucher.type) {
      case VoucherType.sales:
        // SALE Posting Rule:
        // AR Dr (credit) or Cash/Bank Dr (liquid) = invoice total
        // Sales Cr = taxable amount
        // Output GST Cr = tax
        final taxAmount = voucher.taxInCents;
        final taxableAmount = voucher.subtotalInCents > 0
            ? voucher.subtotalInCents
            : (totalAmount - taxAmount);

        final salesDrAccountId = (voucher.paymentMode == PaymentMode.credit)
            ? arAccountId
            : liquidAccountId;
        final salesDrNarration = (voucher.paymentMode == PaymentMode.credit)
            ? 'Trade Receivable - ${voucher.partyName ?? "Customer"}'
            : 'Settlement via ${voucher.paymentMode.displayName} - ${voucher.partyName ?? "Customer"}';

        // AR / Liquid Debit Line
        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_dr',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: salesDrAccountId,
          partyId: Value(voucher.partyId),
          debitInCents: Value(totalAmount),
          creditInCents: const Value(0),
          narration: Value(salesDrNarration),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));

        // Sales Revenue Credit Line
        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_sales',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: salesAccountId,
          partyId: Value(voucher.partyId),
          debitInCents: const Value(0),
          creditInCents: Value(taxableAmount),
          narration: Value('Sales Revenue #${voucher.voucherNumber}'),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));

        // Output GST Credit Line (if tax > 0)
        if (taxAmount > 0) {
          linesToInsert.add(JournalLinesCompanion.insert(
            id: '${journalId}_line_tax',
            companyId: Value(companyId),
            journalId: journalId,
            accountId: outputGstAccountId,
            partyId: Value(voucher.partyId),
            debitInCents: const Value(0),
            creditInCents: Value(taxAmount),
            narration: Value('Output GST on Sales #${voucher.voucherNumber}'),
            createdAt: Value(voucher.date),
            updatedAt: Value(now),
          ));
        }
        break;

      case VoucherType.purchase:
        // PURCHASE Posting Rule:
        // Purchase/Inventory Dr = taxable amount
        // Input GST Dr = tax
        // AP Cr (credit) or Cash/Bank Cr (liquid) = total
        final taxAmount = voucher.taxInCents;
        final taxableAmount = voucher.subtotalInCents > 0
            ? voucher.subtotalInCents
            : (totalAmount - taxAmount);

        // Purchases / COGS Debit Line
        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_purchases',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: purchasesAccountId,
          partyId: Value(voucher.partyId),
          debitInCents: Value(taxableAmount),
          creditInCents: const Value(0),
          narration: Value('Purchases #${voucher.voucherNumber}'),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));

        // Input GST Debit Line (if tax > 0)
        if (taxAmount > 0) {
          linesToInsert.add(JournalLinesCompanion.insert(
            id: '${journalId}_line_tax',
            companyId: Value(companyId),
            journalId: journalId,
            accountId: inputGstAccountId,
            partyId: Value(voucher.partyId),
            debitInCents: Value(taxAmount),
            creditInCents: const Value(0),
            narration: Value('Input GST ITC on Purchases #${voucher.voucherNumber}'),
            createdAt: Value(voucher.date),
            updatedAt: Value(now),
          ));
        }

        final purchaseCrAccountId = (voucher.paymentMode == PaymentMode.credit)
            ? apAccountId
            : liquidAccountId;
        final purchaseCrNarration = (voucher.paymentMode == PaymentMode.credit)
            ? 'Trade Payable - ${voucher.partyName ?? "Supplier"}'
            : 'Payment disbursed via ${voucher.paymentMode.displayName} - ${voucher.partyName ?? "Supplier"}';

        // AP / Liquid Credit Line
        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_cr',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: purchaseCrAccountId,
          partyId: Value(voucher.partyId),
          debitInCents: const Value(0),
          creditInCents: Value(totalAmount),
          narration: Value(purchaseCrNarration),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));
        break;

      case VoucherType.receipt:
        // RECEIPT Posting Rule:
        // Cash/Bank Dr = receipt amount
        // AR Cr = receipt amount
        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_dr',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: liquidAccountId,
          partyId: Value(voucher.partyId),
          debitInCents: Value(totalAmount),
          creditInCents: const Value(0),
          narration: Value('Payment received via ${voucher.paymentMode.displayName}'),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));

        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_cr',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: arAccountId,
          partyId: Value(voucher.partyId),
          debitInCents: const Value(0),
          creditInCents: Value(totalAmount),
          narration: Value('Settlement of receivable - ${voucher.partyName ?? "Customer"}'),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));
        break;

      case VoucherType.payment:
        // PAYMENT Posting Rule:
        // AP Dr = payment amount
        // Cash/Bank Cr = payment amount
        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_dr',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: apAccountId,
          partyId: Value(voucher.partyId),
          debitInCents: Value(totalAmount),
          creditInCents: const Value(0),
          narration: Value('Settlement of payable - ${voucher.partyName ?? "Supplier"}'),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));

        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_cr',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: liquidAccountId,
          partyId: Value(voucher.partyId),
          debitInCents: const Value(0),
          creditInCents: Value(totalAmount),
          narration: Value('Payment disbursed via ${voucher.paymentMode.displayName}'),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));
        break;

      case VoucherType.expense:
        // EXPENSE Posting Rule:
        // Debit: categoryAccountId (or operatingExpenseAccountId fallback)
        // Credit: walletAccountId (or liquidAccountId fallback)
        final expDrAccId = voucher.categoryAccountId ?? operatingExpenseAccountId;
        final expCrAccId = voucher.walletAccountId ?? liquidAccountId;

        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_dr',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: expDrAccId,
          partyId: Value(voucher.partyId),
          debitInCents: Value(totalAmount),
          creditInCents: const Value(0),
          narration: Value(voucher.narration ?? 'Expense'),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));

        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_cr',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: expCrAccId,
          partyId: Value(voucher.partyId),
          debitInCents: const Value(0),
          creditInCents: Value(totalAmount),
          narration: Value(voucher.narration ?? 'Paid from wallet'),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));
        break;

      case VoucherType.income:
        // INCOME Posting Rule:
        // Debit: walletAccountId (or liquidAccountId fallback)
        // Credit: categoryAccountId (or otherIncomeAccountId fallback)
        final incDrAccId = voucher.walletAccountId ?? liquidAccountId;
        final incCrAccId = voucher.categoryAccountId ?? otherIncomeAccountId;

        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_dr',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: incDrAccId,
          partyId: Value(voucher.partyId),
          debitInCents: Value(totalAmount),
          creditInCents: const Value(0),
          narration: Value(voucher.narration ?? 'Received into wallet'),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));

        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_cr',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: incCrAccId,
          partyId: Value(voucher.partyId),
          debitInCents: const Value(0),
          creditInCents: Value(totalAmount),
          narration: Value(voucher.narration ?? 'Income'),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));
        break;

      case VoucherType.transfer:
        // TRANSFER Posting Rule:
        // Debit: toWalletAccountId (or bank/cash fallback based on paymentMode)
        // Credit: walletAccountId (or cash/bank fallback based on paymentMode)
        final isTransferCashToBank = voucher.paymentMode == PaymentMode.bank;
        final trfDrAccId = voucher.toWalletAccountId ?? (isTransferCashToBank ? bankAccountId : cashAccountId);
        final trfCrAccId = voucher.walletAccountId ?? (isTransferCashToBank ? cashAccountId : bankAccountId);

        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_dr',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: trfDrAccId,
          debitInCents: Value(totalAmount),
          creditInCents: const Value(0),
          narration: Value(voucher.narration ?? 'Fund Transfer Inflow'),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));

        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_cr',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: trfCrAccId,
          debitInCents: const Value(0),
          creditInCents: Value(totalAmount),
          narration: Value(voucher.narration ?? 'Fund Transfer Outflow'),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));
        break;

      case VoucherType.contra:
        // CONTRA Posting Rule (Cash / Bank transfer):
        // Destination Dr, Source Cr
        final isCashDepositToBank = voucher.paymentMode == PaymentMode.bank;
        final drAcc = voucher.toWalletAccountId ?? (isCashDepositToBank ? bankAccountId : cashAccountId);
        final crAcc = voucher.walletAccountId ?? (isCashDepositToBank ? cashAccountId : bankAccountId);

        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_dr',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: drAcc,
          debitInCents: Value(totalAmount),
          creditInCents: const Value(0),
          narration: Value('Fund Transfer (Contra) Inflow'),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));

        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_cr',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: crAcc,
          debitInCents: const Value(0),
          creditInCents: Value(totalAmount),
          narration: Value('Fund Transfer (Contra) Outflow'),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));
        break;

      case VoucherType.journal:
        // MANUAL JOURNAL / ADJUSTMENT
        // If items are specified, map them to lines
        if (voucher.items.isNotEmpty) {
          for (int i = 0; i < voucher.items.length; i++) {
            final itm = voucher.items[i];
            final isDr = itm.unitPriceInCents > 0;
            linesToInsert.add(JournalLinesCompanion.insert(
              id: '${journalId}_line_$i',
              companyId: Value(companyId),
              journalId: journalId,
              accountId: itm.itemId.isNotEmpty ? itm.itemId : operatingExpenseAccountId,
              partyId: Value(voucher.partyId),
              debitInCents: Value(isDr ? itm.totalInCents : 0),
              creditInCents: Value(!isDr ? itm.totalInCents : 0),
              narration: Value(itm.itemName),
              createdAt: Value(voucher.date),
              updatedAt: Value(now),
            ));
          }
        } else {
          // Default symmetrical 2-leg entry for party
          linesToInsert.add(JournalLinesCompanion.insert(
            id: '${journalId}_line_dr',
            companyId: Value(companyId),
            journalId: journalId,
            accountId: arAccountId,
            partyId: Value(voucher.partyId),
            debitInCents: Value(totalAmount),
            creditInCents: const Value(0),
            narration: Value(voucher.narration ?? 'Journal Debit'),
            createdAt: Value(voucher.date),
            updatedAt: Value(now),
          ));
          linesToInsert.add(JournalLinesCompanion.insert(
            id: '${journalId}_line_cr',
            companyId: Value(companyId),
            journalId: journalId,
            accountId: salesAccountId,
            partyId: Value(voucher.partyId),
            debitInCents: const Value(0),
            creditInCents: Value(totalAmount),
            narration: Value(voucher.narration ?? 'Journal Credit'),
            createdAt: Value(voucher.date),
            updatedAt: Value(now),
          ));
        }
        break;

      default:
        return JournalModel(
          id: journalId,
          companyId: companyId,
          journalNumber: journalNumber,
          date: voucher.date,
          createdAt: now,
          updatedAt: now,
        );
    }

    // Verify mathematical Double-Entry equality: Total Debit == Total Credit
    final sumDebit = linesToInsert.fold<int>(0, (acc, l) => acc + l.debitInCents.value);
    final sumCredit = linesToInsert.fold<int>(0, (acc, l) => acc + l.creditInCents.value);

    if (sumDebit != sumCredit || sumDebit <= 0) {
      throw UnbalancedJournalException(
        totalDebit: sumDebit,
        totalCredit: sumCredit,
        message: 'Unbalanced Journal: Total Debit ($sumDebit cents) != Total Credit ($sumCredit cents). Transaction rejected.',
      );
    }

    // Insert Journal Header
    await _db.into(_db.journals).insertOnConflictUpdate(
          JournalsCompanion.insert(
            id: journalId,
            companyId: Value(companyId),
            journalNumber: journalNumber,
            voucherId: Value(voucher.id),
            date: voucher.date,
            narration: Value(voucher.narration ?? '${voucher.type.displayName} #${voucher.voucherNumber}'),
            totalAmountInCents: Value(sumDebit),
            status: const Value('posted'),
            createdAt: Value(voucher.date),
            updatedAt: Value(now),
          ),
        );

    // Query any previous lines before replacing them (for edit/repost)
    final previousLines = await (_db.select(_db.journalLines)..where((t) => t.journalId.equals(journalId))).get();
    final previousAccountIds = previousLines.map((l) => l.accountId).toSet();

    // Delete any previous lines if re-posting/updating
    await (_db.delete(_db.journalLines)..where((t) => t.journalId.equals(journalId))).go();

    // Insert Journal Lines
    for (final line in linesToInsert) {
      await _db.into(_db.journalLines).insertOnConflictUpdate(line);
    }

    // Update all affected Account balances (both previously affected and newly affected)
    final affectedAccountIds = {
      ...previousAccountIds,
      ...linesToInsert.map((l) => l.accountId.value),
    };
    for (final accId in affectedAccountIds) {
      await _recalculateAccountBalance(accId, companyId);
    }

    return JournalModel(
      id: journalId,
      companyId: companyId,
      journalNumber: journalNumber,
      voucherId: voucher.id,
      date: voucher.date,
      narration: voucher.narration,
      totalAmountInCents: sumDebit,
      status: 'posted',
      lines: linesToInsert
          .map((l) => JournalLineModel(
                id: l.id.value,
                companyId: l.companyId.value,
                journalId: l.journalId.value,
                accountId: l.accountId.value,
                partyId: l.partyId.value,
                debitInCents: l.debitInCents.value,
                creditInCents: l.creditInCents.value,
                narration: l.narration.value,
                createdAt: l.createdAt.value,
                updatedAt: l.updatedAt.value,
              ))
          .toList(),
      createdAt: voucher.date,
      updatedAt: now,
    );
  }

  /// Posts a standalone balanced Journal Entry (manual journal or adjustment).
  /// Rejects any unbalanced journal entry.
  Future<JournalModel> postJournalEntry({
    required JournalModel journal,
    required String userId,
  }) async {
    return await _db.transaction(() async {
      await ensureCompanyAccounts(journal.companyId);

      final totalDebit = journal.totalDebit;
      final totalCredit = journal.totalCredit;

      if (totalDebit != totalCredit || totalDebit <= 0) {
        throw UnbalancedJournalException(
          totalDebit: totalDebit,
          totalCredit: totalCredit,
          message: 'Cannot post unbalanced journal entry. Total Debit ($totalDebit) != Total Credit ($totalCredit).',
        );
      }

      final now = DateTime.now();

      // Insert Journal Header
      await _db.into(_db.journals).insertOnConflictUpdate(
            JournalsCompanion.insert(
              id: journal.id,
              companyId: Value(journal.companyId),
              journalNumber: journal.journalNumber,
              voucherId: Value(journal.voucherId),
              date: journal.date,
              narration: Value(journal.narration),
              totalAmountInCents: Value(totalDebit),
              status: Value(journal.status),
              createdAt: Value(journal.createdAt),
              updatedAt: Value(now),
            ),
          );

      // Insert Lines
      await (_db.delete(_db.journalLines)..where((t) => t.journalId.equals(journal.id))).go();
      for (final line in journal.lines) {
        await _db.into(_db.journalLines).insertOnConflictUpdate(
              JournalLinesCompanion.insert(
                id: line.id,
                companyId: Value(journal.companyId),
                journalId: journal.id,
                accountId: line.accountId,
                partyId: Value(line.partyId),
                debitInCents: Value(line.debitInCents),
                creditInCents: Value(line.creditInCents),
                narration: Value(line.narration),
                createdAt: Value(line.createdAt),
                updatedAt: Value(now),
              ),
            );

        // Recalculate party balance if linked to a party
        if (line.partyId != null) {
          await _recalculatePartyBalance(line.partyId!, journal.companyId);
        }
      }

      // Update Account balances
      final affectedAccountIds = journal.lines.map((l) => l.accountId).toSet();
      for (final accId in affectedAccountIds) {
        await _recalculateAccountBalance(accId, journal.companyId);
      }

      // Record audit
      await _auditService.recordLog(
        companyId: journal.companyId,
        userId: userId,
        entityType: 'journal',
        entityId: journal.id,
        action: AuditAction.insert,
        newState: journal.toMap(),
      );

      return journal;
    });
  }

  /// Posts Opening Balances for Cash, Bank, AR (customers), AP (suppliers), Inventory, and Capital.
  /// Automatically balances total assets with total liabilities and equity.
  Future<JournalModel> postOpeningBalances({
    required String companyId,
    required String userId,
    DateTime? date,
    int cashInCents = 0,
    int bankInCents = 0,
    int inventoryInCents = 0,
    Map<String, int> receivablesByParty = const {}, // PartyId -> Amount (cents)
    Map<String, int> payablesByParty = const {}, // PartyId -> Amount (cents)
    int? explicitCapitalInCents,
  }) async {
    return await _db.transaction(() async {
      await ensureCompanyAccounts(companyId);

      final postingDate = date ?? DateTime.now();
      final now = DateTime.now();
      final journalId = 'jnl_opening_${companyId}_${postingDate.year}';
      final journalNumber = 'JNL-OPENING-${postingDate.year}';

      final List<JournalLinesCompanion> lines = [];

      final cashAccountId = '${companyId}_${DefaultAccounts.cashId}';
      final bankAccountId = '${companyId}_${DefaultAccounts.bankId}';
      final inventoryAccountId = '${companyId}_${DefaultAccounts.inventoryId}';
      final arAccountId = '${companyId}_${DefaultAccounts.arId}';
      final apAccountId = '${companyId}_${DefaultAccounts.apId}';
      final capitalAccountId = '${companyId}_${DefaultAccounts.capitalId}';

      int totalAssetDebits = 0;
      int totalLiabCredits = 0;

      // 1. Cash Opening Balance
      if (cashInCents > 0) {
        totalAssetDebits += cashInCents;
        lines.add(JournalLinesCompanion.insert(
          id: '${journalId}_cash',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: cashAccountId,
          debitInCents: Value(cashInCents),
          creditInCents: const Value(0),
          narration: const Value('Opening Balance - Cash in Hand'),
          createdAt: Value(postingDate),
          updatedAt: Value(now),
        ));
      }

      // 2. Bank Opening Balance
      if (bankInCents > 0) {
        totalAssetDebits += bankInCents;
        lines.add(JournalLinesCompanion.insert(
          id: '${journalId}_bank',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: bankAccountId,
          debitInCents: Value(bankInCents),
          creditInCents: const Value(0),
          narration: const Value('Opening Balance - Bank Account'),
          createdAt: Value(postingDate),
          updatedAt: Value(now),
        ));
      }

      // 3. Inventory Opening Stock Value
      if (inventoryInCents > 0) {
        totalAssetDebits += inventoryInCents;
        lines.add(JournalLinesCompanion.insert(
          id: '${journalId}_inventory',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: inventoryAccountId,
          debitInCents: Value(inventoryInCents),
          creditInCents: const Value(0),
          narration: const Value('Opening Stock Valuation'),
          createdAt: Value(postingDate),
          updatedAt: Value(now),
        ));
      }

      // 4. Receivables (Customer Balances)
      int idx = 0;
      for (final entry in receivablesByParty.entries) {
        final partyId = entry.key;
        final amount = entry.value;
        if (amount <= 0) continue;

        totalAssetDebits += amount;
        lines.add(JournalLinesCompanion.insert(
          id: '${journalId}_ar_${idx++}',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: arAccountId,
          partyId: Value(partyId),
          debitInCents: Value(amount),
          creditInCents: const Value(0),
          narration: const Value('Opening Trade Receivable'),
          createdAt: Value(postingDate),
          updatedAt: Value(now),
        ));

        // Create initial party ledger entry for party view
        await _db.into(_db.ledgerEntries).insertOnConflictUpdate(
              LedgerEntriesCompanion.insert(
                id: 'open_ar_${partyId}_$journalId',
                companyId: Value(companyId),
                partyId: partyId,
                amountInCents: amount,
                type: EntryType.gave,
                date: postingDate,
                note: const Value('Opening Receivable Balance'),
                isVoided: const Value(false),
                createdAt: Value(postingDate),
              ),
            );
        await _recalculatePartyBalance(partyId, companyId);
      }

      // 5. Payables (Supplier Balances)
      idx = 0;
      for (final entry in payablesByParty.entries) {
        final partyId = entry.key;
        final amount = entry.value;
        if (amount <= 0) continue;

        totalLiabCredits += amount;
        lines.add(JournalLinesCompanion.insert(
          id: '${journalId}_ap_${idx++}',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: apAccountId,
          partyId: Value(partyId),
          debitInCents: const Value(0),
          creditInCents: Value(amount),
          narration: const Value('Opening Trade Payable'),
          createdAt: Value(postingDate),
          updatedAt: Value(now),
        ));

        // Create initial party ledger entry for party view
        await _db.into(_db.ledgerEntries).insertOnConflictUpdate(
              LedgerEntriesCompanion.insert(
                id: 'open_ap_${partyId}_$journalId',
                companyId: Value(companyId),
                partyId: partyId,
                amountInCents: amount,
                type: EntryType.got,
                date: postingDate,
                note: const Value('Opening Payable Balance'),
                isVoided: const Value(false),
                createdAt: Value(postingDate),
              ),
            );
        await _recalculatePartyBalance(partyId, companyId);
      }

      // 6. Balancing Capital / Equity Line
      final netEquity = totalAssetDebits - totalLiabCredits;
      if (netEquity > 0) {
        lines.add(JournalLinesCompanion.insert(
          id: '${journalId}_capital',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: capitalAccountId,
          debitInCents: const Value(0),
          creditInCents: Value(netEquity),
          narration: const Value("Owner's Opening Capital & Equity"),
          createdAt: Value(postingDate),
          updatedAt: Value(now),
        ));
      } else if (netEquity < 0) {
        lines.add(JournalLinesCompanion.insert(
          id: '${journalId}_capital',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: capitalAccountId,
          debitInCents: Value(netEquity.abs()),
          creditInCents: const Value(0),
          narration: const Value("Owner's Opening Capital Deficit"),
          createdAt: Value(postingDate),
          updatedAt: Value(now),
        ));
      }

      final sumDr = lines.fold<int>(0, (acc, l) => acc + l.debitInCents.value);
      final sumCr = lines.fold<int>(0, (acc, l) => acc + l.creditInCents.value);

      if (sumDr != sumCr || sumDr == 0) {
        throw UnbalancedJournalException(
          totalDebit: sumDr,
          totalCredit: sumCr,
          message: 'Opening balance journal must be balanced.',
        );
      }

      // Insert Journal Header
      await _db.into(_db.journals).insertOnConflictUpdate(
            JournalsCompanion.insert(
              id: journalId,
              companyId: Value(companyId),
              journalNumber: journalNumber,
              voucherId: const Value(null),
              date: postingDate,
              narration: const Value('Opening Balances Posting'),
              totalAmountInCents: Value(sumDr),
              status: const Value('posted'),
              createdAt: Value(postingDate),
              updatedAt: Value(now),
            ),
          );

      // Insert Lines
      await (_db.delete(_db.journalLines)..where((t) => t.journalId.equals(journalId))).go();
      for (final line in lines) {
        await _db.into(_db.journalLines).insertOnConflictUpdate(line);
      }

      // Update Account balances
      final affectedAccountIds = lines.map((l) => l.accountId.value).toSet();
      for (final accId in affectedAccountIds) {
        await _recalculateAccountBalance(accId, companyId);
      }

      final createdJournal = JournalModel(
        id: journalId,
        companyId: companyId,
        journalNumber: journalNumber,
        date: postingDate,
        narration: 'Opening Balances Posting',
        totalAmountInCents: sumDr,
        status: 'posted',
        lines: lines
            .map((l) => JournalLineModel(
                  id: l.id.value,
                  companyId: l.companyId.value,
                  journalId: l.journalId.value,
                  accountId: l.accountId.value,
                  partyId: l.partyId.value,
                  debitInCents: l.debitInCents.value,
                  creditInCents: l.creditInCents.value,
                  narration: l.narration.value,
                  createdAt: l.createdAt.value,
                  updatedAt: l.updatedAt.value,
                ))
            .toList(),
        createdAt: postingDate,
        updatedAt: now,
      );

      await _auditService.recordLog(
        companyId: companyId,
        userId: userId,
        entityType: 'journal',
        entityId: journalId,
        action: AuditAction.insert,
        newState: createdJournal.toMap(),
      );

      return createdJournal;
    });
  }

  /// Voids a voucher and all its associated double-entry ledger entries.
  Future<void> voidVoucher({
    required String voucherId,
    required String companyId,
    required String userId,
  }) async {
    await _db.transaction(() async {
      // 1. Mark voucher voided
      await (_db.update(_db.vouchers)..where((t) => t.id.equals(voucherId) & t.companyId.equals(companyId))).write(
        const VouchersCompanion(
          status: Value('voided'),
        ),
      );

      // 2. Void Journal Header and Lines
      final journalId = 'jnl_$voucherId';
      await (_db.update(_db.journals)..where((t) => t.id.equals(journalId) & t.companyId.equals(companyId))).write(
        const JournalsCompanion(
          status: Value('voided'),
        ),
      );

      // 3. Void Party Ledger Entry
      final entryId = 'vch_entry_$voucherId';
      await (_db.update(_db.ledgerEntries)..where((t) => t.id.equals(entryId) & t.companyId.equals(companyId))).write(
        const LedgerEntriesCompanion(
          isVoided: Value(true),
        ),
      );

      // 4. Void Stock Ledger Entry
      await (_db.update(_db.stockLedger)..where((t) => t.voucherId.equals(voucherId) & t.companyId.equals(companyId))).write(
        const StockLedgerCompanion(
          isDeleted: Value(true),
        ),
      );

      // 5. Query voucher to recalculate party and inventory balances
      final voucherRow = await (_db.select(_db.vouchers)..where((t) => t.id.equals(voucherId))).getSingleOrNull();
      if (voucherRow != null && voucherRow.partyId != null) {
        await _recalculatePartyBalance(voucherRow.partyId!, companyId);
      }

      // 6. Recalculate affected accounts
      final lines = await (_db.select(_db.journalLines)..where((t) => t.journalId.equals(journalId))).get();
      final affectedAccountIds = lines.map((l) => l.accountId).toSet();
      for (final accId in affectedAccountIds) {
        await _recalculateAccountBalance(accId, companyId);
      }

      // 7. Audit log
      await _auditService.recordLog(
        companyId: companyId,
        userId: userId,
        entityType: 'voucher',
        entityId: voucherId,
        action: AuditAction.voided,
        newState: {'id': voucherId, 'status': 'voided'},
      );
    });
  }

  /// Edits an existing voucher, replacing its double-entry journal lines and recalculating balances.
  Future<VoucherModel> editVoucher({
    required VoucherModel voucher,
    required String userId,
  }) async {
    return await postVoucher(voucher: voucher, userId: userId);
  }

  Future<void> _postPartyLedgerEntry(VoucherModel voucher) async {
    // Expense, income, and transfer do not touch party subledger entries
    if (voucher.type == VoucherType.expense ||
        voucher.type == VoucherType.income ||
        voucher.type == VoucherType.transfer) {
      return;
    }

    if (voucher.partyId == null || voucher.totalAmountInCents == 0) return;

    final entryId = 'vch_entry_${voucher.id}';
    EntryType entryType;
    String note = voucher.narration ?? '${voucher.type.displayName} #${voucher.voucherNumber}';

    switch (voucher.type) {
      case VoucherType.sales:
        // Sales to customer -> You will get (Receivable) -> EntryType.gave
        entryType = EntryType.gave;
        break;
      case VoucherType.purchase:
        // Purchase from supplier -> You owe (Payable) -> EntryType.got
        entryType = EntryType.got;
        break;
      case VoucherType.receipt:
        // Payment received from party -> Reduces receivable -> EntryType.got
        entryType = EntryType.got;
        break;
      case VoucherType.payment:
        // Payment made to party -> Reduces payable -> EntryType.gave
        entryType = EntryType.gave;
        break;
      case VoucherType.contra:
      case VoucherType.journal:
        entryType = EntryType.gave;
        break;
      default:
        return;
    }

    await _db.into(_db.ledgerEntries).insertOnConflictUpdate(
          LedgerEntriesCompanion.insert(
            id: entryId,
            companyId: Value(voucher.companyId),
            partyId: voucher.partyId!,
            amountInCents: voucher.totalAmountInCents,
            type: entryType,
            date: voucher.date,
            note: Value(note),
            receiptPhotoUrl: Value(voucher.receiptPhotoUrl),
            isVoided: const Value(false),
            createdAt: Value(voucher.date),
          ),
        );

    // Recalculate party balance
    await _recalculatePartyBalance(voucher.partyId!, voucher.companyId);
  }

  Future<void> _postInventoryStockMovements(VoucherModel voucher) async {
    if (voucher.items.isEmpty) return;

    for (int i = 0; i < voucher.items.length; i++) {
      final item = voucher.items[i];
      final stockEntryId = 'stk_${voucher.id}_$i';

      StockTransactionType txnType;
      double stockDelta;

      if (voucher.type == VoucherType.sales) {
        // Sale reduces stock
        txnType = StockTransactionType.outward;
        stockDelta = -item.quantity;
      } else if (voucher.type == VoucherType.purchase) {
        // Purchase adds stock
        txnType = StockTransactionType.inward;
        stockDelta = item.quantity;
      } else {
        continue;
      }

      final currentItem = await (_db.select(_db.inventoryItems)
            ..where((t) => t.id.equals(item.itemId) & t.companyId.equals(voucher.companyId)))
          .getSingleOrNull();

      if (currentItem != null) {
        final newStockQty = currentItem.currentStockQuantity + stockDelta;

        // Update item running stock
        await (_db.update(_db.inventoryItems)..where((t) => t.id.equals(item.itemId))).write(
          InventoryItemsCompanion(
            currentStockQuantity: Value(newStockQty),
            updatedAt: Value(DateTime.now()),
          ),
        );

        // Record stock ledger movement
        await _db.into(_db.stockLedger).insertOnConflictUpdate(
              StockLedgerCompanion.insert(
                id: stockEntryId,
                companyId: Value(voucher.companyId),
                itemId: item.itemId,
                voucherId: Value(voucher.id),
                transactionType: txnType.name,
                quantity: item.quantity,
                unitCostInCents: Value(item.unitPriceInCents),
                totalCostInCents: Value(item.totalInCents),
                runningStockQuantity: Value(newStockQty),
                date: voucher.date,
                note: Value('${voucher.type.displayName} #${voucher.voucherNumber}'),
                createdAt: Value(DateTime.now()),
              ),
            );
      }
    }
  }

  Future<void> _recalculatePartyBalance(String partyId, String companyId) async {
    final partyQuery = _db.select(_db.parties)
      ..where((t) => t.id.equals(partyId) & t.companyId.equals(companyId));
    final party = await partyQuery.getSingleOrNull();
    if (party == null) return;

    final entriesQuery = _db.select(_db.ledgerEntries)
      ..where((t) => t.partyId.equals(partyId) & t.companyId.equals(companyId) & t.isVoided.equals(false));
    final entries = await entriesQuery.get();

    int newBalance = 0;
    DateTime latestDate = party.lastUpdated;

    for (final entry in entries) {
      if (entry.type == EntryType.gave) {
        newBalance += entry.amountInCents;
      } else {
        newBalance -= entry.amountInCents;
      }
      if (entry.date.isAfter(latestDate)) {
        latestDate = entry.date;
      }
    }

    await (_db.update(_db.parties)..where((t) => t.id.equals(partyId) & t.companyId.equals(companyId))).write(
      PartiesCompanion(
        netBalanceInCents: Value(newBalance),
        lastUpdated: Value(latestDate),
      ),
    );
  }

  /// Recalculates and updates the running balance for an account from posted journal lines.
  Future<void> recalculateAccountBalance(String accountId, String companyId) =>
      _recalculateAccountBalance(accountId, companyId);

  Future<void> _recalculateAccountBalance(String accountId, String companyId) async {
    final account = await (_db.select(_db.accounts)
          ..where((t) => t.id.equals(accountId) & t.companyId.equals(companyId)))
        .getSingleOrNull();
    if (account == null) return;

    // Sum all non-voided posted journal lines for this account
    final query = _db.select(_db.journalLines).join([
      innerJoin(_db.journals, _db.journals.id.equalsExp(_db.journalLines.journalId)),
    ])
      ..where(_db.journalLines.accountId.equals(accountId) &
          _db.journalLines.companyId.equals(companyId) &
          _db.journalLines.isDeleted.equals(false) &
          _db.journals.status.equals('posted'));

    final rows = await query.get();

    int totalDebit = 0;
    int totalCredit = 0;
    for (final row in rows) {
      final line = row.readTable(_db.journalLines);
      totalDebit += line.debitInCents;
      totalCredit += line.creditInCents;
    }

    final accountType = AccountType.values.firstWhere(
      (e) => e.name.toLowerCase() == account.type.toLowerCase(),
      orElse: () => AccountType.asset,
    );

    final netBalance = accountType.isDebitNormal
        ? (totalDebit - totalCredit)
        : (totalCredit - totalDebit);

    await (_db.update(_db.accounts)..where((t) => t.id.equals(accountId) & t.companyId.equals(companyId))).write(
      AccountsCompanion(
        currentBalanceInCents: Value(netBalance),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );
  }
}
