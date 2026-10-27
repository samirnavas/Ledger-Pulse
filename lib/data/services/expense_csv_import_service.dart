import 'dart:convert';
import 'package:intl/intl.dart';

import '../../domain/exceptions/ledger_exceptions.dart';
import '../local/drift_expense_repository.dart';
import '../models/account_model.dart';
import '../models/company_model.dart';
import '../models/voucher_model.dart';

/// Mapping configuration indicating which CSV column index maps to which transaction field.
class ExpenseCsvColumnMapping {
  final int dateIndex;
  final int amountIndex;
  final int typeIndex;
  final int categoryIndex;
  final int walletIndex;
  final int toWalletIndex;
  final int narrationIndex;
  final int referenceIndex;

  const ExpenseCsvColumnMapping({
    this.dateIndex = 0,
    this.amountIndex = 1,
    this.typeIndex = -1,
    this.categoryIndex = -1,
    this.walletIndex = -1,
    this.toWalletIndex = -1,
    this.narrationIndex = -1,
    this.referenceIndex = -1,
  });

  /// Automatically detects column mappings from the given CSV header row.
  static ExpenseCsvColumnMapping detectFromHeaders(List<String> rawHeaders) {
    final headers = rawHeaders.map((h) => h.replaceAll('"', '').trim().toLowerCase()).toList();

    int find(List<String> synonyms) {
      for (final s in synonyms) {
        final idx = headers.indexWhere((h) => h.contains(s));
        if (idx != -1) return idx;
      }
      return -1;
    }

    final dateIdx = find(['date', 'time', 'txn date', 'day']);
    final amountIdx = find(['amount', 'spent', 'received', 'total', 'value', 'price', 'inr', 'sum']);
    final typeIdx = find(['type', 'kind', 'transaction type', 'txn type']);
    final catIdx = find(['category', 'cat', 'expense category', 'head']);
    final walletIdx = find(['wallet', 'from wallet', 'account', 'from account', 'bank', 'mode', 'payment mode']);
    final toWalletIdx = find(['to wallet', 'to account', 'destination', 'target wallet', 'target']);
    final narrationIdx = find(['narration', 'note', 'notes', 'description', 'remarks', 'memo']);
    final refIdx = find(['reference', 'ref', 'voucher no', 'voucher', 'cheque', 'id']);

    return ExpenseCsvColumnMapping(
      dateIndex: dateIdx != -1 ? dateIdx : 0,
      amountIndex: amountIdx != -1 ? amountIdx : (headers.length > 1 ? 1 : 0),
      typeIndex: typeIdx,
      categoryIndex: catIdx,
      walletIndex: walletIdx,
      toWalletIndex: toWalletIdx,
      narrationIndex: narrationIdx,
      referenceIndex: refIdx,
    );
  }
}

/// Represents a single parsed row from the imported CSV file.
class ParsedExpenseTransaction {
  final int rowIndex;
  final DateTime? date;
  final String dateRaw;
  final int amountInCents;
  final String amountRaw;
  final VoucherType type;
  final String? categoryName;
  final String? walletName;
  final String? toWalletName;
  final String? narration;
  final String? referenceNumber;
  final List<String> errors;

  const ParsedExpenseTransaction({
    required this.rowIndex,
    required this.date,
    required this.dateRaw,
    required this.amountInCents,
    required this.amountRaw,
    required this.type,
    this.categoryName,
    this.walletName,
    this.toWalletName,
    this.narration,
    this.referenceNumber,
    this.errors = const [],
  });

  bool get isValid => errors.isEmpty && amountInCents > 0 && date != null;
  double get amount => amountInCents / 100.0;
}

/// Result of parsing an expense transactions CSV.
class ExpenseCsvImportResult {
  final List<ParsedExpenseTransaction> rows;
  final List<String> warnings;
  final ExpenseCsvColumnMapping mapping;
  final List<String> headers;

  const ExpenseCsvImportResult({
    required this.rows,
    required this.warnings,
    required this.mapping,
    required this.headers,
  });

  int get totalCount => rows.length;
  int get validCount => rows.where((r) => r.isValid).length;
  int get invalidCount => rows.where((r) => !r.isValid).length;
}

/// Service providing CSV importing of transactions with column mapping and preview validation.
/// Guarded behind [AppModule.dataImport]. Modelled after [DataImportService].
class ExpenseCsvImportService {
  /// Throws [ModuleDisabledException] if dataImport module is not enabled for company
  static void verifyModuleEnabled(Company company) {
    if (!company.isModuleEnabled(AppModule.dataImport)) {
      throw ModuleDisabledException(AppModule.dataImport);
    }
  }

