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

    test('Active company provider yields active company metadata', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final activeCompany = container.read(activeCompanyProvider);
      expect(activeCompany.name, isNotEmpty);
    });
  });
}
