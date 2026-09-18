import 'package:flutter/cupertino.dart';
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
    this.border = 1.2,
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlassContainer(
      width: width,
      height: height,
      padding: padding,
      margin: margin,
      borderRadius: borderRadius,
      blur: blur,
      border: border,
      color: color,
      borderColor: borderColor,
      onTap: onTap,
      child: child,
    );
  }
}



