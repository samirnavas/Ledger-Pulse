import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/adaptive_button.dart';
import '../../../core/widgets/adaptive_scaffold.dart';
import '../../../data/reporting/report_export_service.dart';
import '../../../data/reporting/report_models.dart';
import '../../providers/company_providers.dart';
import '../../providers/reporting_providers.dart';

/// Dynamic multi-column report preview screen for hub reports (e.g. Daybook, P&L, GST).
class DynamicReportView extends ConsumerStatefulWidget {
  final String reportId;

  const DynamicReportView({
    super.key,
    required this.reportId,
  });

  @override
  ConsumerState<DynamicReportView> createState() => _DynamicReportViewState();
}

class _DynamicReportViewState extends ConsumerState<DynamicReportView> {
  bool _isExporting = false;

  Future<void> _exportDynamicCsv(ReportData report) async {
    HapticFeedback.lightImpact();
    setState(() => _isExporting = true);
    try {
      final company = ref.read(activeCompanyProvider);
      final file = await ReportExportService.exportToExcelCsv(
        report: report,
        company: company,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported Excel CSV: ${file.path.split(RegExp(r"[\\/]")).last}'),
            backgroundColor: AppColors.receivableGreen,
          ),
        );
        // ignore: deprecated_member_use
        await Share.shareXFiles([XFile(file.path)], text: report.metadata.title);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export CSV: $e'),
            backgroundColor: AppColors.payableRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _printDynamicPdf(ReportData report) async {
    HapticFeedback.lightImpact();
    setState(() => _isExporting = true);
    try {
      final company = ref.read(activeCompanyProvider);
      await ReportExportService.printReport(
        report: report,
        company: company,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to print PDF: $e'),
            backgroundColor: AppColors.payableRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reportAsync = ref.watch(dynamicReportDataProvider(widget.reportId));

    return reportAsync.when(
      loading: () => const AdaptiveScaffold(
        title: 'Report Preview',
        body: Center(child: CupertinoActivityIndicator()),
      ),
      error: (err, _) => AdaptiveScaffold(
        title: 'Report Preview',
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Error generating report: $err',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.payableRed),
            ),
          ),
        ),
      ),
      data: (report) {
        return AdaptiveScaffold(
          title: report.metadata.title,
          actions: [
            IconButton(
              tooltip: 'Export to Excel (CSV)',
              icon: Icon(
                AdaptiveThemeHelper.isIos(context) ? CupertinoIcons.table : Icons.table_view_rounded,
              ),
              onPressed: _isExporting ? null : () => _exportDynamicCsv(report),
            ),
            IconButton(
              tooltip: 'Print / Save PDF',
              icon: Icon(
                AdaptiveThemeHelper.isIos(context) ? CupertinoIcons.printer : Icons.print_rounded,
              ),
              onPressed: _isExporting ? null : () => _printDynamicPdf(report),
            ),
          ],
          body: Column(
            children: [
              // Header Card
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: isIos
                    ? LiquidGlassContainer(
                        padding: const EdgeInsets.all(16),
                        borderRadius: 18,
                        child: _buildReportHeaderContent(report),
                      )
                    : Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant.withValues(
                                  alpha: isDark ? 0.35 : 0.5,
                                ),
                          ),
                        ),
                        child: _buildReportHeaderContent(report),
                      ),
              ),

              // Summary Stats (if any)
              if (report.summary.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: report.summary.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.key,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                entry.value.toString(),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

              // Dynamic Table
              Expanded(
                child: report.rows.isEmpty
                    ? const Center(child: Text('No data found for this report.'))
                    : SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                            ),
                            columns: report.columns.map((c) {
                              return DataColumn(
                                label: Text(
                                  c.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              );
                            }).toList(),
                            rows: report.rows.map((r) {
                              return DataRow(
                                cells: report.columns.map((c) {
                                  final val = r.get(c.key)?.toString() ?? '';
                                  return DataCell(
                                    Text(val, style: const TextStyle(fontSize: 12)),
                                  );
                                }).toList(),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
              ),

              // Bottom Action Buttons
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                decoration: BoxDecoration(
                  color: isIos
                      ? CupertinoColors.systemBackground
                      : Theme.of(context).colorScheme.surfaceContainer,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(
                            alpha: isDark ? 0.35 : 0.5,
                          ),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: AdaptiveButton(
                        onPressed: _isExporting ? () {} : () => _exportDynamicCsv(report),
                        type: AdaptiveButtonType.secondary,
                        height: 48,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              AdaptiveThemeHelper.isIos(context) ? CupertinoIcons.table : Icons.table_view_rounded,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Export Excel (CSV)',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AdaptiveButton(
                        onPressed: _isExporting ? () {} : () => _printDynamicPdf(report),
                        type: AdaptiveButtonType.primary,
                        height: 48,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              AdaptiveThemeHelper.isIos(context) ? CupertinoIcons.printer : Icons.print_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Print / PDF',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
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
          ),
        );
      },
    );
  }

  Widget _buildReportHeaderContent(ReportData report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                report.metadata.title,
                style: AppTypography.headlineMedium,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                report.metadata.category.displayName,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          report.metadata.description,
          style: AppTypography.bodySmall,
        ),
        const Divider(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Generated: ${DateFormatter.formatShortDate(report.generatedAt)}',
              style: AppTypography.labelSmall,
            ),
            if (report.dateRangeLabel != null)
              Text(
                'Period: ${report.dateRangeLabel}',
                style: AppTypography.labelSmall,
              ),
          ],
        ),
      ],
    );
  }
}
