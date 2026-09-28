import 'dart:ui' show clampDouble;
import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/adaptive_theme.dart';

export 'package:animations/animations.dart';

/// Helper function to create an adaptive PageRoute.
/// On iOS, it uses CupertinoPageRoute / Cupertino transitions for native edge-swipe back.
/// On Android, it utilizes animations package transitions (SharedAxis / FadeThrough)
/// or enhanced predictive back transitions with background page exposure reduction & shadow.
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

enum _PredictiveBackPhase { idle, start, update, commit, cancel }

typedef _PredictiveBackGestureDetectorWidgetBuilder = Widget Function(
  BuildContext context,
  _PredictiveBackPhase phase,
  PredictiveBackEvent? startBackEvent,
  PredictiveBackEvent? currentBackEvent,
);

class _EnhancedPredictiveBackGestureDetector extends StatefulWidget {
  const _EnhancedPredictiveBackGestureDetector({
    required this.route,
    required this.builder,
  });

  final PageRoute<dynamic> route;
  final _PredictiveBackGestureDetectorWidgetBuilder builder;

  @override
  State<_EnhancedPredictiveBackGestureDetector> createState() =>
      _EnhancedPredictiveBackGestureDetectorState();
}

class _EnhancedPredictiveBackGestureDetectorState
    extends State<_EnhancedPredictiveBackGestureDetector>
    with WidgetsBindingObserver {
  bool get _isEnabled =>
      widget.route.isCurrent && widget.route.popGestureEnabled;

  _PredictiveBackPhase _phase = _PredictiveBackPhase.idle;
  _PredictiveBackPhase get phase => _phase;
  set phase(_PredictiveBackPhase phase) {
    if (_phase != phase && mounted) {
      setState(() => _phase = phase);
    }
  }

  PredictiveBackEvent? _startBackEvent;
  PredictiveBackEvent? get startBackEvent => _startBackEvent;
  set startBackEvent(PredictiveBackEvent? startBackEvent) {
    if (_startBackEvent != startBackEvent && mounted) {
      setState(() => _startBackEvent = startBackEvent);
    }
  }

  PredictiveBackEvent? _currentBackEvent;
  PredictiveBackEvent? get currentBackEvent => _currentBackEvent;
  set currentBackEvent(PredictiveBackEvent? currentBackEvent) {
    if (_currentBackEvent != currentBackEvent && mounted) {
      setState(() => _currentBackEvent = currentBackEvent);
    }
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    phase = _PredictiveBackPhase.start;
    final bool gestureInProgress = !backEvent.isButtonEvent && _isEnabled;
    if (!gestureInProgress) {
      return false;
    }
    widget.route.handleStartBackGesture(progress: 1 - backEvent.progress);
    startBackEvent = currentBackEvent = backEvent;
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    phase = _PredictiveBackPhase.update;
    widget.route.handleUpdateBackGestureProgress(progress: 1 - backEvent.progress);
    currentBackEvent = backEvent;
  }

  @override
  void handleCancelBackGesture() {
    phase = _PredictiveBackPhase.cancel;
    widget.route.handleCancelBackGesture();
    startBackEvent = currentBackEvent = null;
  }

  @override
  void handleCommitBackGesture() {
    phase = _PredictiveBackPhase.commit;
    widget.route.handleCommitBackGesture();
    startBackEvent = currentBackEvent = null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectivePhase = widget.route.popGestureInProgress
        ? phase
        : _PredictiveBackPhase.idle;
    return widget.builder(context, effectivePhase, startBackEvent, currentBackEvent);
  }
}

class _EnhancedPredictiveBackPageTransition extends StatefulWidget {
  const _EnhancedPredictiveBackPageTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.phase,
    required this.startBackEvent,
    required this.currentBackEvent,
    required this.child,
    this.showShadow = true,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final _PredictiveBackPhase phase;
  final PredictiveBackEvent? startBackEvent;
  final PredictiveBackEvent? currentBackEvent;
  final Widget child;
  final bool showShadow;

  @override
  State<_EnhancedPredictiveBackPageTransition> createState() =>
      _EnhancedPredictiveBackPageTransitionState();
}

