import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/company_model.dart';
import '../../data/models/voucher_model.dart';
import '../../data/reporting/expense_report_engine.dart';
import '../../data/reporting/report_export_service.dart';
import '../../data/reporting/report_models.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';

enum ReportDateFilter {
  thisMonth('This Month'),
  last3Months('Last 3 Months'),
  last6Months('Last 6 Months'),
  thisYear('This Year'),
  allTime('All Time');

  final String label;
  const ReportDateFilter(this.label);
}

/// Comprehensive expense reports, spending trends, income vs expense breakdowns,
/// wallet balance distributions, and CSV/PDF export hub.
class ExpenseReportsScreen extends ConsumerStatefulWidget {
  const ExpenseReportsScreen({super.key});

  @override
  ConsumerState<ExpenseReportsScreen> createState() =>
      _ExpenseReportsScreenState();
}

class _ExpenseReportsScreenState extends ConsumerState<ExpenseReportsScreen> {
  ReportDateFilter _selectedFilter = ReportDateFilter.thisMonth;
  bool _isExporting = false;

  (DateTime start, DateTime end) _getDateRange(ReportDateFilter filter) {
    final now = DateTime.now();
    switch (filter) {
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
      case ReportDateFilter.last6Months:
        return (
          DateTime(now.year, now.month - 5, 1),
          DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999),
        );
      case ReportDateFilter.thisYear:
        return (
          DateTime(now.year, 1, 1),
          DateTime(now.year, 12, 31, 23, 59, 59, 999),
        );
      case ReportDateFilter.allTime:
        return (
          DateTime(2000, 1, 1),
          DateTime(now.year + 1, 12, 31, 23, 59, 59, 999),
        );
    }
  }

  Future<void> _exportCsv(List<VoucherModel> txns) async {
    final company = ref.read(activeCompanyProvider);
    final repo = ref.read(expenseRepositoryProvider);
    setState(() => _isExporting = true);

    try {
      final categories = await repo.getCategories(includeArchived: true);
      final wallets = await repo.getWallets(includeArchived: true);
      final catNames = {for (final c in categories) c.id: c.name};
      final walNames = {for (final w in wallets) w.id: w.name};

      final range = _getDateRange(_selectedFilter);
      final file = await ReportExportService.exportTransactionsCsv(
        transactions: txns,
        company: company,
        categoryNames: catNames,
        walletNames: walNames,
        startDate: range.$1,
        endDate: range.$2,
      );

      if (mounted) {
        await ReportExportService.shareFile(
          file: file,
          subject: '${company.name} Transactions Export',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportPdf(List<VoucherModel> txns) async {
    final company = ref.read(activeCompanyProvider);
    final repo = ref.read(expenseRepositoryProvider);
    setState(() => _isExporting = true);

    try {
      final categories = await repo.getCategories(includeArchived: true);
      final wallets = await repo.getWallets(includeArchived: true);
      final catNames = {for (final c in categories) c.id: c.name};
      final walNames = {for (final w in wallets) w.id: w.name};

      final range = _getDateRange(_selectedFilter);
      await ReportExportService.printTransactions(
        transactions: txns,
        company: company,
        categoryNames: catNames,
        walletNames: walNames,
        startDate: range.$1,
        endDate: range.$2,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showProfitAndLoss(List<VoucherModel> txns) {
    final company = ref.read(activeCompanyProvider);
    final range = _getDateRange(_selectedFilter);
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
    final theme = Theme.of(context);
    final range = _getDateRange(_selectedFilter);

    // Watch transactions and categories
    final txnsAsync = ref.watch(transactionsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final walletsAsync = ref.watch(walletsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Trends'),
        actions: [
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            txnsAsync.maybeWhen(
              data: (txns) => PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (val) {
                  if (val == 'csv') _exportCsv(txns);
                  if (val == 'pdf') _exportPdf(txns);
                  if (val == 'pnl') _showProfitAndLoss(txns);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'csv',
                    child: Row(
                      children: [
                        Icon(Icons.table_chart_outlined, size: 20),
                        SizedBox(width: 10),
                        Text('Export CSV'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'pdf',
                    child: Row(
                      children: [
                        Icon(Icons.picture_as_pdf_outlined, size: 20),
                        SizedBox(width: 10),
                        Text('Print / PDF Statement'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'pnl',
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 20),
                        SizedBox(width: 10),
                        Text('View Profit & Loss'),
                      ],
                    ),
                  ),
                ],
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ],
      ),
      body: txnsAsync.when(
        data: (allTxns) {
          final categories = categoriesAsync.value ?? [];
          final wallets = walletsAsync.value ?? [];

          // Compute reports
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

          final walletReport = ExpenseReportEngine.calculateWalletBalanceHistory(
            wallets: wallets,
            vouchers: allTxns,
          );

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Date filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ReportDateFilter.values.map((f) {
                    final isSelected = _selectedFilter == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: isSelected,
                        label: Text(f.label),
                        onSelected: (_) {
                          setState(() => _selectedFilter = f);
                        },
                        selectedColor: theme.colorScheme.primary.withAlpha(50),
                        labelStyle: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? theme.colorScheme.primary : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // 1. Income vs Expense Overview Card
              _IncomeVsExpenseCard(report: incExpReport),
              const SizedBox(height: 16),

              // 2. Monthly Trend Chart (CustomPainter)
              _MonthlyTrendCard(report: trendReport),
              const SizedBox(height: 16),

              // 3. Category Spending Breakdown (Donut Chart CustomPainter)
              _CategoryBreakdownCard(report: catReport),
              const SizedBox(height: 16),

              // 4. Wallet Distribution
              _WalletDistributionCard(report: walletReport),
              const SizedBox(height: 24),

              // Quick Action Bar
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _exportCsv(allTxns),
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('Export CSV'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _exportPdf(allTxns),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('PDF / Print'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(child: Text('Error loading reports: $e')),
      ),
    );
  }
}

// ==========================================
// 1. INCOME VS EXPENSE CARD
// ==========================================

class _IncomeVsExpenseCard extends StatelessWidget {
  final IncomeVsExpenseReport report;

  const _IncomeVsExpenseCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LiquidGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Income vs Expense',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (report.savingsRate >= 0 ? Colors.green : Colors.red).withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${report.savingsRate.toStringAsFixed(1)}% Saved',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: report.savingsRate >= 0 ? Colors.green : Colors.red,
                  ),
                ),
              ),
            ],
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
                        const Icon(Icons.arrow_downward, color: Colors.green, size: 16),
                        const SizedBox(width: 4),
                        Text('Income', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyFormatter.format(report.totalIncomeInCents),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                    Text('${report.incomeTransactionCount} entries', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              Container(width: 1, height: 48, color: Colors.grey.withAlpha(50)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.arrow_upward, color: Colors.redAccent, size: 16),
                        const SizedBox(width: 4),
                        Text('Expense', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyFormatter.format(report.totalExpenseInCents),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent),
                    ),
                    Text('${report.expenseTransactionCount} entries', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Net Savings',
                style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
              ),
              Text(
                CurrencyFormatter.format(report.netSavingsInCents),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: report.netSavingsInCents >= 0 ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Avg. Daily Spend',
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
              ),
              Text(
                CurrencyFormatter.format(report.averageDailySpendInCents.round()),
                style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 2. MONTHLY TREND CARD (CUSTOM PAINTER)
// ==========================================

class _MonthlyTrendCard extends StatelessWidget {
  final MonthlyTrendReport report;

  const _MonthlyTrendCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LiquidGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Monthly Trend (Last 6 Months)',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  _LegendDot(color: Colors.green, label: 'Income'),
                  const SizedBox(width: 8),
                  _LegendDot(color: Colors.redAccent, label: 'Expense'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 170,
            width: double.infinity,
            child: CustomPaint(
              painter: _MonthlyTrendChartPainter(
                months: report.months,
                isDark: isDark,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Avg. Monthly Spend: ${CurrencyFormatter.format(report.averageMonthlyExpenseInCents.round())}',
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
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
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}

class _MonthlyTrendChartPainter extends CustomPainter {
  final List<MonthlyTrendItem> months;
  final bool isDark;

  _MonthlyTrendChartPainter({required this.months, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;

    final double bottomPadding = 24.0;
    final double chartHeight = size.height - bottomPadding;
    final double width = size.width;

    // Find max value
    int maxVal = 1;
    for (final m in months) {
      if (m.totalIncomeInCents > maxVal) maxVal = m.totalIncomeInCents;
      if (m.totalExpenseInCents > maxVal) maxVal = m.totalExpenseInCents;
    }

    final double groupWidth = width / months.length;
    final double barWidth = (groupWidth * 0.32).clamp(6.0, 18.0);
    final double spacing = 3.0;

    final incomePaint = Paint()..color = Colors.green;
    final expensePaint = Paint()..color = Colors.redAccent;
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white10 : Colors.black12)
      ..strokeWidth = 1.0;

    // Draw grid lines
    canvas.drawLine(Offset(0, chartHeight), Offset(width, chartHeight), gridPaint);
    canvas.drawLine(Offset(0, chartHeight / 2), Offset(width, chartHeight / 2), gridPaint);

    final textStyle = TextStyle(
      color: isDark ? Colors.white60 : Colors.black54,
      fontSize: 10,
    );

    for (int i = 0; i < months.length; i++) {
      final m = months[i];
      final double groupCenterX = i * groupWidth + (groupWidth / 2);

      // Heights
      final double inHeight = (m.totalIncomeInCents / maxVal) * (chartHeight * 0.88);
      final double exHeight = (m.totalExpenseInCents / maxVal) * (chartHeight * 0.88);

      // Income bar
      final inRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(groupCenterX - barWidth - (spacing / 2), chartHeight - inHeight, barWidth, inHeight),
        const Radius.circular(4),
      );
      canvas.drawRRect(inRect, incomePaint);

      // Expense bar
      final exRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(groupCenterX + (spacing / 2), chartHeight - exHeight, barWidth, exHeight),
        const Radius.circular(4),
      );
      canvas.drawRRect(exRect, expensePaint);

      // Month label
      final textSpan = TextSpan(
        text: m.monthLabel.split(' ').first, // e.g. "Oct"
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
  bool shouldRepaint(covariant _MonthlyTrendChartPainter oldDelegate) => true;
}

// ==========================================
// 3. CATEGORY BREAKDOWN CARD (DONUT CHART)
// ==========================================

class _CategoryBreakdownCard extends StatelessWidget {
  final CategorySpendingReport report;

  const _CategoryBreakdownCard({required this.report});

  static const List<Color> _palette = [
    Color(0xFF3B82F6), // Blue
    Color(0xFFEF4444), // Red
    Color(0xFF10B981), // Green
    Color(0xFFF59E0B), // Amber
    Color(0xFF8B5CF6), // Purple
    Color(0xFFEC4899), // Pink
    Color(0xFF06B6D4), // Cyan
    Color(0xFF84CC16), // Lime
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (report.categories.isEmpty) {
      return LiquidGlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Spending by Category', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No expense transactions recorded in this period', style: TextStyle(color: Colors.grey)),
              ),
            ),
          ],
        ),
      );
    }

    return LiquidGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Spending by Category', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(
                CurrencyFormatter.format(report.totalSpentInCents),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Donut Chart
          Center(
            child: SizedBox(
              width: 140,
              height: 140,
              child: CustomPaint(
                painter: _CategoryDonutPainter(
                  categories: report.categories,
                  totalSpend: report.totalSpentInCents,
                  palette: _palette,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Category List
          ...report.categories.asMap().entries.map((entry) {
            final idx = entry.key;
            final cat = entry.value;
            final color = _palette[idx % _palette.length];

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cat.categoryName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      Text(
                        '${cat.percentage.toStringAsFixed(1)}%',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        CurrencyFormatter.format(cat.totalSpentInCents),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: (cat.percentage / 100.0).clamp(0.0, 1.0),
                      backgroundColor: isDark ? Colors.white10 : Colors.black12,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 4,
                    ),
                  ),
                  if (cat.subCategories.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 18, top: 4),
                      child: Column(
                        children: cat.subCategories.map((sub) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('• ${sub.categoryName}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                Text(
                                  CurrencyFormatter.format(sub.totalSpentInCents),
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
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

  _CategoryDonutPainter({
    required this.categories,
    required this.totalSpend,
    required this.palette,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalSpend <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 24.0;
    final rect = Rect.fromCircle(center: center, radius: radius - (strokeWidth / 2));

    double startAngle = -math.pi / 2;

    for (int i = 0; i < categories.length; i++) {
      final sweepAngle = (categories[i].totalSpentInCents / totalSpend) * 2 * math.pi;
      final paint = Paint()
        ..color = palette[i % palette.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _CategoryDonutPainter oldDelegate) => true;
}

// ==========================================
// 4. WALLET DISTRIBUTION CARD
// ==========================================

class _WalletDistributionCard extends StatelessWidget {
  final WalletBalanceHistoryReport report;

  const _WalletDistributionCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LiquidGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Wallets & Accounts', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(
                'Total: ${CurrencyFormatter.format(report.totalBalanceInCents)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...report.wallets.map((w) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 20, color: Colors.blueAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(w.walletName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(
                          'In: ${CurrencyFormatter.format(w.totalInInCents)} • Out: ${CurrencyFormatter.format(w.totalOutInCents)}',
                          style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    CurrencyFormatter.format(w.currentBalanceInCents),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
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
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
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
                  Text('Profit & Loss Statement', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  Text(company.name, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
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
                            fontWeight: isNet ? FontWeight.bold : FontWeight.w500,
                            fontSize: isNet ? 15 : 13,
                          ),
                        ),
                      ),
                      Text(
                        amount,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: isNet ? 16 : 14,
                          color: isNet ? Colors.green : null,
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
