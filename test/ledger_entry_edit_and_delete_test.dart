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
  TestWidgetsFlutterBinding.ensureInitialized();

  final testParty = Party(
    id: 'test_party_1',
    name: 'Voucher Customer',
    phoneNumber: '9876543210',
    type: PartyType.customer,
    netBalanceInCents: 250000,
    lastUpdated: DateTime(2026, 9, 1),
  );

  final testEntry = LedgerEntry(
    id: 'test_entry_1',
    partyId: 'test_party_1',
    amountInCents: 250000, // ₹2,500
    type: EntryType.gave,
    date: DateTime(2026, 9, 1, 10, 30),
    note: 'Invoice #1001 for goods',
    runningBalanceInCents: 250000,
  );

  group('Ledger Transaction Edit & Delete Flow Tests', () {
    testWidgets(
      'Tapping transaction row opens Transaction Voucher sheet with Edit and Delete options',
      (tester) async {
        final mockRepo = MockLedgerRepository();
        addTearDown(mockRepo.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ledgerRepositoryProvider.overrideWithValue(mockRepo),
              ledgerUpdatesStreamProvider.overrideWith((ref) => const Stream.empty()),
              partyDetailProvider('test_party_1').overrideWith((ref) => Future.value(testParty)),
              partyLedgerEntriesProvider('test_party_1').overrideWith((ref) => Future.value([testEntry])),
            ],
            child: const MaterialApp(
              home: PartyLedgerScreen(partyId: 'test_party_1'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify transaction row exists
        expect(find.text('Invoice #1001 for goods'), findsOneWidget);
        expect(find.text('- ₹ 2,500.00'), findsOneWidget);

        // Tap the transaction row
        await tester.tap(find.text('Invoice #1001 for goods'));
        await tester.pump();
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

        final editParty = testParty.copyWith(id: 'test_party_edit', name: 'Edit Customer');
        final editEntry = testEntry.copyWith(id: 'test_entry_edit', partyId: 'test_party_edit', amountInCents: 150000, note: 'Old Note');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ledgerRepositoryProvider.overrideWithValue(mockRepo),
              ledgerUpdatesStreamProvider.overrideWith((ref) => const Stream.empty()),
              partyDetailProvider('test_party_edit').overrideWith((ref) => Future.value(editParty)),
              partyLedgerEntriesProvider('test_party_edit').overrideWith((ref) => Future.value([editEntry])),
            ],
            child: const MaterialApp(
              home: PartyLedgerScreen(partyId: 'test_party_edit'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Tap transaction row to open voucher
        await tester.tap(find.text('Old Note'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Tap Edit Note / Details
        await tester.tap(find.text('Edit Note / Details'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify AddEntryBottomSheet opened in edit mode
        expect(find.byType(AddEntryBottomSheet), findsOneWidget);
        expect(find.text('EDIT ENTRY'), findsOneWidget);
        expect(find.text('1500'), findsOneWidget); // Pre-filled amount display
        expect(
          find.descendant(
            of: find.byType(AddEntryBottomSheet),
            matching: find.text('Old Note'),
          ),
          findsOneWidget,
        );
        expect(find.text('Update You Gave Entry'), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping Delete / Void Entry prompts AdaptiveConfirmDialog and voids entry on confirmation',
      (tester) async {
        final mockRepo = MockLedgerRepository();
        addTearDown(mockRepo.dispose);

        final voidParty = testParty.copyWith(id: 'test_party_void', name: 'Void Customer', netBalanceInCents: 50000);
        final voidEntry = testEntry.copyWith(id: 'test_entry_void', partyId: 'test_party_void', amountInCents: 50000, note: 'Mistaken Entry');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ledgerRepositoryProvider.overrideWithValue(mockRepo),
              ledgerUpdatesStreamProvider.overrideWith((ref) => const Stream.empty()),
              partyDetailProvider('test_party_void').overrideWith((ref) => Future.value(voidParty)),
              partyLedgerEntriesProvider('test_party_void').overrideWith((ref) => Future.value([voidEntry])),
            ],
            child: const MaterialApp(
              home: PartyLedgerScreen(partyId: 'test_party_void'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Tap transaction row to open voucher
        await tester.tap(find.text('Mistaken Entry'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Tap Delete / Void Entry
        await tester.tap(find.text('Delete / Void Entry'));
        await tester.pump();
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
        await tester.pump();
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

        final headerParty = testParty.copyWith(id: 'test_party_header_menu', name: 'Header Menu Customer', netBalanceInCents: 0);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ledgerRepositoryProvider.overrideWithValue(mockRepo),
              ledgerUpdatesStreamProvider.overrideWith((ref) => const Stream.empty()),
              partyDetailProvider('test_party_header_menu').overrideWith((ref) => Future.value(headerParty)),
              partyLedgerEntriesProvider('test_party_header_menu').overrideWith((ref) => Future.value([])),
            ],
            child: const MaterialApp(
              home: PartyLedgerScreen(partyId: 'test_party_header_menu'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Find and tap the 3-dot party options button in top app bar
        final optionsButton = find.byTooltip('Party Options');
        expect(optionsButton, findsOneWidget);
        await tester.tap(optionsButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify party context menu opens with Edit Details and Delete Party
        expect(find.text('Edit Details'), findsOneWidget);
        expect(find.text('Delete Party'), findsOneWidget);
      },
    );
  });
}
