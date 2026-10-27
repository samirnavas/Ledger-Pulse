import 'package:drift/drift.dart';
import '../../data/models/account_model.dart';
import '../../data/models/party_model.dart';
import '../../data/models/rbac_model.dart';
import '../../data/models/transaction_model.dart';
import '../models/audit_log_model.dart';
import '../security/access_control_service.dart';
import 'database.dart';
import 'drift_ledger_base.dart';

/// Mixin handling Ledger Entries and running balance recalculation for DriftLedgerRepository.
mixin DriftEntriesMixin on DriftLedgerRepositoryBase {
  Future<List<LedgerEntry>> getEntriesForParty(String partyId) async {
    await ensureInitialized();

    final query = db.select(db.ledgerEntries)
      ..where((t) => t.partyId.equals(partyId) & t.companyId.equals(currentCompanyId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.date),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);

    final rows = await query.get();

    int currentBalance = 0;
    final List<LedgerEntry> entriesWithRunningBalance = [];

    for (final row in rows) {
      if (!row.isVoided) {
        if (row.type == EntryType.gave) {
          currentBalance += row.amountInCents;
        } else {
          currentBalance -= row.amountInCents;
        }
      }

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

  Future<void> addEntry(LedgerEntry entry) async {
    await ensureInitialized();

    // Verify party existence and determine role permission
    final party = await getPartyById(entry.partyId);
    final action = party.type == PartyType.customer
        ? UserAction.createCustomerEntry
        : UserAction.createSupplierEntry;
    AccessControlService.verifyPermission(currentRole, action);

    final entryId = entry.id.trim().isEmpty ? uuid.v4() : entry.id;
    final effectiveEntry = entry.id == entryId ? entry : entry.copyWith(id: entryId);

    await db.transaction(() async {
      await db.into(db.ledgerEntries).insertOnConflictUpdate(
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
              createdAt: Value(effectiveEntry.date),
              updatedAt: Value(DateTime.now()),
              isDeleted: const Value(false),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );

      await recordOutboxEntry(
        targetTable: 'ledger_entries',
        recordId: effectiveEntry.id,
        mutationType: 'INSERT',
        payload: {
          ...effectiveEntry.toMap(),
          'companyId': currentCompanyId,
        },
      );

      await recordAuditLog(
        entityType: 'ledger_entry',
        entityId: effectiveEntry.id,
        action: AuditAction.insert,
        newState: effectiveEntry.toMap(),
      );

      await _recalculatePartyBalanceInTx(effectiveEntry.partyId);

      // Synchronize standalone ledger entry with double-entry journals & accounts
      if (!effectiveEntry.id.startsWith('vch_entry_') && !effectiveEntry.id.startsWith('open_')) {
        await postingEngine.ensureCompanyAccounts(currentCompanyId);
        final isCustomer = party.type == PartyType.customer;
        final arAccountId = '${currentCompanyId}_${DefaultAccounts.arId}';
        final apAccountId = '${currentCompanyId}_${DefaultAccounts.apId}';
        final cashAccountId = '${currentCompanyId}_${DefaultAccounts.cashId}';
        final salesAccountId = '${currentCompanyId}_${DefaultAccounts.salesId}';
        final purchasesAccountId = '${currentCompanyId}_${DefaultAccounts.purchasesCogsId}';

        String drAcc;
        String crAcc;
        String note;

        if (isCustomer) {
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
        final jnlNumber = 'JNL-ENT-${effectiveEntry.id.length > 8 ? effectiveEntry.id.substring(0, 8) : effectiveEntry.id}';
        final now = DateTime.now();

        await db.into(db.journals).insertOnConflictUpdate(
              JournalsCompanion.insert(
                id: jnlId,
                companyId: Value(currentCompanyId),
                journalNumber: jnlNumber,
                date: effectiveEntry.date,
                narration: Value(note),
                totalAmountInCents: Value(effectiveEntry.amountInCents),
                status: const Value('posted'),
                createdAt: Value(effectiveEntry.date),
                updatedAt: Value(now),
              ),
            );

        await db.into(db.journalLines).insert(
              JournalLinesCompanion.insert(
                id: '${jnlId}_dr',
                companyId: Value(currentCompanyId),
                journalId: jnlId,
                accountId: drAcc,
                partyId: Value(effectiveEntry.partyId),
                debitInCents: Value(effectiveEntry.amountInCents),
                creditInCents: const Value(0),
                narration: Value(note),
                createdAt: Value(effectiveEntry.date),
                updatedAt: Value(now),
              ),
            );

        await db.into(db.journalLines).insert(
              JournalLinesCompanion.insert(
                id: '${jnlId}_cr',
                companyId: Value(currentCompanyId),
                journalId: jnlId,
                accountId: crAcc,
                partyId: Value(effectiveEntry.partyId),
                debitInCents: const Value(0),
                creditInCents: Value(effectiveEntry.amountInCents),
                narration: Value(note),
                createdAt: Value(effectiveEntry.date),
                updatedAt: Value(now),
              ),
            );

        await _recalculateAccountBalanceInTx(drAcc);
        await _recalculateAccountBalanceInTx(crAcc);
      }
    });

    updateStreamController.add(null);
    triggerBackgroundSync();
  }

  Future<void> updateEntry(LedgerEntry entry) async {
    await ensureInitialized();
    AccessControlService.verifyPermission(currentRole, UserAction.updateEntry);

    final existing = await (db.select(db.ledgerEntries)
          ..where((t) => t.id.equals(entry.id) & t.companyId.equals(currentCompanyId)))
        .getSingleOrNull();

    if (existing == null) {
      throw Exception('Ledger entry not found with id: ${entry.id}');
    }

    final oldMap = {
      'id': existing.id,
      'partyId': existing.partyId,
      'amountInCents': existing.amountInCents,
      'type': existing.type.name,
      'date': existing.date.toIso8601String(),
      'note': existing.note,
      'isVoided': existing.isVoided,
    };

    await db.transaction(() async {
      final amountChanged = existing.amountInCents != entry.amountInCents;
      final typeChanged = existing.type != entry.type;

      if (amountChanged || typeChanged) {
        // Immutable adjustment:
        await (db.update(db.ledgerEntries)..where((t) => t.id.equals(existing.id) & t.companyId.equals(currentCompanyId))).write(
          LedgerEntriesCompanion(
            isVoided: const Value(true),
            updatedAt: Value(DateTime.now()),
            syncStatus: const Value(SyncRecordStatus.pending),
          ),
        );

        final offsettingType = existing.type == EntryType.gave
            ? EntryType.got
            : EntryType.gave;
        final timestamp = DateTime.now();
        final offsetEntryId = uuid.v4();
        final offsetNote = 'Reversal: Voided entry #${existing.id}';

        await db.into(db.ledgerEntries).insert(
          LedgerEntriesCompanion.insert(
            id: offsetEntryId,
            companyId: Value(currentCompanyId),
            partyId: existing.partyId,
            amountInCents: existing.amountInCents,
            type: offsettingType,
            date: timestamp,
            note: Value(offsetNote),
            isVoided: const Value(false),
            createdAt: Value(timestamp),
            updatedAt: Value(timestamp),
            isDeleted: const Value(false),
            syncStatus: const Value(SyncRecordStatus.pending),
          ),
        );

        final newEntryId = uuid.v4();
        final replacementEntry = entry.copyWith(id: newEntryId);

        await db.into(db.ledgerEntries).insert(
          LedgerEntriesCompanion.insert(
            id: replacementEntry.id,
            companyId: Value(currentCompanyId),
            partyId: replacementEntry.partyId,
            amountInCents: replacementEntry.amountInCents,
            type: replacementEntry.type,
            date: replacementEntry.date,
            note: Value(replacementEntry.note),
            receiptPhotoUrl: Value(replacementEntry.receiptPhotoUrl),
            isVoided: const Value(false),
            createdAt: Value(timestamp),
            updatedAt: Value(timestamp),
            isDeleted: const Value(false),
            syncStatus: const Value(SyncRecordStatus.pending),
          ),
        );

        await recordOutboxEntry(
          targetTable: 'ledger_entries',
          recordId: existing.id,
          mutationType: 'UPDATE',
          payload: {'id': existing.id, 'isVoided': true, 'companyId': currentCompanyId},
        );

        await recordOutboxEntry(
          targetTable: 'ledger_entries',
          recordId: offsetEntryId,
          mutationType: 'INSERT',
          payload: {
            'id': offsetEntryId,
            'companyId': currentCompanyId,
            'partyId': existing.partyId,
            'amountInCents': existing.amountInCents,
            'type': offsettingType.name,
            'date': timestamp.toIso8601String(),
            'note': offsetNote,
          },
        );

        await recordOutboxEntry(
          targetTable: 'ledger_entries',
          recordId: replacementEntry.id,
          mutationType: 'INSERT',
          payload: {
            ...replacementEntry.toMap(),
            'companyId': currentCompanyId,
          },
        );

        await recordAuditLog(
          entityType: 'ledger_entry',
          entityId: entry.id,
          action: AuditAction.update,
          oldState: oldMap,
          newState: replacementEntry.toMap(),
        );

        await _recalculatePartyBalanceInTx(entry.partyId);
      } else {
        await (db.update(db.ledgerEntries)..where((t) => t.id.equals(entry.id) & t.companyId.equals(currentCompanyId))).write(
          LedgerEntriesCompanion(
            date: Value(entry.date),
            note: Value(entry.note),
            receiptPhotoUrl: Value(entry.receiptPhotoUrl),
            updatedAt: Value(DateTime.now()),
            syncStatus: const Value(SyncRecordStatus.pending),
          ),
        );

        await recordOutboxEntry(
          targetTable: 'ledger_entries',
          recordId: entry.id,
          mutationType: 'UPDATE',
          payload: {
            ...entry.toMap(),
            'companyId': currentCompanyId,
          },
        );

        await recordAuditLog(
          entityType: 'ledger_entry',
          entityId: entry.id,
          action: AuditAction.update,
          oldState: oldMap,
          newState: entry.toMap(),
        );

        await _recalculatePartyBalanceInTx(entry.partyId);
      }
    });

    updateStreamController.add(null);
    triggerBackgroundSync();
  }

  Future<void> deleteEntry(String entryId) async {
    await ensureInitialized();
    AccessControlService.verifyPermission(currentRole, UserAction.voidEntry);

    final originalQuery = db.select(db.ledgerEntries)
      ..where((t) => t.id.equals(entryId) & t.companyId.equals(currentCompanyId));
    final original = await originalQuery.getSingleOrNull();

    if (original == null || original.isVoided) {
      return;
    }

    final offsettingType = original.type == EntryType.gave
        ? EntryType.got
        : EntryType.gave;
    final timestamp = DateTime.now();
    final offsetEntryId = uuid.v4();
    final offsetNote = 'Offset: Voided entry #${original.id}'
        '${original.note != null && original.note!.isNotEmpty ? ' (${original.note})' : ''}';

    final offsetEntry = LedgerEntry(
      id: offsetEntryId,
      partyId: original.partyId,
      amountInCents: original.amountInCents,
      type: offsettingType,
      date: timestamp,
      note: offsetNote,
    );

    final oldMap = {
      'id': original.id,
      'partyId': original.partyId,
      'amountInCents': original.amountInCents,
      'type': original.type.name,
      'isVoided': false,
    };

    await db.transaction(() async {
      await (db.update(db.ledgerEntries)..where((t) => t.id.equals(entryId) & t.companyId.equals(currentCompanyId)))
          .write(
        LedgerEntriesCompanion(
          isVoided: const Value(true),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      await db.into(db.ledgerEntries).insert(
            LedgerEntriesCompanion.insert(
              id: offsetEntry.id,
              companyId: Value(currentCompanyId),
              partyId: offsetEntry.partyId,
              amountInCents: offsetEntry.amountInCents,
              type: offsetEntry.type,
              date: offsetEntry.date,
              note: Value(offsetEntry.note),
              receiptPhotoUrl: Value(offsetEntry.receiptPhotoUrl),
              isVoided: const Value(false),
              createdAt: Value(offsetEntry.date),
              updatedAt: Value(DateTime.now()),
              isDeleted: const Value(false),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );

      await recordOutboxEntry(
        targetTable: 'ledger_entries',
        recordId: original.id,
        mutationType: 'UPDATE',
        payload: {'id': original.id, 'isVoided': true, 'companyId': currentCompanyId},
      );

      await recordOutboxEntry(
        targetTable: 'ledger_entries',
        recordId: offsetEntry.id,
        mutationType: 'INSERT',
        payload: {
          ...offsetEntry.toMap(),
          'companyId': currentCompanyId,
        },
      );

      await recordAuditLog(
        entityType: 'ledger_entry',
        entityId: original.id,
        action: AuditAction.voided,
        oldState: oldMap,
        newState: {'id': original.id, 'isVoided': true, 'offsetEntryId': offsetEntry.id},
      );

      await _recalculatePartyBalanceInTx(original.partyId);
    });

    updateStreamController.add(null);
    triggerBackgroundSync();
  }

  Future<(int totalReceivable, int totalPayable)> getBusinessSummary() async {
    await ensureInitialized();

    final parties = await (db.select(db.parties)
          ..where((t) => t.companyId.equals(currentCompanyId) & t.isDeleted.equals(false)))
        .get();
    int totalReceivable = 0;
    int totalPayable = 0;

    for (final p in parties) {
      if (p.netBalanceInCents > 0) {
        totalReceivable += p.netBalanceInCents;
      } else if (p.netBalanceInCents < 0) {
        totalPayable += p.netBalanceInCents.abs();
      }
    }

    return (totalReceivable, totalPayable);
  }

  Future<void> _recalculatePartyBalanceInTx(String partyId) async {
    final partyQuery = db.select(db.parties)
      ..where((t) => t.id.equals(partyId) & t.companyId.equals(currentCompanyId));
    final party = await partyQuery.getSingleOrNull();
    if (party == null) return;

    final entriesQuery = db.select(db.ledgerEntries)
      ..where((t) => t.partyId.equals(partyId) & t.companyId.equals(currentCompanyId));
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

    await (db.update(db.parties)..where((t) => t.id.equals(partyId) & t.companyId.equals(currentCompanyId))).write(
      PartiesCompanion(
        netBalanceInCents: Value(newBalance),
        lastUpdated: Value(latestDate),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );

    await recordOutboxEntry(
      targetTable: 'parties',
      recordId: partyId,
      mutationType: 'UPDATE',
      payload: {
        'id': partyId,
        'name': party.name,
        'phoneNumber': party.phoneNumber,
        'type': party.type.name,
        'companyId': currentCompanyId,
        'netBalanceInCents': newBalance,
        'lastUpdated': latestDate.toIso8601String(),
      },
    );
  }

  Future<void> _recalculateAccountBalanceInTx(String accountId) async {
    final account = await (db.select(db.accounts)
          ..where((t) => t.id.equals(accountId) & t.companyId.equals(currentCompanyId)))
        .getSingleOrNull();
    if (account == null) return;

    final query = db.select(db.journalLines).join([
      innerJoin(db.journals, db.journals.id.equalsExp(db.journalLines.journalId)),
    ])
      ..where(db.journalLines.accountId.equals(accountId) &
          db.journalLines.companyId.equals(currentCompanyId) &
          db.journalLines.isDeleted.equals(false) &
          db.journals.status.equals('posted'));

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

    await (db.update(db.accounts)..where((t) => t.id.equals(accountId) & t.companyId.equals(currentCompanyId))).write(
      AccountsCompanion(
        currentBalanceInCents: Value(netBalance),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
