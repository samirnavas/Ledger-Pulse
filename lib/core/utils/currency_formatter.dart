import 'package:intl/intl.dart';

class CurrencyFormatter {
  static const String currencySymbol = '₹';

  /// Resolves currency symbol for a currency code.
  static String getSymbol(String currencyCode) {
    switch (currencyCode.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'JPY':
        return '¥';
      case 'AED':
        return 'AED ';
      case 'CAD':
        return 'CA\$';
      case 'AUD':
        return 'A\$';
      case 'SGD':
        return 'S\$';
      case 'INR':
      default:
        return '₹';
    }
  }

  /// Resolves number formatting locale for a currency code.
  static String getLocale(String currencyCode) {
    switch (currencyCode.toUpperCase()) {
      case 'USD':
      case 'CAD':
      case 'AUD':
      case 'SGD':
        return 'en_US';
      case 'GBP':
        return 'en_GB';
      case 'EUR':
        return 'de_DE';
      case 'JPY':
        return 'ja_JP';
      case 'AED':
        return 'en_AE';
      case 'INR':
      default:
        return 'en_IN';
    }
  }

  /// Formats an integer amount in lowest denomination (paise/cents) to currency string.
  /// Example: 450000 with INR -> "₹4,500.00", with USD -> "$4,500.00".
  static String format(
    int amountInCents, {
    String currencyCode = 'INR',
    bool includeSymbol = true,
    bool showSign = false,
    bool absolute = false,
    bool showDecimalsAlways = true,
  }) {
    final int valueToFormat = absolute ? amountInCents.abs() : amountInCents;
    final double units = valueToFormat / 100.0;
    final sym = getSymbol(currencyCode);
    final loc = getLocale(currencyCode);

    final NumberFormat format = NumberFormat.currency(
      locale: loc,
      symbol: includeSymbol ? (sym.endsWith(' ') ? sym : '$sym ') : '',
      decimalDigits: (!showDecimalsAlways && (amountInCents % 100 == 0)) ? 0 : 2,
    );

    String formatted = format.format(units.abs());

    if (showSign && amountInCents != 0) {
      final String sign = amountInCents > 0 ? '+' : '-';
      formatted = '$sign$formatted';
    } else if (valueToFormat < 0 && !absolute) {
      formatted = '-$formatted';
    }

    return formatted;
  }

  /// Compact representation: e.g., ₹12.8K, ₹1.5L for INR, or $1.5M for USD.
  static String formatCompact(
    int amountInCents, {
    String currencyCode = 'INR',
    bool includeSymbol = true,
  }) {
    final double absUnits = (amountInCents.abs()) / 100.0;
    final sym = getSymbol(currencyCode);
    final String symbolPrefix = includeSymbol ? (sym.endsWith(' ') ? sym : '$sym ') : '';

    if (currencyCode.toUpperCase() == 'INR') {
      if (absUnits >= 10000000) {
        return '$symbolPrefix${(absUnits / 10000000).toStringAsFixed(1)}Cr';
      } else if (absUnits >= 100000) {
        return '$symbolPrefix${(absUnits / 100000).toStringAsFixed(1)}L';
      } else if (absUnits >= 1000) {
        return '$symbolPrefix${(absUnits / 1000).toStringAsFixed(1)}K';
      } else {
        return format(amountInCents, currencyCode: currencyCode, includeSymbol: includeSymbol, showDecimalsAlways: false);
      }
    } else {
      if (absUnits >= 1000000000) {
        return '$symbolPrefix${(absUnits / 1000000000).toStringAsFixed(1)}B';
      } else if (absUnits >= 1000000) {
        return '$symbolPrefix${(absUnits / 1000000).toStringAsFixed(1)}M';
      } else if (absUnits >= 1000) {
        return '$symbolPrefix${(absUnits / 1000).toStringAsFixed(1)}K';
      } else {
        return format(amountInCents, currencyCode: currencyCode, includeSymbol: includeSymbol, showDecimalsAlways: false);
      }
    }
  }

  /// Converts user input string (e.g. "4500.50" or "4,500") to integer cents (450050).
  static int parseToCents(String input) {
    final cleaned = input
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[₹\$€£¥]|AED|CA\$|A\$|S\$'), '')
        .trim();
    if (cleaned.isEmpty) return 0;

    final double? parsed = double.tryParse(cleaned);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return 0;

    return (parsed * 100).round();
  }
}
