import 'package:flutter/material.dart';

import '../../../core/theme/adaptive_theme.dart';
import '../../../core/widgets/liquid_glass_card.dart';

/// Card wrapper adapting between iOS LiquidGlassCard and Material 3 elevated container.
class VoucherAdaptiveCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const VoucherAdaptiveCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 24,
        padding: padding,
        color: isDark
            ? const Color(0xFF1E293B).withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.7),
        borderColor: isDark
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.black.withValues(alpha: 0.08),
        child: child,
      );
    } else {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.45),
            width: 1,
          ),
        ),
        child: child,
      );
    }
  }
}
