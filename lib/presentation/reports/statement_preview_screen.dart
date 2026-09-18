import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/strings.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../data/models/party_model.dart';
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
  bool _isExporting = false;

  Future<Uint8List> _generatePdfDocument({
    required Party party,
    required List<LedgerEntry> entries,
    required int totalGave,
    required int totalGot,
    required StatementPeriod period,
  }) async {
    final pdf = pw.Document();

    pw.Font? regularFont;
    pw.Font? boldFont;
    try {
      regularFont = await PdfGoogleFonts.interRegular();
      boldFont = await PdfGoogleFonts.interBold();
    } catch (_) {
      // Fallback to standard PDF typography in offline / test environments
    }

    final theme = (regularFont != null && boldFont != null)
        ? pw.ThemeData.withFont(base: regularFont, bold: boldFont)
        : pw.ThemeData.base();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: theme,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'LEDGER PULSE',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo900,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Party Account Statement',
                      style: const pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Generated: ${DateFormatter.formatShortDate(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                    pw.Text(
                      'Period: ${period.label}',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 1, color: PdfColors.grey300),
            pw.SizedBox(height: 10),
            // Party details and financial summary box
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        party.name,
                        style: pw.TextStyle(
                          fontSize: 15,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('Phone: ${party.phoneNumber}',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
                      pw.Text('Type: ${party.type.displayName}',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Total Gave: Rs ${(totalGave / 100).toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.red800,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Total Got: Rs ${(totalGot / 100).toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.green800,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Net Balance: Rs ${(party.netBalanceInCents.abs() / 100).toStringAsFixed(2)} (${party.netBalanceInCents > 0 ? "You'll Get" : party.netBalanceInCents < 0 ? "You'll Give" : "Settled"})',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.indigo900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
          ],
        ),
        build: (context) {
          if (entries.isEmpty) {
            return [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 24),
                child: pw.Center(
                  child: pw.Text(
                    'No transactions recorded for this period.',
                    style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                  ),
                ),
              ),
            ];
          }

          return [
            pw.TableHelper.fromTextArray(
              headers: [
                'Date & Time',
                'Description / Note',
                'Debit (Gave)',
                'Credit (Got)',
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 10,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.indigo900,
              ),
              cellHeight: 22,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
              },
              cellStyle: const pw.TextStyle(fontSize: 9),
              data: entries.map((entry) {
                final isGave = entry.type == EntryType.gave;
                return [
                  '${DateFormatter.formatShortDate(entry.date)} ${DateFormatter.formatTime(entry.date)}',
                  entry.note ?? (isGave ? 'You Gave' : 'You Got'),
                  isGave ? 'Rs ${(entry.amountInCents / 100).toStringAsFixed(2)}' : '-',
                  !isGave ? 'Rs ${(entry.amountInCents / 100).toStringAsFixed(2)}' : '-',
                ];
              }).toList(),
            ),
          ];
        },
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 16),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount} - Generated by Ledger Pulse',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ),
    );

    return pdf.save();
  }

  Future<void> _exportPdf({
    required Party party,
    required List<LedgerEntry> entries,
    required int totalGave,
    required int totalGot,
  }) async {
    HapticFeedback.lightImpact();
    setState(() => _isExporting = true);

    try {
      final pdfBytes = await _generatePdfDocument(
        party: party,
        entries: entries,
        totalGave: totalGave,
        totalGot: totalGot,
        period: _selectedPeriod,
      );

      final safeName = party.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final fileName = 'LedgerPulse_${safeName}_Statement.pdf';
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes);

      final xFile = XFile(file.path, mimeType: 'application/pdf', name: fileName);
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [xFile],
        text: 'Ledger Statement for ${party.name} (${_selectedPeriod.label})',
        subject: 'Statement - ${party.name}',
      );
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
      } catch (_) {
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
    final isIos = AdaptiveThemeHelper.isIos(context);

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
                        isIos
                            ? LiquidGlassContainer(
                                padding: const EdgeInsets.all(16),
                                borderRadius: 18,
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
                                          style:
                                              AppTypography.labelSmall.copyWith(
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
                                              CurrencyFormatter.format(
                                                  totalGave),
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.payableRed,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            const Text(
                                              'Total Got',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    AppColors.receivableGreen,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              CurrencyFormatter.format(
                                                  totalGot),
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    AppColors.receivableGreen,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              )
                            : Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.outlineVariant.withValues(
                                        alpha: Theme.of(context).brightness == Brightness.dark
                                            ? 0.35
                                            : 0.5),
                                    width: 1,
                                  ),
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
                                          style:
                                              AppTypography.labelSmall.copyWith(
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
                                              CurrencyFormatter.format(
                                                  totalGave),
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.payableRed,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            const Text(
                                              'Total Got',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    AppColors.receivableGreen,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              CurrencyFormatter.format(
                                                  totalGot),
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    AppColors.receivableGreen,
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
                          : Theme.of(context).colorScheme.surfaceContainer,
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant.withValues(
                              alpha: Theme.of(context).brightness == Brightness.dark
                                  ? 0.35
                                  : 0.5),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Share on WhatsApp
                        Expanded(
                          child: AdaptiveButton(
                            onPressed: () => _shareOnWhatsApp(
                              party: party,
                              entries: filteredEntries,
                              totalGave: totalGave,
                              totalGot: totalGot,
                            ),
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
                            onPressed: _isExporting
                                ? () {}
                                : () => _exportPdf(
                                      party: party,
                                      entries: filteredEntries,
                                      totalGave: totalGave,
                                      totalGot: totalGot,
                                    ),
                            type: AdaptiveButtonType.primary,
                            height: 48,
                            child: _isExporting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  )
                                : Row(
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
      ),
    );
  }
}
