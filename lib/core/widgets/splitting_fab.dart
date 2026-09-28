import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import '../constants/colors.dart';

/// An expressive Material 3 Floating Action Button with spring physics that
/// smoothly splits into dual action buttons (Save and Cancel) and smoothly recombines.
class SplittingProfileFab extends StatefulWidget {
  final bool isEditing;
  final VoidCallback onEdit;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const SplittingProfileFab({
    super.key,
    required this.isEditing,
    required this.onEdit,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<SplittingProfileFab> createState() => _SplittingProfileFabState();
}

class _SplittingProfileFabState extends State<SplittingProfileFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _splitController;
  late final Animation<double> _cancelScaleAnimation;
  late final Animation<double> _cancelFadeAnimation;
  late final Animation<Offset> _cancelSlideAnimation;
  late final Animation<double> _gapAnimation;

  @override
  void initState() {
    super.initState();
    _splitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _cancelScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _splitController,
        curve: const Interval(0.1, 1.0, curve: Curves.easeOutBack),
        reverseCurve: const Interval(0.0, 0.75, curve: Curves.easeInBack),
      ),
    );

    _cancelFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _splitController,
        curve: const Interval(0.15, 0.85, curve: Curves.easeOut),
        reverseCurve: const Interval(0.0, 0.6, curve: Curves.easeIn),
      ),
    );

    _cancelSlideAnimation = Tween<Offset>(
      begin: const Offset(0.5, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _splitController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    _gapAnimation = Tween<double>(begin: 0.0, end: 12.0).animate(
      CurvedAnimation(
        parent: _splitController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    if (widget.isEditing) {
      _splitController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(SplittingProfileFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEditing != oldWidget.isEditing) {
      if (widget.isEditing) {
        _splitController.forward();
      } else {
        _splitController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _splitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final editBgColor = colorScheme.primaryContainer;
    final editFgColor = colorScheme.onPrimaryContainer;

    final saveBgColor = AppColors.receivableGreen;
    const saveFgColor = Colors.white;

    final cancelBgColor = isDark
        ? const Color(0xFF451A1A)
        : const Color(0xFFFEE2E2);
    final cancelFgColor = isDark
        ? const Color(0xFFFCA5A5)
        : AppColors.payableRed;

    return AnimatedBuilder(
      animation: _splitController,
      builder: (context, _) {
        final progress = _splitController.value;
        final mainBg = Color.lerp(editBgColor, saveBgColor, progress)!;
        final mainFg = Color.lerp(editFgColor, saveFgColor, progress)!;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Cancel Action Button (Splits out to the left)
            if (progress > 0.01) ...[
              FadeTransition(
                opacity: _cancelFadeAnimation,
                child: SlideTransition(
                  position: _cancelSlideAnimation,
                  child: ScaleTransition(
                    scale: _cancelScaleAnimation,
                    child: _SpringFabButton(
                      backgroundColor: cancelBgColor,
                      tooltip: 'Cancel editing',
                      onTap: widget.onCancel,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close_rounded, color: cancelFgColor, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Cancel',
                            style: TextStyle(
                              color: cancelFgColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: _gapAnimation.value),
            ],

            // 2. Main Action Button (Morphs between Edit Profile & Save Changes)
            _SpringFabButton(
              backgroundColor: mainBg,
              tooltip: widget.isEditing ? 'Save profile changes' : 'Edit profile',
              onTap: widget.isEditing ? widget.onSave : widget.onEdit,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: widget.isEditing
                    ? Row(
                        key: const ValueKey('save_fab_content'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded, color: mainFg, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Save Changes',
                            style: TextStyle(
                              color: mainFg,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        key: const ValueKey('edit_fab_content'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_rounded, color: mainFg, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Edit Profile',
                            style: TextStyle(
                              color: mainFg,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A physics-powered Material 3 button matching [SpringMorphingFab] characteristics.
class _SpringFabButton extends StatefulWidget {
  final Widget child;
  final Color backgroundColor;
  final VoidCallback onTap;
  final String tooltip;

  const _SpringFabButton({
    required this.child,
    required this.backgroundColor,
    required this.onTap,
    required this.tooltip,
  });

  @override
  State<_SpringFabButton> createState() => _SpringFabButtonState();
}

class _SpringFabButtonState extends State<_SpringFabButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;

  static const double _mass = 1.0;
  static const double _stiffness = 600.0;
  static const double _damping = 22.0;
  static const double _elevation = 6.0;
  static const double _pressedElevation = 2.0;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _animateToTarget(double target) {
    final simulation = SpringSimulation(
      const SpringDescription(
        mass: _mass,
        stiffness: _stiffness,
        damping: _damping,
      ),
      _pressController.value,
      target,
      _pressController.velocity,
    );
    _pressController.animateWith(simulation);
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
    return AnimatedBuilder(
      animation: _pressController,
      builder: (context, child) {
        final double progress = _pressController.value.clamp(0.0, 1.0);
        final double currentElevation = ui.lerpDouble(
          _elevation,
          _pressedElevation,
          progress,
        )!;
        final double scale = 1.0 - (progress * 0.04);
        final double cornerRadius = ui.lerpDouble(18.0, 26.0, progress)!;

        return Transform.scale(
          scale: scale,
          child: Tooltip(
            message: widget.tooltip,
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              behavior: HitTestBehavior.opaque,
              child: GestureDetector(
                onTap: widget.onTap,
                child: Material(
                  color: widget.backgroundColor,
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
          ),
        );
      },
      child: widget.child,
    );
  }
}
