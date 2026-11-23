import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/adaptive_theme.dart';
import 'draggable_modal_sheet.dart';

/// Class wrapper for displaying and structuring platform-adaptive form bottom sheets.
class AdaptiveFormSheet {
  /// Displays a modal form sheet adaptively styled for Cupertino (iOS/macOS)
  /// and Material 3 (Android/web/desktop).
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget Function(BuildContext sheetContext) builder,
    String? title,
    String? doneLabel,
    VoidCallback? onDone,
    bool isDismissible = true,
    bool enableDrag = true,
    bool useRootNavigator = false,
  }) {
    return showAdaptiveFormSheet<T>(
      context: context,
      builder: builder,
      title: title,
      doneLabel: doneLabel,
      onDone: onDone,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      useRootNavigator: useRootNavigator,
    );
  }
}

/// Helper function to show a platform-adaptive form modal sheet.
Future<T?> showAdaptiveFormSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext sheetContext) builder,
  String? title,
  String? doneLabel,
  VoidCallback? onDone,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
}) {
  final isIos = AdaptiveThemeHelper.isIos(context);

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _AdaptiveFormSheetWrapper(
      isIos: isIos,
      showHandle: enableDrag,
      title: title,
      doneLabel: doneLabel,
      onDone: onDone,
      child: builder(sheetContext),
    ),
  );
}

class _AdaptiveFormSheetWrapper extends StatelessWidget {
  final bool isIos;
  final bool showHandle;
  final String? title;
  final String? doneLabel;
  final VoidCallback? onDone;
  final Widget child;

  const _AdaptiveFormSheetWrapper({
    required this.isIos,
    required this.showHandle,
    this.title,
    this.doneLabel,
    this.onDone,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isIos
        ? (isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemBackground)
        : (isDark ? const Color(0xFF1E2128) : theme.colorScheme.surface);

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: mediaQuery.size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showHandle) const ModalDragHandle(),

              // Optional Header
              if (title != null || doneLabel != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (isIos)
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size.square(32),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      if (title != null)
                        Expanded(
                          child: Text(
                            title!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isIos ? 17 : 18,
                              fontWeight: FontWeight.w600,
                              color: isIos
                                  ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      if (doneLabel != null)
                        if (isIos)
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size.square(32),
                            onPressed: onDone ?? () => Navigator.of(context).pop(),
                            child: Text(
                              doneLabel!,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          )
                        else
                          TextButton(
                            onPressed: onDone ?? () => Navigator.of(context).pop(),
                            child: Text(
                              doneLabel!,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          )
                      else
                        const SizedBox(width: 40),
                    ],
                  ),
                ),

              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
