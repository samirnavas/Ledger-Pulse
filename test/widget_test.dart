import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_pulse/main.dart';
import 'package:ledger_pulse/core/constants/strings.dart';

import 'package:ledger_pulse/data/mock/mock_ledger_repository.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';

void main() {
  testWidgets('LedgerPulseApp renders Dashboard with metrics and parties',
      (WidgetTester tester) async {
    final mockRepo = MockLedgerRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ledgerRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: const LedgerPulseApp(),
      ),
    );

    // Initial pump
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify top metric cards are visible
    expect(find.text(AppStrings.youWillGet), findsOneWidget);
    expect(find.text(AppStrings.youWillGive), findsOneWidget);

    // Verify Customers tab is rendered
    expect(find.text(AppStrings.customersTab), findsOneWidget);
    expect(find.text(AppStrings.suppliersTab), findsOneWidget);

    // Verify search bar
    expect(find.text(AppStrings.searchHint), findsOneWidget);
  });
}
