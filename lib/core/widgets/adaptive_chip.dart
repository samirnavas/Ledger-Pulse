import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/adaptive_theme.dart';

/// Item representation for [AdaptiveChipRow].
class AdaptiveChipItem<T> {
  final T value;
  final String label;
  final Widget? icon;

  const AdaptiveChipItem({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// Platform-adaptive individual filter/choice chip.
/// - Android: M3 [FilterChip] styled to match theme.
/// - iOS: Glass pill container with [CupertinoColors.activeBlue] selected highlight.
class AdaptiveChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final ValueChanged<bool>? onSelected;
  final Widget? icon;
  final Color? selectedColor;

  const AdaptiveChip({
    super.key,
    required this.label,
    required this.isSelected,
    this.onSelected,
    this.icon,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isIos) {
      final activeColor = selectedColor ?? CupertinoColors.activeBlue;
      final bgColor = isSelected
          ? activeColor
          : (isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.06));
      final textColor = isSelected
          ? CupertinoColors.white
          : (isDark ? CupertinoColors.white : CupertinoColors.black);
      final borderColor = isSelected
          ? activeColor
          : (isDark
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.black.withValues(alpha: 0.12));

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onSelected?.call(!isSelected);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                icon!,
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: textColor,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      avatar: icon,
      onSelected: (val) {
        HapticFeedback.lightImpact();
        onSelected?.call(val);
      },
      selectedColor: selectedColor ?? theme.colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected
            ? (selectedColor != null
                ? Colors.white
                : theme.colorScheme.onPrimaryContainer)
            : theme.colorScheme.onSurface,
      ),
    );
  }
}

/// Horizontal scrollable row of [AdaptiveChip]s supporting both single and multi-selection.
class AdaptiveChipRow<T> extends StatelessWidget {
  final List<AdaptiveChipItem<T>> items;
  final T? selectedValue;
  final ValueChanged<T?>? onSelected;
  final Set<T>? selectedValues;
  final ValueChanged<Set<T>>? onMultiSelected;
  final EdgeInsetsGeometry padding;
  final double spacing;
  final Color? selectedColor;

  const AdaptiveChipRow({
    super.key,
    required this.items,
    this.selectedValue,
    this.onSelected,
    this.selectedValues,
    this.onMultiSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.spacing = 8.0,
    this.selectedColor,
  });

  bool get isMultiSelect => selectedValues != null && onMultiSelected != null;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: padding,
      child: Row(
        children: items.map((item) {
          final isSelected = isMultiSelect
              ? (selectedValues!.contains(item.value))
              : (selectedValue == item.value);

          return Padding(
            padding: EdgeInsets.only(right: spacing),
            child: AdaptiveChip(
              label: item.label,
              icon: item.icon,
              isSelected: isSelected,
              selectedColor: selectedColor,
              onSelected: (selected) {
                if (isMultiSelect) {
                  final newSet = Set<T>.from(selectedValues!);
                  if (selected) {
                    newSet.add(item.value);
                  } else {
                    newSet.remove(item.value);
                  }
                  onMultiSelected!(newSet);
                } else {
                  if (selected) {
                    onSelected?.call(item.value);
                  } else if (selectedValue == item.value) {
                    onSelected?.call(null);
                  }
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}
