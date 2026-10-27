import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/adaptive_theme.dart';

/// Item representation for [showAdaptivePicker].
class AdaptivePickerItem<T> {
  final T value;
  final String label;
  final String? subtitle;
  final Widget? icon;
  final bool isDestructive;

  const AdaptivePickerItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.isDestructive = false,
  });
}

/// Static convenience wrapper for adaptive picker.
class AdaptivePicker {
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? message,
    required List<AdaptivePickerItem<T>> items,
    T? selectedValue,
    String cancelLabel = 'Cancel',
  }) {
    return showAdaptivePicker<T>(
      context: context,
      title: title,
      message: message,
      items: items,
      selectedValue: selectedValue,
      cancelLabel: cancelLabel,
    );
  }
}

/// Shows a platform-adaptive selection picker.
/// On iOS: CupertinoActionSheet.
/// On Material: Material 3 Bottom Sheet selection list.
Future<T?> showAdaptivePicker<T>({
  required BuildContext context,
  required String title,
  String? message,
  required List<AdaptivePickerItem<T>> items,
  T? selectedValue,
  String cancelLabel = 'Cancel',
}) async {
  final isIos = AdaptiveThemeHelper.isIos(context);

  if (isIos) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        message: message != null ? Text(message) : null,
        actions: items.map((item) {
          final isSelected = item.value == selectedValue;
          return CupertinoActionSheetAction(
            isDestructiveAction: item.isDestructive,
            onPressed: () => Navigator.of(ctx).pop(item.value),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (item.icon != null) ...[
                  item.icon!,
                  const SizedBox(width: 8),
                ],
                Text(
                  item.label,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  const Icon(CupertinoIcons.checkmark, size: 18),
                ],
              ],
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: Text(cancelLabel),
        ),
      ),
    );
  } else {
    final theme = Theme.of(context);
    return showModalBottomSheet<T>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: Text(
                      message,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                ...items.map((item) {
                  final isSelected = item.value == selectedValue;
                  return ListTile(
                    leading: item.icon,
                    title: Text(
                      item.label,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: item.isDestructive ? theme.colorScheme.error : null,
                      ),
                    ),
                    subtitle: item.subtitle != null ? Text(item.subtitle!) : null,
                    trailing: isSelected
                        ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                        : null,
                    onTap: () => Navigator.of(ctx).pop(item.value),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}
