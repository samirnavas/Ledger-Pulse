import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/widgets/adaptive_chip.dart';
import 'package:ledger_pulse/core/widgets/adaptive_controls.dart';
import 'package:ledger_pulse/core/widgets/adaptive_list_row.dart';
import 'package:ledger_pulse/core/widgets/adaptive_section_header.dart';
import 'package:ledger_pulse/core/widgets/adaptive_surface_card.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/presentation/expense/expense_csv_import_sheet.dart';
import 'package:ledger_pulse/presentation/expense/expense_reports_screen.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/expense_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final company = Company(
    id: 'cmp_ui7_test',
    name: 'UI7 Test Company',
    legalName: 'UI7 Test Company Inc',
    currencyCode: 'USD',
    mode: CompanyMode.expenseTracker,
    enabledModules: {AppModule.dataImport, AppModule.budgets},
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final category = AccountModel(
    id: 'cat_groceries',
    companyId: company.id,
    code: '5100',
    name: 'Groceries',
    type: AccountType.expense,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final wallet = AccountModel(
    id: 'w_cash',
    companyId: company.id,
    code: '1001',
    name: 'Main Wallet',
    type: AccountType.asset,
    currentBalanceInCents: 50000,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final now = DateTime.now();
  final List<VoucherModel> testVouchers = [
    VoucherModel(
      id: 'v_1',
      companyId: company.id,
      voucherNumber: 'EXP-1',
      date: DateTime(now.year, now.month, 5),
      type: VoucherType.expense,
      totalAmountInCents: 3500, // $35.00
      walletAccountId: wallet.id,
      categoryAccountId: category.id,
      narration: 'Grocery run',
      createdAt: now,
      updatedAt: now,
    ),
    VoucherModel(
      id: 'v_2',
      companyId: company.id,
      voucherNumber: 'INC-1',
      date: DateTime(now.year, now.month, 10),
      type: VoucherType.income,
      totalAmountInCents: 10000, // $100.00
      walletAccountId: wallet.id,
      categoryAccountId: category.id,
      narration: 'Salary bonus',
      createdAt: now,
      updatedAt: now,
    ),
  ];

  Widget buildAppWithScreen({
    required TargetPlatform platform,
    required Widget child,
  }) {
    return ProviderScope(
      overrides: [
        activeCompanyProvider.overrideWithValue(company),
        transactionsProvider.overrideWith((ref) async => testVouchers),
        categoriesProvider.overrideWith((ref) async => [category]),
        walletsProvider.overrideWith((ref) async => [wallet]),
      ],
      child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          platform: platform,
        ),
        home: Scaffold(body: child),
      ),
    );
  }

  group('Prompt UI-7 Reports & Export Sheet Tests', () {
    testWidgets('Reports tab renders on Android with AdaptiveChips and Section Cards',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildAppWithScreen(
          platform: TargetPlatform.android,
          child: const ExpenseReportsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Period selector chip row
      expect(find.byType(AdaptiveChipRow<ReportDateFilter>), findsOneWidget);
      expect(find.text('This Month'), findsWidgets);
      expect(find.text('Last 3 Months'), findsWidgets);
      expect(find.text('This Year'), findsWidgets);
      expect(find.text('Custom'), findsWidgets);

      // Report section cards & headers
      expect(find.byType(AdaptiveSurfaceCard), findsNWidgets(4));
      expect(find.byType(AdaptiveSectionHeader), findsNWidgets(4));
      expect(find.text('Spending by category'), findsOneWidget);
      expect(find.text('Monthly trend'), findsOneWidget);
      expect(find.text('Income vs expense'), findsOneWidget);
      expect(find.text('Wallet balance history'), findsOneWidget);
    });

    testWidgets('Reports tab renders on iOS with Cupertino styling', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildAppWithScreen(
          platform: TargetPlatform.iOS,
          child: const ExpenseReportsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdaptiveChipRow<ReportDateFilter>), findsOneWidget);
      expect(find.byType(AdaptiveSurfaceCard), findsNWidgets(4));
      expect(find.byType(AdaptiveSectionHeader), findsNWidgets(4));
    });

    testWidgets('Export sheet opens with showAdaptiveFormSheet and AdaptiveListRows',
        (tester) async {
      await tester.pumpWidget(
        buildAppWithScreen(
          platform: TargetPlatform.android,
          child: Builder(
            builder: (context) {
              return Consumer(
                builder: (context, ref, child) {
                  return ElevatedButton(
                    onPressed: () {
                      ExpenseReportsScreen.showExportSheet(
                        context: context,
                        ref: ref,
                        transactions: testVouchers,
                        dateRange: (DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
                      );
                    },
                    child: const Text('Open Export'),
                  );
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Export'));
      await tester.pumpAndSettle();

      // Verify adaptive form sheet title and rows
      expect(find.text('Export Report'), findsOneWidget);
      expect(find.text('Export as CSV'), findsOneWidget);
      expect(find.text('Export as PDF'), findsOneWidget);
      expect(find.byType(AdaptiveListRow), findsNWidgets(2));
      expect(find.byType(ListTile), findsNothing);
    });
  });

  group('Prompt UI-7 CSV Import Sheet Tests', () {
    const sampleCsv = '''
Date,Amount,Type,Category,Wallet,Narration
2026-10-15,45.50,Expense,Groceries,Main Wallet,Weekly store purchase
2026-10-16,120.00,Income,Salary,Main Wallet,Freelance payment
''';

    testWidgets('CSV import sheet step layout and column mapping flow', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildAppWithScreen(
          platform: TargetPlatform.android,
          child: const ExpenseCsvImportSheet(
            csvContent: sampleCsv,
            fileName: 'sample_txns.csv',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: Column Mapping
      expect(find.text('Import CSV Transactions'), findsOneWidget);
      expect(find.text('Map CSV Headers'), findsOneWidget);
      expect(find.byType(AdaptiveDropdownField<int>), findsNWidgets(6));

      // Advance to Step 2: Preview
      final previewText = find.text('Preview Transactions');
      expect(previewText, findsOneWidget);
      await tester.tap(previewText);
      await tester.pumpAndSettle();

      // Step 2: Preview with AdaptiveListRows
      expect(find.text('Total Rows'), findsOneWidget);
      expect(find.text('Valid'), findsOneWidget);
      expect(find.byType(AdaptiveListRow), findsWidgets);
      expect(find.text('Back'), findsOneWidget);
    });
  });
}
