import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/adaptive_section_header.dart';
import '../../../core/widgets/adaptive_surface_card.dart';
import '../../../data/models/account_model.dart';
import 'category_breakdown_grid.dart';

class CategoryBreakdownCard extends StatelessWidget {
  final Map<String, int> categoryTotalsInCents;
  final List<AccountModel> categories;
  final String currencyCode;
  final int totalExpenseInCents;
  final void Function(String categoryId)? onCategoryTap;
  final VoidCallback? onCardTap;

  const CategoryBreakdownCard({
    super.key,
    required this.categoryTotalsInCents,
    required this.categories,
    required this.currencyCode,
    required this.totalExpenseInCents,
    this.onCategoryTap,
    this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Filter categories that have spending > 0
    final Map<String, AccountModel> catMap = {
      for (final c in categories) c.id: c,
    };

    final List<MapEntry<String, int>> spentEntries =
        categoryTotalsInCents.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    if (spentEntries.isEmpty || totalExpenseInCents <= 0) {
      return AdaptiveSurfaceCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdaptiveSectionHeader(title: 'Category Breakdown'),
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

    return AdaptiveSurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveSectionHeader(
            padding: EdgeInsets.zero,
            title: 'Category Breakdown',
            trailing: GestureDetector(
              onTap: onCardTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${spentEntries.length} ${spentEntries.length == 1 ? 'Category' : 'Categories'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (onCardTap != null) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            CurrencyFormatter.format(
              totalExpenseInCents,
              currencyCode: currencyCode,
            ),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          CategoryBreakdownGrid(
            currencyCode: currencyCode,
            tiles: [
              for (final entry in spentEntries.take(6))
                (
                  name: catMap[entry.key]?.name ?? 'Other',
                  amountInCents: entry.value,
                  percentage: entry.value / totalExpenseInCents * 100,
                  onTap: onCategoryTap == null
                      ? null
                      : () => onCategoryTap!(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
