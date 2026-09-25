import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lottie/lottie.dart';
import '../constants/colors.dart';
import '../constants/typography.dart';
import '../theme/adaptive_theme.dart';
import 'adaptive_button.dart';

/// A rich, animated empty state view that supports Lottie animation assets,
/// fallback icons, titles, subtitles, and optional action buttons.
class EmptyStateView extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? lottieAsset;
  final IconData? fallbackIcon;
  final Widget? actionButton;
  final String? actionLabel;
  final VoidCallback? onActionPressed;
  final double animationSize;

  const EmptyStateView({
    super.key,
    required this.title,
    required this.subtitle,
    this.lottieAsset,
    IconData? fallbackIcon,
    IconData? icon,
    this.actionButton,
    this.actionLabel,
    this.onActionPressed,
    this.animationSize = 140,
  }) : fallbackIcon = fallbackIcon ?? icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget visualWidget;
    if (lottieAsset != null) {
      visualWidget = Lottie.asset(
        lottieAsset!,
        width: animationSize,
        height: animationSize,
        fit: BoxFit.contain,
        repeat: false,
        errorBuilder: (context, error, stackTrace) {
          return _buildFallbackIcon(context, isDark);
        },
      );
    } else {
      visualWidget = _buildFallbackIcon(context, isDark);
    }

    final effectiveActionButton = actionButton ??
        (actionLabel != null && onActionPressed != null
            ? AdaptiveButton(
                onPressed: onActionPressed!,
                child: Text(actionLabel!),
              )
            : null);

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated visual (Lottie or Icon)
            visualWidget
                .animate()
                .fadeIn(duration: 400.ms)
                .scale(begin: const Offset(0.85, 0.85), end: const Offset(1.0, 1.0), duration: 400.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 16),

            // Title
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                letterSpacing: -0.2,
              ),
            )
                .animate()
                .fadeIn(delay: 150.ms, duration: 350.ms)
                .slideY(begin: 0.15, end: 0, delay: 150.ms, duration: 350.ms),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                height: 1.4,
              ),
            )
                .animate()
                .fadeIn(delay: 250.ms, duration: 350.ms)
                .slideY(begin: 0.15, end: 0, delay: 250.ms, duration: 350.ms),

            // Optional action button
            if (effectiveActionButton != null) ...[
              const SizedBox(height: 20),
              effectiveActionButton
                  .animate()
                  .fadeIn(delay: 350.ms, duration: 350.ms)
                  .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.0, 1.0), delay: 350.ms, duration: 350.ms),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackIcon(BuildContext context, bool isDark) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    return Container(
      width: animationSize * 0.65,
      height: animationSize * 0.65,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: isDark ? 0.15 : 0.08),
        shape: BoxShape.circle,
      ),
      child: Icon(
        fallbackIcon ?? (isIos ? CupertinoIcons.tray : Icons.inbox_rounded),
        size: animationSize * 0.35,
        color: AppColors.primaryBlue.withValues(alpha: 0.7),
      ),
    );
  }
}
