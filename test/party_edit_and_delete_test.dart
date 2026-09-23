import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/mock/mock_ledger_repository.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/presentation/home/party_list_tab.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Party List Edit & Delete Flow Tests', () {
    testWidgets('3-dot menu or long press opens contextual menu with Edit and Delete options',
        (WidgetTester tester) async {
      final repo = MockLedgerRepository();
      addTearDown(repo.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ledgerRepositoryProvider.overrideWithValue(repo),
            ledgerUpdatesStreamProvider.overrideWith((ref) => const Stream.empty()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PartyListTab(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify parties are rendered
      expect(find.text('Rahul Sharma'), findsOneWidget);

      // Tap 3-dot options button for Rahul Sharma
      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify contextual menu options
      expect(find.text('Edit Details'), findsOneWidget);
      expect(find.text('Delete Party'), findsOneWidget);
    });

    testWidgets('Tapping Edit Details opens AddPartyDialog in Edit Mode pre-populated',
        (WidgetTester tester) async {
      final repo = MockLedgerRepository();
      addTearDown(repo.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ledgerRepositoryProvider.overrideWithValue(repo),
            ledgerUpdatesStreamProvider.overrideWith((ref) => const Stream.empty()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PartyListTab(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap options and select "Edit Details"
      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Edit Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Verify AddPartyDialog is opened with Edit Customer title and prefilled fields
      expect(find.text('Edit Customer'), findsOneWidget);
      expect(find.text('Rahul Sharma'), findsWidgets);
      expect(find.text('Save Changes'), findsOneWidget);
    });

    testWidgets('Tapping Delete on unsettled party displays safety alert dialog with balance',
        (WidgetTester tester) async {
      final repo = MockLedgerRepository();
      addTearDown(repo.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ledgerRepositoryProvider.overrideWithValue(repo),
            ledgerUpdatesStreamProvider.overrideWith((ref) => const Stream.empty()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PartyListTab(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Rahul Sharma has active balance (₹4,500.00 = 450000 cents)
      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Delete Party'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify alert dialog prevents deletion
      expect(find.text('Cannot Delete Party'), findsOneWidget);
      expect(
        find.textContaining('Cannot delete a party with an outstanding balance of ₹ 4,500.00'),
        findsOneWidget,
      );
      expect(find.text('OK'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('Tapping Delete on 0-balance party confirms and deletes party',
        (WidgetTester tester) async {
      final repo = MockLedgerRepository();
      addTearDown(repo.dispose);

      // Add a settled 0-balance party using runAsync for the delayed future
      final zeroParty = Party(
        id: 'party_zero_test',
        name: 'Zero Balance Customer',
        phoneNumber: '+91 9123400000',
        type: PartyType.customer,
        netBalanceInCents: 0,
        lastUpdated: DateTime.now().add(const Duration(hours: 1)),
      );
      await tester.runAsync(() => repo.addParty(zeroParty));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ledgerRepositoryProvider.overrideWithValue(repo),
            ledgerUpdatesStreamProvider.overrideWith((ref) => const Stream.empty()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PartyListTab(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Zero Balance Customer'), findsOneWidget);

      // Open options for the newly added zero balance party (first in sorted list)
      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Delete Party'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify confirmation dialog
      expect(find.text('Delete Party?'), findsOneWidget);
      expect(
        find.textContaining('Are you sure you want to delete Zero Balance Customer?'),
        findsOneWidget,
      );

      // Confirm deletion
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify SnackBar and party removal
      expect(find.text('Zero Balance Customer deleted and archived.'), findsOneWidget);
      expect(find.text('Zero Balance Customer'), findsNothing);

      // Advance past SnackBar timer and dismissal animation
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}


