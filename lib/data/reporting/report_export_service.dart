import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/utils/date_formatter.dart';
import '../models/company_model.dart';
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
}
