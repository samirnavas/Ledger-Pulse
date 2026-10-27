import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/strings.dart';
import '../../core/constants/typography.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../data/models/party_model.dart';
import '../../data/models/transaction_model.dart';
import '../providers/ledger_providers.dart';
import 'pdf_export_modal.dart';
import 'widgets/dynamic_report_view.dart';
import 'widgets/statement_action_bar.dart';
import 'widgets/statement_header_card.dart';
import 'widgets/statement_pdf_generator.dart';

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
  final String? reportId;

  const StatementPreviewScreen({
    super.key,
    this.partyId = '',
    this.reportId,
  });

  @override
  ConsumerState<StatementPreviewScreen> createState() =>
      _StatementPreviewScreenState();
}

class _StatementPreviewScreenState
    extends ConsumerState<StatementPreviewScreen> {
  StatementPeriod _selectedPeriod = StatementPeriod.allTime;
  bool _isExporting = false;

  Future<void> _exportPdf({
    required Party party,
    required List<LedgerEntry> entries,
    required int totalGave,
    required int totalGot,
  }) async {
    HapticFeedback.lightImpact();
    setState(() => _isExporting = true);

    try {
      final pdfBytes = await StatementPdfGenerator.generate(
        party: party,
        entries: entries,
        totalGave: totalGave,
        totalGot: totalGot,
        periodLabel: _selectedPeriod.label,
      );

      final safeName = party.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final fileName = 'LedgerPulse_${safeName}_Statement.pdf';
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes);

      if (mounted) {
        await PdfExportModal.show(
          context: context,
          pdfBytes: pdfBytes,
          file: file,
          fileName: fileName,
          partyName: party.name,
          periodLabel: _selectedPeriod.label,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export PDF: $e'),
            backgroundColor: AppColors.payableRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _shareOnWhatsApp({
    required Party party,
    required List<LedgerEntry> entries,
    required int totalGave,
    required int totalGot,
  }) async {
    HapticFeedback.lightImpact();

    final cleanPhone = party.phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final buffer = StringBuffer();
    buffer.writeln('📋 *Ledger Statement for ${party.name}*');
    buffer.writeln('Period: ${_selectedPeriod.label}');
    buffer.writeln('---------------------------');
    buffer.writeln('• Total Gave: ₹${(totalGave / 100).toStringAsFixed(2)}');
    buffer.writeln('• Total Got: ₹${(totalGot / 100).toStringAsFixed(2)}');

    final net = party.netBalanceInCents;
    if (net > 0) {
      buffer.writeln('*Net Receivable:* ₹${(net / 100).toStringAsFixed(2)} (You will get)');
    } else if (net < 0) {
      buffer.writeln('*Net Payable:* ₹${(-net / 100).toStringAsFixed(2)} (You will give)');
    } else {
      buffer.writeln('*Net Balance:* ₹0.00 (Settled)');
    }
    buffer.writeln('---------------------------');
    buffer.writeln('Recent Transactions (${entries.length}):');
    for (final e in entries.take(8)) {
      final date = DateFormatter.formatShortDate(e.date);
      final type = e.type == EntryType.gave ? 'Gave (-)' : 'Got (+)';
      final note = (e.note != null && e.note!.isNotEmpty) ? ' [${e.note}]' : '';
      buffer.writeln('• $date: $type ₹${(e.amountInCents / 100).toStringAsFixed(2)}$note');
    }
    if (entries.length > 8) {
      buffer.writeln('... and ${entries.length - 8} more transactions.');
    }
    buffer.writeln('\nGenerated via Ledger Pulse');

    final prefilledText = buffer.toString();
    final encodedText = Uri.encodeComponent(prefilledText);
    final uri = Uri.parse('whatsapp://send?phone=$cleanPhone&text=$encodedText');
    final webUri = Uri.parse('https://wa.me/$cleanPhone?text=$encodedText');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      try {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (webErr) {
        debugPrint('Web WhatsApp launch fallback failed: $webErr');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open WhatsApp: $e'),
              backgroundColor: AppColors.payableRed,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.partyId.isEmpty && widget.reportId != null) {
      return DynamicReportView(reportId: widget.reportId!);
    }

    final partyAsync = ref.watch(partyDetailProvider(widget.partyId));
    final entriesAsync = ref.watch(partyLedgerEntriesProvider(widget.partyId));

    return PopScope(
      canPop: !_isExporting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isExporting) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please wait while export is processing.'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      },
      child: AdaptiveScaffold(
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
                          AdaptiveSegmentedControl<StatementPeriod>(
                            groupValue: _selectedPeriod,
                            children: const {
                              StatementPeriod.allTime: Text(
                                AppStrings.allTime,
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              StatementPeriod.thirtyDays: Text(
                                AppStrings.last30Days,
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            },
                            onValueChanged: (val) {
                              setState(() => _selectedPeriod = val);
                            },
                          ),
                          const SizedBox(height: 12),

                          // Statement Header Card
                          StatementHeaderCard(
                            party: party,
                            totalGave: totalGave,
                            totalGot: totalGot,
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
                    StatementActionBar(
                      isExporting: _isExporting,
                      onShareWhatsApp: () => _shareOnWhatsApp(
                        party: party,
                        entries: filteredEntries,
                        totalGave: totalGave,
                        totalGot: totalGot,
                      ),
                      onExportPdf: () => _exportPdf(
                        party: party,
                        entries: filteredEntries,
                        totalGave: totalGave,
                        totalGot: totalGot,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