  /// Parses CSV transactions with automatic or custom column mapping.
  static ExpenseCsvImportResult parseTransactionsCsv({
    required String csvContent,
    required Company company,
    ExpenseCsvColumnMapping? customMapping,
  }) {
    verifyModuleEnabled(company);

    final lines = const LineSplitter().convert(csvContent);
    if (lines.isEmpty) {
      return const ExpenseCsvImportResult(
        rows: [],
        warnings: ['Empty CSV file provided'],
        mapping: ExpenseCsvColumnMapping(),
        headers: [],
      );
    }

    // Extract headers (ignoring potential UTF-8 BOM)
    String firstLine = lines.first.trim();
    if (firstLine.startsWith('\uFEFF')) {
      firstLine = firstLine.substring(1);
    }

    // Skip metadata lines until header row is encountered
    int headerLineIdx = 0;
    while (headerLineIdx < lines.length) {
      final line = lines[headerLineIdx].trim();
      if (line.isNotEmpty && (line.contains(',') || line.contains(';'))) {
        final split = _splitCsvLine(line);
        final lower = split.map((s) => s.toLowerCase()).toList();
        if (lower.any((s) => s.contains('date') || s.contains('amount') || s.contains('voucher') || s.contains('type'))) {
          firstLine = line;
          break;
        }
      }
      headerLineIdx++;
    }

    if (headerLineIdx >= lines.length) {
      headerLineIdx = 0;
      firstLine = lines.first.trim();
    }

    final headers = _splitCsvLine(firstLine);
    final mapping = customMapping ?? ExpenseCsvColumnMapping.detectFromHeaders(headers);

    final List<ParsedExpenseTransaction> rows = [];
    final List<String> warnings = [];

    for (int i = headerLineIdx + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (line.startsWith('"--- SUMMARY') || line.startsWith('--- SUMMARY')) break;

      final cols = _splitCsvLine(line);
      final List<String> rowErrors = [];

      // 1. Date parsing
      final dateRaw = (mapping.dateIndex >= 0 && mapping.dateIndex < cols.length)
          ? cols[mapping.dateIndex].trim()
          : '';
      final parsedDate = _parseDate(dateRaw);
      if (parsedDate == null) {
        rowErrors.add('Invalid date: "$dateRaw"');
      }

      // 2. Amount parsing
      final amountRaw = (mapping.amountIndex >= 0 && mapping.amountIndex < cols.length)
          ? cols[mapping.amountIndex].trim()
          : '';
      final parsedAmountCents = _parseAmountToCents(amountRaw);
      if (parsedAmountCents <= 0) {
        rowErrors.add('Invalid amount: "$amountRaw"');
      }

      // 3. Type parsing
      final typeRaw = (mapping.typeIndex >= 0 && mapping.typeIndex < cols.length)
          ? cols[mapping.typeIndex].trim()
          : '';
      final parsedType = _parseType(typeRaw);

      // 4. Category
      final categoryRaw = (mapping.categoryIndex >= 0 && mapping.categoryIndex < cols.length)
          ? cols[mapping.categoryIndex].trim()
          : null;

      // 5. Wallet
      final walletRaw = (mapping.walletIndex >= 0 && mapping.walletIndex < cols.length)
          ? cols[mapping.walletIndex].trim()
          : null;

      // 6. To Wallet (for transfers)
      final toWalletRaw = (mapping.toWalletIndex >= 0 && mapping.toWalletIndex < cols.length)
          ? cols[mapping.toWalletIndex].trim()
          : null;

      // 7. Narration / Notes
      final narrationRaw = (mapping.narrationIndex >= 0 && mapping.narrationIndex < cols.length)
          ? cols[mapping.narrationIndex].trim()
          : null;

      // 8. Reference
      final refRaw = (mapping.referenceIndex >= 0 && mapping.referenceIndex < cols.length)
          ? cols[mapping.referenceIndex].trim()
          : null;

      rows.add(
        ParsedExpenseTransaction(
          rowIndex: i + 1,
          date: parsedDate,
          dateRaw: dateRaw,
          amountInCents: parsedAmountCents,
          amountRaw: amountRaw,
          type: parsedType,
          categoryName: categoryRaw?.isNotEmpty == true ? categoryRaw : null,
          walletName: walletRaw?.isNotEmpty == true ? walletRaw : null,
          toWalletName: toWalletRaw?.isNotEmpty == true ? toWalletRaw : null,
          narration: narrationRaw?.isNotEmpty == true ? narrationRaw : null,
          referenceNumber: refRaw?.isNotEmpty == true ? refRaw : null,
          errors: rowErrors,
        ),
      );
    }

    if (rows.isEmpty) {
      warnings.add('No valid transaction rows found in CSV.');
    }

    return ExpenseCsvImportResult(
      rows: rows,
      warnings: warnings,
      mapping: mapping,
      headers: headers,
    );
  }

