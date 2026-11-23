import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/adaptive_theme.dart';
import 'adaptive_button.dart';
import 'draggable_modal_sheet.dart';

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
/// The handle resizes the sheet independently of the list scroll position.
Future<T?> showAdaptivePicker<T>({
  required BuildContext context,
  required String title,
  String? message,
  required List<AdaptivePickerItem<T>> items,
  T? selectedValue,
  String cancelLabel = 'Cancel',
}) {
  final isIos = AdaptiveThemeHelper.isIos(context);
  final height = MediaQuery.sizeOf(context).height;
  final itemHeight = items.any((item) => item.subtitle != null) ? 72 : 56;
  final initialSize = ((144 + items.length * itemHeight) / height)
      .clamp(0.30, 0.60);

  return showAdaptiveDraggableModal<T>(
    context: context,
    useRootNavigator: isIos,
    initialChildSize: initialSize,
    builder: (context, scrollController) {
      final theme = Theme.of(context);
      return Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(title, style: theme.textTheme.titleLarge),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(message, style: theme.textTheme.bodyMedium),
                ),
              for (final item in items)
                ListTile(
                  leading: item.icon,
                  title: Text(
                    item.label,
                    style: TextStyle(
                      fontWeight: item.value == selectedValue
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: item.isDestructive ? theme.colorScheme.error : null,
                    ),
                  ),
                  subtitle: item.subtitle == null ? null : Text(item.subtitle!),
                  selected: item.value == selectedValue,
                  trailing: item.value == selectedValue
                      ? Icon(isIos ? CupertinoIcons.checkmark : Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.of(context).pop(item.value),
                ),
              AdaptiveButton(
                type: AdaptiveButtonType.text,
                onPressed: () => Navigator.of(context).pop(),
                child: Text(cancelLabel),
              ),
            ],
          ),
        ),
      );
    },
  );
}
