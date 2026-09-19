import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../domain/exceptions/ledger_exceptions.dart';
import '../../domain/repositories/i_ledger_repository.dart';
import '../mock/mock_seed_data.dart';
import '../models/party_model.dart';
import '../models/transaction_model.dart';
import 'database.dart';

class DriftLedgerRepository implements ILedgerRepository {
  final AppDatabase _db;
  final String _assetPath;
  final StreamController<void> _updateStreamController =
      StreamController<void>.broadcast();

  Future<void>? _initFuture;

  DriftLedgerRepository({
    AppDatabase? db,
    String assetPath = 'assets/data/data.json',
  })  : _db = db ?? AppDatabase(),
        _assetPath = assetPath;

  AppDatabase get db => _db;

  Future<void> _ensureInitialized() {
    _initFuture ??= _seedIfEmpty();
    return _initFuture!;
  }

  Future<void> _seedIfEmpty() async {
    try {
      final existingCount = await _db.select(_db.parties).get();
      if (existingCount.isNotEmpty) {
        return;
      }

      // Database is empty; seed from asset or mock data
      List<Party> initialParties = [];
      List<LedgerEntry> initialEntries = [];

      try {
        final jsonString = await rootBundle.loadString(_assetPath);
        final Map<String, dynamic> data = jsonDecode(jsonString);

        if (data['parties'] is List) {
          for (final p in data['parties']) {
            initialParties.add(Party.fromMap(p as Map<String, dynamic>));
          }
        }
        if (data['entries'] is List) {
          for (final e in data['entries']) {
            initialEntries.add(LedgerEntry.fromMap(e as Map<String, dynamic>));
          }
        }
      } catch (e) {
        debugPrint('DriftLedgerRepository: fallback to mock seed data ($e)');
        initialParties = MockSeedData.initialParties;
        initialEntries = MockSeedData.initialEntries;
      }

      await _db.transaction(() async {
        for (final party in initialParties) {
          await _db.into(_db.parties).insertOnConflictUpdate(
                PartiesCompanion.insert(
                  id: party.id,
                  name: party.name,
                  phoneNumber: party.phoneNumber,
                  type: party.type,
                  netBalanceInCents: Value(party.netBalanceInCents),
                  lastUpdated: party.lastUpdated,
                ),
              );
        }

        for (final entry in initialEntries) {
          await _db.into(_db.ledgerEntries).insertOnConflictUpdate(
                LedgerEntriesCompanion.insert(
                  id: entry.id,
                  partyId: entry.partyId,
                  amountInCents: entry.amountInCents,
                  type: entry.type,
                  date: entry.date,
                  note: Value(entry.note),
                  receiptPhotoUrl: Value(entry.receiptPhotoUrl),
                  isVoided: const Value(false),
                  createdAt: Value(entry.date),
                ),
              );
        }
      });
    } catch (e) {
      debugPrint('DriftLedgerRepository: error during initial seeding ($e)');
    }
  }

  @override
  Stream<void> get repositoryUpdatesStream => _updateStreamController.stream;

  @override
  Future<List<Party>> getParties({PartyType? filter}) async {
    await _ensureInitialized();

    final query = _db.select(_db.parties)
      ..where((t) => t.isDeleted.equals(false))
      ..orderBy([
        (t) => OrderingTerm.desc(t.lastUpdated),
      ]);

    if (filter != null) {
      query.where((t) => t.isDeleted.equals(false) & t.type.equals(filter.name));
    }

    final rows = await query.get();
    return rows
        .map(
          (row) => Party(
            id: row.id,
            name: row.name,
            phoneNumber: row.phoneNumber,
            type: row.type,
            netBalanceInCents: row.netBalanceInCents,
            lastUpdated: row.lastUpdated,
          ),
        )
        .toList();
  }

