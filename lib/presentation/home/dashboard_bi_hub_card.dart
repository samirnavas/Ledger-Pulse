import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/liquid_glass_card.dart';

import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/utils/currency_formatter.dart';
import '../providers/reporting_providers.dart';
import '../reports/reporting_hub_screen.dart';

class DashboardBiHubCard extends ConsumerStatefulWidget {
  const DashboardBiHubCard({super.key});

  @override
  ConsumerState<DashboardBiHubCard> createState() => _DashboardBiHubCardState();
}

class _DashboardBiHubCardState extends ConsumerState<DashboardBiHubCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final biAsync = ref.watch(dashboardBiMetricsProvider);

    return biAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (err, stack) => const SizedBox.shrink(),
      data: (bi) {
        final cardContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with title & expand toggle
            InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _isExpanded = !_isExpanded);
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isIos ? CupertinoIcons.chart_bar_alt_fill : Icons.insights_rounded,
                        color: AppColors.primaryBlue,
                        size: 20,
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
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            _isExpanded
                                ? 'Tap to collapse analytics'
                                : 'Tap to view Income vs. Expense & BI trends',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _isExpanded
                          ? (isIos ? CupertinoIcons.chevron_up : Icons.keyboard_arrow_up_rounded)
                          : (isIos ? CupertinoIcons.chevron_down : Icons.keyboard_arrow_down_rounded),
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),

            // Expanded BI Hub Details
            if (_isExpanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Quick Stats: Sales Velocity & Net Profit
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            context: context,
                            title: 'Sales Velocity',
                            value: '${CurrencyFormatter.format(bi.salesVelocityPerDayInCents.round())}/day',
                            icon: Icons.speed_rounded,
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
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                            iconColor: bi.netProfitInCents >= 0
                                ? AppColors.receivableGreen
                                : AppColors.payableRed,
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 2. Monthly Income vs. Expense Trend Chart
                    Text(
                      'Income vs. Expense Trend',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildTrendChart(context, bi.monthlyTrends, isDark),
                    const SizedBox(height: 16),

                    // 3. Cash Flow Breakdown (Receivables vs Payables)
                    Text(
                      'Cash Flow & Working Capital',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildCashFlowBreakdown(context, bi, isDark),
                    const SizedBox(height: 16),

                    // 4. Top Expense Categories
                    if (bi.topExpenseCategories.isNotEmpty) ...[
                      Text(
                        'Top Expense Drivers',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...bi.topExpenseCategories.take(3).map((cat) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Text(
                                  cat.categoryName,
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  CurrencyFormatter.format(cat.amountInCents),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 44,
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.payableRed.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${cat.percentage.toStringAsFixed(0)}%',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.payableRed,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 14),
                    ],

                    // 5. Shortcut to Master Reporting Hub
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).push(
                            createAdaptivePageRoute(
                              builder: (ctx) => const ReportingHubScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.analytics_rounded, size: 18),
                        label: const Text(
                          'Open Master Reporting Hub (36 Reports & GSTR)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );

        if (isIos) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: LiquidGlassCard(
              borderRadius: 18,
              color: isDark
                  ? const Color(0xFF1E293B).withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.8),
              borderColor: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.08),
              child: cardContent,
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant.withValues(
                      alpha: isDark ? 0.35 : 0.5,
                    ),
              ),
            ),
            child: cardContent,
          ),
        );
      },
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
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
      return const Text('No recent monthly data');
    }

    int maxVal = 1;
    for (final t in trends) {
      if (t.incomeInCents > maxVal) maxVal = t.incomeInCents;
      if (t.expenseInCents > maxVal) maxVal = t.expenseInCents;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: trends.map((t) {
              final incomeHeight = ((t.incomeInCents / maxVal) * 55).clamp(4.0, 55.0);
              final expenseHeight = ((t.expenseInCents / maxVal) * 55).clamp(4.0, 55.0);

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
                  const SizedBox(height: 6),
                  Text(
                    t.monthLabel,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 8, height: 8, color: AppColors.receivableGreen),
              const SizedBox(width: 4),
              const Text('Income', style: TextStyle(fontSize: 10)),
              const SizedBox(width: 16),
              Container(width: 8, height: 8, color: AppColors.payableRed),
              const SizedBox(width: 4),
              const Text('Expense', style: TextStyle(fontSize: 10)),
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
            height: 12,
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
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Receivables: ${CurrencyFormatter.format(bi.totalReceivableInCents)}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.receivableGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Payables: ${CurrencyFormatter.format(bi.totalPayableInCents)}',
              style: const TextStyle(
                fontSize: 11,
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
