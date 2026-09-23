import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/sync_engine.dart';
import '../../data/local/database.dart';
import '../../data/local/drift_ledger_repository.dart';
import '../../data/models/party_model.dart';
import '../../data/models/transaction_model.dart';
import '../../domain/repositories/i_ledger_repository.dart';
import 'profile_provider.dart';

// Singleton Drift AppDatabase provider
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() {
    db.close();
  });
  return db;
});

// Singleton SyncEngine provider
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final engine = SyncEngine(db: db);
  ref.onDispose(() {
    engine.dispose();
  });
  return engine;
});

// Single repository instance backed directly by local SQLite (Drift)
final ledgerRepositoryProvider = Provider<ILedgerRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final syncEngine = ref.watch(syncEngineProvider);
  final profile = ref.watch(userProfileProvider);
  final repo = DriftLedgerRepository(
    db: db,
    syncEngine: syncEngine,
    currentCompanyId: profile.activeCompanyId,
    currentUserId: profile.id,
    currentRole: profile.role,
  );
  ref.onDispose(() {
    repo.dispose();
  });
  return repo;
});

// Stream of updates triggered by any add/delete in the repository
final ledgerUpdatesStreamProvider = StreamProvider<void>((ref) {
  final repo = ref.watch(ledgerRepositoryProvider);
  return repo.repositoryUpdatesStream;
});

// Active party filter Notifier
class PartyTypeFilterNotifier extends Notifier<PartyType?> {
  @override
  PartyType? build() => PartyType.customer;

  void setFilter(PartyType? filter) {
    state = filter;
  }
}

final selectedPartyTypeFilterProvider =
    NotifierProvider<PartyTypeFilterNotifier, PartyType?>(
  PartyTypeFilterNotifier.new,
);

// Search query Notifier
class PartySearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }
}

final partySearchQueryProvider =
    NotifierProvider<PartySearchQueryNotifier, String>(
  PartySearchQueryNotifier.new,
);

// Search focus / active state Notifier to collapse dashboard metrics on search
class PartySearchActiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setActive(bool active) {
    state = active;
  }
}

final isPartySearchActiveProvider =
    NotifierProvider<PartySearchActiveNotifier, bool>(
  PartySearchActiveNotifier.new,
);

// Sorting options for party list
enum PartySortOption {
  mostRecent,
  highestReceivable,
  alphabetical;

  String get label {
    switch (this) {
      case PartySortOption.mostRecent:
        return 'Most Recent';
      case PartySortOption.highestReceivable:
        return 'Highest Receivable';
      case PartySortOption.alphabetical:
        return 'Alphabetical';
    }
  }
}

class PartySortOptionNotifier extends Notifier<PartySortOption> {
  @override
  PartySortOption build() => PartySortOption.mostRecent;

  void setSort(PartySortOption option) {
    state = option;
  }
}

final partySortOptionProvider =
    NotifierProvider<PartySortOptionNotifier, PartySortOption>(
  PartySortOptionNotifier.new,
);

// Parties list provider, auto-refreshes when repo emits update
final partyListProvider = FutureProvider<List<Party>>((ref) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  final sub = repo.repositoryUpdatesStream.listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);

  final filter = ref.watch(selectedPartyTypeFilterProvider);
  final query = ref.watch(partySearchQueryProvider).toLowerCase().trim();
  final sortOption = ref.watch(partySortOptionProvider);

  final rawParties = await repo.getParties(filter: filter);
  var filteredParties = rawParties;
  if (query.isNotEmpty) {
    final cleanDigits = query.replaceAll(RegExp(r'\D'), '');
    filteredParties = rawParties.where((p) {
      final nameMatches = p.name.toLowerCase().contains(query);
      final phoneDigits = p.phoneNumber.replaceAll(RegExp(r'\D'), '');
      final phoneMatches = p.phoneNumber.toLowerCase().contains(query) ||
          (cleanDigits.isNotEmpty && phoneDigits.contains(cleanDigits));
      return nameMatches || phoneMatches;
    }).toList();
  }

  final sortedParties = List<Party>.from(filteredParties);
  switch (sortOption) {
    case PartySortOption.alphabetical:
      sortedParties.sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      break;
    case PartySortOption.highestReceivable:
      sortedParties.sort((a, b) =>
          b.netBalanceInCents.compareTo(a.netBalanceInCents));
      break;
    case PartySortOption.mostRecent:
      sortedParties.sort((a, b) =>
          b.lastUpdated.compareTo(a.lastUpdated));
      break;
  }

  return sortedParties;
});

// Business summary (Total Receivable, Total Payable)
final businessSummaryProvider =
    FutureProvider<(int totalReceivable, int totalPayable)>((ref) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  final sub = repo.repositoryUpdatesStream.listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);

  return repo.getBusinessSummary();
});

