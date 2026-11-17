import 'package:animations/animations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

export 'package:animations/animations.dart';

/// Helper function to create an adaptive PageRoute.
/// On iOS, it uses CupertinoPageRoute for native edge-swipe back and Cupertino styling.
/// On Android, it returns AdaptivePageRoute (MaterialPageRoute) which integrates
/// natively with Android 14+ PredictiveBackPageTransitionsBuilder and Material 3 Expressive motion.
Route<T> createAdaptivePageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
  SharedAxisTransitionType transitionType = SharedAxisTransitionType.horizontal,
  bool useFadeThrough = false,
  bool fullscreenDialog = false,
  bool isModal = false,
}) {
  final bool effectiveIsModal = fullscreenDialog || isModal;
  if (useFadeThrough) {
    return PageRouteBuilder<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final contrastAdjustedChild = ForegroundPageShadowTransition(
          animation: animation,
          enabled: !effectiveIsModal,
          child: BackgroundExposureTransition(
            secondaryAnimation: secondaryAnimation,
            enabled: !effectiveIsModal,
            child: child,
          ),
        );
        return FadeThroughTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          child: contrastAdjustedChild,
        );
      },
    );
  }

  // Preserve native Cupertino edge-swipe and navigation on iOS
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return CupertinoPageRoute<T>(
      builder: builder,
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      maintainState: true,
    );
  }

  return AdaptivePageRoute<T>(
    builder: builder,
    settings: settings,
    transitionType: transitionType,
    useFadeThrough: useFadeThrough,
    fullscreenDialog: fullscreenDialog,
    isModal: isModal,
  );
}

/// A widget that decreases the exposure and brightness of the background page
/// when it is covered by a foreground route or revealed in predictive back preview.
/// Disabled for modal routes so modals maintain clean underlying backgrounds.
class BackgroundExposureTransition extends StatelessWidget {
  const BackgroundExposureTransition({
    super.key,
    required this.secondaryAnimation,
    required this.child,
    this.enabled = true,
  });

  final Animation<double> secondaryAnimation;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    final route = ModalRoute.of(context);
    if (route is PageRoute && route.fullscreenDialog) {
      return child;
    }
    if (route is AdaptivePageRoute && route.effectiveIsModal) {
      return child;
    }

    return AnimatedBuilder(
      animation: secondaryAnimation,
      builder: (context, child) {
        final progress = secondaryAnimation.value;
        if (progress <= 0.0) {
          return child!;
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final curvedProgress = Curves.easeInOutCubic.transform(progress.clamp(0.0, 1.0));

        // In light mode: 30% dark scrim to decrease exposure against bright foreground cards.
        // In dark mode: 45% deep scrim to lower background page luminosity.
        final maxScrimOpacity = isDark ? 0.45 : 0.30;
        final scrimColor = Colors.black.withValues(
          alpha: maxScrimOpacity * curvedProgress,
        );

        return Stack(
          fit: StackFit.passthrough,
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: scrimColor,
                ),
              ),
            ),
          ],
        );
      },
      child: child,
    );
  }
}

/// A widget that applies an ambient and directional drop shadow to the foreground page
/// during page transitions and predictive back gestures to clearly separate it from the background page.
/// Disabled for modal routes to prevent unwanted perimeter shadows on modals.
class ForegroundPageShadowTransition extends StatelessWidget {
  const ForegroundPageShadowTransition({
    super.key,
    required this.animation,
    required this.child,
    this.enabled = true,
  });

  final Animation<double> animation;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    final route = ModalRoute.of(context);
    if (route is PageRoute && route.fullscreenDialog) {
      return child;
    }
    if (route is AdaptivePageRoute && route.effectiveIsModal) {
      return child;
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        if (animation.value <= 0.0) {
          return child!;
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final ambientAlpha = (isDark ? 0.50 : 0.25) * animation.value.clamp(0.0, 1.0);
        final keyAlpha = (isDark ? 0.38 : 0.16) * animation.value.clamp(0.0, 1.0);

        return DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: ambientAlpha),
                blurRadius: 36,
                spreadRadius: 2,
                offset: const Offset(-6, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: keyAlpha),
                blurRadius: 12,
                spreadRadius: 0,
                offset: const Offset(-2, 2),
              ),
            ],
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}

/// Predictive back page transitions builder that delegates to Flutter's native,
/// official [PredictiveBackPageTransitionsBuilder] introduced in Flutter SDK.
///
/// On Android U and above (API 34+), it provides gesture-driven predictive back
/// navigation with interactive scaling, native corner curvature, and smooth
/// reveal of the destination route underneath.
/// On earlier Android versions, it falls back to Material 3 [FadeForwardsPageTransitionsBuilder].
typedef EnhancedPredictiveBackPageTransitionsBuilder = PredictiveBackPageTransitionsBuilder;

class AdaptivePageRoute<T> extends MaterialPageRoute<T> {
  final SharedAxisTransitionType transitionType;
  final bool useFadeThrough;
  final bool isModal;

  AdaptivePageRoute({
    required super.builder,
    super.settings,
    this.transitionType = SharedAxisTransitionType.horizontal,
    this.useFadeThrough = false,
    super.fullscreenDialog = false,
    this.isModal = false,
    super.maintainState = true,
  });

  bool get effectiveIsModal => fullscreenDialog || isModal;
}

