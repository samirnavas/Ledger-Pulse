import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/constants/strings.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';
import 'package:ledger_pulse/presentation/ledger/party_ledger_screen.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/reports/statement_preview_screen.dart';

void main() {
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

  group('Contact Calling and Statement Preview/Export Tests', () {
    testWidgets('PartyLedgerScreen renders tappable phone number and Call button',
        (WidgetTester tester) async {
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

      // Verify phone number and call button exist
      expect(find.text('+91 98765 43210'), findsOneWidget);
      expect(find.text(AppStrings.callParty), findsOneWidget);
      expect(find.byIcon(Icons.call_rounded), findsOneWidget);

      // Tap phone number
      await tester.tap(find.text('+91 98765 43210'));
      await tester.pump();

      // Tap call party button
      await tester.tap(find.text(AppStrings.callParty));
      await tester.pump();
    });

    testWidgets('StatementPreviewScreen renders summary, table, WhatsApp and PDF buttons',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            partyDetailProvider('party_1').overrideWith((ref) => Future.value(testParty)),
            partyLedgerEntriesProvider('party_1').overrideWith((ref) => Future.value(testEntries)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StatementPreviewScreen(partyId: 'party_1'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      // Verify period chips and party details
      expect(find.text('All Time'), findsOneWidget);
      expect(find.text('Last 30 Days'), findsOneWidget);
      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('+91 98765 43210'), findsOneWidget);

      // Verify action buttons
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);

      // Switch period to Last 30 Days
      await tester.tap(find.text('Last 30 Days'));
      await tester.pump();
      expect(find.text('Last 30 Days'), findsOneWidget);

      // Tap WhatsApp Share button
      await tester.tap(find.text('WhatsApp'));
      await tester.pump();

      // Tap Export PDF button
      await tester.tap(find.text('Export PDF'));
      await tester.pump();
    });
  });
}

