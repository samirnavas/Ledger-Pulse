import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../domain/exceptions/ledger_exceptions.dart';
import '../local/audit_service.dart';
import '../local/database.dart';
import '../models/account_model.dart';
import '../models/audit_log_model.dart';
import '../models/journal_model.dart';
import '../models/stock_ledger_model.dart';
import '../models/transaction_model.dart';
import '../models/voucher_model.dart';

class VoucherPostingEngine {
  final AppDatabase _db;
  final AuditService _auditService;
  final _uuid = const Uuid();

  VoucherPostingEngine(this._db, this._auditService);

  /// Ensures that default core Chart of Accounts exist for the specified company.
  Future<void> ensureCompanyAccounts(String companyId) async {
    final existingCount = await (_db.select(_db.accounts)
          ..where((t) => t.companyId.equals(companyId) & t.isDeleted.equals(false)))
        .get();

    if (existingCount.isNotEmpty) return;

    final defaultAccounts = DefaultAccounts.getDefaultAccounts(companyId);
    for (final acc in defaultAccounts) {
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
              currentBalanceInCents: Value(acc.currentBalanceInCents),
              createdAt: Value(acc.createdAt),
              updatedAt: Value(acc.updatedAt),
              isDeleted: const Value(false),
              syncStatus: const Value(SyncRecordStatus.synced),
            ),
          );
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
    final cashAccountId = '${companyId}_${DefaultAccounts.cashId}';
    final bankAccountId = '${companyId}_${DefaultAccounts.bankId}';
    final operatingExpenseAccountId = '${companyId}_${DefaultAccounts.indirectExpensesId}';

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
        // Expense Dr = expense amount
        // Cash/Bank Cr = expense amount
        linesToInsert.add(JournalLinesCompanion.insert(
          id: '${journalId}_line_dr',
          companyId: Value(companyId),
          journalId: journalId,
          accountId: operatingExpenseAccountId,
          partyId: Value(voucher.partyId),
          debitInCents: Value(totalAmount),
          creditInCents: const Value(0),
          narration: Value(voucher.narration ?? 'Operating Expense'),
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
          narration: Value('Paid via ${voucher.paymentMode.displayName}'),
          createdAt: Value(voucher.date),
          updatedAt: Value(now),
        ));
        break;

      case VoucherType.contra:
        // CONTRA Posting Rule (Cash / Bank transfer):
        // Destination Dr, Source Cr
        final isCashDepositToBank = voucher.paymentMode == PaymentMode.bank;
        final drAcc = isCashDepositToBank ? bankAccountId : cashAccountId;
        final crAcc = isCashDepositToBank ? cashAccountId : bankAccountId;

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

    // Delete any previous lines if re-posting/updating
    await (_db.delete(_db.journalLines)..where((t) => t.journalId.equals(journalId))).go();

    // Insert Journal Lines
    for (final line in linesToInsert) {
      await _db.into(_db.journalLines).insertOnConflictUpdate(line);
    }

    // Update affected Account balances
    final affectedAccountIds = linesToInsert.map((l) => l.accountId.value).toSet();
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

  Future<void> _postPartyLedgerEntry(VoucherModel voucher) async {
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
      case VoucherType.expense:
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
      ),
    );
  }
}
