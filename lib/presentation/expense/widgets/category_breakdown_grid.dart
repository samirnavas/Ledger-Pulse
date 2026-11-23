import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';

typedef CategoryBreakdownTileData = ({
  String name,
  int amountInCents,
  double percentage,
  VoidCallback? onTap,
});

class CategoryBreakdownGrid extends StatelessWidget {
  const CategoryBreakdownGrid({
    super.key,
    required this.tiles,
    required this.currencyCode,
  });

  final List<CategoryBreakdownTileData> tiles;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    const gap = 8.0;
    final colors = Theme.of(context).colorScheme;
    final accents = [
      (colors.primaryContainer, colors.onPrimaryContainer),
      (colors.secondaryContainer, colors.onSecondaryContainer),
      (colors.tertiaryContainer, colors.onTertiaryContainer),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final minimumWidth = MediaQuery.textScalerOf(context).scale(78);
        final columns = ((constraints.maxWidth + gap) / (minimumWidth + gap))
            .floor()
            .clamp(1, 3);
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (index, tile) in tiles.indexed)
              SizedBox(
                width: width,
                child: _CategoryBreakdownTile(
                  tile: tile,
                  currencyCode: currencyCode,
                  colors: accents[index % accents.length],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CategoryBreakdownTile extends StatelessWidget {
  const _CategoryBreakdownTile({
    required this.tile,
    required this.currencyCode,
    required this.colors,
  });

  final CategoryBreakdownTileData tile;
  final String currencyCode;
  final (Color, Color) colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground) = colors;
    final share = tile.percentage.toStringAsFixed(
      tile.percentage >= 10 ? 0 : 1,
    );
    final amount = CurrencyFormatter.format(
      tile.amountInCents,
      currencyCode: currencyCode,
    );

    return Tooltip(
      message: '${tile.name} · $amount · $share%',
      excludeFromSemantics: true,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: foreground.withValues(alpha: 0.15)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tile.onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(color: foreground),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          CurrencyFormatter.formatCompact(
                            tile.amountInCents,
                            currencyCode: currencyCode,
                            includeSymbol: true,
                          ),
                          semanticsLabel: amount,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$share%',
                      semanticsLabel: '$share percent of spending',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: foreground,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
