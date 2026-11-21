import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';
import 'package:ledger_pulse/domain/exceptions/ledger_exceptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an offline posting and its outbox survive database reopen', () async {
    final folder = await Directory.systemTemp.createTemp('ledger-posting-');
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}/offline.sqlite');
    final date = DateTime.utc(2026, 1, 1, 15, 20);
    var db = AppDatabase(NativeDatabase(file));
    var repo = DriftLedgerRepository(db: db, autoSync: false);
    await repo.addParty(Party(
      id: 'offline-party', name: 'Offline', phoneNumber: '',
      type: PartyType.customer, netBalanceInCents: 0, lastUpdated: date,
    ));
    final entry = LedgerEntry(
      id: 'offline-transaction', partyId: 'offline-party',
      amountInCents: 12345, type: EntryType.gave, date: date,
    );
    await repo.addEntry(entry);
    repo.dispose();
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    repo = DriftLedgerRepository(db: db, autoSync: false);
    try {
      await repo.addEntry(entry);
      final rows = await repo.getEntriesForParty('offline-party');
      expect(rows.single.runningBalanceInCents, 12345);
      expect(rows.single.date.toUtc(), date);
      expect((await db.select(db.journals).get()).single.totalAmountInCents, 12345);
      final outbox = await db.select(db.syncOutbox).get();
      expect(outbox.where((row) => row.targetTable == 'ledger_entries').single.recordId, entry.id);
    } finally {
      repo.dispose();
      await db.close();
    }
  });

  group('DriftLedgerRepository', () {
    late AppDatabase db;
    late DriftLedgerRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftLedgerRepository(db: db, autoSync: false);
    });

    tearDown(() async {
      repo.dispose();
      await db.close();
    });

    test(
      'fresh install has empty parties, and loadSampleData loads fixtures',
      () async {
        expect(await repo.getParties(), isEmpty);
        await repo.loadSampleData();
        final parties = await repo.getParties();
        expect(parties, isNotEmpty);
        expect(parties.any((p) => p.name == 'Rahul Sharma'), isTrue);
      },
    );

    test('filters parties by PartyType correctly', () async {
      await repo.loadSampleData();
      final customers = await repo.getParties(filter: PartyType.customer);
      expect(customers, isNotEmpty);
      expect(customers.every((p) => p.type == PartyType.customer), isTrue);

      final suppliers = await repo.getParties(filter: PartyType.supplier);
      expect(suppliers, isNotEmpty);
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
              item.targetTable == 'parties' &&
              item.recordId == 'test_party_drift_1',
        ),
        isTrue,
      );
    });

    test(
      'adds debit (gave) and credit (got) entries with balance updates',
      () async {
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
      },
    );

    test(
      'strict business logic: deleteEntry retains the audit row without creating an offset',
      () async {
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
        final originalDbRow = await (db.select(
          db.ledgerEntries,
        )..where((t) => t.id.equals(originalEntryId))).getSingleOrNull();

        expect(originalDbRow, isNotNull);
        expect(originalDbRow!.isVoided, isTrue);

        expect(
          (await repo.getEntriesForParty(partyId)).single.runningBalanceInCents,
          0,
        );
        party = await repo.getPartyById(partyId);
        expect(party.netBalanceInCents, 0);

        // The outbox carries the void and the journal update.
        final outboxList = await db.select(db.syncOutbox).get();
        expect(
          outboxList.any(
            (o) =>
                o.targetTable == 'ledger_entries' &&
                o.recordId == originalEntryId &&
                o.mutationType == 'UPSERT',
          ),
          isTrue,
        );
        expect(
          outboxList.any(
            (o) =>
                o.targetTable == 'journals' &&
                o.recordId == 'jnl_entry_$originalEntryId' &&
                o.mutationType == 'UPSERT',
          ),
          isTrue,
        );
      },
    );

    test(
      'updateParty updates party fields while preserving existing running balance',
      () async {
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
          netBalanceInCents:
              0, // Should be ignored in updateParty, preserving DB balance
          lastUpdated: DateTime.now(),
        );

        await repo.updateParty(updatedParty);

        final fetched = await repo.getPartyById(partyId);
        expect(fetched.name, 'Updated Business Name');
        expect(fetched.phoneNumber, '+91 9999999999');
        expect(fetched.type, PartyType.supplier);
        expect(fetched.netBalanceInCents, 45000); // Preserved!
      },
    );

    test(
      'deleteParty throws ActiveBalanceException when party has active non-zero balance',
      () async {
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
      },
    );

    test(
      'archiving a settled party preserves its transaction history',
      () async {
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
        final dbPartyRow = await (db.select(
          db.parties,
        )..where((t) => t.id.equals(partyId))).getSingle();
        expect(dbPartyRow.isDeleted, isTrue);

        // Verify the journal history remains available after archive
        final dbEntries = await (db.select(
          db.ledgerEntries,
        )..where((t) => t.partyId.equals(partyId))).get();
        expect(dbEntries, hasLength(2));
        expect(dbEntries.every((e) => !e.isVoided && !e.isDeleted), isTrue);
      },
    );

    test(
      'updateEntry with non-financial changes updates note and receipt in place',
      () async {
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
            date: DateTime(2026, 1, 1),
            note: 'Updated note with receipt',
            receiptPhotoUrl: 'https://example.com/receipt.jpg',
          ),
        );

        final entries = await repo.getEntriesForParty(partyId);
        expect(entries.length, 1);
        expect(entries.first.id, entryId);
        expect(entries.first.note, 'Updated note with receipt');
        expect(
          entries.first.receiptPhotoUrl,
          'https://example.com/receipt.jpg',
        );
        expect(entries.first.amountInCents, 5000);
      },
    );

    test(
      'updateEntry with amount change executes immutable adjustment & balance recalculation',
      () async {
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
        final correction = LedgerEntry(
          id: originalEntryId,
          partyId: partyId,
          amountInCents: 80000,
          type: EntryType.gave,
          kind: LedgerEntryKind.credit,
          date: DateTime.now(),
          note: 'Corrected sale amount',
        );
        await Future.wait([repo.updateEntry(correction), repo.updateEntry(correction)]);
        await expectLater(
          repo.updateEntry(correction.copyWith(amountInCents: 70000)),
          throwsStateError,
        );

        // 1. Verify party net balance is now updated to 80000 cents atomically
        party = await repo.getPartyById(partyId);
        expect(party.netBalanceInCents, 80000);

        // 2. Verify original entry row is voided
        final originalRow = await (db.select(
          db.ledgerEntries,
        )..where((t) => t.id.equals(originalEntryId))).getSingle();
        expect(originalRow.isVoided, isTrue);

        // The original and one replacement remain available for audit.
        final allDbEntries = await (db.select(
          db.ledgerEntries,
        )..where((t) => t.partyId.equals(partyId))).get();
        expect(allDbEntries.length, 2);
        final journals = await db.select(db.journals).get();
        expect(
          journals
              .where((row) => row.status == 'posted')
              .single
              .totalAmountInCents,
          80000,
        );
      },
    );

    test('calculates business summary accurately', () async {
      final (totalReceivable, totalPayable) = await repo.getBusinessSummary();
      expect(totalReceivable, isNonNegative);
      expect(totalPayable, isNonNegative);
    });

    test(
      'opening, backdated, partial and excess payments reconcile after retry',
      () async {
        const partyId = 'reconcile_party';
        await repo.addParty(
          Party(
            id: partyId,
            name: 'Reconcile',
            phoneNumber: '',
            type: PartyType.customer,
            netBalanceInCents: 10000,
            lastUpdated: DateTime.utc(2026, 1, 1),
          ),
        );
        final partial = LedgerEntry(
          id: 'partial-payment',
          partyId: partyId,
          amountInCents: 3000,
          type: EntryType.got,
          date: DateTime.utc(2026, 1, 3),
        );
        await Future.wait([repo.addEntry(partial), repo.addEntry(partial)]);
        await repo.addEntry(
          partial.copyWith(
            id: 'backdated',
            amountInCents: 2000,
            date: DateTime.utc(2026, 1, 2),
          ),
        );
        await repo.addEntry(
          partial.copyWith(
            id: 'excess',
            amountInCents: 6000,
            date: DateTime.utc(2026, 1, 4),
          ),
        );
        final entries = await repo.getEntriesForParty(partyId);
        expect(entries.map((entry) => entry.runningBalanceInCents), [
          10000,
          8000,
          5000,
          -1000,
        ]);
        expect((await repo.getPartyById(partyId)).netBalanceInCents, -1000);
        expect(await repo.getBusinessSummary(), (0, 1000));
        expect(
          await (db.select(
            db.journals,
          )..where((row) => row.id.equals('jnl_entry_partial-payment'))).get(),
          hasLength(1),
        );
      },
    );

    test(
      'matched legacy offsets are neutral while similar user notes still count',
      () async {
        const partyId = 'legacy-party';
        final date = DateTime.utc(2026, 1, 1);
        await repo.addParty(
          Party(
            id: partyId,
            name: 'Legacy',
            phoneNumber: '',
            type: PartyType.customer,
            netBalanceInCents: 0,
            lastUpdated: date,
          ),
        );
        await db
            .into(db.ledgerEntries)
            .insert(
              LedgerEntriesCompanion.insert(
                id: 'legacy-original',
                partyId: partyId,
                amountInCents: 10000,
                type: EntryType.gave,
                date: date,
                isVoided: const Value(true),
              ),
            );
        await db
            .into(db.ledgerEntries)
            .insert(
              LedgerEntriesCompanion.insert(
                id: 'legacy-offset',
                partyId: partyId,
                amountInCents: 10000,
                type: EntryType.got,
                date: date.add(const Duration(days: 1)),
                note: const Value(
                  'Offset: Voided entry #legacy-original (old note)',
                ),
              ),
            );
        await repo.addEntry(
          LedgerEntry(
            id: 'normal',
            partyId: partyId,
            amountInCents: 1200,
            type: EntryType.gave,
            date: date,
            note: 'Reversal: Voided entry #legacy-original',
          ),
        );
        final entries = await repo.getEntriesForParty(partyId);
        expect(entries.map((entry) => entry.id), ['legacy-original', 'normal']);
        expect(entries.last.runningBalanceInCents, 1200);
        expect((await repo.getPartyById(partyId)).netBalanceInCents, 1200);
      },
    );

    test('rejects duplicate party names and normalized phone numbers', () async {
      final party = Party(
        id: 'unique-party',
        name: 'River Trading',
        phoneNumber: '+91 (98765) 43210',
        type: PartyType.customer,
        netBalanceInCents: 0,
        lastUpdated: DateTime.utc(2026, 1, 1),
      );
      await repo.addParty(party);
      final duplicateName = party.copyWith(
        id: 'duplicate-name',
        name: ' river   trading ',
        phoneNumber: '',
      );
      final duplicateContact = party.copyWith(
        id: 'duplicate-contact',
        name: 'River Contact',
        type: PartyType.supplier,
        phoneNumber: '98765-43210',
        netBalanceInCents: 500,
      );
      await expectLater(repo.addParty(duplicateName), throwsA(isA<DuplicatePartyException>()));
      await expectLater(repo.addParty(duplicateContact), throwsA(isA<DuplicatePartyException>()));
      expect(await repo.getEntriesForParty(duplicateContact.id), isEmpty);
      expect(
        (await db.select(db.syncOutbox).get()).map((row) => row.recordId),
        isNot(contains(duplicateContact.id)),
      );
      expect(
        await repo.findImportDuplicates([
          duplicateContact.copyWith(phoneNumber: '0091 9876543210'),
        ]),
        hasLength(1),
      );

      await repo.deleteParty(party.id);
      await expectLater(repo.addParty(duplicateContact), throwsA(isA<DuplicatePartyException>()));
      await repo.restoreParty(party.id);
      expect((await repo.getPartyById(party.id)).name, party.name);
    });

    test('archive, restore and duplicate CSV import preserve journal history', () async {
      final now = DateTime.utc(2026, 1, 1);
      final archived = Party(id: 'archive-test', name: 'North Trading',
        phoneNumber: '', type: PartyType.customer, netBalanceInCents: 0,
        lastUpdated: now);
      await repo.addParty(archived);
      await repo.deleteParty(archived.id);
      expect((await repo.getParties(archived: true)).map((p) => p.id), contains(archived.id));

      final fresh = archived.copyWith(id: 'fresh-import', name: 'South Trading',
        netBalanceInCents: 100);
      final duplicate = archived.copyWith(id: 'duplicate-import', name: ' north   trading ');
      await expectLater(repo.importLedgerParties([fresh, duplicate]), throwsStateError);
      expect(await repo.getEntriesForParty(fresh.id), isEmpty);

      await repo.restoreParty(archived.id);
      await repo.restoreParty(archived.id);
      expect(await repo.getParties(archived: true), isEmpty);
      expect((await repo.getPartyById(archived.id)).name, 'North Trading');

      await repo.importLedgerParties([fresh]);
      expect((await repo.getEntriesForParty(fresh.id)).single.runningBalanceInCents, 100);
      await expectLater(repo.importLedgerParties([fresh]), throwsStateError);
      expect(await repo.getEntriesForParty(fresh.id), hasLength(1));
    });

    test('standalone posting rejects an expense profile', () async {
      final now = DateTime.now();
      await repo.createCompany(
        Company(
          id: 'exp-only',
          name: 'Expense',
          legalName: 'Expense',
          mode: CompanyMode.expenseTracker,
          createdAt: now,
          updatedAt: now,
        ),
      );
      repo.setContext(companyId: 'exp-only');
      await db
          .into(db.parties)
          .insert(
            PartiesCompanion.insert(
              id: 'misplaced',
              companyId: const Value('exp-only'),
              name: 'Legacy misplaced party',
              phoneNumber: '',
              type: PartyType.customer,
              lastUpdated: now,
            ),
          );
      await expectLater(
        repo.addEntry(
          LedgerEntry(
            id: 'reject-expense',
            partyId: 'misplaced',
            amountInCents: 100,
            type: EntryType.gave,
            date: now,
          ),
        ),
        throwsStateError,
      );
      expect(await db.select(db.ledgerEntries).get(), isEmpty);
    });
  });
}