  @override
  Future<Party> getPartyById(String partyId) async {
    await _ensureInitialized();

    final query = _db.select(_db.parties)
      ..where((t) => t.id.equals(partyId) & t.isDeleted.equals(false));
    final row = await query.getSingleOrNull();

    if (row == null) {
      throw Exception('Party not found with id: $partyId');
    }

    return Party(
      id: row.id,
      name: row.name,
      phoneNumber: row.phoneNumber,
      type: row.type,
      netBalanceInCents: row.netBalanceInCents,
      lastUpdated: row.lastUpdated,
    );
  }

  @override
  Future<void> addParty(Party party) async {
    await _ensureInitialized();

    await _db.transaction(() async {
      await _db.into(_db.parties).insertOnConflictUpdate(
            PartiesCompanion.insert(
              id: party.id,
              name: party.name,
              phoneNumber: party.phoneNumber,
              type: party.type,
              netBalanceInCents: Value(party.netBalanceInCents),
              lastUpdated: party.lastUpdated,
              isDeleted: const Value(false),
            ),
          );

      await _db.into(_db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              entityType: 'party',
              entityId: party.id,
              action: 'upsert',
              payload: jsonEncode(party.toMap()),
            ),
          );
    });

    _updateStreamController.add(null);
  }

  @override
  Future<void> updateParty(Party party) async {
    await _ensureInitialized();

    final existing = await (_db.select(_db.parties)
          ..where((t) => t.id.equals(party.id) & t.isDeleted.equals(false)))
        .getSingleOrNull();

    if (existing == null) {
      throw Exception('Party not found with id: ${party.id}');
    }

    await _db.transaction(() async {
      await (_db.update(_db.parties)..where((t) => t.id.equals(party.id))).write(
        PartiesCompanion(
          name: Value(party.name),
          phoneNumber: Value(party.phoneNumber),
          type: Value(party.type),
          lastUpdated: Value(DateTime.now()),
        ),
      );

      await _db.into(_db.syncOutbox).insert(
        SyncOutboxCompanion.insert(
          entityType: 'party',
          entityId: party.id,
          action: 'update',
          payload: jsonEncode(party.toMap()),
        ),
      );
    });

    _updateStreamController.add(null);
  }

  @override
  Future<void> deleteParty(String partyId) async {
    await _ensureInitialized();

    final party = await (_db.select(_db.parties)
          ..where((t) => t.id.equals(partyId) & t.isDeleted.equals(false)))
        .getSingleOrNull();

    if (party == null) {
      return;
    }

    if (party.netBalanceInCents != 0) {
      throw const ActiveBalanceException(
        'Cannot delete a party with an active balance.',
      );
    }

    await _db.transaction(() async {
      // Soft-delete party to maintain referential integrity
      await (_db.update(_db.parties)..where((t) => t.id.equals(partyId))).write(
        const PartiesCompanion(
          isDeleted: Value(true),
        ),
      );

      // Void/archive associated entries
      await (_db.update(_db.ledgerEntries)..where((t) => t.partyId.equals(partyId))).write(
        const LedgerEntriesCompanion(
          isVoided: Value(true),
        ),
      );

      await _db.into(_db.syncOutbox).insert(
        SyncOutboxCompanion.insert(
          entityType: 'party',
          entityId: partyId,
          action: 'delete',
          payload: jsonEncode({'id': partyId, 'isDeleted': true}),
        ),
      );
    });

    _updateStreamController.add(null);
  }

  @override
  Future<List<LedgerEntry>> getEntriesForParty(String partyId) async {
    await _ensureInitialized();

    // Query chronologically ascending to calculate running balances
    final query = _db.select(_db.ledgerEntries)
      ..where((t) => t.partyId.equals(partyId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.date),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);

    final rows = await query.get();

    int currentBalance = 0;
    final List<LedgerEntry> entriesWithRunningBalance = [];

    for (final row in rows) {
      if (row.type == EntryType.gave) {
        currentBalance += row.amountInCents;
      } else {
        currentBalance -= row.amountInCents;
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

    // Return newest first for timeline presentation
    entriesWithRunningBalance.sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(entriesWithRunningBalance);
  }

  @override
  Future<void> addEntry(LedgerEntry entry) async {
    await _ensureInitialized();

    await _db.transaction(() async {
      await _db.into(_db.ledgerEntries).insertOnConflictUpdate(
            LedgerEntriesCompanion.insert(
              id: entry.id,
              partyId: entry.partyId,
              amountInCents: entry.amountInCents,
              type: entry.type,
              date: entry.date,
              note: Value(entry.note),
              receiptPhotoUrl: Value(entry.receiptPhotoUrl),
              isVoided: const Value(false),
              createdAt: Value(entry.date),
            ),
          );

      await _db.into(_db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              entityType: 'ledger_entry',
              entityId: entry.id,
              action: 'insert',
              payload: jsonEncode(entry.toMap()),
            ),
          );

      await _recalculatePartyBalanceInTx(entry.partyId);
    });

    _updateStreamController.add(null);
  }

  @override
  Future<void> updateEntry(LedgerEntry entry) async {
    await _ensureInitialized();

    final existing = await (_db.select(_db.ledgerEntries)
          ..where((t) => t.id.equals(entry.id)))
        .getSingleOrNull();

    if (existing == null) {
      throw Exception('Ledger entry not found with id: ${entry.id}');
    }

    await _db.transaction(() async {
      final amountChanged = existing.amountInCents != entry.amountInCents;
      final typeChanged = existing.type != entry.type;

      if (amountChanged || typeChanged) {
        // Immutable adjustment:
        // 1. Mark existing entry as isVoided = true
        await (_db.update(_db.ledgerEntries)..where((t) => t.id.equals(existing.id))).write(
          const LedgerEntriesCompanion(
            isVoided: Value(true),
          ),
        );

        // 2. Insert reversing offset entry
        final offsettingType = existing.type == EntryType.gave
            ? EntryType.got
            : EntryType.gave;
        final timestamp = DateTime.now();
        final offsetEntryId = 'entry_offset_${timestamp.millisecondsSinceEpoch}';
        final offsetNote = 'Reversal: Voided entry #${existing.id}';

        await _db.into(_db.ledgerEntries).insert(
          LedgerEntriesCompanion.insert(
            id: offsetEntryId,
            partyId: existing.partyId,
            amountInCents: existing.amountInCents,
            type: offsettingType,
            date: timestamp,
            note: Value(offsetNote),
            isVoided: const Value(false),
            createdAt: Value(timestamp),
          ),
        );

        // 3. Insert updated entry
        final newEntryId = 'entry_rev_${timestamp.millisecondsSinceEpoch + 1}';
        final replacementEntry = entry.copyWith(id: newEntryId);

        await _db.into(_db.ledgerEntries).insert(
          LedgerEntriesCompanion.insert(
            id: replacementEntry.id,
            partyId: replacementEntry.partyId,
            amountInCents: replacementEntry.amountInCents,
            type: replacementEntry.type,
            date: replacementEntry.date,
            note: Value(replacementEntry.note),
            receiptPhotoUrl: Value(replacementEntry.receiptPhotoUrl),
            isVoided: const Value(false),
            createdAt: Value(timestamp),
          ),
        );

        // 4. Record sync outbox items
        await _db.into(_db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            entityType: 'ledger_entry',
            entityId: existing.id,
            action: 'void',
            payload: jsonEncode({'id': existing.id, 'isVoided': true}),
          ),
        );

        await _db.into(_db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            entityType: 'ledger_entry',
            entityId: offsetEntryId,
            action: 'insert',
            payload: jsonEncode({
              'id': offsetEntryId,
              'partyId': existing.partyId,
              'amountInCents': existing.amountInCents,
              'type': offsettingType.name,
              'date': timestamp.toIso8601String(),
              'note': offsetNote,
            }),
          ),
        );

        await _db.into(_db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            entityType: 'ledger_entry',
            entityId: replacementEntry.id,
            action: 'insert',
            payload: jsonEncode(replacementEntry.toMap()),
          ),
        );

        // 5. Recalculate party balance atomically
        await _recalculatePartyBalanceInTx(entry.partyId);
      } else {
        // In-place non-financial field update (note, date, receiptPhotoUrl)
        await (_db.update(_db.ledgerEntries)..where((t) => t.id.equals(entry.id))).write(
          LedgerEntriesCompanion(
            date: Value(entry.date),
            note: Value(entry.note),
            receiptPhotoUrl: Value(entry.receiptPhotoUrl),
          ),
        );

        await _db.into(_db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            entityType: 'ledger_entry',
            entityId: entry.id,
            action: 'update',
            payload: jsonEncode(entry.toMap()),
          ),
        );

        await _recalculatePartyBalanceInTx(entry.partyId);
      }
    });

    _updateStreamController.add(null);
  }

  @override
  Future<void> deleteEntry(String entryId) async {
    await _ensureInitialized();

    final originalQuery = _db.select(_db.ledgerEntries)
      ..where((t) => t.id.equals(entryId));
    final original = await originalQuery.getSingleOrNull();

    if (original == null || original.isVoided) {
      // Entry already voided or does not exist
      return;
    }

    // Double-Entry Safeguard:
    // 1. Mark the original entry as isVoided = true
    // 2. Insert an offsetting entry (gave -> got, got -> gave)
    final offsettingType = original.type == EntryType.gave
        ? EntryType.got
        : EntryType.gave;
    final timestamp = DateTime.now();
    final offsetEntryId = 'entry_offset_${timestamp.millisecondsSinceEpoch}';
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

    await _db.transaction(() async {
      // 1. Mark original entry as voided
      await (_db.update(_db.ledgerEntries)..where((t) => t.id.equals(entryId)))
          .write(
        const LedgerEntriesCompanion(
          isVoided: Value(true),
        ),
      );

      // 2. Insert offsetting entry
      await _db.into(_db.ledgerEntries).insert(
            LedgerEntriesCompanion.insert(
              id: offsetEntry.id,
              partyId: offsetEntry.partyId,
              amountInCents: offsetEntry.amountInCents,
              type: offsetEntry.type,
              date: offsetEntry.date,
              note: Value(offsetEntry.note),
              receiptPhotoUrl: Value(offsetEntry.receiptPhotoUrl),
              isVoided: const Value(false),
              createdAt: Value(offsetEntry.date),
            ),
          );

      // 3. Record sync outbox items
      await _db.into(_db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              entityType: 'ledger_entry',
              entityId: original.id,
              action: 'void',
              payload: jsonEncode({'id': original.id, 'isVoided': true}),
            ),
          );

      await _db.into(_db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              entityType: 'ledger_entry',
              entityId: offsetEntry.id,
              action: 'insert',
              payload: jsonEncode(offsetEntry.toMap()),
            ),
          );

      // 4. Recalculate party net balance
      await _recalculatePartyBalanceInTx(original.partyId);
    });

    _updateStreamController.add(null);
  }

  @override
  Future<(int totalReceivable, int totalPayable)> getBusinessSummary() async {
    await _ensureInitialized();

    final parties = await (_db.select(_db.parties)
          ..where((t) => t.isDeleted.equals(false)))
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
    final partyQuery = _db.select(_db.parties)
      ..where((t) => t.id.equals(partyId));
    final party = await partyQuery.getSingleOrNull();
    if (party == null) return;

    final entriesQuery = _db.select(_db.ledgerEntries)
      ..where((t) => t.partyId.equals(partyId));
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

    await (_db.update(_db.parties)..where((t) => t.id.equals(partyId))).write(
      PartiesCompanion(
        netBalanceInCents: Value(newBalance),
        lastUpdated: Value(latestDate),
      ),
    );

    await _db.into(_db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            entityType: 'party',
            entityId: partyId,
            action: 'update_balance',
            payload: jsonEncode({
              'partyId': partyId,
              'netBalanceInCents': newBalance,
              'lastUpdated': latestDate.toIso8601String(),
            }),
          ),
        );
  }

  void dispose() {
    _updateStreamController.close();
  }
}
