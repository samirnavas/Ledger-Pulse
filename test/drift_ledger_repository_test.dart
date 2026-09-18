import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';

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

    test('calculates business summary accurately', () async {
      final (totalReceivable, totalPayable) = await repo.getBusinessSummary();
      expect(totalReceivable, isNonNegative);
      expect(totalPayable, isNonNegative);
    });
  });
}