// Live party details by ID
final partyDetailProvider =
    FutureProvider.family<Party, String>((ref, partyId) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  final sub = repo.repositoryUpdatesStream.listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);

  return repo.getPartyById(partyId);
});

// Ledger entries with running balance computed line-by-line chronologically
final partyLedgerEntriesProvider =
    FutureProvider.family<List<LedgerEntry>, String>((ref, partyId) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  final sub = repo.repositoryUpdatesStream.listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);

  final rawEntries = await repo.getEntriesForParty(partyId);

  // Sort ascending by date to compute cumulative running balance chronologically
  final sortedEntries = List<LedgerEntry>.from(rawEntries)
    ..sort((a, b) => a.date.compareTo(b.date));

  int runningBalance = 0;
  final entriesWithBalance = <LedgerEntry>[];
  for (final entry in sortedEntries) {
    if (entry.type == EntryType.gave) {
      runningBalance += entry.amountInCents;
    } else {
      runningBalance -= entry.amountInCents;
    }
    entriesWithBalance.add(
      entry.copyWith(runningBalanceInCents: runningBalance),
    );
  }

  // Return reverse chronological order (newest first) for ledger stream display
  return entriesWithBalance.reversed.toList();
});

// Standard Aliases for domain & presentation layer consistency
final partiesProvider = partyListProvider;
final partyByIdProvider = partyDetailProvider;
final ledgerEntriesProvider = partyLedgerEntriesProvider;

// Controller for mutations (add/update/delete party, add/update/delete entry)
class LedgerActionController {
  final Ref _ref;
  final ILedgerRepository _repo;

  LedgerActionController(this._ref, this._repo);

  void _invalidateProviders({String? partyId}) {
    _ref.invalidate(partiesProvider);
    _ref.invalidate(partyListProvider);
    _ref.invalidate(businessSummaryProvider);
    if (partyId != null) {
      _ref.invalidate(partyByIdProvider(partyId));
      _ref.invalidate(partyDetailProvider(partyId));
      _ref.invalidate(ledgerEntriesProvider(partyId));
      _ref.invalidate(partyLedgerEntriesProvider(partyId));
    }
  }

  Future<void> addParty({
    required String name,
    required String phoneNumber,
    required PartyType type,
    int initialBalanceInCents = 0,
  }) async {
    final partyId = 'party_${DateTime.now().millisecondsSinceEpoch}';
    final party = Party(
      id: partyId,
      name: name.trim(),
      phoneNumber: phoneNumber.trim(),
      type: type,
      netBalanceInCents: initialBalanceInCents,
      lastUpdated: DateTime.now(),
    );
    await _repo.addParty(party);

    // If there is an initial balance, add an opening ledger entry
    if (initialBalanceInCents != 0) {
      final entry = LedgerEntry(
        id: 'entry_init_${DateTime.now().millisecondsSinceEpoch}',
        partyId: partyId,
        amountInCents: initialBalanceInCents.abs(),
        type: initialBalanceInCents > 0 ? EntryType.gave : EntryType.got,
        date: DateTime.now(),
        note: 'Opening Balance',
      );
      await _repo.addEntry(entry);
    }

    _invalidateProviders(partyId: partyId);
  }

  Future<void> updateParty(Party party) async {
    await _repo.updateParty(party);
    _invalidateProviders(partyId: party.id);
  }

  Future<void> deleteParty(String partyId) async {
    await _repo.deleteParty(partyId);
    _invalidateProviders(partyId: partyId);
  }

  Future<void> addEntry({
    required String partyId,
    required int amountInCents,
    required EntryType type,
    required DateTime date,
    String? note,
    String? receiptPhotoUrl,
  }) async {
    final entry = LedgerEntry(
      id: 'entry_${DateTime.now().millisecondsSinceEpoch}',
      partyId: partyId,
      amountInCents: amountInCents,
      type: type,
      date: date,
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
      receiptPhotoUrl: receiptPhotoUrl,
    );
    await _repo.addEntry(entry);
    _invalidateProviders(partyId: partyId);
  }

  Future<void> updateEntry(LedgerEntry entry) async {
    await _repo.updateEntry(entry);
    _invalidateProviders(partyId: entry.partyId);
  }

  Future<void> deleteEntry(String entryId, [String? partyId]) async {
    await _repo.deleteEntry(entryId);
    _invalidateProviders(partyId: partyId);
  }
}

final ledgerActionControllerProvider = Provider<LedgerActionController>((ref) {
  final repo = ref.watch(ledgerRepositoryProvider);
  return LedgerActionController(ref, repo);
});
