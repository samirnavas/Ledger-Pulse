import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/liquid_glass_card.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../data/reporting/custom_sql_report_engine.dart';
import '../../data/reporting/report_export_service.dart';
import '../../data/reporting/report_models.dart';
import '../providers/company_providers.dart';
import '../providers/reporting_providers.dart';

class DesktopCustomReportStudio extends ConsumerStatefulWidget {
  const DesktopCustomReportStudio({super.key});

  @override
  ConsumerState<DesktopCustomReportStudio> createState() =>
      _DesktopCustomReportStudioState();
}

class _DesktopCustomReportStudioState
    extends ConsumerState<DesktopCustomReportStudio> {
  final TextEditingController _sqlController = TextEditingController();
  final TextEditingController _titleController =
      TextEditingController(text: 'Custom Query Report');

  List<CustomSqlTemplate> _templates = [];
  CustomSqlTemplate? _selectedTemplate;
  ReportData? _reportData;
  String? _errorMessage;
  bool _isLoading = false;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadPreloadedTemplates();
  }

  @override
  void dispose() {
    _sqlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadPreloadedTemplates() async {
    try {
      final xmlString = await rootBundle
          .loadString('assets/data/custom_reports_sample.xml');
      final templates = CustomSqlReportEngine.parseXmlTemplates(xmlString);
      if (mounted) {
        setState(() {
          _templates = templates;
          if (templates.isNotEmpty) {
            _onSelectTemplate(templates.first);
          }
        });
      }
    } catch (e) {
      // In tests or minimal setups, fallback to hardcoded templates
      final fallbackTemplates = [
        const CustomSqlTemplate(
          id: 'tpl_top_vouchers',
          title: 'Top 10 High Value Vouchers',
          description: 'Lists highest value vouchers across all types',
          sqlQuery:
              'SELECT voucher_number, voucher_type, date, total_amount_in_cents FROM vouchers ORDER BY total_amount_in_cents DESC LIMIT 10;',
          columns: [],
        ),
        const CustomSqlTemplate(
          id: 'tpl_active_parties',
          title: 'Parties Directory & Balance',
          description: 'All customers and suppliers with net balances',
          sqlQuery:
              'SELECT name, phone_number, type, net_balance_in_cents FROM parties ORDER BY name ASC;',
          columns: [],
        ),
      ];
      if (mounted) {
        setState(() {
          _templates = fallbackTemplates;
          if (fallbackTemplates.isNotEmpty) {
            _onSelectTemplate(fallbackTemplates.first);
          }
        });
      }
    }
  }

  void _onSelectTemplate(CustomSqlTemplate template) {
    setState(() {
      _selectedTemplate = template;
      _titleController.text = template.title;
      _sqlController.text = template.sqlQuery.trim();
      _errorMessage = null;
    });
  }

  Future<void> _runQuery() async {
    final query = _sqlController.text.trim();
    if (query.isEmpty) {
      setState(() => _errorMessage = 'Please enter an SQL query to execute.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final engine = ref.read(customSqlReportEngineProvider);
      final report = await engine.executeRawSql(
        sqlQuery: query,
        reportTitle: _titleController.text.trim().isEmpty
            ? 'Custom SQL Report'
            : _titleController.text.trim(),
        reportDescription: 'Executed via Desktop Custom Report Studio',
      );

      setState(() {
        _reportData = report;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
        _reportData = null;
      });
    }
  }

  Future<void> _exportCsv() async {
    if (_reportData == null) return;
    setState(() => _isExporting = true);
    try {
      final company = ref.read(activeCompanyProvider);
      final file = await ReportExportService.exportToExcelCsv(
        report: _reportData!,
        company: company,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported CSV: ${file.path.split(RegExp(r"[\\/]")).last}'),
            backgroundColor: AppColors.receivableGreen,
          ),
        );
        // ignore: deprecated_member_use
        await Share.shareXFiles([XFile(file.path)], text: _reportData!.metadata.title);
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

  Future<void> _printOrExportPdf() async {
    if (_reportData == null) return;
    setState(() => _isExporting = true);
    try {
      final company = ref.read(activeCompanyProvider);
      await ReportExportService.printReport(
        report: _reportData!,
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

    return AdaptiveScaffold(
      title: 'Desktop Custom Report Studio',
      actions: [
        if (_reportData != null) ...[
          IconButton(
            tooltip: 'Export to Excel (CSV)',
            icon: const Icon(Icons.table_view_rounded),
            onPressed: _isExporting ? null : _exportCsv,
          ),
          IconButton(
            tooltip: 'Print / Save PDF',
            icon: const Icon(Icons.print_rounded),
            onPressed: _isExporting ? null : _printOrExportPdf,
          ),
        ],
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Template selection card
            _buildTemplateSelector(context, isIos, isDark),
            const SizedBox(height: 16),

            // 2. Query Editor Box
            _buildQueryEditor(context, isIos, isDark),
            const SizedBox(height: 16),

            // 3. Action Toolbar
            Row(
              children: [
                Expanded(
                  child: AdaptiveButton(
                    onPressed: _isLoading ? () {} : _runQuery,
                    type: AdaptiveButtonType.primary,
                    height: 48,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.play_arrow_rounded, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Run Query',
                                style: TextStyle(
                                  fontSize: 15,
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
            const SizedBox(height: 16),

            // 4. Error banner if any
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.payableRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.payableRed.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.payableRed, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppColors.payableRed,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 5. Query Results Table
            if (_reportData != null)
              _buildResultsSection(context, isIos, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateSelector(BuildContext context, bool isIos, bool isDark) {
    final dropdownWidget = DropdownButtonFormField<CustomSqlTemplate>(
      initialValue: _selectedTemplate,
      decoration: InputDecoration(
        labelText: 'Pre-built SQL Template',
        prefixIcon: const Icon(Icons.description_rounded),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
      items: _templates.map((tpl) {
        return DropdownMenuItem<CustomSqlTemplate>(
          value: tpl,
          child: Text(tpl.title, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: (tpl) {
        if (tpl != null) _onSelectTemplate(tpl);
      },
    );

    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 16,
        color: isDark
            ? const Color(0xFF1E293B).withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.8),
        borderColor: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Custom SQL Templates',
                style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              dropdownWidget,
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Custom SQL Templates',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            dropdownWidget,
          ],
        ),
      ),
    );
  }

  Widget _buildQueryEditor(BuildContext context, bool isIos, bool isDark) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleController,
          decoration: InputDecoration(
            labelText: 'Report Title',
            prefixIcon: const Icon(Icons.title_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'SQL Query (Read-Only SELECT queries only):',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _sqlController,
            maxLines: 6,
            style: const TextStyle(
              fontFamily: 'Courier',
              fontSize: 13,
              letterSpacing: 0.4,
            ),
            decoration: const InputDecoration(
              hintText: 'SELECT * FROM table LIMIT 50;',
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
      ],
    );

    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 16,
        color: isDark
            ? const Color(0xFF1E293B).withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.8),
        borderColor: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: content,
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: content,
      ),
    );
  }

  Widget _buildResultsSection(BuildContext context, bool isIos, bool isDark) {
    final report = _reportData!;

    final tableWidget = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(
          Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
        ),
        columns: report.columns.map((col) {
          return DataColumn(
            label: Text(
              col.label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          );
        }).toList(),
        rows: report.rows.map((row) {
          return DataRow(
            cells: report.columns.map((col) {
              final val = row.get(col.key)?.toString() ?? '';
              return DataCell(
                Text(val, style: const TextStyle(fontSize: 12)),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );

    final innerContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${report.metadata.title} (${report.rows.length} rows)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                AdaptiveButton(
                  onPressed: _isExporting ? () {} : _exportCsv,
                  type: AdaptiveButtonType.secondary,
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: const [
                      Icon(Icons.file_download_rounded, size: 16),
                      SizedBox(width: 4),
                      Text('Excel CSV', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AdaptiveButton(
                  onPressed: _isExporting ? () {} : _printOrExportPdf,
                  type: AdaptiveButtonType.primary,
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: const [
                      Icon(Icons.print_rounded, size: 16, color: Colors.white),
                      SizedBox(width: 4),
                      Text('Print / PDF',
                          style: TextStyle(fontSize: 12, color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: tableWidget,
        ),
      ],
    );

    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 16,
        color: isDark
            ? const Color(0xFF1E293B).withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.8),
        borderColor: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: innerContent,
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: innerContent,
      ),
    );
  }
}
