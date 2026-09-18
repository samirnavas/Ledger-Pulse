import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../domain/repositories/i_ledger_repository.dart';
import '../mock/mock_seed_data.dart';
import '../models/party_model.dart';
import '../models/transaction_model.dart';

/// Fully self-contained local in-app repository.
/// Loads initial data from bundled `assets/data/data.json` without requiring
/// any external server, terminal command, or computer connection.
class LocalAssetLedgerRepository implements ILedgerRepository {
  final List<Party> _parties = [];
  final List<LedgerEntry> _entries = [];
  final StreamController<void> _updateStreamController =
      StreamController<void>.broadcast();

  Future<void>? _initFuture;
  final String _assetPath;

  LocalAssetLedgerRepository({String assetPath = 'assets/data/data.json'})
      : _assetPath = assetPath;

  Future<void> _ensureInitialized() {
    _initFuture ??= _loadInitialData();
    return _initFuture!;
  }

  Future<void> _loadInitialData() async {
    try {
      final jsonString = await rootBundle.loadString(_assetPath);
      final Map<String, dynamic> data = jsonDecode(jsonString);

      if (data['parties'] is List) {
        final List<dynamic> partiesList = data['parties'];
        _parties.clear();
        for (final p in partiesList) {
          _parties.add(Party.fromMap(p as Map<String, dynamic>));
        }
      }

      if (data['entries'] is List) {
        final List<dynamic> entriesList = data['entries'];
        _entries.clear();
        for (final e in entriesList) {
          _entries.add(LedgerEntry.fromMap(e as Map<String, dynamic>));
        }
      }
    } catch (e) {
      debugPrint('LocalAssetLedgerRepository: fallback to mock seed data ($e)');
      _parties.clear();
      _entries.clear();
      _parties.addAll(MockSeedData.initialParties);
      _entries.addAll(MockSeedData.initialEntries);
    }
  }

  @override
  Stream<void> get repositoryUpdatesStream => _updateStreamController.stream;

  @override
  Future<List<Party>> getParties({PartyType? filter}) async {
    await _ensureInitialized();
    if (filter == null) {
      return List.unmodifiable(_parties);
    }
    return List.unmodifiable(_parties.where((p) => p.type == filter).toList());
  }

  @override
  Future<Party> getPartyById(String partyId) async {
    await _ensureInitialized();
    final party = _parties.firstWhere(
      (p) => p.id == partyId,
      orElse: () => throw Exception('Party not found with id: $partyId'),
    );
    return party;
  }

  @override
  Future<void> addParty(Party party) async {
    await _ensureInitialized();
    final existingIndex = _parties.indexWhere((p) => p.id == party.id);
    if (existingIndex >= 0) {
      _parties[existingIndex] = party;
    } else {
      _parties.insert(0, party);
    }
    _updateStreamController.add(null);
  }

  @override
  Future<List<LedgerEntry>> getEntriesForParty(String partyId) async {
    await _ensureInitialized();
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

    // Return newest first for timeline presentation
    entriesWithRunningBalance.sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(entriesWithRunningBalance);
  }

  @override
  Future<void> addEntry(LedgerEntry entry) async {
    await _ensureInitialized();
    _entries.add(entry);
    _recalculatePartyBalance(entry.partyId);
    _updateStreamController.add(null);
  }

  @override
  Future<void> deleteEntry(String entryId) async {
    await _ensureInitialized();
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
    await _ensureInitialized();
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
