import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/colors.dart';
import '../theme/adaptive_theme.dart';

enum AdaptiveButtonType {
  primary,
  secondary,
  destructive,
  success,
  text,
}

class AdaptiveButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final AdaptiveButtonType type;
  final bool isFullWidth;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final bool isLoading;

  const AdaptiveButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.type = AdaptiveButtonType.primary,
    this.isFullWidth = false,
    this.height = 50,
    this.padding,
    this.isLoading = false,
  });

  @override
  State<AdaptiveButton> createState() => _AdaptiveButtonState();
}

class _AdaptiveButtonState extends State<AdaptiveButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    Color backgroundColor;
    Color foregroundColor = Colors.white;

    switch (widget.type) {
      case AdaptiveButtonType.primary:
        backgroundColor = isIos ? AppColors.primaryBlue : colorScheme.primary;
        foregroundColor = isIos ? Colors.white : colorScheme.onPrimary;
        break;
      case AdaptiveButtonType.success:
        backgroundColor = isDark ? const Color(0xFF16A34A) : AppColors.receivableGreen;
        foregroundColor = Colors.white;
        break;
      case AdaptiveButtonType.destructive:
        backgroundColor = isDark ? const Color(0xFFDC2626) : AppColors.payableRed;
        foregroundColor = Colors.white;
        break;
      case AdaptiveButtonType.secondary:
        backgroundColor = isIos
            ? (isDark ? CupertinoColors.systemGrey5 : AppColors.borderLight)
            : colorScheme.surfaceContainerHighest;
        foregroundColor = isIos
            ? (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)
            : colorScheme.onSurface;
        break;
      case AdaptiveButtonType.text:
        backgroundColor = Colors.transparent;
        foregroundColor = isIos ? AppColors.primaryBlue : colorScheme.primary;
        break;
    }

    final VoidCallback? effectiveOnPressed = widget.onPressed == null || widget.isLoading
        ? null
        : () {
            HapticFeedback.lightImpact();
            widget.onPressed!();
          };

    final Widget content = widget.isLoading
        ? SizedBox(
            height: 20,
            width: 20,
            child: isIos
                ? const CupertinoActivityIndicator(color: Colors.white)
                : CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: foregroundColor,
                  ),
          )
        : widget.child;

    Widget buttonWidget;

    if (isIos) {
      final button = CupertinoButton(
        padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: widget.type == AdaptiveButtonType.text ? null : backgroundColor,
        borderRadius: BorderRadius.circular(14),
        onPressed: effectiveOnPressed,
        child: DefaultTextStyle(
          style: TextStyle(
            color: foregroundColor,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          child: content,
        ),
      );

      if (widget.isFullWidth) {
        buttonWidget = SizedBox(
          width: double.infinity,
          height: widget.height,
          child: button,
        );
      } else {
        buttonWidget = button;
      }
    } else {
      // Material Design 3 Expressive
      Widget m3Button;
      if (widget.type == AdaptiveButtonType.text) {
        m3Button = TextButton(
          onPressed: effectiveOnPressed,
          style: TextButton.styleFrom(
            foregroundColor: foregroundColor,
            padding: widget.padding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          child: content,
        );
      } else {
        m3Button = FilledButton(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            elevation: 0,
            padding: widget.padding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24), // M3 expressive radius
            ),
          ),
          child: content,
        );
      }

      if (widget.isFullWidth) {
        buttonWidget = SizedBox(
          width: double.infinity,
          height: widget.height,
          child: m3Button,
        );
      } else {
        buttonWidget = m3Button;
      }
    }

    return AnimatedScale(
      scale: _isPressed ? 0.95 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: Listener(
        onPointerDown: (_) {
          if (widget.onPressed != null && !widget.isLoading) {
            HapticFeedback.lightImpact();
            setState(() => _isPressed = true);
          }
        },
        onPointerUp: (_) {
          if (_isPressed) {
            setState(() => _isPressed = false);
          }
        },
        onPointerCancel: (_) {
          if (_isPressed) {
            setState(() => _isPressed = false);
          }
        },
        child: buttonWidget,
      ),
    );
  }
}

