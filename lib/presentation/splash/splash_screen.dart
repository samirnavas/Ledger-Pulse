import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/strings.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../auth/phone_input_screen.dart';
import '../home/dashboard_screen.dart';
import '../providers/auth_providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  final VoidCallback? onAnimationComplete;
  final Duration holdDuration;

  const SplashScreen({
    super.key,
    this.onAnimationComplete,
    this.holdDuration = const Duration(milliseconds: 1500),
  });

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _hasNavigated = false;

  void _onSequenceFinished() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    if (widget.onAnimationComplete != null) {
      widget.onAnimationComplete!();
      return;
    }

    final authState = ref.read(authControllerProvider);
    final targetWidget = authState.isAuthenticated
        ? const DashboardScreen()
        : const PhoneInputScreen();

    Navigator.of(context).pushReplacement(
      createAdaptivePageRoute(
        builder: (_) => targetWidget,
        useFadeThrough: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    // Adaptive background color
    final backgroundColor = isIos
        ? (isDark
            ? AppColors.surfaceDark
            : AppColors.cupertinoSystemBackground)
        : (isDark
            ? Theme.of(context).colorScheme.surface
            : AppColors.surfaceLight);

    final textColor = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimaryLight;

    final subtextColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    // Animation timeline calculation:
    // 1. Fade in & scale: 500ms
    // 2. Hold: widget.holdDuration (default 1500ms)
    // 3. Exit delay = 500ms + holdDuration
    const entryDuration = Duration(milliseconds: 500);
    final exitDelay = entryDuration + widget.holdDuration;
    const exitDuration = Duration(milliseconds: 450);

    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Polished App Logo with subtle elevation & gradient border
          Container(
            width: 96,
            height: 96,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceCardDark : AppColors.surfaceWhite,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.15),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/icons/app_icon.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: AppColors.primaryBlueLight,
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 48,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Brand Typography
          Text(
            AppStrings.appName,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),

          // Subtitle / Tagline
          Text(
            'Smart Digital Ledger & Bookkeeping',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: subtextColor,
              letterSpacing: 0.2,
            ),
          ),
        ],
      )
          .animate(
            onComplete: (_) => _onSequenceFinished(),
          )
          // 1. Fade In
          .fadeIn(
            duration: entryDuration,
            curve: Curves.easeOut,
          )
          // 2. Slight Scale Up
          .scale(
            begin: const Offset(0.88, 0.88),
            end: const Offset(1.0, 1.0),
            duration: entryDuration,
            curve: Curves.easeOutCubic,
          )
          // 3. Slide Up (after holding for 1.5s)
          .slideY(
            begin: 0,
            end: -0.22,
            delay: exitDelay,
            duration: exitDuration,
            curve: Curves.easeInOutCubic,
          )
          // 4. Fade Out (after holding for 1.5s)
          .fadeOut(
            delay: exitDelay,
            duration: exitDuration,
            curve: Curves.easeInOutCubic,
          ),
    );

    if (isIos) {
      return CupertinoPageScaffold(
        backgroundColor: backgroundColor,
        child: SafeArea(child: content),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(child: content),
    );
  }
}
