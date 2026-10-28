import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/adaptive_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/adaptive_list_row.dart';
import '../../../core/widgets/adaptive_surface_card.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../data/models/account_model.dart';

/// A sleek category spending breakdown widget featuring custom donut chart
/// rendering, adaptive color swatches, percentage allocations, and currency amounts.
/// Wrapped in [AdaptiveSurfaceCard] with [AdaptiveListRow] density for the legend.
class CategoryBreakdownCard extends StatelessWidget {
  final Map<String, int> categoryTotalsInCents;
  final List<AccountModel> categories;
  final String currencyCode;
  final int totalExpenseInCents;
  final void Function(String categoryId)? onCategoryTap;

  const CategoryBreakdownCard({
    super.key,
    required this.categoryTotalsInCents,
    required this.categories,
    required this.currencyCode,
    required this.totalExpenseInCents,
    this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = theme.brightness == Brightness.dark;

    // Build palette from colorScheme (primary, secondary, tertiary & containers on Android)
    // and fixed iOS system palette on iOS.
    final List<Color> palette = isIos
        ? const [
            CupertinoColors.systemBlue,
            CupertinoColors.systemIndigo,
            CupertinoColors.systemPurple,
            CupertinoColors.systemPink,
            CupertinoColors.systemOrange,
            CupertinoColors.systemTeal,
            CupertinoColors.systemGreen,
            CupertinoColors.systemYellow,
            CupertinoColors.systemRed,
            CupertinoColors.systemMint,
            CupertinoColors.systemCyan,
          ]
        : [
            theme.colorScheme.primary,
            theme.colorScheme.secondary,
            theme.colorScheme.tertiary,
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer,
            theme.colorScheme.tertiaryContainer,
            theme.colorScheme.surfaceTint,
            theme.colorScheme.error,
          ];

    // Filter categories that have spending > 0
    final Map<String, AccountModel> catMap = {
      for (final c in categories) c.id: c,
    };

    final List<MapEntry<String, int>> spentEntries = categoryTotalsInCents.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (spentEntries.isEmpty || totalExpenseInCents <= 0) {
      return AdaptiveSurfaceCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Category Breakdown',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No expenses recorded for this period.',
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

    final List<_CategorySlice> slices = [];
    for (int i = 0; i < spentEntries.length; i++) {
      final entry = spentEntries[i];
      final cat = catMap[entry.key];
      final name = cat?.name ?? 'Other';
      final color = palette[i % palette.length];
      final percentage = (entry.value / totalExpenseInCents) * 100.0;
      slices.add(_CategorySlice(
        categoryId: entry.key,
        name: name,
        amountInCents: entry.value,
        percentage: percentage,
        color: color,
      ));
    }

    return AdaptiveSurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Category Breakdown',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${spentEntries.length} ${spentEntries.length == 1 ? 'Category' : 'Categories'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Custom Donut Chart
              SizedBox(
                width: 110,
                height: 110,
                child: CustomPaint(
                  painter: _DonutChartPainter(
                    slices: slices,
                    backgroundColor: isDark
                        ? const Color(0xFF27272A)
                        : const Color(0xFFE2E8F0),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Total',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          CurrencyFormatter.formatCompact(
                            totalExpenseInCents,
                            currencyCode: currencyCode,
                            includeSymbol: false,
                          ),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Category legend list (Top 4) using AdaptiveListRow density
              Expanded(
                child: Column(
                  children: slices.take(4).map((slice) {
                    return AdaptiveListRow(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      showDivider: false,
                      onTap: onCategoryTap != null
                          ? () => onCategoryTap!(slice.categoryId)
                          : null,
                      leading: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: slice.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: slice.name,
                      subtitle: '${slice.percentage.toStringAsFixed(0)}%',
                      trailing: AmountText(
                        amountInCents: slice.amountInCents,
                        variant: AmountVariant.small,
                        currencyCode: currencyCode,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategorySlice {
  final String categoryId;
  final String name;
  final int amountInCents;
  final double percentage;
  final Color color;

  const _CategorySlice({
    required this.categoryId,
    required this.name,
    required this.amountInCents,
    required this.percentage,
    required this.color,
  });
}

class _DonutChartPainter extends CustomPainter {
  final List<_CategorySlice> slices;
  final Color backgroundColor;

  const _DonutChartPainter({
    required this.slices,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 14.0;

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius - strokeWidth / 2, backgroundPaint);

    double startAngle = -3.141592653589793 / 2;

    for (final slice in slices) {
      final sweepAngle = (slice.percentage / 100.0) * 2 * 3.141592653589793;
      final slicePaint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      // Draw arc slightly reduced for rounded separator gap
      const gap = 0.04;
      if (sweepAngle > gap) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
          startAngle + gap / 2,
          sweepAngle - gap,
          false,
          slicePaint,
        );
      }
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) => true;
}
