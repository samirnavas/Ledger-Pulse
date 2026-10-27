import 'package:drift/drift.dart';
import '../../data/models/account_model.dart';
import '../../data/models/journal_model.dart';
import '../../data/models/sync_model.dart';
import '../../domain/exceptions/ledger_exceptions.dart';
import 'database.dart';
import 'drift_ledger_base.dart';

/// Mixin handling Accounts and Journals for DriftLedgerRepository.
mixin DriftAccountsJournalsMixin on DriftLedgerRepositoryBase {
  Future<List<AccountModel>> getAccounts({AccountType? type}) async {
    await ensureInitialized();
    await postingEngine.ensureCompanyAccounts(currentCompanyId);

    final query = db.select(db.accounts)
      ..where((t) => t.companyId.equals(currentCompanyId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.code)]);

    if (type != null) {
      query.where((t) => t.type.equals(type.name));
    }

    final rows = await query.get();
    return rows
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
  }

  Future<AccountModel> getAccountById(String id) async {
    await ensureInitialized();
    final r = await (db.select(db.accounts)
          ..where((t) => t.id.equals(id) & t.companyId.equals(currentCompanyId) & t.isDeleted.equals(false)))
        .getSingleOrNull();

    if (r == null) {
      throw AccountNotFoundException(id);
    }

    return AccountModel(
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
    );
  }

  Future<void> addAccount(AccountModel account) async {
    await ensureInitialized();
    final now = DateTime.now();
    await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            id: account.id,
            companyId: Value(currentCompanyId),
            code: account.code,
            name: account.name,
            type: account.type.name,
            parentAccountId: Value(account.parentAccountId),
            isSystem: Value(account.isSystem),
            isActive: Value(account.isActive),
            description: Value(account.description),
            currentBalanceInCents: Value(account.currentBalanceInCents),
            createdAt: Value(account.createdAt),
            updatedAt: Value(now),
            isDeleted: const Value(false),
            syncStatus: const Value(SyncRecordStatus.pending),
          ),
        );
    updateStreamController.add(null);
  }

  Future<List<JournalModel>> getJournals({DateTime? startDate, DateTime? endDate}) async {
    await ensureInitialized();
    final query = db.select(db.journals)
      ..where((t) => t.companyId.equals(currentCompanyId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.createdAt)]);

    if (startDate != null) {
      query.where((t) => t.date.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((t) => t.date.isSmallerOrEqualValue(endDate));
    }

    final journals = await query.get();
    final List<JournalModel> result = [];

    for (final j in journals) {
      final lines = await (db.select(db.journalLines)
            ..where((t) => t.journalId.equals(j.id) & t.isDeleted.equals(false)))
          .get();

      result.add(JournalModel(
        id: j.id,
        companyId: j.companyId,
        journalNumber: j.journalNumber,
        voucherId: j.voucherId,
        date: j.date,
        narration: j.narration,
        totalAmountInCents: j.totalAmountInCents,
        status: j.status,
        lines: lines
            .map((l) => JournalLineModel(
                  id: l.id,
                  companyId: l.companyId,
                  journalId: l.journalId,
                  accountId: l.accountId,
                  partyId: l.partyId,
                  debitInCents: l.debitInCents,
                  creditInCents: l.creditInCents,
                  narration: l.narration,
                  createdAt: l.createdAt,
                  updatedAt: l.updatedAt,
                ))
            .toList(),
        createdAt: j.createdAt,
        updatedAt: j.updatedAt,
      ));
    }

    return result;
  }

  Future<JournalModel> postJournalEntry(JournalModel journal) async {
    await ensureInitialized();
    final result = await postingEngine.postJournalEntry(
      journal: journal.copyWith(companyId: currentCompanyId),
      userId: currentUserId,
    );
    updateStreamController.add(null);
    triggerBackgroundSync();
    return result;
  }

  Future<JournalModel> postOpeningBalances({
    DateTime? date,
    int cashInCents = 0,
    int bankInCents = 0,
    int inventoryInCents = 0,
    Map<String, int> receivablesByParty = const {},
    Map<String, int> payablesByParty = const {},
    int? explicitCapitalInCents,
  }) async {
    await ensureInitialized();
    final result = await postingEngine.postOpeningBalances(
      companyId: currentCompanyId,
      userId: currentUserId,
      date: date,
      cashInCents: cashInCents,
      bankInCents: bankInCents,
      inventoryInCents: inventoryInCents,
      receivablesByParty: receivablesByParty,
      payablesByParty: payablesByParty,
      explicitCapitalInCents: explicitCapitalInCents,
    );
    updateStreamController.add(null);
    triggerBackgroundSync();
    return result;
  }
}
