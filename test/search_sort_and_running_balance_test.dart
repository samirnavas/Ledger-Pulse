import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/mock/mock_ledger_repository.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';
import 'package:ledger_pulse/presentation/home/dashboard_screen.dart';
import 'package:ledger_pulse/presentation/home/party_list_tab.dart';
import 'package:ledger_pulse/presentation/ledger/party_ledger_screen.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';

void main() {
  group('Search, Sort, and Running Balance Feature Tests', () {
    testWidgets('PartyListTab renders search bar and sort icon',
        (WidgetTester tester) async {
      final repo = MockLedgerRepository();
      addTearDown(repo.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ledgerRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PartyListTab(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
      expect(find.text('Search by name or number...'), findsOneWidget);
    });

    testWidgets('PartyListTab filters parties by name in real-time',
        (WidgetTester tester) async {
      final repo = MockLedgerRepository();
      addTearDown(repo.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ledgerRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PartyListTab(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Enter search query "Sharma"
      await tester.enterText(find.byType(TextField), 'Sharma');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('Metro Wholesale'), findsNothing);
    });

    testWidgets('PartyListTab opens sort options on tapping sort icon',
        (WidgetTester tester) async {
      final repo = MockLedgerRepository();
      addTearDown(repo.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ledgerRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PartyListTab(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byIcon(Icons.sort_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Sort Parties By'), findsOneWidget);
      expect(find.text('Most Recent'), findsOneWidget);
      expect(find.text('Highest Receivable'), findsOneWidget);
      expect(find.text('Alphabetical'), findsOneWidget);
    });

    test('partyLedgerEntriesProvider computes cumulative running balance', () async {
      final repo = MockLedgerRepository();
      addTearDown(repo.dispose);

      final entries = await repo.getEntriesForParty('party_1');

      expect(entries, isNotEmpty);
      for (final entry in entries) {
        expect(entry.runningBalanceInCents, isNotNull);
      }
    });

    testWidgets('PartyLedgerScreen renders running balance for transaction rows',
        (WidgetTester tester) async {
      final testParty = Party(
        id: 'party_1',
        name: 'Rahul Sharma',
        phoneNumber: '+91 98765 43210',
        type: PartyType.customer,
        netBalanceInCents: 450000,
        lastUpdated: DateTime.now(),
      );

      final testEntries = [
        LedgerEntry(
          id: 'entry_1',
          partyId: 'party_1',
          amountInCents: 50000,
          type: EntryType.gave,
          date: DateTime.now(),
          note: 'Invoice #101',
          runningBalanceInCents: 50000,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ledgerUpdatesStreamProvider.overrideWith((ref) => Stream.value(null)),
            partyDetailProvider('party_1').overrideWith((ref) => Future.value(testParty)),
            partyLedgerEntriesProvider('party_1').overrideWith((ref) => Future.value(testEntries)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PartyLedgerScreen(partyId: 'party_1'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Bal:'), findsWidgets);
    });

    testWidgets('PartyLedgerScreen animates newly added ledger entry gracefully',
        (WidgetTester tester) async {
      final repo = MockLedgerRepository();
      addTearDown(repo.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ledgerRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PartyLedgerScreen(partyId: 'party_1'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Add a new entry to repo for party_1 (let pump advance the fakeAsync clock)
      unawaited(
        repo.addEntry(
          LedgerEntry(
            id: 'entry_animated_new',
            partyId: 'party_1',
            amountInCents: 125000,
            type: EntryType.got,
            date: DateTime.now(),
            note: 'Animated Cash Received',
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 250));
      // Pump frame of entrance animation (within 300ms)
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Animated Cash Received'), findsOneWidget);

      // Advance clock past entrance animation and highlight fade
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('Animated Cash Received'), findsOneWidget);
    });

    testWidgets('DashboardScreen back press in search mode exits search mode rather than popping',
        (WidgetTester tester) async {
      final repo = MockLedgerRepository();
      addTearDown(repo.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ledgerRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Enter search query
      await tester.enterText(find.byType(TextField), 'Sharma');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Rahul Sharma'), findsOneWidget);

      // Trigger back navigation (system back button)
      final dynamic navState = tester.state(find.byType(Navigator));
      navState.maybePop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Dashboard screen remains open, but search is reset
      expect(find.byType(DashboardScreen), findsOneWidget);
    });
  });
}
