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
  bool fullscreenDialog = false,
}) {
  if (useFadeThrough) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeThroughTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          child: child,
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
  );
}

class AdaptivePageRoute<T> extends MaterialPageRoute<T> {
  final SharedAxisTransitionType transitionType;
  final bool useFadeThrough;

  AdaptivePageRoute({
    required super.builder,
    super.settings,
    this.transitionType = SharedAxisTransitionType.horizontal,
    this.useFadeThrough = false,
    super.fullscreenDialog = false,
    super.maintainState = true,
  });

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (useFadeThrough) {
      return FadeThroughTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      );
    }

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

    final theme = Theme.of(context);
    return theme.pageTransitionsTheme.buildTransitions<T>(
      this,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

