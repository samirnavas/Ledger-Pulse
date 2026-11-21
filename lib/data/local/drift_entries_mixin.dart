import 'package:drift/drift.dart';
import '../../core/network/sync_codec.dart';
import '../../data/models/account_model.dart';
import '../../data/models/party_model.dart';
import '../../data/models/rbac_model.dart';
import '../../data/models/transaction_model.dart';
import '../models/audit_log_model.dart';
import '../security/access_control_service.dart';
import 'database.dart';
import 'drift_ledger_base.dart';
import 'ledger_entry_balance.dart';
export 'ledger_entry_balance.dart' show calculatePartyBalanceFromRows;

/// Mixin handling Ledger Entries and running balance recalculation for DriftLedgerRepository.
mixin DriftEntriesMixin on DriftLedgerRepositoryBase {
  Future<List<LedgerEntry>> getEntriesForParty(String partyId) async {
    await ensureInitialized();

    final query = db.select(db.ledgerEntries)
      ..where(
        (t) => t.partyId.equals(partyId) & t.companyId.equals(currentCompanyId),
      )
      ..orderBy([
        (t) => OrderingTerm.asc(t.date),
        (t) => OrderingTerm.asc(t.createdAt),
        (t) => OrderingTerm.asc(t.id),
      ]);

    final rows = await query.get();

    int currentBalance = 0;
    final List<LedgerEntry> entriesWithRunningBalance = [];

    final balance = LedgerEntryBalance(rows);
    for (final row in rows) {
      if (row.isDeleted || balance.isLegacyOffset(row)) continue;
      currentBalance += balance.delta(row);
      entriesWithRunningBalance.add(
        LedgerEntry(
          id: row.id,
          partyId: row.partyId,
          amountInCents: row.amountInCents,
          type: row.type,
          date: row.date,
          note: row.note,
          receiptPhotoUrl: row.receiptPhotoUrl,
          runningBalanceInCents: currentBalance,
          isVoided: row.isVoided,
        ),
      );
    }

    return List.unmodifiable(entriesWithRunningBalance);
  }

  @override
  Future<void> addEntry(LedgerEntry entry) async {
    await ensureInitialized();

    if (entry.amountInCents <= 0) {
      throw ArgumentError.value(entry.amountInCents);
    }
    if (entry.id.startsWith('vch_entry_') || entry.id.startsWith('open_')) {
      throw ArgumentError.value(
        entry.id,
        'id',
        'Reserved ledger projection ID',
      );
    }

    // Verify party existence and determine role permission
    final party = await getPartyById(entry.partyId);
    final action = party.type == PartyType.customer
        ? UserAction.createCustomerEntry
        : UserAction.createSupplierEntry;
    AccessControlService.verifyPermission(currentRole, action);

    final entryId = entry.id.trim().isEmpty ? uuid.v4() : entry.id;
    final effectiveEntry = entry.id == entryId
        ? entry
        : entry.copyWith(id: entryId);

    await db.transaction(() async {
      await requireLedgerProfile();
      final previous = await (db.select(
        db.ledgerEntries,
      )..where((t) => t.id.equals(entryId))).getSingleOrNull();
      if (previous != null) {
        if (previous.companyId != currentCompanyId ||
            previous.partyId != entry.partyId ||
            previous.amountInCents != entry.amountInCents ||
            previous.type != entry.type ||
            previous.date.millisecondsSinceEpoch ~/ 1000 !=
                entry.date.millisecondsSinceEpoch ~/ 1000 ||
            previous.note != entry.note ||
            previous.receiptPhotoUrl != entry.receiptPhotoUrl) {
          throw StateError(
            'Ledger entry ID already exists with different data',
          );
        }
        return;
      }
      final now = DateTime.now();
      await _insertEntryPosting(effectiveEntry, party, now);

      await recordAuditLog(
        entityType: 'ledger_entry',
        entityId: effectiveEntry.id,
        action: AuditAction.insert,
        newState: effectiveEntry.toMap(),
      );
    });

    updateStreamController.add(null);
    triggerBackgroundSync();
  }

  Future<void> _insertEntryPosting(
    LedgerEntry effectiveEntry,
    Party party,
    DateTime now,
  ) async {
    await db
        .into(db.ledgerEntries)
        .insert(
          LedgerEntriesCompanion.insert(
            id: effectiveEntry.id,
            companyId: Value(currentCompanyId),
            partyId: effectiveEntry.partyId,
            amountInCents: effectiveEntry.amountInCents,
            type: effectiveEntry.type,
            date: effectiveEntry.date,
            note: Value(effectiveEntry.note),
            receiptPhotoUrl: Value(effectiveEntry.receiptPhotoUrl),
            isVoided: const Value(false),
            createdAt: Value(now),
            updatedAt: Value(now),
            isDeleted: const Value(false),
            syncStatus: const Value(SyncRecordStatus.pending),
          ),
        );

    await _queueEntry((await _findEntry(effectiveEntry.id))!);
    await _postEntryJournal(effectiveEntry, party, now);
    await _recalculatePartyBalanceInTx(effectiveEntry.partyId);
  }

  Future<void> _postEntryJournal(
    LedgerEntry effectiveEntry,
    Party party,
    DateTime now,
  ) async {
    await postingEngine.ensureCompanyAccounts(currentCompanyId);
    final isCustomer = party.type == PartyType.customer;
    final arAccountId = '${currentCompanyId}_${DefaultAccounts.arId}';
    final apAccountId = '${currentCompanyId}_${DefaultAccounts.apId}';
    final method = LedgerPaymentMethod.read(effectiveEntry.note);
    final settlementAccount = method == null || method == LedgerPaymentMethod.cash
        ? DefaultAccounts.cashId : DefaultAccounts.bankId;
    final cashAccountId = '${currentCompanyId}_$settlementAccount';
    final salesAccountId = '${currentCompanyId}_${DefaultAccounts.salesId}';
    final purchasesAccountId =
        '${currentCompanyId}_${DefaultAccounts.purchasesCogsId}';

    String drAcc;
    String crAcc;
    String note;

    if (effectiveEntry.id.startsWith('entry_init_')) {
      final equity =
          '${currentCompanyId}_${DefaultAccounts.openingBalanceEquityId}';
      final partyAccount = isCustomer ? arAccountId : apAccountId;
      final debitParty = effectiveEntry.type == EntryType.gave;
      drAcc = debitParty ? partyAccount : equity;
      crAcc = debitParty ? equity : partyAccount;
      note = 'Opening Balance';
    } else if (isCustomer) {
      if (effectiveEntry.type == EntryType.got) {
        // Customer Receipt: Cash/Bank DR, AR CR
        drAcc = cashAccountId;
        crAcc = arAccountId;
        note = effectiveEntry.note ?? 'Customer Receipt - ${party.name}';
      } else {
        // Customer Debit: AR DR, Sales CR
        drAcc = arAccountId;
        crAcc = salesAccountId;
        note = effectiveEntry.note ?? 'Customer Charge - ${party.name}';
      }
    } else {
      if (effectiveEntry.type == EntryType.gave) {
        // Supplier Payment: AP DR, Cash/Bank CR
        drAcc = apAccountId;
        crAcc = cashAccountId;
        note = effectiveEntry.note ?? 'Supplier Payment - ${party.name}';
      } else {
        // Supplier Bill: Purchases DR, AP CR
        drAcc = purchasesAccountId;
        crAcc = apAccountId;
        note = effectiveEntry.note ?? 'Supplier Bill - ${party.name}';
      }
    }

    final jnlId = 'jnl_entry_${effectiveEntry.id}';
    final jnlNumber =
        'JNL-ENT-${effectiveEntry.id.length > 8 ? effectiveEntry.id.substring(0, 8) : effectiveEntry.id}';

    await db
        .into(db.journals)
        .insert(
          JournalsCompanion.insert(
            id: jnlId,
            companyId: Value(currentCompanyId),
            journalNumber: jnlNumber,
            date: effectiveEntry.date,
            narration: Value(note),
            totalAmountInCents: Value(effectiveEntry.amountInCents),
            status: const Value('posted'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    await db
        .into(db.journalLines)
        .insert(
          JournalLinesCompanion.insert(
            id: '${jnlId}_dr',
            companyId: Value(currentCompanyId),
            journalId: jnlId,
            accountId: drAcc,
            partyId: Value(effectiveEntry.partyId),
            debitInCents: Value(effectiveEntry.amountInCents),
            creditInCents: const Value(0),
            narration: Value(note),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    await db
        .into(db.journalLines)
        .insert(
          JournalLinesCompanion.insert(
            id: '${jnlId}_cr',
            companyId: Value(currentCompanyId),
            journalId: jnlId,
            accountId: crAcc,
            partyId: Value(effectiveEntry.partyId),
            debitInCents: const Value(0),
            creditInCents: Value(effectiveEntry.amountInCents),
            narration: Value(note),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    await _queueJournal(jnlId);
    await _recalculateAccountBalanceInTx(drAcc);
    await _recalculateAccountBalanceInTx(crAcc);
  }

  Future<LedgerEntryTableData?> _findEntry(String id) =>
      (db.select(db.ledgerEntries)..where(
            (t) => t.id.equals(id) & t.companyId.equals(currentCompanyId),
          ))
          .getSingleOrNull();

  Future<void> _queueEntry(LedgerEntryTableData row) => recordOutboxEntry(
    targetTable: 'ledger_entries',
    recordId: row.id,
    mutationType: 'UPSERT',
    payload: {
      ...row.toJson(),
      'date': encodeTime(row.date),
      'createdAt': encodeTime(row.createdAt),
      'updatedAt': encodeTime(row.updatedAt),
    },
  );

  Future<void> _queueJournal(String id) async {
    final journal =
        await (db.select(db.journals)..where(
              (t) => t.id.equals(id) & t.companyId.equals(currentCompanyId),
            ))
            .getSingle();
    await recordOutboxEntry(
      targetTable: 'journals',
      recordId: id,
      mutationType: 'UPSERT',
      payload: {
        ...journal.toJson(),
        'date': encodeTime(journal.date),
        'createdAt': encodeTime(journal.createdAt),
        'updatedAt': encodeTime(journal.updatedAt),
      },
    );
    final lines =
        await (db.select(db.journalLines)..where(
              (t) =>
                  t.journalId.equals(id) & t.companyId.equals(currentCompanyId),
            ))
            .get();
    for (final line in lines) {
      await recordOutboxEntry(
        targetTable: 'journal_lines',
        recordId: line.id,
        mutationType: 'UPSERT',
        payload: {
          ...line.toJson(),
          'createdAt': encodeTime(line.createdAt),
          'updatedAt': encodeTime(line.updatedAt),
        },
      );
    }
  }

  Future<void> _voidEntryInTransaction(
    LedgerEntryTableData entry,
    DateTime now,
  ) async {
    if (entry.id.startsWith('open_')) {
      throw StateError('Correct opening balances through their source journal');
    }
    await (db.update(
      db.ledgerEntries,
    )..where((t) => t.id.equals(entry.id))).write(
      LedgerEntriesCompanion(
        isVoided: const Value(true),
        revision: Value(entry.revision + 1),
        updatedAt: Value(now),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );
    await _queueEntry((await _findEntry(entry.id))!);

    final journalId = 'jnl_entry_${entry.id}';
    final journal =
        await (db.select(db.journals)..where(
              (row) =>
                  row.id.equals(journalId) &
                  row.companyId.equals(currentCompanyId),
            ))
            .getSingleOrNull();
    if (journal == null) return;
    await (db.update(db.journals)..where(
          (t) => t.id.equals(journalId) & t.companyId.equals(currentCompanyId),
        ))
        .write(
          JournalsCompanion(
            status: const Value('voided'),
            revision: Value(journal.revision + 1),
            updatedAt: Value(now),
            syncStatus: const Value(SyncRecordStatus.pending),
          ),
        );
    await _queueJournal(journalId);
    final lines =
        await (db.select(db.journalLines)..where(
              (t) =>
                  t.journalId.equals(journalId) &
                  t.companyId.equals(currentCompanyId),
            ))
            .get();
    for (final accountId in lines.map((line) => line.accountId).toSet()) {
      await _recalculateAccountBalanceInTx(accountId);
    }
  }

  Future<void> updateEntry(LedgerEntry entry) async {
    await ensureInitialized();
    AccessControlService.verifyPermission(currentRole, UserAction.updateEntry);
    if (entry.amountInCents <= 0) {
      throw ArgumentError.value(entry.amountInCents);
    }

    await db.transaction(() async {
      await requireLedgerProfile();
      final original = await _findEntry(entry.id);
      if (original == null ||
          original.isDeleted ||
          original.partyId != entry.partyId) {
        throw StateError('Ledger entry unavailable for correction');
      }
      if (original.isVoided) return;
      if (entry.id.startsWith('vch_entry_') || entry.id.startsWith('open_')) {
        throw StateError('Correct this entry through its source document');
      }

      final now = DateTime.now();
      final financialChange =
          LedgerPaymentMethod.read(original.note) != LedgerPaymentMethod.read(entry.note) ||
          original.amountInCents != entry.amountInCents ||
          original.type != entry.type ||
          original.date.millisecondsSinceEpoch ~/ 1000 !=
              entry.date.millisecondsSinceEpoch ~/ 1000;
      if (financialChange) {
        await _voidEntryInTransaction(original, now);
        final replacement = entry.copyWith(
          id: entry.id.startsWith('entry_init_')
              ? 'entry_init_corrected_${entry.id}'
              : 'corrected_${entry.id}',
          isVoided: false,
        );
        final party = await getPartyById(original.partyId);
        await _insertEntryPosting(replacement, party, now);
        await recordAuditLog(
          entityType: 'ledger_entry',
          entityId: entry.id,
          action: AuditAction.update,
          oldState: original.toJson(),
          newState: (await _findEntry(replacement.id))!.toJson(),
        );
      } else {
        await (db.update(
          db.ledgerEntries,
        )..where((t) => t.id.equals(entry.id))).write(
          LedgerEntriesCompanion(
            note: Value(entry.note),
            receiptPhotoUrl: Value(entry.receiptPhotoUrl),
            revision: Value(original.revision + 1),
            updatedAt: Value(now),
            syncStatus: const Value(SyncRecordStatus.pending),
          ),
        );
        final updated = (await _findEntry(entry.id))!;
        await _queueEntry(updated);
        await recordAuditLog(
          entityType: 'ledger_entry',
          entityId: entry.id,
          action: AuditAction.update,
          oldState: original.toJson(),
          newState: updated.toJson(),
        );
      }
    });
    updateStreamController.add(null);
    triggerBackgroundSync();
  }

  Future<void> deleteEntry(String entryId) async {
    await ensureInitialized();
    AccessControlService.verifyPermission(currentRole, UserAction.voidEntry);
    await db.transaction(() async {
      await requireLedgerProfile();
      final original = await _findEntry(entryId);
      if (original == null || original.isDeleted || original.isVoided) return;
      if (entryId.startsWith('vch_entry_')) {
        await postingEngine.voidVoucher(
          voucherId: entryId.substring('vch_entry_'.length),
          companyId: currentCompanyId,
          userId: currentUserId,
        );
        return;
      }
      await _voidEntryInTransaction(original, DateTime.now());
      await _recalculatePartyBalanceInTx(original.partyId);
      await recordAuditLog(
        entityType: 'ledger_entry',
        entityId: entryId,
        action: AuditAction.voided,
        oldState: original.toJson(),
        newState: (await _findEntry(entryId))!.toJson(),
      );
    });
    updateStreamController.add(null);
    triggerBackgroundSync();
  }

  Future<(int totalReceivable, int totalPayable)> getBusinessSummary() async {
    await ensureInitialized();

    final parties =
        await (db.select(db.parties)..where(
              (t) =>
                  t.companyId.equals(currentCompanyId) &
                  t.isDeleted.equals(false),
            ))
            .get();
    int totalReceivable = 0;
    int totalPayable = 0;

    final balances = await readLedgerPartyBalances(db, currentCompanyId);
    for (final p in parties) {
      final balance = balances[p.id] ?? p.netBalanceInCents;
      if (balance > 0) {
        totalReceivable += balance;
      } else if (balance < 0) {
        totalPayable -= balance;
      }
    }

    return (totalReceivable, totalPayable);
  }

  Future<void> _recalculatePartyBalanceInTx(String partyId) async {
    final partyQuery = db.select(db.parties)
      ..where(
        (t) => t.id.equals(partyId) & t.companyId.equals(currentCompanyId),
      );
    final party = await partyQuery.getSingleOrNull();
    if (party == null) return;

    final entriesQuery = db.select(db.ledgerEntries)
      ..where(
        (t) => t.partyId.equals(partyId) & t.companyId.equals(currentCompanyId),
      );
    final entries = await entriesQuery.get();

    final newBalance = calculatePartyBalanceFromRows(entries);
    DateTime latestDate = party.lastUpdated;

    for (final entry in entries) {
      if (!entry.isDeleted && entry.date.isAfter(latestDate)) {
        latestDate = entry.date;
      }
    }

    await (db.update(db.parties)..where(
          (t) => t.id.equals(partyId) & t.companyId.equals(currentCompanyId),
        ))
        .write(
          PartiesCompanion(
            netBalanceInCents: Value(newBalance),
            lastUpdated: Value(latestDate),
            updatedAt: Value(DateTime.now()),
            syncStatus: const Value(SyncRecordStatus.pending),
          ),
        );

    final updatedPartyRow =
        await (db.select(db.parties)..where(
              (t) =>
                  t.id.equals(partyId) & t.companyId.equals(currentCompanyId),
            ))
            .getSingle();

    await recordOutboxEntry(
      targetTable: 'parties',
      recordId: partyId,
      mutationType: 'UPDATE',
      payload: {
        'id': updatedPartyRow.id,
        'companyId': currentCompanyId,
        'name': updatedPartyRow.name,
        'phoneNumber': updatedPartyRow.phoneNumber,
        'type': updatedPartyRow.type.name,
        'netBalanceInCents': updatedPartyRow.netBalanceInCents,
        'lastUpdated': encodeTime(updatedPartyRow.lastUpdated),
        'isDeleted': updatedPartyRow.isDeleted,
        'updatedAt': encodeTime(updatedPartyRow.updatedAt),
      },
    );
  }

  Future<void> _recalculateAccountBalanceInTx(String accountId) async {
    final account =
        await (db.select(db.accounts)..where(
              (t) =>
                  t.id.equals(accountId) & t.companyId.equals(currentCompanyId),
            ))
            .getSingleOrNull();
    if (account == null) return;

    final query =
        db.select(db.journalLines).join([
          innerJoin(
            db.journals,
            db.journals.id.equalsExp(db.journalLines.journalId),
          ),
        ])..where(
          db.journalLines.accountId.equals(accountId) &
              db.journalLines.companyId.equals(currentCompanyId) &
              db.journalLines.isDeleted.equals(false) &
              db.journals.status.equals('posted'),
        );

    final rows = await query.get();

    int totalDebit = 0;
    int totalCredit = 0;
    for (final row in rows) {
      final line = row.readTable(db.journalLines);
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

    await (db.update(db.accounts)..where(
          (t) => t.id.equals(accountId) & t.companyId.equals(currentCompanyId),
        ))
        .write(
          AccountsCompanion(
            currentBalanceInCents: Value(netBalance),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }
}
