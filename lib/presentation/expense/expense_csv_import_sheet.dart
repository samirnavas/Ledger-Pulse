import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/currency_formatter.dart';
import '../../data/models/company_model.dart';
import '../../data/models/voucher_model.dart';
import '../../data/services/expense_csv_import_service.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';

/// Interactive modal sheet that parses CSV transaction files, previews the rows,
/// shows validation errors, allows column mapping review, and confirms saving.
class ExpenseCsvImportSheet extends ConsumerStatefulWidget {
  final String csvContent;
  final String fileName;

  const ExpenseCsvImportSheet({
    super.key,
    required this.csvContent,
    required this.fileName,
  });

  static Future<void> show({
    required BuildContext context,
    required String csvContent,
    required String fileName,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExpenseCsvImportSheet(
        csvContent: csvContent,
        fileName: fileName,
      ),
    );
  }

  @override
  ConsumerState<ExpenseCsvImportSheet> createState() =>
      _ExpenseCsvImportSheetState();
}

class _ExpenseCsvImportSheetState extends ConsumerState<ExpenseCsvImportSheet> {
  ExpenseCsvImportResult? _parseResult;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _parseCsv();
  }

  void _parseCsv() {
    final company = ref.read(activeCompanyProvider);
    if (!company.isModuleEnabled(AppModule.dataImport)) {
      setState(() {
        _errorMessage =
            'Data Import module is not enabled for this company. Please enable it in Company Settings.';
      });
      return;
    }

    try {
      final res = ExpenseCsvImportService.parseTransactionsCsv(
        csvContent: widget.csvContent,
        company: company,
      );
      setState(() {
        _parseResult = res;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to parse CSV: $e';
      });
    }
  }

  Future<void> _importTransactions() async {
    final res = _parseResult;
    if (res == null || res.validCount == 0) return;

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(expenseRepositoryProvider);
      final categories = await repo.getCategories();
      final wallets = await repo.getWallets();

      final savedCount = await ExpenseCsvImportService.saveImportedTransactions(
        repo: repo,
        rows: res.rows,
        availableCategories: categories,
        availableWallets: wallets,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully imported $savedCount transactions!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Import failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final res = _parseResult;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withAlpha(80),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Import CSV Transactions',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.fileName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Body
          if (_errorMessage != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (res == null)
            const Expanded(
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else
            Expanded(
              child: Column(
                children: [
                  // Summary badge bar
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _StatBadge(
                          label: 'Total Rows',
                          value: '${res.totalCount}',
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 12),
                        _StatBadge(
                          label: 'Valid to Import',
                          value: '${res.validCount}',
                          color: Colors.green,
                        ),
                        const SizedBox(width: 12),
                        _StatBadge(
                          label: 'Errors',
                          value: '${res.invalidCount}',
                          color: res.invalidCount > 0 ? Colors.red : Colors.grey,
                        ),
                      ],
                    ),
                  ),

                  // Preview table
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: res.rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = res.rows[index];
                        final isValid = row.isValid;

                        return Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 8),
                          decoration: BoxDecoration(
                            color: isValid
                                ? Colors.transparent
                                : Colors.red.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: isValid
                                    ? Colors.green.withAlpha(30)
                                    : Colors.red.withAlpha(30),
                                child: Icon(
                                  isValid
                                      ? (row.type == VoucherType.income
                                          ? Icons.arrow_downward
                                          : row.type == VoucherType.transfer
                                              ? Icons.swap_horiz
                                              : Icons.arrow_upward)
                                      : Icons.warning_amber_rounded,
                                  size: 14,
                                  color: isValid ? Colors.green : Colors.red,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          row.categoryName ??
                                              (row.type == VoucherType.transfer
                                                  ? 'Transfer'
                                                  : 'Uncategorized'),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          isValid
                                              ? CurrencyFormatter.format(
                                                  row.amountInCents)
                                              : row.amountRaw,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isValid
                                                ? (row.type == VoucherType.income
                                                    ? Colors.green
                                                    : Colors.redAccent)
                                                : Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${row.dateRaw} • ${row.walletName ?? "Default Wallet"}${row.toWalletName != null ? " → ${row.toWalletName}" : ""}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.black54,
                                      ),
                                    ),
                                    if (row.narration?.isNotEmpty == true)
                                      Text(
                                        row.narration!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: isDark
                                              ? Colors.white38
                                              : Colors.black38,
                                        ),
                                      ),
                                    if (row.errors.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          row.errors.join(', '),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.red,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // Footer actions
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: (_isSaving || res.validCount == 0)
                            ? null
                            : _importTransactions,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? const CircularProgressIndicator.adaptive(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              )
                            : Text(
                                'Import ${res.validCount} Transactions',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
