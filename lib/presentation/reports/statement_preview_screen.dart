import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/strings.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../data/models/transaction_model.dart';
import '../providers/ledger_providers.dart';

enum StatementPeriod {
  thirtyDays,
  allTime;

  String get label {
    switch (this) {
      case StatementPeriod.thirtyDays:
        return AppStrings.last30Days;
      case StatementPeriod.allTime:
        return AppStrings.allTime;
    }
  }
}

class StatementPreviewScreen extends ConsumerStatefulWidget {
  final String partyId;

  const StatementPreviewScreen({
    super.key,
    required this.partyId,
  });

  @override
  ConsumerState<StatementPreviewScreen> createState() =>
      _StatementPreviewScreenState();
}

class _StatementPreviewScreenState
    extends ConsumerState<StatementPreviewScreen> {
  StatementPeriod _selectedPeriod = StatementPeriod.allTime;

  void _showExportPreview(String type) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              type == 'WhatsApp'
                  ? Icons.chat_rounded
                  : Icons.picture_as_pdf_rounded,
              color: type == 'WhatsApp'
                  ? const Color(0xFF25D366)
                  : AppColors.payableRed,
            ),
            const SizedBox(width: 10),
            Text('$type Export'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              type == 'WhatsApp'
                  ? 'Ledger statement formatted for instant WhatsApp sharing:'
                  : 'PDF statement generated successfully:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceCardM3,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '📄 LedgerPulse_${widget.partyId}_Statement.pdf\nPeriod: ${_selectedPeriod.label}\nStatus: Ready to send',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppColors.textPrimaryLight,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Statement shared via $type!'),
                  backgroundColor: AppColors.primaryBlue,
                ),
              );
            },
            child: Text('Share Now'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);

    final partyAsync = ref.watch(partyDetailProvider(widget.partyId));
    final entriesAsync = ref.watch(partyLedgerEntriesProvider(widget.partyId));

    return AdaptiveScaffold(
      title: AppStrings.statementPreview,
      body: partyAsync.when(
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (party) {
          return entriesAsync.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (err, _) => Center(child: Text('Error: $err')),
            data: (allEntries) {
              final now = DateTime.now();
              final thirtyDaysAgo = now.subtract(const Duration(days: 30));

              final filteredEntries = _selectedPeriod == StatementPeriod.thirtyDays
                  ? allEntries
                      .where((e) => e.date.isAfter(thirtyDaysAgo))
                      .toList()
                  : allEntries;

              int totalGave = 0;
              int totalGot = 0;
              for (final e in filteredEntries) {
                if (e.type == EntryType.gave) {
                  totalGave += e.amountInCents;
                } else {
                  totalGot += e.amountInCents;
                }
              }

              return Column(
                children: [
                  // 1. Period Selector & Statement Summary Card
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        // Filter Segmented Toggle
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(child: Text(AppStrings.allTime)),
                                selected:
                                    _selectedPeriod == StatementPeriod.allTime,
                                selectedColor: AppColors.primaryBlueLight,
                                onSelected: (val) {
                                  if (val) {
                                    setState(() => _selectedPeriod =
                                        StatementPeriod.allTime);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(child: Text(AppStrings.last30Days)),
                                selected:
                                    _selectedPeriod == StatementPeriod.thirtyDays,
                                selectedColor: AppColors.primaryBlueLight,
                                onSelected: (val) {
                                  if (val) {
                                    setState(() => _selectedPeriod =
                                        StatementPeriod.thirtyDays);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Statement Header Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isIos
                                ? CupertinoColors.white
                                : AppColors.surfaceWhite,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                                color: AppColors.borderLight, width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    party.name,
                                    style: AppTypography.headlineMedium,
                                  ),
                                  Text(
                                    party.type.displayName,
                                    style: AppTypography.labelSmall.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryBlue,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(party.phoneNumber,
                                  style: AppTypography.bodyMedium),
                              const Divider(height: 24),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Total Gave',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.payableRed,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        CurrencyFormatter.format(totalGave),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.payableRed,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text(
                                        'Total Got',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.receivableGreen,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        CurrencyFormatter.format(totalGot),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.receivableGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. Summary Table of Entries
                  Expanded(
                    child: filteredEntries.isEmpty
                        ? const Center(child: Text('No entries in this period'))
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: filteredEntries.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final entry = filteredEntries[index];
                              final isGave = entry.type == EntryType.gave;

                              return Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Row(
                                  children: [
                                    // Date
                                    SizedBox(
                                      width: 80,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            DateFormatter.formatShortDate(
                                                entry.date),
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            DateFormatter.formatTime(entry.date),
                                            style: AppTypography.labelSmall,
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Note / Description
                                    Expanded(
                                      child: Text(
                                        entry.note ?? (isGave ? 'You Gave' : 'You Got'),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),

                                    // Debit (Gave) column
                                    SizedBox(
                                      width: 85,
                                      child: Text(
                                        isGave
                                            ? CurrencyFormatter.format(
                                                entry.amountInCents)
                                            : '-',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: isGave
                                              ? AppColors.payableRed
                                              : AppColors.textMutedLight,
                                        ),
                                      ),
                                    ),

                                    // Credit (Got) column
                                    SizedBox(
                                      width: 85,
                                      child: Text(
                                        !isGave
                                            ? CurrencyFormatter.format(
                                                entry.amountInCents)
                                            : '-',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: !isGave
                                              ? AppColors.receivableGreen
                                              : AppColors.textMutedLight,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),

                  // 3. Persistent Action Bar: Share on WhatsApp & Export PDF
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    decoration: BoxDecoration(
                      color: isIos
                          ? CupertinoColors.systemBackground
                          : AppColors.surfaceWhite,
                      border: const Border(
                        top: BorderSide(color: AppColors.borderLight, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Share on WhatsApp
                        Expanded(
                          child: AdaptiveButton(
                            onPressed: () => _showExportPreview('WhatsApp'),
                            type: AdaptiveButtonType.secondary,
                            height: 48,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.chat_rounded,
                                  size: 18,
                                  color: Color(0xFF25D366),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'WhatsApp',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF15803D),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Export PDF
                        Expanded(
                          child: AdaptiveButton(
                            onPressed: () => _showExportPreview('PDF'),
                            type: AdaptiveButtonType.primary,
                            height: 48,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.picture_as_pdf_rounded,
                                    size: 18, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  AppStrings.exportPdf,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
