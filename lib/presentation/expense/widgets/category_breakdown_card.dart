import 'package:flutter/material.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/liquid_glass_card.dart';
import '../../../data/models/account_model.dart';

/// A sleek category spending breakdown widget featuring custom donut chart
/// rendering, category color swatches, percentage allocations, and currency amounts.
class CategoryBreakdownCard extends StatelessWidget {
  final Map<String, int> categoryTotalsInCents;
  final List<AccountModel> categories;
  final String currencyCode;
  final int totalExpenseInCents;

  const CategoryBreakdownCard({
    super.key,
    required this.categoryTotalsInCents,
    required this.categories,
    required this.currencyCode,
    required this.totalExpenseInCents,
  });

  static const List<Color> _palette = [
    Color(0xFF6366F1), // Indigo
    Color(0xFFEC4899), // Pink
    Color(0xFF10B981), // Emerald
    Color(0xFFF59E0B), // Amber
    Color(0xFF8B5CF6), // Purple
    Color(0xFF06B6D4), // Cyan
    Color(0xFFF97316), // Orange
    Color(0xFF14B8A6), // Teal
    Color(0xFFE11D48), // Rose
    Color(0xFF64748B), // Slate
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Filter categories that have spending > 0
    final Map<String, AccountModel> catMap = {
      for (final c in categories) c.id: c,
    };

    final List<MapEntry<String, int>> spentEntries = categoryTotalsInCents.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (spentEntries.isEmpty || totalExpenseInCents <= 0) {
      return LiquidGlassCard(
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
      final color = _palette[i % _palette.length];
      final percentage = (entry.value / totalExpenseInCents) * 100.0;
      slices.add(_CategorySlice(
        name: name,
        amountInCents: entry.value,
        percentage: percentage,
        color: color,
      ));
    }

    return LiquidGlassCard(
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
              const SizedBox(width: 20),
              // Category legend list (Top 4)
              Expanded(
                child: Column(
                  children: slices.take(4).map((slice) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: slice.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              slice.name,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${slice.percentage.toStringAsFixed(0)}%',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            CurrencyFormatter.format(
                              slice.amountInCents,
                              currencyCode: currencyCode,
                              showDecimalsAlways: false,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
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
  final String name;
  final int amountInCents;
  final double percentage;
  final Color color;

  const _CategorySlice({
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
