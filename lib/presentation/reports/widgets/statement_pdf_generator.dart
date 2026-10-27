import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/utils/date_formatter.dart';
import '../../../data/models/party_model.dart';
import '../../../data/models/transaction_model.dart';

/// PDF Generation service for party ledger account statements.
class StatementPdfGenerator {
  static Future<Uint8List> generate({
    required Party party,
    required List<LedgerEntry> entries,
    required int totalGave,
    required int totalGot,
    required String periodLabel,
  }) async {
    final pdf = pw.Document();

    pw.Font? regularFont;
    pw.Font? boldFont;
    try {
      regularFont = await PdfGoogleFonts.interRegular().timeout(const Duration(milliseconds: 250));
      boldFont = await PdfGoogleFonts.interBold().timeout(const Duration(milliseconds: 250));
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
                      'Period: $periodLabel',
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
}
