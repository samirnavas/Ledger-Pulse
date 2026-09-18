import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/local/local_asset_ledger_repository.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalAssetLedgerRepository', () {
    late LocalAssetLedgerRepository repo;

    setUp(() {
      repo = LocalAssetLedgerRepository();
    });

    tearDown(() {
      repo.dispose();
    });

    test('initializes and returns parties list', () async {
      final parties = await repo.getParties();
      expect(parties, isNotEmpty);
      expect(parties.any((p) => p.name == 'Rahul Sharma'), isTrue);
    });

    test('filters parties by type', () async {
      final customers = await repo.getParties(filter: PartyType.customer);
      expect(customers.every((p) => p.type == PartyType.customer), isTrue);

      final suppliers = await repo.getParties(filter: PartyType.supplier);
      expect(suppliers.every((p) => p.type == PartyType.supplier), isTrue);
    });

    test('adds new party and notifies update stream', () async {
      bool streamFired = false;
      repo.repositoryUpdatesStream.listen((_) {
        streamFired = true;
      });

      final newParty = Party(
        id: 'test_party_1',
        name: 'Direct In-App User',
        phoneNumber: '+91 9123456780',
        type: PartyType.customer,
        netBalanceInCents: 10000,
        lastUpdated: DateTime.now(),
      );

      await repo.addParty(newParty);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(streamFired, isTrue);

      final fetched = await repo.getPartyById('test_party_1');
      expect(fetched.name, 'Direct In-App User');
    });

    test('adds entry and recalculates party balance', () async {
      final partyId = 'test_calc_party';
      await repo.addParty(
        Party(
          id: partyId,
          name: 'Calc User',
          phoneNumber: '+91 9998887776',
          type: PartyType.customer,
          netBalanceInCents: 0,
          lastUpdated: DateTime.now(),
        ),
      );

      // Add "gave" entry (+₹500.00)
      await repo.addEntry(
        LedgerEntry(
          id: 'entry_test_1',
          partyId: partyId,
          amountInCents: 50000,
          type: EntryType.gave,
          date: DateTime.now(),
          note: 'Credit sale',
        ),
      );

      final partyAfterGave = await repo.getPartyById(partyId);
      expect(partyAfterGave.netBalanceInCents, 50000);

      // Add "got" entry (-₹200.00)
      await repo.addEntry(
        LedgerEntry(
          id: 'entry_test_2',
          partyId: partyId,
          amountInCents: 20000,
          type: EntryType.got,
          date: DateTime.now(),
          note: 'Payment received',
        ),
      );

      final partyAfterGot = await repo.getPartyById(partyId);
      expect(partyAfterGot.netBalanceInCents, 30000);

      // Verify entries list with running balance
      final entries = await repo.getEntriesForParty(partyId);
      expect(entries.length, 2);
    });

    test('calculates business summary correctly', () async {
      final (receivable, payable) = await repo.getBusinessSummary();
      expect(receivable, isNonNegative);
      expect(payable, isNonNegative);
    });
  });
}
