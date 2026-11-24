import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/strings.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/paypr_logo.dart';
import '../auth/app_root_gate.dart';

class SplashScreen extends ConsumerStatefulWidget {
  /// Global indicator whether the splash screen is currently active and animating.
  /// Used by deep linking / widget launch handlers to prevent opening modals
  /// on top of SplashScreen before Navigator.pushReplacement has settled.
  static bool isSplashActive = true;

  /// Fast-track flag set when launching directly into an action (e.g. quick_add).
  /// Bypasses the hold duration so the target screen and modal appear promptly.
  static bool skipHold = false;

  final VoidCallback? onAnimationComplete;
  final Duration holdDuration;

  const SplashScreen({
    super.key,
    this.onAnimationComplete,
    this.holdDuration = const Duration(milliseconds: 450),
  });

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final _logoAnimation = AnimationController(vsync: this);
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    SplashScreen.isSplashActive = true;
  }

  @override
  void dispose() {
    _logoAnimation.dispose();
    SplashScreen.isSplashActive = false;
    SplashScreen.skipHold = false;
    super.dispose();
  }

  void _onSequenceFinished() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    SplashScreen.isSplashActive = false;
    SplashScreen.skipHold = false;

    if (widget.onAnimationComplete != null) {
      widget.onAnimationComplete!();
      return;
    }

    Navigator.of(context).pushReplacement(
      createAdaptivePageRoute(
        builder: (_) => const AppRootGate(),
        useFadeThrough: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark =
        Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    // Adaptive background color
    final backgroundColor = isIos
        ? (isDark ? AppColors.surfaceDark : AppColors.cupertinoSystemBackground)
        : (isDark
              ? Theme.of(context).colorScheme.surface
              : AppColors.surfaceLight);

    final textColor = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimaryLight;

    final subtextColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    // Animation timeline calculation (snappy & fast):
    // 1. Fade in & scale: 300ms (or 100ms when fast-tracking deep links)
    // 2. Hold: widget.holdDuration (default 450ms, or zero when skipping hold)
    // 3. Exit delay = entryDuration + holdDuration
    final entryDuration = SplashScreen.skipHold
        ? const Duration(milliseconds: 100)
        : const Duration(milliseconds: 300);
    final effectiveHold = SplashScreen.skipHold
        ? Duration.zero
        : widget.holdDuration;
    final exitDelay = entryDuration + effectiveHold;
    final exitDuration = SplashScreen.skipHold
        ? const Duration(milliseconds: 100)
        : const Duration(milliseconds: 250);
    final animateLogo =
        !SplashScreen.skipHold && !MediaQuery.disableAnimationsOf(context);
    const staticLogo = PayprLogo(size: 96);

    final logo = animateLogo
        ? Lottie.asset(
            'assets/animations/paypr_splash.json',
            controller: _logoAnimation,
            onLoaded: (_) {
              _logoAnimation.duration = exitDelay;
              _logoAnimation.forward();
            },
            frameBuilder: (_, child, composition) => composition == null
                ? staticLogo
                : Container(
                    width: 96,
                    height: 96,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: PayprLogo.backgroundColor,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: child,
                  ),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => staticLogo,
          )
        : staticLogo;

    final branding = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(height: 24),
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
        Text(
          AppStrings.tagline,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: subtextColor,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
    final content = Center(
      child: branding
          .animate(onComplete: (_) => _onSequenceFinished())
          .fadeIn(duration: entryDuration, curve: Curves.easeOut)
          .scale(
            begin: const Offset(0.88, 0.88),
            end: const Offset(1.0, 1.0),
            duration: entryDuration,
            curve: Curves.easeOutCubic,
          )
          .slideY(
            begin: 0,
            end: -0.22,
            delay: exitDelay,
            duration: exitDuration,
            curve: Curves.easeInOutCubic,
          )
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
