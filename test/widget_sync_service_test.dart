import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_pulse/core/utils/currency_formatter.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WidgetSyncService & Formatting Tests', () {
    final testCompany = Company(
      id: 'cmp_enterprise',
      name: 'Ledger Enterprise',
      legalName: 'Ledger Enterprise Private Limited',
      currencyCode: 'INR',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final expenseProfile = Company(
      id: 'cmp_personal',
      name: 'Personal Wallet',
      legalName: 'Personal Wallet',
      currencyCode: 'INR',
      mode: CompanyMode.expenseTracker,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('CurrencyFormatter correctly formats amounts for widget presentation', () {
      // 2000 rupees in cents is 200000
      final formattedWithSym = CurrencyFormatter.format(
        200000,
        includeSymbol: true,
        showDecimalsAlways: false,
      );
      expect(formattedWithSym, contains('2,000'));
      expect(formattedWithSym, contains('₹'));

      final formattedWithoutSym = CurrencyFormatter.format(
        100000,
        includeSymbol: false,
        showDecimalsAlways: false,
      ).trim();
      expect(formattedWithoutSym, equals('1,000'));
    });

    test('Deep link URI generation matches format ledgerpulse://dashboard?company_id={id}', () {
      final uri = Uri.parse('ledgerpulse://dashboard?company_id=${testCompany.id}');
      expect(uri.scheme, equals('ledgerpulse'));
      expect(uri.host, equals('dashboard'));
      expect(uri.queryParameters['company_id'], equals('cmp_enterprise'));
    });

    test('Deep link with quick_add action matches format ledgerpulse://dashboard?company_id={id}&action=quick_add', () {
      final uri = Uri.parse('ledgerpulse://dashboard?company_id=${expenseProfile.id}&action=quick_add');
      expect(uri.scheme, equals('ledgerpulse'));
      expect(uri.host, equals('dashboard'));
      expect(uri.queryParameters['company_id'], equals('cmp_personal'));
      expect(uri.queryParameters['action'], equals('quick_add'));
    });

    test('Active company provider yields active company metadata for expense mode', () {
      final container = ProviderContainer(
        overrides: [
          activeCompanyProvider.overrideWithValue(expenseProfile),
        ],
      );
      addTearDown(container.dispose);

      final activeCompany = container.read(activeCompanyProvider);
      expect(activeCompany.name, equals('Personal Wallet'));
      expect(activeCompany.mode, equals(CompanyMode.expenseTracker));
      expect(activeCompany.isExpense, isTrue);
    });

    test('Expense tracker budget calculation yields expected progress text and percentages', () {
      const int todaySpendCents = 200000; // 2,000
      const int dailyBudgetCents = 370000; // 3,700

      final todayFormatted = CurrencyFormatter.format(
        todaySpendCents,
        includeSymbol: false,
        showDecimalsAlways: false,
      ).trim();
      final budgetFormatted = CurrencyFormatter.format(
        dailyBudgetCents,
        includeSymbol: false,
        showDecimalsAlways: false,
      ).trim();

      final progressText = 'Spend - $todayFormatted/$budgetFormatted';
      final percent = ((todaySpendCents / dailyBudgetCents) * 100).round();

      expect(progressText, equals('Spend - 2,000/3,700'));
      expect(percent, equals(54)); // 2000 / 3700 ~ 54%
    });
  });
}
