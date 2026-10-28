import 'package:flutter/material.dart';
import '../constants/typography.dart';
import 'adaptive_surface_card.dart';
import 'amount_text.dart';

/// Platform-adaptive metric summary card primitive, extracting the dashboard's
/// "You'll Get" / "You'll Give" card styling into a generic reusable component.
class AdaptiveMetricCard extends StatelessWidget {
  final String label;
  final int amountInCents;
  final Color accentColor;
  final Widget icon;
  final AmountVariant amountVariant;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String currencyCode;
  final Color? labelColor;
  final Color? amountColor;

  const AdaptiveMetricCard({
    super.key,
    required this.label,
    required this.amountInCents,
    required this.accentColor,
    required this.icon,
    this.amountVariant = AmountVariant.large,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.currencyCode = 'INR',
    this.labelColor,
    this.amountColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final effectiveLabelColor = labelColor ??
        (isDark ? accentColor : _getDarkerTone(accentColor));
    final effectiveAmountColor = amountColor ?? accentColor;

    return AdaptiveSurfaceCard(
      accentColor: accentColor,
      padding: padding,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: isDark
                      ? accentColor.withValues(alpha: 0.2)
                      : accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: icon,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.labelSmall.copyWith(
                    color: effectiveLabelColor,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          AmountText(
            amountInCents: amountInCents,
            variant: amountVariant,
            overrideColor: effectiveAmountColor,
            currencyCode: currencyCode,
          ),
        ],
      ),
    );
  }

  /// Calculates a slightly deeper shade for high contrast in light mode
  static Color _getDarkerTone(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0)).toColor();
  }
}
