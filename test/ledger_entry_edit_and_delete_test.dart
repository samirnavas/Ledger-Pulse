import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/mock/mock_ledger_repository.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';
import 'package:ledger_pulse/presentation/ledger/add_entry_bottom_sheet.dart';
import 'package:ledger_pulse/presentation/ledger/party_ledger_screen.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';

void main() {
  group('Ledger Transaction Edit & Delete Flow Tests', () {
    testWidgets(
      'Tapping transaction row opens Transaction Voucher sheet with Edit and Delete options',
      (tester) async {
        final mockRepo = MockLedgerRepository();
        addTearDown(mockRepo.dispose);
        final party = Party(
          id: 'test_party_voucher',
          name: 'Voucher Customer',
          phoneNumber: '9876543210',
          type: PartyType.customer,
          netBalanceInCents: 250000,
          lastUpdated: DateTime(2026, 9, 1),
        );
        final entry = LedgerEntry(
          id: 'test_entry_voucher',
          partyId: party.id,
          amountInCents: 250000, // ₹2,500
          type: EntryType.gave,
          date: DateTime(2026, 9, 1, 10, 30),
          note: 'Invoice #1001 for goods',
        );

        await mockRepo.addParty(party);
        await mockRepo.addEntry(entry);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ledgerRepositoryProvider.overrideWithValue(mockRepo),
            ],
            child: MaterialApp(
              home: PartyLedgerScreen(partyId: party.id),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Verify transaction row exists
        expect(find.text('Invoice #1001 for goods'), findsOneWidget);
        expect(find.text('- ₹2,500.00'), findsOneWidget);

        // Tap the transaction row
        await tester.tap(find.text('Invoice #1001 for goods'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Verify Transaction Voucher bottom sheet is open
        expect(find.text('Transaction Voucher'), findsOneWidget);
        expect(find.text('Edit Note / Details'), findsOneWidget);
        expect(find.text('Delete / Void Entry'), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping Edit Note / Details opens AddEntryBottomSheet in Edit Mode pre-populated',
      (tester) async {
        final mockRepo = MockLedgerRepository();
        addTearDown(mockRepo.dispose);
        final party = Party(
          id: 'test_party_edit',
          name: 'Edit Customer',
          phoneNumber: '9876543211',
          type: PartyType.customer,
          netBalanceInCents: 150000,
          lastUpdated: DateTime(2026, 9, 1),
        );
        final entry = LedgerEntry(
          id: 'test_entry_edit',
          partyId: party.id,
          amountInCents: 150000, // ₹1,500
          type: EntryType.gave,
          date: DateTime(2026, 9, 1, 14, 0),
          note: 'Old Note',
        );

        await mockRepo.addParty(party);
        await mockRepo.addEntry(entry);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ledgerRepositoryProvider.overrideWithValue(mockRepo),
            ],
            child: MaterialApp(
              home: PartyLedgerScreen(partyId: party.id),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Tap transaction row to open voucher
        await tester.tap(find.text('Old Note'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Tap Edit Note / Details
        await tester.tap(find.text('Edit Note / Details'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Verify AddEntryBottomSheet opened in edit mode
        expect(find.byType(AddEntryBottomSheet), findsOneWidget);
        expect(find.text('EDIT ENTRY'), findsOneWidget);
        expect(find.text('1500'), findsOneWidget); // Pre-filled amount display
        expect(find.text('Old Note'), findsOneWidget); // Pre-filled note
        expect(find.text('Update You Gave Entry'), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping Delete / Void Entry prompts AdaptiveConfirmDialog and voids entry on confirmation',
      (tester) async {
        final mockRepo = MockLedgerRepository();
        addTearDown(mockRepo.dispose);
        final party = Party(
          id: 'test_party_void',
          name: 'Void Customer',
          phoneNumber: '9876543212',
          type: PartyType.customer,
          netBalanceInCents: 50000,
          lastUpdated: DateTime(2026, 9, 1),
        );
        final entry = LedgerEntry(
          id: 'test_entry_void',
          partyId: party.id,
          amountInCents: 50000, // ₹500
          type: EntryType.gave,
          date: DateTime(2026, 9, 1, 16, 0),
          note: 'Mistaken Entry',
        );

        await mockRepo.addParty(party);
        await mockRepo.addEntry(entry);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ledgerRepositoryProvider.overrideWithValue(mockRepo),
            ],
            child: MaterialApp(
              home: PartyLedgerScreen(partyId: party.id),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Tap transaction row to open voucher
        await tester.tap(find.text('Mistaken Entry'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Tap Delete / Void Entry
        await tester.tap(find.text('Delete / Void Entry'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Verify confirmation dialog appears with the exact safety warning message
        expect(find.text('Void Transaction?'), findsOneWidget);
        expect(
          find.text(
            'Void this entry? A reversing entry will be added to balance the ledger.',
          ),
          findsOneWidget,
        );

        // Confirm voiding
        await tester.tap(find.text('Void Entry'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Verify transaction voided notification
        expect(
          find.text('Transaction voided. Reversing entry recorded.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Tapping top app bar 3-dot options button opens Party Context Menu with Edit and Delete options',
      (tester) async {
        final mockRepo = MockLedgerRepository();
        addTearDown(mockRepo.dispose);
        final party = Party(
          id: 'test_party_header_menu',
          name: 'Header Menu Customer',
          phoneNumber: '9876543213',
          type: PartyType.customer,
          netBalanceInCents: 0,
          lastUpdated: DateTime(2026, 9, 1),
        );

        await mockRepo.addParty(party);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ledgerRepositoryProvider.overrideWithValue(mockRepo),
            ],
            child: MaterialApp(
              home: PartyLedgerScreen(partyId: party.id),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Find and tap the 3-dot party options button in top app bar
        final optionsButton = find.byTooltip('Party Options');
        expect(optionsButton, findsOneWidget);
        await tester.tap(optionsButton);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Verify party context menu opens with Edit Details and Delete Party
        expect(find.text('Edit Details'), findsOneWidget);
        expect(find.text('Delete Party'), findsOneWidget);
      },
    );
  });
}
