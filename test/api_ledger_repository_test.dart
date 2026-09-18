import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ledger_pulse/data/api/api_ledger_repository.dart';
import 'package:ledger_pulse/data/models/party_model.dart';

void main() {
  group('ApiLedgerRepository', () {
    test('getParties returns parsed parties from server', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/parties');
        return http.Response(
          jsonEncode([
            {
              'id': 'p1',
              'name': 'Test User',
              'phoneNumber': '+91 1234567890',
              'type': 'customer',
              'netBalanceInCents': 50000,
              'lastUpdated': '2026-09-17T12:00:00.000Z',
            }
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final repo = ApiLedgerRepository(client: mockClient);
      final parties = await repo.getParties();
      expect(parties.length, 1);
      expect(parties.first.name, 'Test User');
      expect(parties.first.netBalanceInCents, 50000);
      repo.dispose();
    });

    test('addParty posts party payload and triggers update stream', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/parties');
        final decoded = jsonDecode(request.body);
        expect(decoded['name'], 'New Supplier');
        return http.Response(request.body, 201);
      });

      final repo = ApiLedgerRepository(client: mockClient);
      bool streamFired = false;
      repo.repositoryUpdatesStream.listen((_) {
        streamFired = true;
      });

      await repo.addParty(
        Party(
          id: 'p2',
          name: 'New Supplier',
          phoneNumber: '+91 9999999999',
          type: PartyType.supplier,
          netBalanceInCents: -20000,
          lastUpdated: DateTime.now(),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(streamFired, isTrue);
      repo.dispose();
    });

    test('getBusinessSummary returns tuple of receivable and payable', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/summary');
        return http.Response(
          jsonEncode({
            'totalReceivable': 120000,
            'totalPayable': 45000,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final repo = ApiLedgerRepository(client: mockClient);
      final (receivable, payable) = await repo.getBusinessSummary();
      expect(receivable, 120000);
      expect(payable, 45000);
      repo.dispose();
    });
  });
}
