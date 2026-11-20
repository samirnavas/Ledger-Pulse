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
  final Clip clipBehavior;

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
    this.clipBehavior = Clip.none,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveRadius = borderRadius ?? (isIos ? 20.0 : 28.0);
    final shape = BorderRadius.circular(effectiveRadius);
    final content = clipBehavior == Clip.none
        ? child
        : ClipRRect(
            borderRadius: shape,
            clipBehavior: clipBehavior,
            child: child,
          );

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
        borderRadius: effectiveRadius,
        padding: padding,
        margin: margin,
        color: color,
        borderColor: accentColor?.withValues(alpha: isDark ? 0.35 : 0.2),
        onTap: onTap,
        child: content,
      );

      if (!isDark && lightShadows != null) {
        card = Container(
          decoration: BoxDecoration(
            borderRadius: shape,
            boxShadow: lightShadows,
          ),
          child: card,
        );
      }

      if (onTap == null) return card;

      return _IosPressFadeWidget(onTap: onTap, child: card);
    }

    final cardBorder = Border.all(
      color: (accentColor ?? Theme.of(context).colorScheme.primary).withValues(
        alpha: isDark ? 0.22 : 0.16,
      ),
      width: 0.75,
    );

    final containerDecoration = BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: shape,
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
          borderRadius: shape,
          child: InkWell(
            borderRadius: shape,
            onTap: () {
              HapticFeedback.lightImpact();
              onTap!();
            },
            child: Padding(
              padding: padding ?? const EdgeInsets.all(16),
              child: content,
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
      child: content,
    );
  }
}

class _IosPressFadeWidget extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _IosPressFadeWidget({required this.child, required this.onTap});

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
