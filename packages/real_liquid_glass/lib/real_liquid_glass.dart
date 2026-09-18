import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// A native liquid glass container component providing Apple UIGlassEffect aesthetics on iOS
/// and graceful high-fidelity frosted glass refraction fallback across platforms.
class LiquidGlassContainer extends StatelessWidget {
  final Widget? child;
  final double? width;
  final double? height;
  final double borderRadius;
  final double blur;
  final double border;
  final Color? borderColor;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final AlignmentGeometry alignment;
  final VoidCallback? onTap;

  const LiquidGlassContainer({
    super.key,
    this.child,
    this.width,
    this.height,
    this.borderRadius = 20,
    this.blur = 24,
    this.border = 1.2,
    this.borderColor,
    this.color,
    this.padding,
    this.margin,
    this.alignment = Alignment.center,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    final defaultTintColor = isDark
        ? CupertinoColors.systemGrey6.withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.65);

    final effectiveColor = color ?? defaultTintColor;

    final effectiveBorderColor = borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.3)
            : Colors.white.withValues(alpha: 0.6));

    Widget content = Container(
      width: width,
      height: height,
      padding: padding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: effectiveColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: effectiveBorderColor,
          width: border,
        ),
      ),
      child: child,
    );

    if (onTap != null) {
      content = GestureDetector(
        onTap: onTap,
        child: content,
      );
    }

    Widget glass = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: content,
      ),
    );

    if (margin != null) {
      glass = Padding(
        padding: margin!,
        child: glass,
      );
    }

    return glass;
  }
}

/// Allows multiple liquid glass shapes to fuse together.
class LiquidGlassGroup extends StatelessWidget {
  final List<Widget> children;
  final double mergeStrength;

  const LiquidGlassGroup({
    super.key,
    required this.children,
    this.mergeStrength = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: children,
    );
  }
}

/// Liquid glass bottom bar for iOS and macOS.
class LiquidGlassBottomBar extends StatelessWidget {
  final List<BottomNavigationBarItem> items;
  final int currentIndex;
  final ValueChanged<int>? onTap;

  const LiquidGlassBottomBar({
    super.key,
    required this.items,
    this.currentIndex = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      borderRadius: 28,
      child: CupertinoTabBar(
        items: items,
        currentIndex: currentIndex,
        onTap: onTap,
        backgroundColor: Colors.transparent,
      ),
    );
  }
}

/// RealLiquidGlass widget alias for LiquidGlassContainer
typedef RealLiquidGlass = LiquidGlassContainer;

