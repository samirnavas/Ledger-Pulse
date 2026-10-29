import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_controls.dart';
import '../../core/widgets/adaptive_list_row.dart';
import '../../core/widgets/adaptive_picker.dart';
import '../../core/widgets/adaptive_surface_card.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../data/models/company_model.dart';
import '../../data/models/voucher_model.dart';
import '../../data/services/expense_csv_import_service.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';

enum _ImportStep {
  mapColumns,
  preview,
}

/// Interactive modal sheet built on [DraggableModalSheet] that parses CSV transaction files,
/// configures column mappings via [AdaptiveDropdownField]s, previews rows with [AdaptiveListRow]s,
/// and executes imports using [AdaptiveButton] with [showAppFeedback].
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
    return showAdaptiveDraggableModal<void>(
      context: context,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.40,
      builder: (context, scrollController) => ExpenseCsvImportSheet(
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
  _ImportStep _currentStep = _ImportStep.mapColumns;
  ExpenseCsvImportResult? _parseResult;
  bool _isSaving = false;
  String? _errorMessage;

  // Custom mapping indices (-1 for unmapped)
  int _dateIdx = 0;
  int _amountIdx = 1;
  int _typeIdx = -1;
  int _categoryIdx = -1;
  int _walletIdx = -1;
  int _narrationIdx = -1;

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
      final customMapping = ExpenseCsvColumnMapping(
        dateIndex: _dateIdx,
        amountIndex: _amountIdx,
        typeIndex: _typeIdx,
        categoryIndex: _categoryIdx,
        walletIndex: _walletIdx,
        narrationIndex: _narrationIdx,
      );

      final res = ExpenseCsvImportService.parseTransactionsCsv(
        csvContent: widget.csvContent,
        company: company,
        customMapping: customMapping,
      );

      setState(() {
        _parseResult = res;
        _errorMessage = null;
        // Sync detected mapping on initial load
        if (_dateIdx == 0 && _amountIdx == 1 && _typeIdx == -1) {
          _dateIdx = res.mapping.dateIndex;
          _amountIdx = res.mapping.amountIndex;
          _typeIdx = res.mapping.typeIndex;
          _categoryIdx = res.mapping.categoryIndex;
          _walletIdx = res.mapping.walletIndex;
          _narrationIdx = res.mapping.narrationIndex;
        }
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
        showAppFeedback(
          context,
          'Successfully imported $savedCount transactions!',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        showAppFeedback(
          context,
          'Import failed: $e',
          isError: true,
        );
      }
    }
  }

  List<AdaptivePickerItem<int>> _getPickerItems(List<String> headers) {
    final items = <AdaptivePickerItem<int>>[
      const AdaptivePickerItem(value: -1, label: '-- None / Skip --'),
    ];
    for (int i = 0; i < headers.length; i++) {
      items.add(AdaptivePickerItem(
        value: i,
        label: 'Column ${i + 1}: ${headers[i]}',
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final res = _parseResult;

    return Column(
      children: [
        // Header bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Import CSV Transactions',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${widget.fileName} • Step ${_currentStep == _ImportStep.mapColumns ? "1: Column Mapping" : "2: Preview"}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Divider(color: theme.colorScheme.outlineVariant, height: 1),

        // Body content
        if (_errorMessage != null)
          Expanded(
            child: EmptyStateView(
              icon: Icons.error_outline,
              title: 'Import Error',
              message: _errorMessage!,
            ),
          )
        else if (res == null)
          const Expanded(
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else
          Expanded(
            child: _currentStep == _ImportStep.mapColumns
                ? _buildMappingStep(context, res)
                : _buildPreviewStep(context, res),
          ),
      ],
    );
  }

  Widget _buildMappingStep(
    BuildContext context,
    ExpenseCsvImportResult res,
  ) {
    final pickerItems = _getPickerItems(res.headers);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AdaptiveSurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Map CSV Headers',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Select which column from your CSV file matches each transaction field.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              AdaptiveDropdownField<int>(
                label: 'Date Column',
                value: _dateIdx,
                items: pickerItems,
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _dateIdx = v);
                    _parseCsv();
                  }
                },
              ),
              const SizedBox(height: 12),
              AdaptiveDropdownField<int>(
                label: 'Amount Column',
                value: _amountIdx,
                items: pickerItems,
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _amountIdx = v);
                    _parseCsv();
                  }
                },
              ),
              const SizedBox(height: 12),
              AdaptiveDropdownField<int>(
                label: 'Type Column (Expense/Income)',
                value: _typeIdx,
                items: pickerItems,
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _typeIdx = v);
                    _parseCsv();
                  }
                },
              ),
              const SizedBox(height: 12),
              AdaptiveDropdownField<int>(
                label: 'Category Column',
                value: _categoryIdx,
                items: pickerItems,
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _categoryIdx = v);
                    _parseCsv();
                  }
                },
              ),
              const SizedBox(height: 12),
              AdaptiveDropdownField<int>(
                label: 'Wallet Column',
                value: _walletIdx,
                items: pickerItems,
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _walletIdx = v);
                    _parseCsv();
                  }
                },
              ),
              const SizedBox(height: 12),
              AdaptiveDropdownField<int>(
                label: 'Narration / Description Column',
                value: _narrationIdx,
                items: pickerItems,
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _narrationIdx = v);
                    _parseCsv();
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        AdaptiveButton(
          isFullWidth: true,
          type: AdaptiveButtonType.primary,
          onPressed: () {
            setState(() => _currentStep = _ImportStep.preview);
          },
          child: const Text('Preview Transactions'),
        ),
      ],
    );
  }

  Widget _buildPreviewStep(
    BuildContext context,
    ExpenseCsvImportResult res,
  ) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Summary stats bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _StatBadge(
                label: 'Total Rows',
                value: '${res.totalCount}',
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              _StatBadge(
                label: 'Valid',
                value: '${res.validCount}',
                color: Colors.green,
              ),
              const SizedBox(width: 8),
              _StatBadge(
                label: 'Errors',
                value: '${res.invalidCount}',
                color: res.invalidCount > 0 ? theme.colorScheme.error : Colors.grey,
              ),
            ],
          ),
        ),

        // Preview list with RefreshIndicator.adaptive
        Expanded(
          child: res.rows.isEmpty
              ? const EmptyStateView(
                  icon: Icons.receipt_long_outlined,
                  title: 'No Rows Found',
                  message: 'The selected CSV file contains no valid rows.',
                )
              : RefreshIndicator.adaptive(
                  onRefresh: () async {
                    _parseCsv();
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: res.rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final row = res.rows[index];
                      final isValid = row.isValid;

                      final icon = isValid
                          ? (row.type == VoucherType.income
                              ? Icons.arrow_downward
                              : row.type == VoucherType.transfer
                                  ? Icons.swap_horiz
                                  : Icons.arrow_upward)
                          : Icons.warning_amber_rounded;

                      final iconColor = isValid
                          ? (row.type == VoucherType.income
                              ? Colors.green
                              : theme.colorScheme.primary)
                          : theme.colorScheme.error;

                      final title = row.categoryName ??
                          (row.type == VoucherType.transfer
                              ? 'Transfer'
                              : 'Uncategorized');

                      final subtitle =
                          '${row.dateRaw} • ${row.walletName ?? "Default Wallet"}'
                          '${row.errors.isNotEmpty ? " • Error: ${row.errors.first}" : ""}';

                      return AdaptiveListRow(
                        padding: const EdgeInsets.all(10),
                        showDivider: false,
                        leading: Icon(icon, color: iconColor, size: 20),
                        title: title,
                        subtitle: subtitle,
                        trailing: Text(
                          isValid
                              ? CurrencyFormatter.format(row.amountInCents)
                              : row.amountRaw,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isValid ? null : theme.colorScheme.error,
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: AdaptiveButton(
                  type: AdaptiveButtonType.secondary,
                  onPressed: () {
                    setState(() => _currentStep = _ImportStep.mapColumns);
                  },
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: AdaptiveButton(
                  type: AdaptiveButtonType.primary,
                  isLoading: _isSaving,
                  onPressed: res.validCount == 0 ? null : _importTransactions,
                  child: Text('Import ${res.validCount} Entries'),
                ),
              ),
            ],
          ),
        ),
      ],
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
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
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
