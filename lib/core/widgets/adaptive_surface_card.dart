import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/adaptive_theme.dart';
import 'liquid_glass_card.dart';

/// Platform-adaptive surface card primitive.
/// - iOS: [LiquidGlassCard] with default radius 20, frosted glass blur, and press-fade feedback.
/// - Android: M3 `colorScheme.surfaceContainer` with default radius 28, optional 1.5px accent border,
///   and ripple ink response on tap.
class AdaptiveSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final Color? accentColor;
  final Color? color;
  final VoidCallback? onTap;
  final double? width;
  final double? height;

  const AdaptiveSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius,
    this.accentColor,
    this.color,
    this.onTap,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final lightShadows = !isDark
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              spreadRadius: 0,
              offset: const Offset(0, 3),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              spreadRadius: 0,
              offset: const Offset(0, 1),
            ),
          ]
        : null;

    if (isIos) {
      Widget card = LiquidGlassCard(
        width: width,
        height: height,
        borderRadius: borderRadius ?? 20,
        padding: padding,
        margin: margin,
        color: color,
        borderColor: accentColor?.withValues(alpha: isDark ? 0.35 : 0.2),
        onTap: onTap,
        child: child,
      );

      if (!isDark && lightShadows != null) {
        card = Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius ?? 20),
            boxShadow: lightShadows,
          ),
          child: card,
        );
      }

      if (onTap == null) return card;

      return _IosPressFadeWidget(
        onTap: onTap,
        child: card,
      );
    }

    final effectiveRadius = borderRadius ?? 28.0;
    final cardBorder = accentColor != null
        ? Border.all(
            color: accentColor!.withValues(alpha: isDark ? 0.35 : 0.2),
            width: 1.5,
          )
        : Border.all(
            color: isDark ? Colors.transparent : Colors.black.withValues(alpha: 0.04),
            width: 1.0,
          );

    final containerDecoration = BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(effectiveRadius),
      border: cardBorder,
      boxShadow: lightShadows,
    );

    if (onTap != null) {
      return Container(
        width: width,
        height: height,
        margin: margin,
        decoration: containerDecoration,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(effectiveRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(effectiveRadius),
            onTap: () {
              HapticFeedback.lightImpact();
              onTap!();
            },
            child: Padding(
              padding: padding ?? const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      );
    }

    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: containerDecoration,
      child: child,
    );
  }
}

class _IosPressFadeWidget extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _IosPressFadeWidget({
    required this.child,
    required this.onTap,
  });

  @override
  State<_IosPressFadeWidget> createState() => _IosPressFadeWidgetState();
}

class _IosPressFadeWidgetState extends State<_IosPressFadeWidget> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap!();
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 100),
        opacity: _isPressed ? 0.7 : 1.0,
        child: widget.child,
      ),
    );
  }
}
