import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/core/utils/date_formatter.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';

import 'support/strict_fake_remote.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Entry Timestamp & Date Accuracy Regression Tests', () {
    late AppDatabase dbA;
    late SyncEngine syncEngineA;
    late StrictFakeRemoteSyncBackend fakeRemote;
    late DriftLedgerRepository ledgerRepoA;
    late VoucherPostingEngine postingEngineA;
    late AuditService auditServiceA;

    const companyId = 'cmp_time_reg_1';
    const userId = 'usr_time_reg_1';
    const partyId = 'pty_time_reg_1';

    setUp(() async {
      dbA = AppDatabase(NativeDatabase.memory());
      fakeRemote = StrictFakeRemoteSyncBackend();
      syncEngineA = SyncEngine(
        db: dbA,
        activeUserId: userId,
        fakeRemoteStore: fakeRemote,
        simulateSyncForTesting: true,
      );

      auditServiceA = AuditService(dbA);
      postingEngineA = VoucherPostingEngine(dbA, auditServiceA);

      ledgerRepoA = DriftLedgerRepository(
        db: dbA,
        postingEngine: postingEngineA,
        syncEngine: syncEngineA,
        currentCompanyId: companyId,
        currentUserId: userId,
      );

      // Seed company
      final company = Company(
        id: companyId,
        name: 'Timestamp Precision Inc',
        legalName: 'Timestamp Precision Inc',
        mode: CompanyMode.ledger,
        currencyCode: 'INR',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await ledgerRepoA.createCompany(company);
      await postingEngineA.ensureCompanyAccounts(companyId);

      // Seed party
      await ledgerRepoA.addParty(Party(
        id: partyId,
        name: 'Precision Trading Partner',
        phoneNumber: '+91 98765 43210',
        type: PartyType.customer,
        netBalanceInCents: 0,
        lastUpdated: DateTime.now(),
      ));
    });

    tearDown(() async {
      ledgerRepoA.dispose();
      syncEngineA.dispose();
      await dbA.close();
    });

    // Test cases specified in prompt:
    // 1. 12 November 2026, 10:30 AM IST (offset +05:30 -> UTC 05:00)
    // 2. 12 November 2026, 04:45 PM IST (offset +05:30 -> UTC 11:15)
    // 3. 11 November 2026, 11:55 PM IST (offset +05:30 -> UTC 18:25)
    final specifiedTestTimes = [
      {
        'label': '12 Nov 2026, 10:30 AM IST',
        'dateTime': DateTime(2026, 11, 12, 10, 30, 0),
        'expectedTimeStr': '10:30 AM',
        'expectedDateStr': '12/11/2026',
      },
      {
        'label': '12 Nov 2026, 4:45 PM IST',
        'dateTime': DateTime(2026, 11, 12, 16, 45, 0),
        'expectedTimeStr': '04:45 PM',
        'expectedDateStr': '12/11/2026',
      },
      {
        'label': '11 Nov 2026, 11:55 PM IST',
        'dateTime': DateTime(2026, 11, 11, 23, 55, 0),
        'expectedTimeStr': '11:55 PM',
        'expectedDateStr': '11/11/2026',
      },
    ];

    for (final testCase in specifiedTestTimes) {
      test('Full roundtrip preservation for ${testCase['label']}', () async {
        final targetDateTime = testCase['dateTime'] as DateTime;
        final expectedTimeStr = testCase['expectedTimeStr'] as String;
        final expectedDateStr = testCase['expectedDateStr'] as String;

        // 1. Create entry with specified date/time
        final entryId = 'entry_${targetDateTime.millisecondsSinceEpoch}';
        final entry = LedgerEntry(
          id: entryId,
          partyId: partyId,
          amountInCents: 50000,
          type: EntryType.gave,
          date: targetDateTime,
          note: 'Roundtrip test for ${testCase['label']}',
        );

        // 2. Persist locally
        await ledgerRepoA.addEntry(entry);

        // Verify local storage in Device A
        final localEntry = await (dbA.select(dbA.ledgerEntries)..where((t) => t.id.equals(entryId))).getSingle();
        expect(localEntry.date.year, equals(targetDateTime.year));
        expect(localEntry.date.month, equals(targetDateTime.month));
        expect(localEntry.date.day, equals(targetDateTime.day));
        expect(localEntry.date.hour, equals(targetDateTime.hour));
        expect(localEntry.date.minute, equals(targetDateTime.minute));

        // 3. Serialize and synchronize
        final pushRes = await syncEngineA.pushQueue(companyId: companyId);
        expect(pushRes.success, isTrue);

        // 4. Retrieve from remote representation
        final remoteRow = fakeRemote.getRow('ledger_entries', entryId);
        expect(remoteRow, isNotNull);
        final remoteDateStr = remoteRow!['date'] as String;
        expect(remoteDateStr.endsWith('Z'), isTrue, reason: 'Remote timestamp must be UTC ISO-8601 with Z');

        // 5. Clean Device B pull
        final dbB = AppDatabase(NativeDatabase.memory());
        final syncEngineB = SyncEngine(
          db: dbB,
          activeUserId: userId,
          fakeRemoteStore: fakeRemote,
          simulateSyncForTesting: true,
        );

        final pullRes = await syncEngineB.pullChanges(companyId: companyId);
        expect(pullRes.success, isTrue);

        // 6. Deserialize and display on Device B
        final pulledEntryRow = await (dbB.select(dbB.ledgerEntries)..where((t) => t.id.equals(entryId))).getSingle();
        final pulledModel = LedgerEntry.fromMap({
          'id': pulledEntryRow.id,
          'partyId': pulledEntryRow.partyId,
          'amountInCents': pulledEntryRow.amountInCents,
          'type': pulledEntryRow.type.name,
          'date': pulledEntryRow.date,
          'note': pulledEntryRow.note,
          'isVoided': pulledEntryRow.isVoided,
        });

        // Verify exact local date/time preserved
        expect(pulledModel.date.year, equals(targetDateTime.year));
        expect(pulledModel.date.month, equals(targetDateTime.month));
        expect(pulledModel.date.day, equals(targetDateTime.day));
        expect(pulledModel.date.hour, equals(targetDateTime.hour));
        expect(pulledModel.date.minute, equals(targetDateTime.minute));

        // Format for UI display
        final formattedDate = DateFormatter.formatShortDate(pulledModel.date);
        final formattedTime = DateFormatter.formatTime(pulledModel.date);
        expect(formattedDate, equals(expectedDateStr));
        expect(formattedTime, equals(expectedTimeStr));

        syncEngineB.dispose();
        await dbB.close();
      });
    }

    test('Midnight (00:00) is preserved and never replaced with DateTime.now()', () async {
      final midnightDate = DateTime(2026, 11, 12, 0, 0, 0);

      final entry = LedgerEntry(
        id: 'entry_midnight_1',
        partyId: partyId,
        amountInCents: 10000,
        type: EntryType.got,
        date: midnightDate,
        note: 'Midnight entry test',
      );
      await ledgerRepoA.addEntry(entry);

      // Verify local
      final local = await (dbA.select(dbA.ledgerEntries)..where((t) => t.id.equals('entry_midnight_1'))).getSingle();
      expect(local.date.hour, equals(0));
      expect(local.date.minute, equals(0));

      // Push and pull
      await syncEngineA.pushQueue(companyId: companyId);

      final dbB = AppDatabase(NativeDatabase.memory());
      final syncEngineB = SyncEngine(
        db: dbB,
        activeUserId: userId,
        fakeRemoteStore: fakeRemote,
        simulateSyncForTesting: true,
      );
      await syncEngineB.pullChanges(companyId: companyId);

      final pulled = await (dbB.select(dbB.ledgerEntries)..where((t) => t.id.equals('entry_midnight_1'))).getSingle();
      expect(pulled.date.hour, equals(0));
      expect(pulled.date.minute, equals(0));
      expect(DateFormatter.formatTime(pulled.date), equals('12:00 AM'));

      syncEngineB.dispose();
      await dbB.close();
    });

    test('Date-boundary transition (23:59:59 to next day) preserves calendar date and time', () async {
      final endOfDay = DateTime(2026, 11, 11, 23, 59, 59);

      final entry = LedgerEntry(
        id: 'entry_boundary_1',
        partyId: partyId,
        amountInCents: 20000,
        type: EntryType.gave,
        date: endOfDay,
      );
      await ledgerRepoA.addEntry(entry);
      await syncEngineA.pushQueue(companyId: companyId);

      final dbB = AppDatabase(NativeDatabase.memory());
      final syncEngineB = SyncEngine(
        db: dbB,
        activeUserId: userId,
        fakeRemoteStore: fakeRemote,
        simulateSyncForTesting: true,
      );
      await syncEngineB.pullChanges(companyId: companyId);

      final pulled = await (dbB.select(dbB.ledgerEntries)..where((t) => t.id.equals('entry_boundary_1'))).getSingle();
      expect(pulled.date.day, equals(11));
      expect(pulled.date.month, equals(11));
      expect(pulled.date.year, equals(2026));
      expect(pulled.date.hour, equals(23));
      expect(pulled.date.minute, equals(59));
      expect(pulled.date.second, equals(59));

      syncEngineB.dispose();
      await dbB.close();
    });

    test('Editing only the date preserves time component and createdAt timestamp', () async {
      final initialDateTime = DateTime(2026, 11, 10, 14, 30, 0);
      final entry = LedgerEntry(
        id: 'entry_edit_date_1',
        partyId: partyId,
        amountInCents: 35000,
        type: EntryType.gave,
        date: initialDateTime,
        note: 'Initial entry',
      );
      await ledgerRepoA.addEntry(entry);

      final initialRow = await (dbA.select(dbA.ledgerEntries)..where((t) => t.id.equals('entry_edit_date_1'))).getSingle();
      final initialCreatedAt = initialRow.createdAt;

      // Edit only date to 15 Nov 2026, keeping time at 14:30
      final updatedDateTime = DateTime(2026, 11, 15, initialDateTime.hour, initialDateTime.minute, initialDateTime.second);
      final updatedEntry = entry.copyWith(date: updatedDateTime);

      await ledgerRepoA.updateEntry(updatedEntry);

      final updatedRow = await (dbA.select(dbA.ledgerEntries)..where((t) => t.id.equals('entry_edit_date_1'))).getSingle();
      // Date changed
      expect(updatedRow.date.day, equals(15));
      expect(updatedRow.date.hour, equals(14));
      expect(updatedRow.date.minute, equals(30));

      // createdAt remains UNCHANGED
      expect(updatedRow.createdAt.millisecondsSinceEpoch, equals(initialCreatedAt.millisecondsSinceEpoch));
      // updatedAt was updated
      expect(updatedRow.updatedAt.isAfter(initialCreatedAt) || updatedRow.updatedAt.isAtSameMomentAs(initialCreatedAt), isTrue);
    });

    test('Editing only the time preserves date component and createdAt timestamp', () async {
      final initialDateTime = DateTime(2026, 11, 12, 9, 0, 0);
      final entry = LedgerEntry(
        id: 'entry_edit_time_1',
        partyId: partyId,
        amountInCents: 45000,
        type: EntryType.got,
        date: initialDateTime,
      );
      await ledgerRepoA.addEntry(entry);

      final initialRow = await (dbA.select(dbA.ledgerEntries)..where((t) => t.id.equals('entry_edit_time_1'))).getSingle();
      final initialCreatedAt = initialRow.createdAt;

      // Edit only time to 17:45, keeping date at 12 Nov 2026
      final updatedDateTime = DateTime(initialDateTime.year, initialDateTime.month, initialDateTime.day, 17, 45, 0);
      final updatedEntry = entry.copyWith(date: updatedDateTime);

      await ledgerRepoA.updateEntry(updatedEntry);

      final updatedRow = await (dbA.select(dbA.ledgerEntries)..where((t) => t.id.equals('entry_edit_time_1'))).getSingle();
      expect(updatedRow.date.day, equals(12));
      expect(updatedRow.date.hour, equals(17));
      expect(updatedRow.date.minute, equals(45));

      // createdAt strictly unchanged
      expect(updatedRow.createdAt.millisecondsSinceEpoch, equals(initialCreatedAt.millisecondsSinceEpoch));
    });

    test('Editing both date and time keeps timestamps independent', () async {
      final initialDateTime = DateTime(2026, 11, 5, 8, 15, 0);
      final entry = LedgerEntry(
        id: 'entry_edit_both_1',
        partyId: partyId,
        amountInCents: 60000,
        type: EntryType.gave,
        date: initialDateTime,
      );
      await ledgerRepoA.addEntry(entry);

      final initialRow = await (dbA.select(dbA.ledgerEntries)..where((t) => t.id.equals('entry_edit_both_1'))).getSingle();
      final initialCreatedAt = initialRow.createdAt;

      final updatedDateTime = DateTime(2026, 11, 20, 18, 30, 0);
      final updatedEntry = entry.copyWith(date: updatedDateTime);

      await ledgerRepoA.updateEntry(updatedEntry);

      final updatedRow = await (dbA.select(dbA.ledgerEntries)..where((t) => t.id.equals('entry_edit_both_1'))).getSingle();
      expect(updatedRow.date.day, equals(20));
      expect(updatedRow.date.hour, equals(18));
      expect(updatedRow.date.minute, equals(30));
      expect(updatedRow.createdAt.millisecondsSinceEpoch, equals(initialCreatedAt.millisecondsSinceEpoch));
    });

    test('Repeated synchronization causes zero timestamp drift', () async {
      final intended = DateTime(2026, 11, 12, 10, 30, 0);
      final entry = LedgerEntry(
        id: 'entry_drift_test_1',
        partyId: partyId,
        amountInCents: 15000,
        type: EntryType.gave,
        date: intended,
      );
      await ledgerRepoA.addEntry(entry);

      // 5 repeated push and pull cycles
      for (int i = 0; i < 5; i++) {
        await syncEngineA.pushQueue(companyId: companyId);
        await syncEngineA.pullChanges(companyId: companyId);

        final current = await (dbA.select(dbA.ledgerEntries)..where((t) => t.id.equals('entry_drift_test_1'))).getSingle();
        expect(
          current.date.millisecondsSinceEpoch ~/ 1000,
          equals(intended.millisecondsSinceEpoch ~/ 1000),
          reason: 'Timestamp must remain invariant across sync cycles (cycle $i)',
        );
      }
    });

    test('DateFormatter guarantees accurate local display for UTC and non-UTC DateTime instances', () {
      // UTC instant representing 10:30 AM local
      final localInstant = DateTime(2026, 11, 12, 10, 30, 0);
      final utcInstant = localInstant.toUtc();

      // Formatting either the local or UTC instance through DateFormatter must produce the exact same local display
      final formattedFromLocal = DateFormatter.formatShortDateTime(localInstant);
      final formattedFromUtc = DateFormatter.formatShortDateTime(utcInstant);

      expect(formattedFromUtc, equals(formattedFromLocal));
      expect(DateFormatter.formatTime(utcInstant), equals(DateFormatter.formatTime(localInstant)));
    });
  });
}

