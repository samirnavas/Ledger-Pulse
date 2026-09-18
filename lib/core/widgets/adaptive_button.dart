import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../theme/adaptive_theme.dart';

enum AdaptiveButtonType {
  primary,
  secondary,
  destructive,
  success,
  text,
}

class AdaptiveButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);

    Color backgroundColor;
    Color foregroundColor = Colors.white;

    switch (type) {
      case AdaptiveButtonType.primary:
        backgroundColor = AppColors.primaryBlue;
        break;
      case AdaptiveButtonType.success:
        backgroundColor = AppColors.receivableGreen;
        break;
      case AdaptiveButtonType.destructive:
        backgroundColor = AppColors.payableRed;
        break;
      case AdaptiveButtonType.secondary:
        backgroundColor = AppColors.borderLight;
        foregroundColor = AppColors.textPrimaryLight;
        break;
      case AdaptiveButtonType.text:
        backgroundColor = Colors.transparent;
        foregroundColor = AppColors.primaryBlue;
        break;
    }

    final Widget content = isLoading
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
        : child;

    if (isIos) {
      final button = CupertinoButton(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: type == AdaptiveButtonType.text ? null : backgroundColor,
        borderRadius: BorderRadius.circular(14),
        onPressed: isLoading ? null : onPressed,
        child: DefaultTextStyle(
          style: TextStyle(
            color: foregroundColor,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          child: content,
        ),
      );

      if (isFullWidth) {
        return SizedBox(
          width: double.infinity,
          height: height,
          child: button,
        );
      }
      return button;
    } else {
      // Material Design 3 Expressive
      Widget m3Button;
      if (type == AdaptiveButtonType.text) {
        m3Button = TextButton(
          onPressed: isLoading ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: foregroundColor,
            padding: padding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: content,
        );
      } else {
        m3Button = FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            elevation: 0,
            padding: padding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20), // M3 expressive radius
            ),
          ),
          child: content,
        );
      }

      if (isFullWidth) {
        return SizedBox(
          width: double.infinity,
          height: height,
          child: m3Button,
        );
      }
      return m3Button;
    }
  }
}
