import 'package:flutter/material.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';

class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final double blur;
  final double border;
  final Color? color;
  final Color? borderColor;

  const LiquidGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 20,
    this.onTap,
    this.width,
    this.height,
    this.blur = 24,
    this.border = 0.75,
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LiquidGlassContainer(
      width: width,
      height: height,
      padding: padding,
      margin: margin,
      borderRadius: borderRadius,
      blur: blur,
      border: border,
      color: color ?? (theme.brightness == Brightness.light
          ? theme.colorScheme.surfaceContainer
          : null),
      borderColor: borderColor ?? theme.colorScheme.primary.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.22 : 0.16,
      ),
      onTap: onTap,
      child: child,
    );
  }
}



