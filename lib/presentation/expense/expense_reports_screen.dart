import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_chip.dart';
import '../../core/widgets/adaptive_date_field.dart';
import '../../core/widgets/adaptive_form_sheet.dart';
import '../../core/widgets/adaptive_list_row.dart';
import '../../core/widgets/adaptive_section_header.dart';
import '../../core/widgets/adaptive_surface_card.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/app_feedback.dart';
import '../../data/models/company_model.dart';
import '../../data/models/voucher_model.dart';
import '../../data/reporting/expense_report_engine.dart';
import '../../data/reporting/report_export_service.dart';
import '../../data/reporting/report_models.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import 'widgets/category_breakdown_card.dart';

enum ReportDateFilter {
  thisMonth('This Month'),
  last3Months('Last 3 Months'),
  thisYear('This Year'),
  custom('Custom');

  final String label;
  const ReportDateFilter(this.label);
}

/// Comprehensive expense reports, spending trends, income vs expense breakdowns,
/// wallet balance distributions, and CSV/PDF export hub.
class ExpenseReportsScreen extends ConsumerStatefulWidget {
  const ExpenseReportsScreen({super.key});

  static Future<void> showExportSheet({
    required BuildContext context,
    required WidgetRef ref,
    List<VoucherModel>? transactions,
    (DateTime start, DateTime end)? dateRange,
  }) {
    return showAdaptiveFormSheet<void>(
      context: context,
      title: 'Export Report',
      builder: (sheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AdaptiveListRow(
              leading: Icon(
                AdaptiveThemeHelper.isIos(sheetContext)
                    ? CupertinoIcons.doc_text
                    : Icons.table_chart_outlined,
              ),
              title: 'Export as CSV',
              subtitle: 'Download transaction spreadsheet',
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _performExportCsv(context, ref, transactions, dateRange);
              },
            ),
            AdaptiveListRow(
              leading: Icon(
                AdaptiveThemeHelper.isIos(sheetContext)
                    ? CupertinoIcons.doc
                    : Icons.picture_as_pdf_outlined,
              ),
              title: 'Export as PDF',
              subtitle: 'Print or share formatted PDF report',
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _performExportPdf(context, ref, transactions, dateRange);
              },
            ),
          ],
        );
      },
    );
  }

  static Future<void> _performExportCsv(
    BuildContext context,
    WidgetRef ref,
    List<VoucherModel>? txns,
    (DateTime start, DateTime end)? range,
  ) async {
    try {
      final company = ref.read(activeCompanyProvider);
      final repo = ref.read(expenseRepositoryProvider);
      final transactions = txns ?? await repo.getTransactions();
      final categories = await repo.getCategories(includeArchived: true);
      final wallets = await repo.getWallets(includeArchived: true);
      final catNames = {for (final c in categories) c.id: c.name};
      final walNames = {for (final w in wallets) w.id: w.name};

      final now = DateTime.now();
      final startDate = range?.$1 ?? DateTime(now.year, now.month, 1);
      final endDate =
          range?.$2 ?? DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);

      final file = await ReportExportService.exportTransactionsCsv(
        transactions: transactions,
        company: company,
        categoryNames: catNames,
        walletNames: walNames,
        startDate: startDate,
        endDate: endDate,
      );

      if (context.mounted) {
        await ReportExportService.shareFile(
          file: file,
          subject: '${company.name} Transactions Export',
        );
      }
    } catch (e) {
      if (context.mounted) {
        showAppFeedback(
          context,
          'CSV Export failed: $e',
          isError: true,
        );
      }
    }
  }

  static Future<void> _performExportPdf(
    BuildContext context,
    WidgetRef ref,
    List<VoucherModel>? txns,
    (DateTime start, DateTime end)? range,
  ) async {
    try {
      final company = ref.read(activeCompanyProvider);
      final repo = ref.read(expenseRepositoryProvider);
      final transactions = txns ?? await repo.getTransactions();
      final categories = await repo.getCategories(includeArchived: true);
      final wallets = await repo.getWallets(includeArchived: true);
      final catNames = {for (final c in categories) c.id: c.name};
      final walNames = {for (final w in wallets) w.id: w.name};

      final now = DateTime.now();
      final startDate = range?.$1 ?? DateTime(now.year, now.month, 1);
      final endDate =
          range?.$2 ?? DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);

      await ReportExportService.printTransactions(
        transactions: transactions,
        company: company,
        categoryNames: catNames,
        walletNames: walNames,
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      if (context.mounted) {
        showAppFeedback(
          context,
          'PDF Export failed: $e',
          isError: true,
        );
      }
    }
  }

  @override
  ConsumerState<ExpenseReportsScreen> createState() =>
      _ExpenseReportsScreenState();
}

