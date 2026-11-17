import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_feedback.dart';

/// A pull gesture holds the scroll position until release, even when reversed.
class AppPullToRefresh extends StatefulWidget {
  const AppPullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<AppPullToRefresh> createState() => _AppPullToRefreshState();
}

class _PullGesture {
  bool dragging = false;
  bool held = false;
}

class _AppPullToRefreshState extends State<AppPullToRefresh> {
  static const double _threshold = 100;
  final _gesture = _PullGesture();
  double _distance = 0;
  bool _armed = false;
  bool _refreshing = false;
  bool _canceled = false;
  bool _didHaptic = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axisDirection != AxisDirection.down) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _gesture.dragging = true;
      _canceled = false;
      _didHaptic = false;
    } else if (notification is OverscrollNotification &&
        notification.dragDetails != null &&
        _gesture.held &&
        !_refreshing) {
      final distance = (_distance - notification.overscroll).clamp(
        0.0,
        _threshold,
      );
      setState(() {
        _distance = distance;
        _armed = _distance >= _threshold;
        if (_armed && !_didHaptic) {
          _didHaptic = true;
          HapticFeedback.mediumImpact();
        }
      });
    } else if (notification is ScrollEndNotification) {
      _gesture.dragging = false;
      _gesture.held = false;
      if (_armed && !_refreshing && !_canceled) {
        unawaited(_refresh());
      } else if (!_refreshing && (_distance > 0 || _armed)) {
        setState(() {
          _distance = 0;
          _armed = false;
        });
      }
    }
    return false;
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } catch (error) {
      if (mounted) {
        showAppFeedback(context, 'Could not refresh: $error', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _armed = false;
          _distance = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _distance > 0 || _refreshing;
    final progress = (_distance / _threshold).clamp(0.0, 1.0);
    final colors = Theme.of(context).colorScheme;
    return Listener(
      onPointerCancel: (_) => _canceled = true,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                overscroll: false,
                physics: _RefreshHoldPhysics(_gesture),
              ),
              child: widget.child,
            ),
            if (visible)
              Positioned(
                // Slide out from behind the header, clipped to the page body.
                top: -40 + 80 * progress,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Semantics(
                      liveRegion: true,
                      label: _refreshing
                          ? 'Refreshing'
                          : (_armed ? 'Release to refresh' : 'Pull to refresh'),
                      child: Material(
                        key: const Key('pull_refresh_indicator'),
                        color: colors.surfaceContainerHigh,
                        elevation: 4,
                        shape: const CircleBorder(),
                        child: SizedBox.square(
                          dimension: 40,
                          child: Center(
                            child: _refreshing
                                ? SizedBox.square(
                                    dimension: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: colors.primary,
                                    ),
                                  )
                                : AnimatedRotation(
                                    turns: _armed ? 0.5 : 0,
                                    duration: const Duration(milliseconds: 150),
                                    child: Icon(
                                      Icons.arrow_downward_rounded,
                                      color: colors.primary,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RefreshHoldPhysics extends ClampingScrollPhysics {
  const _RefreshHoldPhysics(this.gesture, {super.parent});
  final _PullGesture gesture;

  @override
  _RefreshHoldPhysics applyTo(ScrollPhysics? ancestor) =>
      _RefreshHoldPhysics(gesture, parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      gesture.held ? offset : super.applyPhysicsToUserOffset(position, offset);

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (gesture.dragging &&
        position.pixels <= position.minScrollExtent &&
        value < position.minScrollExtent) {
      gesture.held = true;
    }
    if (gesture.held) return value - position.pixels;
    return super.applyBoundaryConditions(position, value);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) =>
      gesture.held ? null : super.createBallisticSimulation(position, velocity);
}
