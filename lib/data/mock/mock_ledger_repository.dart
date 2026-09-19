import 'dart:async';
import '../../domain/exceptions/ledger_exceptions.dart';
import '../../domain/repositories/i_ledger_repository.dart';
import '../models/party_model.dart';
import '../models/transaction_model.dart';
import 'mock_seed_data.dart';

class MockLedgerRepository implements ILedgerRepository {
  final List<Party> _parties = [];
  final List<LedgerEntry> _entries = [];
  final StreamController<void> _updateStreamController = StreamController<void>.broadcast();

  MockLedgerRepository() {
    _initData();
  }

  void _initData() {
    _parties.addAll(MockSeedData.initialParties);
    _entries.addAll(MockSeedData.initialEntries);
  }

  @override
  Stream<void> get repositoryUpdatesStream => _updateStreamController.stream;

  @override
  Future<List<Party>> getParties({PartyType? filter}) async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (filter == null) {
      return List.unmodifiable(_parties);
    }
    return List.unmodifiable(_parties.where((p) => p.type == filter).toList());
  }

  @override
  Future<Party> getPartyById(String partyId) async {
    await Future.delayed(const Duration(milliseconds: 50));
    final party = _parties.firstWhere(
      (p) => p.id == partyId,
      orElse: () => throw Exception('Party not found with id: $partyId'),
    );
    return party;
  }

  @override
  Future<void> addParty(Party party) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _parties.insert(0, party);
    _updateStreamController.add(null);
  }

  @override
  Future<void> updateParty(Party party) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final index = _parties.indexWhere((p) => p.id == party.id);
    if (index == -1) {
      throw Exception('Party not found with id: ${party.id}');
    }
    _parties[index] = _parties[index].copyWith(
      name: party.name,
      phoneNumber: party.phoneNumber,
      type: party.type,
      lastUpdated: DateTime.now(),
    );
    _updateStreamController.add(null);
  }

  @override
  Future<void> deleteParty(String partyId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final index = _parties.indexWhere((p) => p.id == partyId);
    if (index == -1) return;

    if (_parties[index].netBalanceInCents != 0) {
      throw const ActiveBalanceException('Cannot delete a party with an active balance.');
    }

    _parties.removeAt(index);
    _entries.removeWhere((e) => e.partyId == partyId);
    _updateStreamController.add(null);
  }


  @override
  Future<List<LedgerEntry>> getEntriesForParty(String partyId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    // Filter entries for this party
    final partyEntries = _entries.where((e) => e.partyId == partyId).toList();

    // Sort chronologically ascending to calculate running balances
    partyEntries.sort((a, b) => a.date.compareTo(b.date));

    int currentBalance = 0;
    final List<LedgerEntry> entriesWithRunningBalance = [];

    for (final entry in partyEntries) {
      if (entry.type == EntryType.gave) {
        currentBalance += entry.amountInCents;
      } else {
        currentBalance -= entry.amountInCents;
      }
      entriesWithRunningBalance.add(
        entry.copyWith(runningBalanceInCents: currentBalance),
      );
    }

    // Return sorted newest first for timeline presentation
    entriesWithRunningBalance.sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(entriesWithRunningBalance);
  }

  @override
  Future<void> addEntry(LedgerEntry entry) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _entries.add(entry);

    // Recalculate party net balance
    _recalculatePartyBalance(entry.partyId);

    _updateStreamController.add(null);
  }

  @override
  Future<void> updateEntry(LedgerEntry entry) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index == -1) {
      throw Exception('Ledger entry not found with id: ${entry.id}');
    }

    _entries[index] = entry;
    _recalculatePartyBalance(entry.partyId);
    _updateStreamController.add(null);
  }

  @override
  Future<void> deleteEntry(String entryId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _entries.indexWhere((e) => e.id == entryId);
    if (index != -1) {
      final partyId = _entries[index].partyId;
      _entries.removeAt(index);
      _recalculatePartyBalance(partyId);
      _updateStreamController.add(null);
    }
  }

  @override
  Future<(int totalReceivable, int totalPayable)> getBusinessSummary() async {
    await Future.delayed(const Duration(milliseconds: 100));
    int totalReceivable = 0;
    int totalPayable = 0;

    for (final party in _parties) {
      if (party.netBalanceInCents > 0) {
        totalReceivable += party.netBalanceInCents;
      } else if (party.netBalanceInCents < 0) {
        totalPayable += party.netBalanceInCents.abs();
      }
    }

    return (totalReceivable, totalPayable);
  }

  void _recalculatePartyBalance(String partyId) {
    final partyIndex = _parties.indexWhere((p) => p.id == partyId);
    if (partyIndex == -1) return;

    final partyEntries = _entries.where((e) => e.partyId == partyId);
    int newBalance = 0;
    DateTime latestDate = _parties[partyIndex].lastUpdated;

    for (final entry in partyEntries) {
      if (entry.type == EntryType.gave) {
        newBalance += entry.amountInCents;
      } else {
        newBalance -= entry.amountInCents;
      }
      if (entry.date.isAfter(latestDate)) {
        latestDate = entry.date;
      }
    }

    _parties[partyIndex] = _parties[partyIndex].copyWith(
      netBalanceInCents: newBalance,
      lastUpdated: latestDate,
    );
  }

  void dispose() {
    _updateStreamController.close();
  }
}
