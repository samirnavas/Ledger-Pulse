import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/mock/mock_ledger_repository.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';

void main() {
  group('MockLedgerRepository Tests', () {
    late MockLedgerRepository repository;

    setUp(() {
      repository = MockLedgerRepository();
    });

    tearDown(() {
      repository.dispose();
    });

    test('Loads 4 initial parties with proper customer/supplier types', () async {
      final allParties = await repository.getParties();
      expect(allParties.length, equals(4));

      final customers = await repository.getParties(filter: PartyType.customer);
      expect(customers.length, equals(2));

      final suppliers = await repository.getParties(filter: PartyType.supplier);
      expect(suppliers.length, equals(2));
    });

    test('Computes initial business summary accurately', () async {
      final (receivable, payable) = await repository.getBusinessSummary();
      // Rahul Sharma = 450000 (Receivable)
      // Ananya Patel = 0
      // Metro Wholesale = -1280000 (Payable 1280000)
      // Apex Logistics = -120000 (Payable 120000)
      expect(receivable, equals(450000));
      expect(payable, equals(1400000));
    });

    test('Adding an entry recalculates party balance and updates business summary', () async {
      // Add a 'gave' entry of ₹500 (50000 cents) to Rahul Sharma (party_1)
      final newEntry = LedgerEntry(
        id: 'test_entry_1',
        partyId: 'party_1',
        amountInCents: 50000,
        type: EntryType.gave,
        date: DateTime.now(),
        note: 'Test Goods Credit',
      );

      await repository.addEntry(newEntry);

      final party = await repository.getPartyById('party_1');
      // Previous 450000 + 50000 = 500000
      expect(party.netBalanceInCents, equals(500000));

      final (receivable, _) = await repository.getBusinessSummary();
      expect(receivable, equals(500000));
    });

    test('Calculates running balances chronologically for party entries', () async {
      final entries = await repository.getEntriesForParty('party_1');
      expect(entries.isNotEmpty, isTrue);

      // Verify each entry has runningBalanceInCents computed
      for (final entry in entries) {
        expect(entry.runningBalanceInCents, isNotNull);
      }
    });
  });
}
