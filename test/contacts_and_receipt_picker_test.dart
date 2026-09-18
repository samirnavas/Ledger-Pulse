import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';
import 'package:ledger_pulse/presentation/home/add_party_dialog.dart';
import 'package:ledger_pulse/presentation/ledger/add_entry_bottom_sheet.dart';

void main() {
  group('AddPartyDialog & AddEntryBottomSheet Feature Tests', () {
    testWidgets('AddPartyDialog renders Import from Contacts button and form fields',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AddPartyDialog(initialType: PartyType.customer),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.contacts_rounded), findsOneWidget);
      expect(find.text('Contact / Business Name'), findsOneWidget);
      expect(find.text('Phone Number'), findsOneWidget);
      expect(find.text('Save & Open Ledger'), findsOneWidget);
    });

    testWidgets('AddEntryBottomSheet renders custom keypad, quick presets, and attach bill button',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AddEntryBottomSheet(
                partyId: 'party_1',
                partyName: 'Sharma Traders',
                initialType: EntryType.gave,
              ),
            ),
          ),
        ),
      );

      // Verify custom keypad and quick preset chips
      expect(find.text('+₹100'), findsOneWidget);
      expect(find.text('+₹500'), findsOneWidget);
      expect(find.text('+₹1000'), findsOneWidget);
      expect(find.text('+₹5000'), findsOneWidget);
      expect(find.text('Attach Bill'), findsOneWidget);
      expect(find.text('Save You Gave Entry'), findsOneWidget);

      // Test tapping preset chip
      await tester.tap(find.text('+₹500'));
      await tester.pump();
      expect(find.text('500'), findsOneWidget);

      // Test tapping keypad digits
      await tester.ensureVisible(find.text('00'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('00'));
      await tester.pump();
      expect(find.text('50000'), findsOneWidget);
    });
  });
}
