import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../models/company_model.dart';
import '../models/voucher_model.dart';
import 'report_models.dart';

class ReportExportService {
  /// Generates a Microsoft Excel-compatible CSV file with UTF-8 BOM and standard table structure
  static Future<File> exportToExcelCsv({
    required ReportData report,
    required Company company,
    Directory? outputDirectory,
  }) async {
    final buffer = StringBuffer();

    // UTF-8 BOM so Microsoft Excel automatically recognizes UTF-8 formatting and symbols
    buffer.write('\uFEFF');

    // Header block
    buffer.writeln('"${company.legalName}"');
    buffer.writeln('"${report.metadata.title}"');
    buffer.writeln('"Generated on: ${DateFormatter.formatShortDate(report.generatedAt)}"');
    if (report.dateRangeLabel != null) {
      buffer.writeln('"Period: ${report.dateRangeLabel}"');
    }
    buffer.writeln();

    // Table Column Headers
    final headerRow = report.columns.map((c) => '"${c.label.replaceAll('"', '""')}"').join(',');
    buffer.writeln(headerRow);

    // Data Rows
    for (final row in report.rows) {
      final line = report.columns.map((c) {
        final val = row.get(c.key)?.toString() ?? '';
        return '"${val.replaceAll('"', '""')}"';
      }).join(',');
      buffer.writeln(line);
    }

    // Summary Footer
    if (report.summary.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('"--- SUMMARY ---"');
      for (final entry in report.summary.entries) {
        buffer.writeln('"${entry.key}","${entry.value.toString().replaceAll('"', '""')}"');
      }
    }

    Directory tempDir;
    if (outputDirectory != null) {
      tempDir = outputDirectory;
    } else {
      try {
        tempDir = await getTemporaryDirectory();
      } catch (_) {
        tempDir = Directory.systemTemp;
      }
    }
    final sanitizedTitle = report.metadata.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final fileName = '${sanitizedTitle}_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsString(buffer.toString());
    return file;
  }

  /// Generates a formatted PDF document representing the report data
  static Future<Uint8List> generateReportPdf({
    required ReportData report,
    required Company company,
  }) async {
    final pdf = pw.Document();

    pw.Font? regularFont;
    pw.Font? boldFont;
    try {
      regularFont = await PdfGoogleFonts.interRegular().timeout(const Duration(milliseconds: 250));
      boldFont = await PdfGoogleFonts.interBold().timeout(const Duration(milliseconds: 250));
    } catch (_) {
      // Fallback
    }

    final theme = (regularFont != null && boldFont != null)
        ? pw.ThemeData.withFont(base: regularFont, bold: boldFont)
        : pw.ThemeData.base();

    final primaryColor = PdfColor.fromHex('#1E293B');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
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
                      company.legalName.toUpperCase(),
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: primaryColor),
                    ),
                    pw.Text(
                      report.metadata.title,
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Generated: ${DateFormatter.formatShortDate(report.generatedAt)}',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                    if (report.dateRangeLabel != null)
                      pw.Text(
                        report.dateRangeLabel!,
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                  ],
                ),
              ],
            ),
            pw.Divider(thickness: 1, color: primaryColor),
            pw.SizedBox(height: 6),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Ludgerpulse ERP • Confidential Financial Report',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
        build: (context) {
          return [
            pw.TableHelper.fromTextArray(
              headers: report.columns.map((c) => c.label).toList(),
              data: report.rows.map((row) {
                return report.columns.map((c) => row.get(c.key)?.toString() ?? '').toList();
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
              headerDecoration: pw.BoxDecoration(color: primaryColor),
              cellStyle: const pw.TextStyle(fontSize: 8.5),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            ),
            if (report.summary.isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: report.summary.entries.map((entry) {
                    return pw.Column(
                      children: [
                        pw.Text(entry.key, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          entry.value.toString(),
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ];
        },
      ),
    );

    return await pdf.save();
  }

  /// Routes the generated report PDF directly to local or network printers
  static Future<bool> printReport({
    required ReportData report,
    required Company company,
  }) async {
    final pdfBytes = await generateReportPdf(report: report, company: company);
    return await Printing.layoutPdf(
      onLayout: (format) async => pdfBytes,
      name: report.metadata.title,
    );
  }

  // ==========================================
  // TRANSACTION EXPORT (CSV, PDF, PRINT, SHARE)
  // ==========================================

  /// Exports a list of transactions for a date range to an Excel-compatible CSV file.
  static Future<File> exportTransactionsCsv({
    required List<VoucherModel> transactions,
    required Company company,
    Map<String, String> categoryNames = const {},
    Map<String, String> walletNames = const {},
    DateTime? startDate,
    DateTime? endDate,
    Directory? outputDirectory,
  }) async {
    final buffer = StringBuffer();
    // UTF-8 BOM
    buffer.write('\uFEFF');

    buffer.writeln('"${company.legalName}"');
    buffer.writeln('"Transaction Statement"');
    buffer.writeln('"Generated on: ${DateFormatter.formatShortDate(DateTime.now())}"');
    if (startDate != null && endDate != null) {
      buffer.writeln('"Period: ${DateFormatter.formatShortDate(startDate)} to ${DateFormatter.formatShortDate(endDate)}"');
    }
    buffer.writeln();

    // Table Column Headers
    buffer.writeln('"Date","Voucher No","Type","Category","Wallet / Account","To Wallet","Amount","Narration","Reference","Status"');

    int totalIncome = 0;
    int totalExpense = 0;

    for (final txn in transactions) {
      final dateStr = DateFormatter.formatShortDate(txn.date);
      final voucherNo = txn.voucherNumber;
      final typeStr = txn.type.displayName;
      final catName = (txn.categoryAccountId != null ? categoryNames[txn.categoryAccountId] : null) ?? '';
      final walletName = (txn.walletAccountId != null ? walletNames[txn.walletAccountId] : null) ?? '';
      final toWalletName = (txn.toWalletAccountId != null ? walletNames[txn.toWalletAccountId] : null) ?? '';
      final amountFormatted = (txn.totalAmountInCents / 100.0).toStringAsFixed(2);
      final narration = txn.narration ?? '';
      final ref = txn.referenceNumber ?? '';
      final status = txn.status.name;

      if (txn.type == VoucherType.income) totalIncome += txn.totalAmountInCents;
      if (txn.type == VoucherType.expense) totalExpense += txn.totalAmountInCents;

      buffer.writeln(
        '"${dateStr.replaceAll('"', '""')}",'
        '"${voucherNo.replaceAll('"', '""')}",'
        '"${typeStr.replaceAll('"', '""')}",'
        '"${catName.replaceAll('"', '""')}",'
        '"${walletName.replaceAll('"', '""')}",'
        '"${toWalletName.replaceAll('"', '""')}",'
        '"$amountFormatted",'
        '"${narration.replaceAll('"', '""')}",'
        '"${ref.replaceAll('"', '""')}",'
        '"$status"',
      );
    }

    buffer.writeln();
    buffer.writeln('"--- SUMMARY ---"');
    buffer.writeln('"Total Transactions","${transactions.length}"');
    buffer.writeln('"Total Income","${(totalIncome / 100.0).toStringAsFixed(2)}"');
    buffer.writeln('"Total Expense","${(totalExpense / 100.0).toStringAsFixed(2)}"');
    buffer.writeln('"Net Savings","${((totalIncome - totalExpense) / 100.0).toStringAsFixed(2)}"');

    Directory tempDir;
    if (outputDirectory != null) {
      tempDir = outputDirectory;
    } else {
      try {
        tempDir = await getTemporaryDirectory();
      } catch (_) {
        tempDir = Directory.systemTemp;
      }
    }
    final fileName = 'Transactions_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsString(buffer.toString());
    return file;
  }

  /// Generates a formatted multi-page PDF document representing transactions.
  static Future<Uint8List> generateTransactionsPdf({
    required List<VoucherModel> transactions,
    required Company company,
    Map<String, String> categoryNames = const {},
    Map<String, String> walletNames = const {},
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final pdf = pw.Document();

    pw.Font? regularFont;
    pw.Font? boldFont;
    try {
      regularFont = await PdfGoogleFonts.interRegular().timeout(const Duration(milliseconds: 250));
      boldFont = await PdfGoogleFonts.interBold().timeout(const Duration(milliseconds: 250));
    } catch (_) {
      // Fallback to default
    }

    final theme = (regularFont != null && boldFont != null)
        ? pw.ThemeData.withFont(base: regularFont, bold: boldFont)
        : pw.ThemeData.base();

    final primaryColor = PdfColor.fromHex('#1E293B');

    int totalIncome = 0;
    int totalExpense = 0;
    for (final txn in transactions) {
      if (txn.status == VoucherStatus.voided) continue;
      if (txn.type == VoucherType.income) totalIncome += txn.totalAmountInCents;
      if (txn.type == VoucherType.expense) totalExpense += txn.totalAmountInCents;
    }
    final netSavings = totalIncome - totalExpense;

    final dateRangeLabel = (startDate != null && endDate != null)
        ? '${DateFormatter.formatShortDate(startDate)} to ${DateFormatter.formatShortDate(endDate)}'
        : 'All Recorded Transactions';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
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
                      company.legalName.toUpperCase(),
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: primaryColor),
                    ),
                    pw.Text(
                      'Transactions Statement',
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Generated: ${DateFormatter.formatShortDate(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                    pw.Text(
                      'Period: $dateRangeLabel',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            ),
            pw.Divider(thickness: 1, color: primaryColor),
            pw.SizedBox(height: 6),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Ledger Pulse • Transaction History Report',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
        build: (context) {
          return [
            // Summary Cards
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const pw.EdgeInsets.only(bottom: 12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(
                    children: [
                      pw.Text('Total Income', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        CurrencyFormatter.format(totalIncome),
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green800),
                      ),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('Total Expense', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        CurrencyFormatter.format(totalExpense),
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.red800),
                      ),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('Net Savings', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        CurrencyFormatter.format(netSavings),
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: netSavings >= 0 ? PdfColors.blue800 : PdfColors.red800,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('Transactions', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '${transactions.length}',
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Transactions Table
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Voucher #', 'Type', 'Category', 'Wallet', 'Amount', 'Notes'],
              data: transactions.map((txn) {
                final dateStr = DateFormatter.formatShortDate(txn.date);
                final catName = (txn.categoryAccountId != null ? categoryNames[txn.categoryAccountId] : null) ?? '-';
                final walletName = (txn.walletAccountId != null ? walletNames[txn.walletAccountId] : null) ?? '-';
                final amountStr = CurrencyFormatter.format(txn.totalAmountInCents);
                final notes = txn.narration ?? txn.referenceNumber ?? '';

                return [
                  dateStr,
                  txn.voucherNumber,
                  txn.type.displayName,
                  catName,
                  walletName,
                  amountStr,
                  notes,
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8.5),
              headerDecoration: pw.BoxDecoration(color: primaryColor),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
            ),
          ];
        },
      ),
    );

    return await pdf.save();
  }

  /// Sends the transactions PDF directly to local or network printing
  static Future<bool> printTransactions({
    required List<VoucherModel> transactions,
    required Company company,
    Map<String, String> categoryNames = const {},
    Map<String, String> walletNames = const {},
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final pdfBytes = await generateTransactionsPdf(
      transactions: transactions,
      company: company,
      categoryNames: categoryNames,
      walletNames: walletNames,
      startDate: startDate,
      endDate: endDate,
    );
    return await Printing.layoutPdf(
      onLayout: (format) async => pdfBytes,
      name: 'Transactions_${company.name}',
    );
  }

  /// Shares a file via native system share sheet
  static Future<void> shareFile({
    required File file,
    String? subject,
    String? text,
  }) async {
    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: subject,
      text: text,
    );
  }
}
