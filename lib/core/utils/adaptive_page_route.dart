import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import '../theme/adaptive_theme.dart';

export 'package:animations/animations.dart';

/// Helper function to create an adaptive PageRoute.
/// On iOS, it uses CupertinoPageRoute / Cupertino transitions for native edge-swipe back.
/// On Android, it utilizes animations package transitions (SharedAxis / FadeThrough)
/// or predictive back transitions.
Route<T> createAdaptivePageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
  SharedAxisTransitionType transitionType = SharedAxisTransitionType.horizontal,
  bool useFadeThrough = false,
}) {
  return AdaptivePageRoute<T>(
    builder: builder,
    settings: settings,
    transitionType: transitionType,
    useFadeThrough: useFadeThrough,
  );
}

class AdaptivePageRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;
  final SharedAxisTransitionType transitionType;
  final bool useFadeThrough;

  AdaptivePageRoute({
    required this.builder,
    super.settings,
    this.transitionType = SharedAxisTransitionType.horizontal,
    this.useFadeThrough = false,
  });

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) => true;

  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final isIos = AdaptiveThemeHelper.isIos(context);

    if (isIos) {
      return const CupertinoPageTransitionsBuilder().buildTransitions<T>(
        this,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }

    if (useFadeThrough) {
      return FadeThroughTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      );
    }

    return SharedAxisTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      transitionType: transitionType,
      child: child,
    );
  }
}
