import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// A Floating Action Button that morphs smoothly using spring physics.
///
/// The morph is powered by a [SpringSimulation] on an [AnimationController],
/// giving a natural, physics-based press/release feel.
class SpringMorphingFab extends StatefulWidget {
  /// Creates a spring-morphing FAB.
  const SpringMorphingFab({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.heroTag,
    this.elevation = 6.0,
    this.pressedElevation = 2.0,
  });

  /// The leading icon.
  final IconData icon;

  /// The text label displayed next to [icon].
  final String label;

  /// Tap callback.
  final VoidCallback onPressed;

  /// Fill colour. Falls back to `colorScheme.primaryContainer`.
  final Color? backgroundColor;

  /// Icon and text colour. Falls back to `colorScheme.onPrimaryContainer`.
  final Color? foregroundColor;

  /// Optional hero tag to disambiguate multiple FABs on screen.
  final Object? heroTag;

  /// Shadow elevation at rest.
  final double elevation;

  /// Shadow elevation when pressed (reduced for "pushed in" feel).
  final double pressedElevation;

  @override
  State<SpringMorphingFab> createState() => _SpringMorphingFabState();
}

class _SpringMorphingFabState extends State<SpringMorphingFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // ── Spring parameters ──
  static const double _mass = 1.0;
  static const double _stiffness = 600.0;
  static const double _damping = 22.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Spring helpers ──

  void _animateToTarget(double target) {
    final simulation = SpringSimulation(
      const SpringDescription(
        mass: _mass,
        stiffness: _stiffness,
        damping: _damping,
      ),
      _controller.value, // current position
      target, // target position
      _controller.velocity, // carry over velocity for fluid feel
    );
    _controller.animateWith(simulation);
  }

  void _onPointerDown(PointerDownEvent _) {
    HapticFeedback.lightImpact();
    _animateToTarget(1.0);
  }

  void _onPointerUp(PointerUpEvent _) {
    _animateToTarget(0.0);
  }

  void _onPointerCancel(PointerCancelEvent _) {
    _animateToTarget(0.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bgColor = widget.backgroundColor ?? colorScheme.primaryContainer;
    final fgColor = widget.foregroundColor ?? colorScheme.onPrimaryContainer;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double progress = _controller.value.clamp(0.0, 1.0);

        final double currentElevation = ui.lerpDouble(
          widget.elevation,
          widget.pressedElevation,
          progress,
        )!;

        final double scale = 1.0 - (progress * 0.04);
        final double cornerRadius = ui.lerpDouble(18.0, 26.0, progress)!;

        return Transform.scale(
          scale: scale,
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            behavior: HitTestBehavior.opaque,
            child: GestureDetector(
              onTap: widget.onPressed,
              child: Material(
                color: bgColor,
                elevation: currentElevation,
                borderRadius: BorderRadius.circular(cornerRadius),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, color: fgColor, size: 22),
          const SizedBox(width: 10),
          Text(
            widget.label,
            style: TextStyle(
              color: fgColor,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
