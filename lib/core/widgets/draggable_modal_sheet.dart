import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/adaptive_theme.dart';

/// An adaptive, fluid draggable modal sheet designed for Material 3 and iOS.
///
/// Features:
/// - Smooth swipe-to-dismiss via [shouldCloseOnMinExtent].
/// - Dynamic snapping between sizes.
/// - Centered pill drag handle with haptic feedback.
/// - Automatic keyboard inset handling to prevent overflows.
class DraggableModalSheet extends StatefulWidget {
  final Widget Function(BuildContext context, ScrollController scrollController) builder;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;
  final List<double>? snapSizes;
  final bool showHandle;
  final bool shouldCloseOnMinExtent;
  final bool showShadow;
  final Color? backgroundColor;
  final BorderRadiusGeometry? borderRadius;
  final DraggableScrollableController? controller;
  final double? maxWidth;

  const DraggableModalSheet({
    super.key,
    required this.builder,
    this.initialChildSize = 0.55,
    this.minChildSize = 0.25,
    this.maxChildSize = 0.95,
    this.snapSizes,
    this.showHandle = true,
    this.shouldCloseOnMinExtent = true,
    this.showShadow = false,
    this.backgroundColor,
    this.borderRadius,
    this.controller,
    this.maxWidth = 600,
  });

  @override
  State<DraggableModalSheet> createState() => _DraggableModalSheetState();
}

class _DraggableModalSheetState extends State<DraggableModalSheet> {
  final _internalController = DraggableScrollableController();

  DraggableScrollableController get _controller =>
      widget.controller ?? _internalController;

  @override
  void dispose() {
    _internalController.dispose();
    super.dispose();
  }

  void _dragHandle(DragUpdateDetails details) {
    if (!_controller.isAttached) return;
    final delta = _controller.pixelsToSize(details.primaryDelta ?? 0);
    _controller.jumpTo(
      (_controller.size - delta).clamp(widget.minChildSize, widget.maxChildSize),
    );
  }

  void _settleHandle(List<double> snapSizes, double velocity) {
    if (!_controller.isAttached || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final size = _controller.size;
    final stops = {widget.minChildSize, ...snapSizes, widget.maxChildSize}
        .toList()..sort();
    final target = switch (velocity) {
      > 700 => stops.lastWhere((stop) => stop < size, orElse: () => stops.first),
      < -700 => stops.firstWhere((stop) => stop > size, orElse: () => stops.last),
      _ => stops.reduce((a, b) => (a - size).abs() <= (b - size).abs() ? a : b),
    };
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    final containerColor = widget.backgroundColor ??
        (isIos
            ? (isDark
                ? const Color(0xFF1C1C1E)
                : CupertinoColors.systemBackground)
            : Theme.of(context).colorScheme.surfaceContainerHighest);

    final effectiveSnapSizes = widget.snapSizes ??
        (widget.initialChildSize < widget.maxChildSize
            ? [widget.initialChildSize, widget.maxChildSize]
            : [widget.initialChildSize]);

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth ?? 600),
        child: DraggableScrollableSheet(
          controller: _controller,
          initialChildSize: widget.initialChildSize.clamp(
            widget.minChildSize,
            widget.maxChildSize,
          ),
          minChildSize: widget.minChildSize,
          maxChildSize: widget.maxChildSize,
          snap: true,
          snapSizes: effectiveSnapSizes,
          snapAnimationDuration: const Duration(milliseconds: 250),
          shouldCloseOnMinExtent: widget.shouldCloseOnMinExtent,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: containerColor,
                borderRadius: widget.borderRadius ??
                    const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: widget.showShadow
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.15),
                          blurRadius: 18,
                          offset: const Offset(0, -4),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.showHandle)
                    ModalDragHandle(
                      onTap: HapticFeedback.selectionClick,
                      onVerticalDragUpdate: _dragHandle,
                      onVerticalDragEnd: (details) => _settleHandle(
                        effectiveSnapSizes,
                        details.primaryVelocity ?? 0,
                      ),
                      onVerticalDragCancel: () => _settleHandle(effectiveSnapSizes, 0),
                    ),
                  Expanded(
                    child: widget.builder(context, scrollController),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A sleek pill drag handle indicator with touch target and affordance.
class ModalDragHandle extends StatelessWidget {
  final VoidCallback? onTap;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final GestureDragCancelCallback? onVerticalDragCancel;
  final EdgeInsetsGeometry margin;
  final double width;
  final double height;

  const ModalDragHandle({
    super.key,
    this.onTap,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onVerticalDragCancel,
    this.margin = const EdgeInsets.only(top: 10, bottom: 8),
    this.width = 36,
    this.height = 4.5,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    final handleColor = isDark
        ? Colors.white.withValues(alpha: 0.3)
        : Colors.black.withValues(alpha: 0.25);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTap: onTap,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      onVerticalDragCancel: onVerticalDragCancel,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(minHeight: onVerticalDragUpdate == null ? 0 : 44),
        alignment: Alignment.center,
        padding: margin,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: handleColor,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      ),
    );
  }
}

/// Convenience helper to open any widget inside a smooth, draggable modal bottom sheet.
Future<T?> showAdaptiveDraggableModal<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, ScrollController scrollController) builder,
  double initialChildSize = 0.55,
  double minChildSize = 0.25,
  double maxChildSize = 0.95,
  List<double>? snapSizes,
  bool showHandle = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
  Color? barrierColor,
  Color? sheetBackgroundColor,
  BorderRadiusGeometry? borderRadius,
  DraggableScrollableController? controller,
  double? maxWidth = 600,
}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: false,
    elevation: 0,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.4),
    builder: (context) => DraggableModalSheet(
      controller: controller,
      maxWidth: maxWidth,
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      snapSizes: snapSizes,
      showHandle: showHandle,
      backgroundColor: sheetBackgroundColor,
      borderRadius: borderRadius,
      builder: builder,
    ),
  );
}
