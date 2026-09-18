import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/utils/currency_formatter.dart';

void main() {
  group('CurrencyFormatter Tests', () {
    test('Formats zero cents properly', () {
      final formatted = CurrencyFormatter.format(0);
      expect(formatted, contains('0.00'));
    });

    test('Formats positive amount in Indian numbering format', () {
      // ₹4,500.00
      final formatted = CurrencyFormatter.format(450000);
      expect(formatted, contains('4,500.00'));
    });

    test('Formats negative amount with sign or absolute', () {
      // -₹12,800.00
      final formatted = CurrencyFormatter.format(-1280000);
      expect(formatted, contains('12,800.00'));
      expect(formatted.startsWith('-'), isTrue);

      final absolute = CurrencyFormatter.format(-1280000, absolute: true);
      expect(absolute.startsWith('-'), isFalse);
    });

    test('Formats compact numbers correctly', () {
      // ₹4,500 -> ₹4.5K
      expect(CurrencyFormatter.formatCompact(450000), contains('4.5K'));
      // ₹1,50,000 -> ₹1.5L
      expect(CurrencyFormatter.formatCompact(15000000), contains('1.5L'));
    });

    test('Parses input strings to integer cents accurately', () {
      expect(CurrencyFormatter.parseToCents('100'), equals(10000));
      expect(CurrencyFormatter.parseToCents('100.50'), equals(10050));
      expect(CurrencyFormatter.parseToCents('₹ 4,500.25'), equals(450025));
      expect(CurrencyFormatter.parseToCents(''), equals(0));
    });
  });
}
