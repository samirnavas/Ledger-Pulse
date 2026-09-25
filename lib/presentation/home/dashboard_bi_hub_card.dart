import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../providers/reporting_providers.dart';
import '../reports/reporting_hub_screen.dart';

/// A sleek, responsive Draggable Modal Sheet presenting Business Intelligence & Cash Flow analytics.
class BusinessIntelligenceSheet extends ConsumerWidget {
  const BusinessIntelligenceSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final biAsync = ref.watch(dashboardBiMetricsProvider);

    final containerColor = isIos
        ? (isDark
            ? CupertinoColors.systemBackground.darkColor
            : CupertinoColors.systemBackground)
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.40,
          maxChildSize: 0.95,
          snap: true,
          snapSizes: const [0.78, 0.95],
          snapAnimationDuration: const Duration(milliseconds: 250),
          shouldCloseOnMinExtent: true,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: containerColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28.0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.15),
                    blurRadius: 18,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 8,
                bottom: MediaQuery.of(context).padding.bottom + 20,
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag Handle
                    const ModalDragHandle(
                      margin: EdgeInsets.only(bottom: 8.0),
                    ),

                    // Sheet Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryBlue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isIos
                                ? CupertinoIcons.chart_bar_alt_fill
                                : Icons.insights_rounded,
                            color: AppColors.primaryBlue,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Business Intelligence & Cash Flow',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                'Telemetry, margins & working capital breakdown',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            isIos ? CupertinoIcons.xmark_circle_fill : Icons.close_rounded,
                            size: 20,
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    // Sheet Body
                    biAsync.when(
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      ),
                      error: (err, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Failed to load analytics: $err',
                            style: const TextStyle(
                              color: AppColors.payableRed,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      data: (bi) => _buildBiContent(context, bi, isDark),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBiContent(
    BuildContext context,
    DashboardBiMetrics bi,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Quick Stats: Sales Velocity & Net Margin
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                context: context,
                title: 'Sales Velocity',
                value:
                    '${CurrencyFormatter.format(bi.salesVelocityPerDayInCents.round())}/day',
                icon: AdaptiveThemeHelper.isIos(context)
                    ? CupertinoIcons.speedometer
                    : Icons.speed_rounded,
                iconColor: AppColors.primaryBlue,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                context: context,
                title: 'Net Margin',
                value: CurrencyFormatter.format(bi.netProfitInCents),
                icon: bi.netProfitInCents >= 0
                    ? (AdaptiveThemeHelper.isIos(context)
                        ? CupertinoIcons.graph_square_fill
                        : Icons.trending_up_rounded)
                    : (AdaptiveThemeHelper.isIos(context)
                        ? CupertinoIcons.graph_square
                        : Icons.trending_down_rounded),
                iconColor: bi.netProfitInCents >= 0
                    ? AppColors.receivableGreen
                    : AppColors.payableRed,
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // 2. Monthly Income vs. Expense Trend Chart
        Text(
          'Income vs. Expense Trend',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        _buildTrendChart(context, bi.monthlyTrends, isDark),
        const SizedBox(height: 18),

        // 3. Cash Flow Breakdown (Receivables vs Payables)
        Text(
          'Cash Flow & Working Capital',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        _buildCashFlowBreakdown(context, bi, isDark),
        const SizedBox(height: 18),

        // 4. Top Expense Categories
        if (bi.topExpenseCategories.isNotEmpty) ...[
          Text(
            'Top Expense Drivers',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          ...bi.topExpenseCategories.take(4).map((cat) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      cat.categoryName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      CurrencyFormatter.format(cat.amountInCents),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 48,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.payableRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${cat.percentage.toStringAsFixed(0)}%',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.payableRed,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
        ],

        // 5. Shortcut to Master Reporting Hub
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop(); // Close sheet
              Navigator.of(context).push(
                createAdaptivePageRoute(
                  builder: (ctx) => const ReportingHubScreen(),
                ),
              );
            },
            icon: Icon(
              AdaptiveThemeHelper.isIos(context)
                  ? CupertinoIcons.chart_pie_fill
                  : Icons.analytics_rounded,
              size: 18,
            ),
            label: const Text(
              'Open Master Reporting Hub (36 Reports & GSTR)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required BuildContext context,
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(
                alpha: isDark ? 0.2 : 0.4,
              ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart(
    BuildContext context,
    List<MonthlyTrendPoint> trends,
    bool isDark,
  ) {
    if (trends.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        alignment: Alignment.center,
        child: const Text('No recent monthly data available'),
      );
    }

    int maxVal = 1;
    for (final t in trends) {
      if (t.incomeInCents > maxVal) maxVal = t.incomeInCents;
      if (t.expenseInCents > maxVal) maxVal = t.expenseInCents;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(
                alpha: isDark ? 0.2 : 0.4,
              ),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: trends.map((t) {
              final incomeHeight =
                  ((t.incomeInCents / maxVal) * 60).clamp(4.0, 60.0);
              final expenseHeight =
                  ((t.expenseInCents / maxVal) * 60).clamp(4.0, 60.0);

              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Income bar (green)
                      Container(
                        width: 12,
                        height: incomeHeight,
                        decoration: BoxDecoration(
                          color: AppColors.receivableGreen,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Expense bar (red)
                      Container(
                        width: 12,
                        height: expenseHeight,
                        decoration: BoxDecoration(
                          color: AppColors.payableRed,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.monthLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.receivableGreen,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Income',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 20),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.payableRed,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Expense',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCashFlowBreakdown(
    BuildContext context,
    DashboardBiMetrics bi,
    bool isDark,
  ) {
    final total = (bi.totalReceivableInCents + bi.totalPayableInCents);
    final recPct = total > 0 ? (bi.totalReceivableInCents / total) : 0.5;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                Expanded(
                  flex: (recPct * 100).round().clamp(1, 99),
                  child: Container(color: AppColors.receivableGreen),
                ),
                Expanded(
                  flex: ((1 - recPct) * 100).round().clamp(1, 99),
                  child: Container(color: AppColors.payableRed),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Receivables: ${CurrencyFormatter.format(bi.totalReceivableInCents)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.receivableGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Payables: ${CurrencyFormatter.format(bi.totalPayableInCents)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.payableRed,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Backward compatibility alias
typedef DashboardBiHubCard = BusinessIntelligenceSheet;
