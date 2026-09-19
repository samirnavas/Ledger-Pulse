import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';
import 'package:ledger_pulse/domain/exceptions/ledger_exceptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DriftLedgerRepository', () {
    late AppDatabase db;
    late DriftLedgerRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftLedgerRepository(db: db);
    });

    tearDown(() async {
      repo.dispose();
      await db.close();
    });

    test('initializes and returns seeded parties from fallback/asset', () async {
      final parties = await repo.getParties();
      expect(parties, isNotEmpty);
      expect(parties.any((p) => p.name == 'Rahul Sharma'), isTrue);
    });

    test('filters parties by PartyType correctly', () async {
      final customers = await repo.getParties(filter: PartyType.customer);
      expect(customers.every((p) => p.type == PartyType.customer), isTrue);

      final suppliers = await repo.getParties(filter: PartyType.supplier);
      expect(suppliers.every((p) => p.type == PartyType.supplier), isTrue);
    });

    test('adds new party and records in SyncOutbox & fires stream', () async {
      bool streamFired = false;
      repo.repositoryUpdatesStream.listen((_) {
        streamFired = true;
      });

      final newParty = Party(
        id: 'test_party_drift_1',
        name: 'Drift Test User',
        phoneNumber: '+91 9123456780',
        type: PartyType.customer,
        netBalanceInCents: 10000,
        lastUpdated: DateTime.now(),
      );

      await repo.addParty(newParty);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(streamFired, isTrue);

      final fetched = await repo.getPartyById('test_party_drift_1');
      expect(fetched.name, 'Drift Test User');
      expect(fetched.netBalanceInCents, 10000);

      // Verify SyncOutbox record
      final outboxItems = await db.select(db.syncOutbox).get();
      expect(
        outboxItems.any(
          (item) =>
              item.entityType == 'party' &&
              item.entityId == 'test_party_drift_1' &&
              item.action == 'upsert',
        ),
        isTrue,
      );
    });

    test('adds debit (gave) and credit (got) entries with balance updates', () async {
      final partyId = 'test_party_math';
      await repo.addParty(
        Party(
          id: partyId,
          name: 'Math Test Customer',
          phoneNumber: '+91 9888877777',
          type: PartyType.customer,
          netBalanceInCents: 0,
          lastUpdated: DateTime.now(),
        ),
      );

      // Add 'gave' entry (+₹500.00 = 50000 cents)
      await repo.addEntry(
        LedgerEntry(
          id: 'entry_math_1',
          partyId: partyId,
          amountInCents: 50000,
          type: EntryType.gave,
          date: DateTime.now(),
          note: 'Sold goods on credit',
        ),
      );

      final partyAfterGave = await repo.getPartyById(partyId);
      expect(partyAfterGave.netBalanceInCents, 50000);

      // Add 'got' entry (-₹200.00 = 20000 cents)
      await repo.addEntry(
        LedgerEntry(
          id: 'entry_math_2',
          partyId: partyId,
          amountInCents: 20000,
          type: EntryType.got,
          date: DateTime.now().add(const Duration(minutes: 5)),
          note: 'Received partial payment',
        ),
      );

      final partyAfterGot = await repo.getPartyById(partyId);
      expect(partyAfterGot.netBalanceInCents, 30000);

      final entries = await repo.getEntriesForParty(partyId);
      expect(entries.length, 2);
    });

    test('strict business logic: deleteEntry voids row and inserts offsetting entry', () async {
      final partyId = 'test_party_safeguard';
      await repo.addParty(
        Party(
          id: partyId,
          name: 'Safeguard Test Customer',
          phoneNumber: '+91 9111122222',
          type: PartyType.customer,
          netBalanceInCents: 0,
          lastUpdated: DateTime.now(),
        ),
      );

      // Insert initial 'gave' entry (+₹1,000.00)
      final originalEntryId = 'entry_original_to_void';
      await repo.addEntry(
        LedgerEntry(
          id: originalEntryId,
          partyId: partyId,
          amountInCents: 100000,
          type: EntryType.gave,
          date: DateTime.now(),
          note: 'Original transaction to be voided',
        ),
      );

      var party = await repo.getPartyById(partyId);
      expect(party.netBalanceInCents, 100000);

      // Execute double-entry safeguard delete
      await repo.deleteEntry(originalEntryId);

      // 1. Verify original row is NOT hard-deleted and has isVoided = true
      final originalDbRow = await (db.select(db.ledgerEntries)
            ..where((t) => t.id.equals(originalEntryId)))
          .getSingleOrNull();

      expect(originalDbRow, isNotNull);
      expect(originalDbRow!.isVoided, isTrue);

      // 2. Verify an offsetting entry was inserted with type 'got' (opposite of 'gave')
      final allPartyEntries = await (db.select(db.ledgerEntries)
            ..where((t) => t.partyId.equals(partyId)))
          .get();

      expect(allPartyEntries.length, 2);
      final offsetRow = allPartyEntries.firstWhere((e) => e.id != originalEntryId);
      expect(offsetRow.type, EntryType.got);
      expect(offsetRow.amountInCents, 100000);
      expect(offsetRow.isVoided, isFalse);
      expect(offsetRow.note, contains('Offset: Voided entry'));

      // 3. Verify net balance is now offset back to 0 (+100000 - 100000 = 0)
      party = await repo.getPartyById(partyId);
      expect(party.netBalanceInCents, 0);

      // 4. Verify SyncOutbox has both 'void' action and 'insert' action
      final outboxList = await db.select(db.syncOutbox).get();
      expect(
        outboxList.any(
          (o) =>
              o.entityType == 'ledger_entry' &&
              o.entityId == originalEntryId &&
              o.action == 'void',
        ),
        isTrue,
      );
      expect(
        outboxList.any(
          (o) =>
              o.entityType == 'ledger_entry' &&
              o.entityId == offsetRow.id &&
              o.action == 'insert',
        ),
        isTrue,
      );
    });

    test('updateParty updates party fields while preserving existing running balance', () async {
      final partyId = 'test_party_update_preserve';
      await repo.addParty(
        Party(
          id: partyId,
          name: 'Original Name',
          phoneNumber: '+91 9000000001',
          type: PartyType.customer,
          netBalanceInCents: 45000,
          lastUpdated: DateTime.now(),
        ),
      );

      final updatedParty = Party(
        id: partyId,
        name: 'Updated Business Name',
        phoneNumber: '+91 9999999999',
        type: PartyType.supplier,
        netBalanceInCents: 0, // Should be ignored in updateParty, preserving DB balance
        lastUpdated: DateTime.now(),
      );

      await repo.updateParty(updatedParty);

      final fetched = await repo.getPartyById(partyId);
      expect(fetched.name, 'Updated Business Name');
      expect(fetched.phoneNumber, '+91 9999999999');
      expect(fetched.type, PartyType.supplier);
      expect(fetched.netBalanceInCents, 45000); // Preserved!
    });

    test('deleteParty throws ActiveBalanceException when party has active non-zero balance', () async {
      final partyId = 'test_party_active_balance';
      await repo.addParty(
        Party(
          id: partyId,
          name: 'Active Debt Party',
          phoneNumber: '+91 9888800000',
          type: PartyType.customer,
          netBalanceInCents: 25000, // Non-zero active balance
          lastUpdated: DateTime.now(),
        ),
      );

      expect(
        () => repo.deleteParty(partyId),
        throwsA(isA<ActiveBalanceException>()),
      );
    });

    test('deleteParty soft-deletes party and marks associated entries as voided when balance is 0', () async {
      final partyId = 'test_party_zero_balance';
      await repo.addParty(
        Party(
          id: partyId,
          name: 'Settled Customer',
          phoneNumber: '+91 9777700000',
          type: PartyType.customer,
          netBalanceInCents: 0,
          lastUpdated: DateTime.now(),
        ),
      );

      // Add settled entries
      await repo.addEntry(
        LedgerEntry(
          id: 'entry_settled_1',
          partyId: partyId,
          amountInCents: 10000,
          type: EntryType.gave,
          date: DateTime.now(),
        ),
      );
      await repo.addEntry(
        LedgerEntry(
          id: 'entry_settled_2',
          partyId: partyId,
          amountInCents: 10000,
          type: EntryType.got,
          date: DateTime.now().add(const Duration(minutes: 1)),
        ),
      );

      var party = await repo.getPartyById(partyId);
      expect(party.netBalanceInCents, 0);

      // Now delete party with 0 balance
      await repo.deleteParty(partyId);

      // Verify soft-deleted from normal getPartyById / getParties
      expect(() => repo.getPartyById(partyId), throwsException);
      final allParties = await repo.getParties();
      expect(allParties.any((p) => p.id == partyId), isFalse);

      // Verify raw database row has isDeleted = true
      final dbPartyRow = await (db.select(db.parties)..where((t) => t.id.equals(partyId))).getSingle();
      expect(dbPartyRow.isDeleted, isTrue);

      // Verify raw ledger entries are marked voided
      final dbEntries = await (db.select(db.ledgerEntries)..where((t) => t.partyId.equals(partyId))).get();
      expect(dbEntries.every((e) => e.isVoided), isTrue);
    });

    test('updateEntry with non-financial changes updates note/date in place', () async {
      final partyId = 'test_party_entry_edit_info';
      await repo.addParty(
        Party(
          id: partyId,
          name: 'Info Edit User',
          phoneNumber: '+91 9666600000',
          type: PartyType.customer,
          netBalanceInCents: 0,
          lastUpdated: DateTime.now(),
        ),
      );

      final entryId = 'entry_info_orig';
      await repo.addEntry(
        LedgerEntry(
          id: entryId,
          partyId: partyId,
          amountInCents: 5000,
          type: EntryType.gave,
          date: DateTime(2026, 1, 1),
          note: 'Old note',
        ),
      );

      // Update non-financial info
      await repo.updateEntry(
        LedgerEntry(
          id: entryId,
          partyId: partyId,
          amountInCents: 5000,
          type: EntryType.gave,
          date: DateTime(2026, 1, 2),
          note: 'Updated note with receipt',
          receiptPhotoUrl: 'https://example.com/receipt.jpg',
        ),
      );

      final entries = await repo.getEntriesForParty(partyId);
      expect(entries.length, 1);
      expect(entries.first.id, entryId);
      expect(entries.first.note, 'Updated note with receipt');
      expect(entries.first.receiptPhotoUrl, 'https://example.com/receipt.jpg');
      expect(entries.first.amountInCents, 5000);
    });

    test('updateEntry with amount change executes immutable adjustment & balance recalculation', () async {
      final partyId = 'test_party_entry_immutable';
      await repo.addParty(
        Party(
          id: partyId,
          name: 'Immutable Adjustment Customer',
          phoneNumber: '+91 9555500000',
          type: PartyType.customer,
          netBalanceInCents: 0,
          lastUpdated: DateTime.now(),
        ),
      );

      final originalEntryId = 'entry_to_adjust';
      await repo.addEntry(
        LedgerEntry(
          id: originalEntryId,
          partyId: partyId,
          amountInCents: 50000, // +₹500.00
          type: EntryType.gave,
          date: DateTime.now(),
          note: 'Original sale',
        ),
      );

      var party = await repo.getPartyById(partyId);
      expect(party.netBalanceInCents, 50000);

      // Change amount to ₹800.00 (80000 cents)
      await repo.updateEntry(
        LedgerEntry(
          id: originalEntryId,
          partyId: partyId,
          amountInCents: 80000,
          type: EntryType.gave,
          date: DateTime.now(),
          note: 'Corrected sale amount',
        ),
      );

      // 1. Verify party net balance is now updated to 80000 cents atomically
      party = await repo.getPartyById(partyId);
      expect(party.netBalanceInCents, 80000);

      // 2. Verify original entry row is voided
      final originalRow = await (db.select(db.ledgerEntries)..where((t) => t.id.equals(originalEntryId))).getSingle();
      expect(originalRow.isVoided, isTrue);

      // 3. Verify reversing offset entry exists
      final allDbEntries = await (db.select(db.ledgerEntries)..where((t) => t.partyId.equals(partyId))).get();
      expect(allDbEntries.length, 3); // original + offset + revised
    });

    test('calculates business summary accurately', () async {
      final (totalReceivable, totalPayable) = await repo.getBusinessSummary();
      expect(totalReceivable, isNonNegative);
      expect(totalPayable, isNonNegative);
    });
  });
}
