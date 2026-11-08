import 'dart:convert';

/// Thrown when an unknown or invalid profile type / company mode is encountered.
class UnknownProfileTypeException implements Exception {
  final String? rawValue;
  const UnknownProfileTypeException(this.rawValue);

  @override
  String toString() =>
      'UnknownProfileTypeException: Unrecognized profile type "$rawValue". '
      'Supported canonical types are "expense" (aliases: "expenseTracker", "expense_tracker") '
      'and "ledger".';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnknownProfileTypeException && other.rawValue == rawValue;

  @override
  int get hashCode => rawValue.hashCode;
}

enum CompanyMode {
  ledger,
  expenseTracker;

  /// Canonical wire/persistence string representation for Expense profiles.
  static const String canonicalExpense = 'expense';

  /// Canonical wire/persistence string representation for Ledger profiles.
  static const String canonicalLedger = 'ledger';

  /// All recognized string representations for Expense profiles.
  static const Set<String> legacyExpenseAliases = {
    'expense',
    'expensetracker',
    'expense_tracker',
  };

  /// All recognized string representations for Ledger profiles.
  static const Set<String> legacyLedgerAliases = {
    'ledger',
  };

  /// Returns the canonical string representation for persistence and wire serialization.
  String get canonicalValue {
    switch (this) {
      case CompanyMode.expenseTracker:
        return canonicalExpense;
      case CompanyMode.ledger:
        return canonicalLedger;
    }
  }

  /// Parses a string into a [CompanyMode], recognizing canonical and legacy values:
  /// - Expense: 'expense', 'expenseTracker', 'expense_tracker'
  /// - Ledger: 'ledger'
  ///
  /// Returns `null` if the value is unrecognized or null.
  static CompanyMode? tryParse(String? name) {
    if (name == null) return null;
    final normalized = name.trim().toLowerCase().replaceAll('-', '_');
    if (legacyExpenseAliases.contains(normalized)) {
      return CompanyMode.expenseTracker;
    }
    if (legacyLedgerAliases.contains(normalized)) {
      return CompanyMode.ledger;
    }
    return null;
  }

  /// Parses a string into a [CompanyMode], recognizing canonical and legacy values.
  ///
  /// Does NOT silently interpret unknown or null values as Ledger.
  /// If [name] is unrecognized and [fallback] is provided, returns [fallback].
  /// Otherwise, throws [UnknownProfileTypeException].
  static CompanyMode fromName(String? name, {CompanyMode? fallback}) {
    final parsed = tryParse(name);
    if (parsed != null) return parsed;
    if (fallback != null) return fallback;
    throw UnknownProfileTypeException(name);
  }
}

enum AppModule {
  parties,
  vouchers,
  inventory,
  gst,
  payroll,
  manufacturing,
  ecommerceSync,
  chequePrinting,
  advancedReports,
  sqlStudio,
  dataImport,
  budgets,
  recurring;

  static const Set<AppModule> allModules = {
    AppModule.parties,
    AppModule.vouchers,
    AppModule.inventory,
    AppModule.gst,
    AppModule.payroll,
    AppModule.manufacturing,
    AppModule.ecommerceSync,
    AppModule.chequePrinting,
    AppModule.advancedReports,
    AppModule.sqlStudio,
    AppModule.dataImport,
    AppModule.budgets,
    AppModule.recurring,
  };

  static AppModule? tryParse(String? name) {
    if (name == null) return null;
    final lower = name.trim().toLowerCase();
    for (final val in AppModule.values) {
      if (val.name.toLowerCase() == lower) {
        return val;
      }
    }
    return null;
  }

  static AppModule? fromName(String? name) => tryParse(name);

  static Set<AppModule> parseSet(dynamic input) {
    if (input == null) return Set.unmodifiable(allModules);
    if (input is String) {
      final trimmed = input.trim();
      if (trimmed.isEmpty || trimmed == 'null') {
        return Set.unmodifiable(allModules);
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return parseSet(decoded);
        }
      } catch (_) {
        return Set.unmodifiable(allModules);
      }
    }
    if (input is Iterable) {
      final result = <AppModule>{};
      for (final item in input) {
        final parsed = tryParse(item?.toString());
        if (parsed != null) {
          result.add(parsed);
        }
      }
      return result;
    }
    return Set.unmodifiable(allModules);
  }
}