  /// Saves valid parsed transactions into the database through [DriftExpenseRepository].
  static Future<int> saveImportedTransactions({
    required DriftExpenseRepository repo,
    required List<ParsedExpenseTransaction> rows,
    required List<AccountModel> availableCategories,
    required List<AccountModel> availableWallets,
  }) async {
    int savedCount = 0;
    if (availableWallets.isEmpty) {
      throw StateError('Cannot import transactions: No wallets exist for the active company.');
    }

    final defaultWallet = availableWallets.first;

    for (final row in rows) {
      if (!row.isValid) continue;

      // Resolve wallet
      AccountModel wallet = defaultWallet;
      if (row.walletName != null) {
        final match = availableWallets.firstWhere(
          (w) => w.name.trim().toLowerCase() == row.walletName!.trim().toLowerCase(),
          orElse: () => defaultWallet,
        );
        wallet = match;
      }

      // Resolve category
      AccountModel? category;
      if (row.categoryName != null) {
        category = availableCategories.firstWhere(
          (c) => c.name.trim().toLowerCase() == row.categoryName!.trim().toLowerCase(),
          orElse: () => availableCategories.isNotEmpty ? availableCategories.first : defaultWallet,
        );
      } else if (availableCategories.isNotEmpty) {
        category = availableCategories.first;
      }

      if (row.type == VoucherType.transfer) {
        AccountModel toWallet = availableWallets.length > 1
            ? availableWallets.firstWhere((w) => w.id != wallet.id)
            : defaultWallet;

        if (row.toWalletName != null) {
          final toMatch = availableWallets.firstWhere(
            (w) => w.name.trim().toLowerCase() == row.toWalletName!.trim().toLowerCase() && w.id != wallet.id,
            orElse: () => toWallet,
          );
          toWallet = toMatch;
        }

        if (wallet.id != toWallet.id) {
          await repo.addTransfer(
            walletAccountId: wallet.id,
            toWalletAccountId: toWallet.id,
            amountInCents: row.amountInCents,
            date: row.date,
            narration: row.narration,
            referenceNumber: row.referenceNumber,
          );
          savedCount++;
        }
      } else if (row.type == VoucherType.income) {
        final catId = category?.id ?? wallet.id;
        await repo.addIncome(
          categoryAccountId: catId,
          walletAccountId: wallet.id,
          amountInCents: row.amountInCents,
          date: row.date,
          narration: row.narration,
          referenceNumber: row.referenceNumber,
        );
        savedCount++;
      } else {
        // Expense
        final catId = category?.id ?? wallet.id;
        await repo.addExpense(
          categoryAccountId: catId,
          walletAccountId: wallet.id,
          amountInCents: row.amountInCents,
          date: row.date,
          narration: row.narration,
          referenceNumber: row.referenceNumber,
        );
        savedCount++;
      }
    }

    return savedCount;
  }

  static DateTime? _parseDate(String raw) {
    if (raw.isEmpty) return null;
    final cleaned = raw.trim();

    // 1. Try ISO8601
    final iso = DateTime.tryParse(cleaned);
    if (iso != null) return iso;

    // 2. Try common formats
    final formats = [
      'dd/MM/yyyy',
      'dd-MM-yyyy',
      'yyyy-MM-dd',
      'MM/dd/yyyy',
      'yyyy/MM/dd',
      'd/M/yyyy',
      'd-M-yyyy',
      'dd MMM yyyy',
      'd MMM yyyy',
    ];

    for (final fmt in formats) {
      try {
        return DateFormat(fmt).parseStrict(cleaned);
      } catch (_) {
        // Intentionally try next date format candidate when parsing CSV dates
      }
    }

    return null;
  }

  static int _parseAmountToCents(String raw) {
    if (raw.isEmpty) return 0;
    // Clean currency symbols, commas, spaces
    final cleaned = raw
        .replaceAll(RegExp(r'[^\d.-]'), '')
        .trim();
    if (cleaned.isEmpty) return 0;

    final val = double.tryParse(cleaned);
    if (val == null) return 0;
    return (val.abs() * 100).round();
  }

  static VoucherType _parseType(String raw) {
    final lower = raw.trim().toLowerCase();
    if (lower.contains('income') || lower.contains('credit') || lower.contains('received') || lower.contains('deposit')) {
      return VoucherType.income;
    }
    if (lower.contains('transfer') || lower.contains('trf') || lower.contains('contra')) {
      return VoucherType.transfer;
    }
    return VoucherType.expense;
  }

  static List<String> _splitCsvLine(String line) {
    final List<String> result = [];
    final matches = RegExp(r'(?:^|,)(?:"([^"]*)"|([^,]*))').allMatches(line);
    for (final m in matches) {
      final val = m.group(1) ?? m.group(2) ?? '';
      result.add(val.trim());
    }
    return result;
  }
}
