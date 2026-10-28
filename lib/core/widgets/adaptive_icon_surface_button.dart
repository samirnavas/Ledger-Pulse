import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';
import '../constants/colors.dart';
import '../theme/adaptive_theme.dart';

/// Platform-adaptive square icon surface button, extracted from the sort & filter
/// action buttons in [PartyListTab].
/// - iOS: [LiquidGlassContainer] height 44, width 44, radius 14.
/// - Android: M3 Container height 48, width 48, radius 24, surfaceContainerHigh.
class AdaptiveIconSurfaceButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isActive;
  final Color? activeColor;
  final Color? inactiveColor;
  final String? tooltip;
  final double? size;

  const AdaptiveIconSurfaceButton({
    super.key,
    required this.icon,
    this.onTap,
    this.isActive = false,
    this.activeColor,
    this.inactiveColor,
    this.tooltip,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final effectiveActiveColor = activeColor ??
        (isIos ? AppColors.primaryBlue : Theme.of(context).colorScheme.primary);
    final effectiveInactiveColor = inactiveColor ??
        (isIos
            ? (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)
            : Theme.of(context).colorScheme.onSurface);

    final color = isActive ? effectiveActiveColor : effectiveInactiveColor;

    Widget button;

    if (isIos) {
      final btnSize = size ?? 44.0;
      button = InkWell(
        onTap: () {
          if (onTap != null) {
            HapticFeedback.lightImpact();
            onTap!();
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: LiquidGlassContainer(
          height: btnSize,
          width: btnSize,
          borderRadius: 14,
          blur: 20,
          border: 1.0,
          child: Icon(
            icon,
            size: 20,
            color: color,
          ),
        ),
      );
    } else {
      final btnSize = size ?? 48.0;
      button = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (onTap != null) {
              HapticFeedback.lightImpact();
              onTap!();
            }
          },
          borderRadius: BorderRadius.circular(24),
          child: Container(
            height: btnSize,
            width: btnSize,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant.withValues(
                      alpha: isDark ? 0.35 : 0.5,
                    ),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              size: 22,
              color: color,
            ),
          ),
        ),
      );
    }

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
