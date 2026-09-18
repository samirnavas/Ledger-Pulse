import 'package:intl/intl.dart';

class CurrencyFormatter {
  static const String currencySymbol = '₹';

  /// Formats an integer amount in lowest denomination (paise/cents) to INR currency string.
  /// Example: 450000 -> "₹4,500.00" or "₹4,500" if paise is 0 and showPaise is false.
  static String format(
    int amountInCents, {
    bool includeSymbol = true,
    bool showSign = false,
    bool absolute = false,
    bool showDecimalsAlways = true,
  }) {
    final int valueToFormat = absolute ? amountInCents.abs() : amountInCents;
    final double rupees = valueToFormat / 100.0;

    // Use Indian currency grouping (lakhs, crores)
    final NumberFormat format = NumberFormat.currency(
      locale: 'en_IN',
      symbol: includeSymbol ? '$currencySymbol ' : '',
      decimalDigits: (!showDecimalsAlways && (amountInCents % 100 == 0)) ? 0 : 2,
    );

    String formatted = format.format(rupees.abs());

    if (showSign && amountInCents != 0) {
      final String sign = amountInCents > 0 ? '+' : '-';
      formatted = '$sign$formatted';
    } else if (valueToFormat < 0 && !absolute) {
      formatted = '-$formatted';
    }

    return formatted;
  }

  /// Compact representation: e.g., ₹12.8K, ₹1.5L
  static String formatCompact(int amountInCents, {bool includeSymbol = true}) {
    final double absRupees = (amountInCents.abs()) / 100.0;
    final String sym = includeSymbol ? '$currencySymbol ' : '';

    if (absRupees >= 10000000) {
      return '$sym${(absRupees / 10000000).toStringAsFixed(1)}Cr';
    } else if (absRupees >= 100000) {
      return '$sym${(absRupees / 100000).toStringAsFixed(1)}L';
    } else if (absRupees >= 1000) {
      return '$sym${(absRupees / 1000).toStringAsFixed(1)}K';
    } else {
      return format(amountInCents, includeSymbol: includeSymbol, showDecimalsAlways: false);
    }
  }

  /// Converts user input string (e.g. "4500.50" or "4500") to integer cents (450050).
  static int parseToCents(String input) {
    final cleaned = input.replaceAll(',', '').replaceAll('₹', '').trim();
    if (cleaned.isEmpty) return 0;

    final double? parsed = double.tryParse(cleaned);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return 0;

    return (parsed * 100).round();
  }
}
