import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/adaptive_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/adaptive_list_row.dart';
import '../../../core/widgets/adaptive_section_header.dart';
import '../../../core/widgets/adaptive_surface_card.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../data/models/account_model.dart';

/// Series color palette helper providing distinct, vibrant, high-contrast colors
/// for data visualization (pie charts, breakdown series) across platforms and themes.
List<Color> getChartPalette(BuildContext context) {
  final isIos = AdaptiveThemeHelper.isIos(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;

  if (isIos) {
    return const [
      CupertinoColors.systemBlue,
      CupertinoColors.systemOrange,
      CupertinoColors.systemGreen,
      CupertinoColors.systemPurple,
      CupertinoColors.systemPink,
      CupertinoColors.systemTeal,
      CupertinoColors.systemYellow,
      CupertinoColors.systemIndigo,
      CupertinoColors.systemRed,
      CupertinoColors.systemMint,
      CupertinoColors.systemCyan,
    ];
  } else {
    if (isDark) {
      return const [
        Color(0xFF818CF8), // Indigo / Periwinkle (Vibrant & crisp on dark)
        Color(0xFF34D399), // Emerald / Mint
        Color(0xFFFBBF24), // Amber / Warm Yellow
        Color(0xFFF472B6), // Pink / Rose
        Color(0xFFA78BFA), // Purple / Violet
        Color(0xFF22D3EE), // Cyan / Sky
        Color(0xFFF87171), // Coral Red
        Color(0xFF2DD4BF), // Teal
        Color(0xFF60A5FA), // Bright Blue
        Color(0xFFA3E635), // Lime
      ];
    } else {
      return const [
        Color(0xFF4F46E5), // Indigo
        Color(0xFF059669), // Emerald
        Color(0xFFD97706), // Amber
        Color(0xFFDB2777), // Pink
        Color(0xFF7C3AED), // Purple
        Color(0xFF0891B2), // Cyan
        Color(0xFFDC2626), // Coral Red
        Color(0xFF0D9488), // Teal
        Color(0xFF2563EB), // Bright Blue
        Color(0xFF65A30D), // Lime
      ];
    }
  }
}

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
    final palette = getChartPalette(context);

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
            const AdaptiveSectionHeader(
              title: 'Category Breakdown',
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
          AdaptiveSectionHeader(
            padding: EdgeInsets.zero,
            title: 'Category Breakdown',
            trailing: Text(
              '${spentEntries.length} ${spentEntries.length == 1 ? 'Category' : 'Categories'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 16),
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
                    backgroundColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
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
      if (slices.length > 1 && sweepAngle > gap) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
          startAngle + gap / 2,
          sweepAngle - gap,
          false,
          slicePaint,
        );
      } else if (sweepAngle > 0) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
          startAngle,
          sweepAngle,
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
