import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/local_asset_ledger_repository.dart';
import '../../data/models/party_model.dart';
import '../../data/models/transaction_model.dart';
import '../../domain/repositories/i_ledger_repository.dart';

// Single repository instance backed directly by in-app bundled assets & local state
final ledgerRepositoryProvider = Provider<ILedgerRepository>((ref) {
  final repo = LocalAssetLedgerRepository();
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

// Parties list provider, auto-refreshes when repo emits update
final partyListProvider = FutureProvider<List<Party>>((ref) async {
  ref.watch(ledgerUpdatesStreamProvider);
  final repo = ref.watch(ledgerRepositoryProvider);
  final filter = ref.watch(selectedPartyTypeFilterProvider);
  final query = ref.watch(partySearchQueryProvider).toLowerCase().trim();

  final parties = await repo.getParties(filter: filter);
  if (query.isEmpty) {
    return parties;
  }
  return parties.where((p) {
    return p.name.toLowerCase().contains(query) ||
        p.phoneNumber.replaceAll(RegExp(r'\D'), '').contains(query);
  }).toList();
});

// Business summary (Total Receivable, Total Payable)
final businessSummaryProvider =
    FutureProvider<(int totalReceivable, int totalPayable)>((ref) async {
  ref.watch(ledgerUpdatesStreamProvider);
  final repo = ref.watch(ledgerRepositoryProvider);
  return repo.getBusinessSummary();
});

// Live party details by ID
final partyDetailProvider =
    FutureProvider.family<Party, String>((ref, partyId) async {
  ref.watch(ledgerUpdatesStreamProvider);
  final repo = ref.watch(ledgerRepositoryProvider);
  return repo.getPartyById(partyId);
});

// Ledger entries with running balance for a specific party
final partyLedgerEntriesProvider =
    FutureProvider.family<List<LedgerEntry>, String>((ref, partyId) async {
  ref.watch(ledgerUpdatesStreamProvider);
  final repo = ref.watch(ledgerRepositoryProvider);
  return repo.getEntriesForParty(partyId);
});

// Controller for mutations (add party, add entry, delete entry)
class LedgerActionController {
  final ILedgerRepository _repo;

  LedgerActionController(this._repo);

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
  }

  Future<void> deleteEntry(String entryId) async {
    await _repo.deleteEntry(entryId);
  }
}

final ledgerActionControllerProvider = Provider<LedgerActionController>((ref) {
  final repo = ref.watch(ledgerRepositoryProvider);
  return LedgerActionController(repo);
});
