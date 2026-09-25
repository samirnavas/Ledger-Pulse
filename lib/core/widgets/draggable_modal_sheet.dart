import 'package:flutter/cupertino.dart';
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
class DraggableModalSheet extends StatelessWidget {
  final Widget Function(BuildContext context, ScrollController scrollController) builder;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;
  final List<double>? snapSizes;
  final bool showHandle;
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
    this.backgroundColor,
    this.borderRadius,
    this.controller,
    this.maxWidth = 600,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    final containerColor = backgroundColor ??
        (isIos
            ? (isDark
                ? const Color(0xFF1C1C1E)
                : CupertinoColors.systemBackground)
            : Theme.of(context).colorScheme.surfaceContainerHighest);

    final effectiveSnapSizes = snapSizes ??
        (initialChildSize < maxChildSize
            ? [initialChildSize, maxChildSize]
            : [initialChildSize]);

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? 600),
        child: DraggableScrollableSheet(
          controller: controller,
          initialChildSize: initialChildSize.clamp(minChildSize, maxChildSize),
          minChildSize: minChildSize,
          maxChildSize: maxChildSize,
          snap: true,
          snapSizes: effectiveSnapSizes,
          snapAnimationDuration: const Duration(milliseconds: 250),
          shouldCloseOnMinExtent: true,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: containerColor,
                borderRadius: borderRadius ??
                    const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.15),
                    blurRadius: 18,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showHandle)
                    ModalDragHandle(
                      onTap: () => HapticFeedback.selectionClick(),
                    ),
                  Expanded(
                    child: builder(context, scrollController),
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
  final EdgeInsetsGeometry margin;
  final double width;
  final double height;

  const ModalDragHandle({
    super.key,
    this.onTap,
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
      onTap: onTap,
      child: Container(
        width: double.infinity,
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
  Color? barrierColor,
  Color? sheetBackgroundColor,
  BorderRadiusGeometry? borderRadius,
  DraggableScrollableController? controller,
  double? maxWidth = 600,
}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
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