class _ExpenseReportsScreenState extends ConsumerState<ExpenseReportsScreen> {
  ReportDateFilter _selectedFilter = ReportDateFilter.thisMonth;
  late DateTime _customStartDate;
  late DateTime _customEndDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _customStartDate = DateTime(now.year, now.month, 1);
    _customEndDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
  }

  (DateTime start, DateTime end) _getDateRange() {
    final now = DateTime.now();
    switch (_selectedFilter) {
      case ReportDateFilter.thisMonth:
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999),
        );
      case ReportDateFilter.last3Months:
        return (
          DateTime(now.year, now.month - 2, 1),
          DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999),
        );
      case ReportDateFilter.thisYear:
        return (
          DateTime(now.year, 1, 1),
          DateTime(now.year, 12, 31, 23, 59, 59, 999),
        );
      case ReportDateFilter.custom:
        return (_customStartDate, _customEndDate);
    }
  }

  void _showProfitAndLoss(List<VoucherModel> txns) {
    final company = ref.read(activeCompanyProvider);
    final range = _getDateRange();
    final report = ExpenseReportEngine.generateProfitAndLoss(
      company: company,
      vouchers: txns,
      startDate: range.$1,
      endDate: range.$2,
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProfitAndLossSheet(report: report, company: company),
    );
  }

  @override
  Widget build(BuildContext context) {
    final range = _getDateRange();

    final txnsAsync = ref.watch(transactionsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final walletsAsync = ref.watch(walletsProvider);

    return Material(
      color: Colors.transparent,
      child: txnsAsync.when(
        data: (allTxns) {
          final categories = categoriesAsync.value ?? [];
          final wallets = walletsAsync.value ?? [];

          final catReport = ExpenseReportEngine.calculateSpendingByCategory(
            vouchers: allTxns,
            categories: categories,
            startDate: range.$1,
            endDate: range.$2,
          );

          final trendReport = ExpenseReportEngine.calculateMonthlyTrend(
            vouchers: allTxns,
            referenceDate: DateTime.now(),
            months: 6,
          );

          final incExpReport = ExpenseReportEngine.calculateIncomeVsExpense(
            vouchers: allTxns,
            startDate: range.$1,
            endDate: range.$2,
          );

          final walletReport =
              ExpenseReportEngine.calculateWalletBalanceHistory(
            wallets: wallets,
            vouchers: allTxns,
          );

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Period Selector using AdaptiveChipRow
              AdaptiveChipRow<ReportDateFilter>(
                padding: EdgeInsets.zero,
                selectedValue: _selectedFilter,
                onSelected: (val) {
                  if (val != null) {
                    setState(() => _selectedFilter = val);
                  }
                },
                items: ReportDateFilter.values
                    .map(
                      (f) => AdaptiveChipItem(
                        value: f,
                        label: f.label,
                      ),
                    )
                    .toList(),
              ),

              if (_selectedFilter == ReportDateFilter.custom) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AdaptiveDateField(
                        label: 'Start Date',
                        selectedDate: _customStartDate,
                        onDateSelected: (d) =>
                            setState(() => _customStartDate = d),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AdaptiveDateField(
                        label: 'End Date',
                        selectedDate: _customEndDate,
                        onDateSelected: (d) => setState(() => _customEndDate = d),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),

              // 1. Spending by Category Card
              _CategoryBreakdownCard(report: catReport),
              const SizedBox(height: 16),

              // 2. Monthly Trend Card
              _MonthlyTrendCard(report: trendReport),
              const SizedBox(height: 16),

              // 3. Income vs Expense Card
              _IncomeVsExpenseCard(report: incExpReport),
              const SizedBox(height: 16),

              // 4. Wallet Balance History Card
              _WalletDistributionCard(report: walletReport),
              const SizedBox(height: 20),

              // Quick P&L Statement Trigger
              Center(
                child: TextButton.icon(
                  onPressed: () => _showProfitAndLoss(allTxns),
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('View Profit & Loss Statement'),
                ),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(child: Text('Error loading reports: $e')),
      ),
    );
  }
}

// ==========================================
// 1. SPENDING BY CATEGORY CARD
// ==========================================

class _CategoryBreakdownCard extends StatefulWidget {
  final CategorySpendingReport report;

  const _CategoryBreakdownCard({required this.report});

  @override
  State<_CategoryBreakdownCard> createState() => _CategoryBreakdownCardState();
}

class _CategoryBreakdownCardState extends State<_CategoryBreakdownCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = getChartPalette(context);

    if (widget.report.categories.isEmpty) {
      return AdaptiveSurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdaptiveSectionHeader(
              padding: EdgeInsets.zero,
              title: 'Spending by category',
            ),
            const SizedBox(height: 16),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No expense transactions recorded in this period',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return AdaptiveSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveSectionHeader(
            padding: EdgeInsets.zero,
            title: 'Spending by category',
            trailing: Text(
              CurrencyFormatter.format(widget.report.totalSpentInCents),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Animated Donut Chart
          Center(
            child: SizedBox(
              width: 140,
              height: 140,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _CategoryDonutPainter(
                      categories: widget.report.categories,
                      totalSpend: widget.report.totalSpentInCents,
                      palette: palette,
                      progress: CurvedAnimation(
                        parent: _controller,
                        curve: Curves.easeOutCubic,
                      ).value,
                      backgroundColor:
                          theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Category items
          ...widget.report.categories.asMap().entries.map((entry) {
            final idx = entry.key;
            final cat = entry.value;
            final color = palette[idx % palette.length];

            return AdaptiveListRow(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              showDivider: false,
              leading: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              title: cat.categoryName,
              subtitle: '${cat.percentage.toStringAsFixed(1)}%',
              trailing: AmountText(
                amountInCents: cat.totalSpentInCents,
                variant: AmountVariant.medium,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _CategoryDonutPainter extends CustomPainter {
  final List<CategorySpendingItem> categories;
  final int totalSpend;
  final List<Color> palette;
  final double progress;
  final Color backgroundColor;

  _CategoryDonutPainter({
    required this.categories,
    required this.totalSpend,
    required this.palette,
    required this.progress,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalSpend <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 20.0;
    final rect = Rect.fromCircle(
      center: center,
      radius: radius - (strokeWidth / 2),
    );

    // Background track
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius - (strokeWidth / 2), bgPaint);

    double startAngle = -math.pi / 2;

    for (int i = 0; i < categories.length; i++) {
      final sweepAngle =
          (categories[i].totalSpentInCents / totalSpend) * 2 * math.pi * progress;
      final paint = Paint()
        ..color = palette[i % palette.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _CategoryDonutPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ==========================================
// 2. MONTHLY TREND CARD
// ==========================================

class _MonthlyTrendCard extends StatefulWidget {
  final MonthlyTrendReport report;

  const _MonthlyTrendCard({required this.report});

  @override
  State<_MonthlyTrendCard> createState() => _MonthlyTrendCardState();
}

class _MonthlyTrendCardState extends State<_MonthlyTrendCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIos = AdaptiveThemeHelper.isIos(context);

    return AdaptiveSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveSectionHeader(
            padding: EdgeInsets.zero,
            title: 'Monthly trend',
            trailing: Text(
              'Avg: ${CurrencyFormatter.format(widget.report.averageMonthlyExpenseInCents.round())}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _LegendDot(
                color: theme.colorScheme.primary,
                label: 'Income',
              ),
              const SizedBox(width: 12),
              _LegendDot(
                color: theme.colorScheme.error,
                label: 'Expense',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 170,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: _MonthlyTrendChartPainter(
                    months: widget.report.months,
                    theme: theme,
                    isIos: isIos,
                    progress: CurvedAnimation(
                      parent: _controller,
                      curve: Curves.easeOutCubic,
                    ).value,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MonthlyTrendChartPainter extends CustomPainter {
  final List<MonthlyTrendItem> months;
  final ThemeData theme;
  final bool isIos;
  final double progress;

  _MonthlyTrendChartPainter({
    required this.months,
    required this.theme,
    required this.isIos,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;

    const double bottomPadding = 24.0;
    final double chartHeight = size.height - bottomPadding;
    final double width = size.width;

    int maxVal = 1;
    for (final m in months) {
      if (m.totalIncomeInCents > maxVal) maxVal = m.totalIncomeInCents;
      if (m.totalExpenseInCents > maxVal) maxVal = m.totalExpenseInCents;
    }

    final double groupWidth = width / months.length;
    final double barWidth = (groupWidth * 0.30).clamp(6.0, 18.0);
    const double spacing = 3.0;

    final incomePaint = Paint()..color = theme.colorScheme.primary;
    final expensePaint = Paint()..color = theme.colorScheme.error;
    final gridPaint = Paint()
      ..color = theme.colorScheme.outlineVariant
      ..strokeWidth = 1.0;

    // Grid lines
    canvas.drawLine(
      Offset(0, chartHeight),
      Offset(width, chartHeight),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, chartHeight / 2),
      Offset(width, chartHeight / 2),
      gridPaint,
    );

    final textStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: 10,
    );

    final double barRadius = isIos ? 6.0 : 8.0;

    for (int i = 0; i < months.length; i++) {
      final m = months[i];
      final double groupCenterX = i * groupWidth + (groupWidth / 2);

      final double inHeight =
          (m.totalIncomeInCents / maxVal) * (chartHeight * 0.85) * progress;
      final double exHeight =
          (m.totalExpenseInCents / maxVal) * (chartHeight * 0.85) * progress;

      // Income bar
      if (inHeight > 0) {
        final inRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            groupCenterX - barWidth - (spacing / 2),
            chartHeight - inHeight,
            barWidth,
            inHeight,
          ),
          Radius.circular(barRadius),
        );
        canvas.drawRRect(inRect, incomePaint);
      }

      // Expense bar
      if (exHeight > 0) {
        final exRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            groupCenterX + (spacing / 2),
            chartHeight - exHeight,
            barWidth,
            exHeight,
          ),
          Radius.circular(barRadius),
        );
        canvas.drawRRect(exRect, expensePaint);
      }

      // Month label
      final labelText = m.monthLabel.split(' ').first;
      final textSpan = TextSpan(
        text: labelText,
        style: textStyle,
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(groupCenterX - (textPainter.width / 2), chartHeight + 6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MonthlyTrendChartPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ==========================================
// 3. INCOME VS EXPENSE CARD
// ==========================================

class _IncomeVsExpenseCard extends StatelessWidget {
  final IncomeVsExpenseReport report;

  const _IncomeVsExpenseCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdaptiveSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveSectionHeader(
            padding: EdgeInsets.zero,
            title: 'Income vs expense',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (report.savingsRate >= 0
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${report.savingsRate.toStringAsFixed(1)}% Saved',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: report.savingsRate >= 0
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.arrow_downward_rounded,
                          color: theme.colorScheme.primary,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Income',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    AmountText(
                      amountInCents: report.totalIncomeInCents,
                      variant: AmountVariant.large,
                    ),
                    Text(
                      '${report.incomeTransactionCount} entries',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: theme.colorScheme.outlineVariant,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.arrow_upward_rounded,
                          color: theme.colorScheme.error,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Expense',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    AmountText(
                      amountInCents: report.totalExpenseInCents,
                      variant: AmountVariant.large,
                    ),
                    Text(
                      '${report.expenseTransactionCount} entries',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: theme.colorScheme.outlineVariant, height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Net Savings',
                style: theme.textTheme.bodyMedium,
              ),
              AmountText(
                amountInCents: report.netSavingsInCents,
                variant: AmountVariant.medium,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Avg. Daily Spend',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                CurrencyFormatter.format(
                  report.averageDailySpendInCents.round(),
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 4. WALLET BALANCE HISTORY CARD
// ==========================================

class _WalletDistributionCard extends StatelessWidget {
  final WalletBalanceHistoryReport report;

  const _WalletDistributionCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdaptiveSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveSectionHeader(
            padding: EdgeInsets.zero,
            title: 'Wallet balance history',
            trailing: Text(
              'Total: ${CurrencyFormatter.format(report.totalBalanceInCents)}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...report.wallets.map((w) {
            return AdaptiveListRow(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              leading: const Icon(
                Icons.account_balance_wallet_outlined,
                size: 20,
              ),
              title: w.walletName,
              subtitle:
                  'In: ${CurrencyFormatter.format(w.totalInInCents)} • Out: ${CurrencyFormatter.format(w.totalOutInCents)}',
              trailing: AmountText(
                amountInCents: w.currentBalanceInCents,
                variant: AmountVariant.medium,
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ==========================================
// PROFIT AND LOSS SHEET
// ==========================================

class _ProfitAndLossSheet extends StatelessWidget {
  final ReportData report;
  final Company company;

  const _ProfitAndLossSheet({required this.report, required this.company});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profit & Loss Statement',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    company.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
          const Divider(height: 24),
          Expanded(
            child: ListView.separated(
              itemCount: report.rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, idx) {
                final row = report.rows[idx];
                final particulars = row.get('particulars')?.toString() ?? '';
                final amount = row.get('amount')?.toString() ?? '';
                final isNet = particulars.toLowerCase().contains('net profit');

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          particulars,
                          style: TextStyle(
                            fontWeight:
                                isNet ? FontWeight.bold : FontWeight.w500,
                            fontSize: isNet ? 15 : 13,
                          ),
                        ),
                      ),
                      Text(
                        amount,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: isNet ? 16 : 14,
                          color: isNet ? theme.colorScheme.primary : null,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
