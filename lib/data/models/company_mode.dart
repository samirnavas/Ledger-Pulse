import 'dart:convert';

enum CompanyMode {
  ledger,
  expenseTracker;

  static CompanyMode fromName(String? name, {CompanyMode fallback = CompanyMode.ledger}) {
    if (name == null) return fallback;
    final lower = name.trim().toLowerCase();
    for (final val in CompanyMode.values) {
      if (val.name.toLowerCase() == lower) {
        return val;
      }
    }
    return fallback;
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