class _EnhancedPredictiveBackPageTransitionState
    extends State<_EnhancedPredictiveBackPageTransition>
    with SingleTickerProviderStateMixin {
  static const double _kMinScale = 0.90;
  static const double _kDivisionFactor = 20.0;
  static const double _kMargin = 8.0;
  static const double _kYPositionFactor = 0.1;
  static const Curve _kCurve = Curves.easeInOutCubicEmphasized;
  static const Interval _kCommitInterval = Interval(
    0.0,
    1.0,
    curve: _kCurve,
  );
  static const double _kDeviceBorderRadius = 32.0;

  final Tween<double> _borderRadiusTween =
      Tween<double>(begin: 0.0, end: _kDeviceBorderRadius);
  final Tween<double> _opacityTween = Tween<double>(begin: 1.0, end: 0.0);
  final Tween<double> _scaleTween = Tween<double>(begin: 1.0, end: _kMinScale);

  final ProxyAnimation _commitAnimation = ProxyAnimation();
  final ProxyAnimation _bounceAnimation = ProxyAnimation();
  double _lastBounceAnimationValue = 0.0;
  final ProxyAnimation _animation = ProxyAnimation();

  CurvedAnimation? _curvedAnimation;
  CurvedAnimation? _curvedAnimationReversed;
  late Animation<Offset> _positionAnimation;
  Offset _lastDrag = Offset.zero;

  double _getYShiftPosition(double screenHeight) {
    final double startTouchY = widget.startBackEvent?.touchOffset?.dy ?? 0;
    final double currentTouchY = widget.currentBackEvent?.touchOffset?.dy ?? 0;
    final double yShiftMax = (screenHeight / _kDivisionFactor) - _kMargin;
    final double rawYShift = currentTouchY - startTouchY;
    final double easedYShift =
        Curves.easeOut.transform(clampDouble(rawYShift.abs() / screenHeight, 0.0, 1.0)) *
        rawYShift.sign *
        yShiftMax;
    return clampDouble(easedYShift, -yShiftMax, yShiftMax);
  }

  void _updateAnimations(Size screenSize) {
    _animation.parent = switch (widget.phase) {
      _PredictiveBackPhase.commit => _curvedAnimationReversed,
      _ => widget.animation,
    };

    _bounceAnimation.parent = switch (widget.phase) {
      _PredictiveBackPhase.commit => Tween<double>(
        begin: 0.0,
        end: _lastBounceAnimationValue,
      ).animate(_curvedAnimation!),
      _ => ReverseAnimation(widget.animation),
    };

    _commitAnimation.parent = switch (widget.phase) {
      _PredictiveBackPhase.commit => _animation,
      _ => kAlwaysDismissedAnimation,
    };

    final double xShift = (screenSize.width / _kDivisionFactor) - _kMargin;
    _positionAnimation = _animation.drive(switch (widget.phase) {
      _PredictiveBackPhase.commit => Tween<Offset>(
        begin: _lastDrag,
        end: Offset(screenSize.height * _kYPositionFactor, 0.0),
      ),
      _ => Tween<Offset>(
        begin: switch (widget.currentBackEvent?.swipeEdge) {
          SwipeEdge.left => Offset(xShift, _getYShiftPosition(screenSize.height)),
          SwipeEdge.right => Offset(-xShift, _getYShiftPosition(screenSize.height)),
          null => Offset(xShift, _getYShiftPosition(screenSize.height)),
        },
        end: Offset.zero,
      ),
    });
  }

  void _updateCurvedAnimations() {
    _curvedAnimation?.dispose();
    _curvedAnimationReversed?.dispose();
    _curvedAnimation =
        CurvedAnimation(parent: widget.animation, curve: _kCommitInterval);
    _curvedAnimationReversed = CurvedAnimation(
      parent: ReverseAnimation(widget.animation),
      curve: _kCommitInterval,
    );
  }

  @override
  void didUpdateWidget(_EnhancedPredictiveBackPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation != oldWidget.animation) {
      _updateCurvedAnimations();
    }
    if (widget.phase != oldWidget.phase &&
        widget.phase == _PredictiveBackPhase.commit) {
      _updateAnimations(MediaQuery.sizeOf(context));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateCurvedAnimations();
    _updateAnimations(MediaQuery.sizeOf(context));
  }

  @override
  void dispose() {
    _curvedAnimation?.dispose();
    _curvedAnimationReversed?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (BuildContext context, Widget? child) {
        _lastBounceAnimationValue = _bounceAnimation.value;
        final double bounce = _bounceAnimation.value;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        final BorderRadius borderRadius =
            BorderRadius.circular(
                _borderRadiusTween.evaluate(_bounceAnimation));

        return Transform.scale(
          scale: _scaleTween.evaluate(_bounceAnimation),
          child: Transform.translate(
            offset: switch (widget.phase) {
              _PredictiveBackPhase.commit => _positionAnimation.value,
              _ => _lastDrag = Offset(
                _positionAnimation.value.dx,
                _getYShiftPosition(MediaQuery.heightOf(context)),
              ),
            },
            child: Opacity(
              opacity: _opacityTween.evaluate(_commitAnimation),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  boxShadow: (widget.showShadow && bounce > 0.001)
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: (isDark ? 0.65 : 0.38) * bounce.clamp(0.0, 1.0),
                            ),
                            blurRadius: 36 * bounce.clamp(0.2, 1.0),
                            spreadRadius: 3 * bounce.clamp(0.0, 1.0),
                            offset: Offset(
                              -10 * bounce.clamp(0.2, 1.0),
                              8 * bounce.clamp(0.2, 1.0),
                            ),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: (isDark ? 0.45 : 0.22) * bounce.clamp(0.0, 1.0),
                            ),
                            blurRadius: 12 * bounce.clamp(0.2, 1.0),
                            spreadRadius: 0,
                            offset: Offset(
                              -3 * bounce.clamp(0.2, 1.0),
                              3 * bounce.clamp(0.2, 1.0),
                            ),
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: borderRadius,
                  child: child,
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

/// Custom PageTransitionsBuilder providing predictive back with layered drop shadows and rounded corner cards.
class EnhancedPredictiveBackPageTransitionsBuilder extends PageTransitionsBuilder {
  const EnhancedPredictiveBackPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final bool isModal = route.fullscreenDialog ||
        (route is AdaptivePageRoute && (route as AdaptivePageRoute).effectiveIsModal);

    return _EnhancedPredictiveBackGestureDetector(
      route: route,
      builder: (context, phase, startBackEvent, currentBackEvent) {
        if (route.popGestureInProgress) {
          return _EnhancedPredictiveBackPageTransition(
            animation: animation,
            phase: phase,
            secondaryAnimation: secondaryAnimation,
            startBackEvent: startBackEvent,
            currentBackEvent: currentBackEvent,
            showShadow: !isModal,
            child: child,
          );
        }

        return FadeForwardsPageTransitionsBuilder().buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
      },
    );
  }
}

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

  Route<dynamic>? _nextRoute;
  Route<dynamic>? get nextRoute => _nextRoute;

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    _nextRoute = nextRoute;
    super.didChangeNext(nextRoute);
  }

  /// Whether the route covering this page is a modal, dialog, or bottom sheet.
  bool get isNextRouteModal {
    final next = _nextRoute;
    if (next == null) return false;
    if (next is PageRoute && next.fullscreenDialog) return true;
    if (next is AdaptivePageRoute && next.effectiveIsModal) return true;
    final typeName = next.runtimeType.toString().toLowerCase();
    if (typeName.contains('modal') ||
        typeName.contains('dialog') ||
        typeName.contains('popup') ||
        typeName.contains('bottomsheet')) {
      return true;
    }
    return false;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // For modals (e.g. fullscreenDialog or isModal), remove the shadow and low-exposure background.
    // Also, if the route pushed on top of this page is a modal or bottom sheet, do not reduce background exposure.
    final bool shouldApplyShadow = !effectiveIsModal;
    final bool shouldReduceExposure = !effectiveIsModal && !isNextRouteModal;

    final contrastAdjustedChild = ForegroundPageShadowTransition(
      animation: animation,
      enabled: shouldApplyShadow,
      child: BackgroundExposureTransition(
        secondaryAnimation: secondaryAnimation,
        enabled: shouldReduceExposure,
        child: child,
      ),
    );

    if (useFadeThrough) {
      return FadeThroughTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: contrastAdjustedChild,
      );
    }

    final isIos = AdaptiveThemeHelper.isIos(context);
    if (isIos) {
      return CupertinoPageTransitionsBuilder().buildTransitions<T>(
        this,
        context,
        animation,
        secondaryAnimation,
        contrastAdjustedChild,
      );
    }

    final theme = Theme.of(context);
    return theme.pageTransitionsTheme.buildTransitions<T>(
      this,
      context,
      animation,
      secondaryAnimation,
      contrastAdjustedChild,
    );
  }
}
