import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/adaptive_theme.dart';

class AdaptiveSegmentedControl<T extends Object> extends StatelessWidget {
  final T groupValue;
  final Map<T, Widget> children;
  final ValueChanged<T> onValueChanged;

  const AdaptiveSegmentedControl({
    super.key,
    required this.groupValue,
    required this.children,
    required this.onValueChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    if (isIos) {
      return SizedBox(
        width: double.infinity,
        child: CupertinoSlidingSegmentedControl<T>(
          groupValue: groupValue,
          children: children.map(
            (key, widget) => MapEntry(
              key,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: widget,
              ),
            ),
          ),
          onValueChanged: (val) {
            if (val != null) {
              HapticFeedback.lightImpact();
              onValueChanged(val);
            }
          },
          backgroundColor: isDark
              ? CupertinoColors.systemGrey6.darkColor
              : CupertinoColors.systemGrey5,
          thumbColor: isDark
              ? const Color(0xFF334155)
              : CupertinoColors.white,
        ),
      );
    } else {
      final scheme = Theme.of(context).colorScheme;
      // Material Design 3 SegmentedButton
      return SizedBox(
        width: double.infinity,
        child: SegmentedButton<T>(
          segments: children.entries.map((entry) {
            return ButtonSegment<T>(
              value: entry.key,
              label: entry.value,
            );
          }).toList(),
          selected: {groupValue},
          onSelectionChanged: (newSelection) {
            if (newSelection.isNotEmpty) {
              HapticFeedback.lightImpact();
              onValueChanged(newSelection.first);
            }
          },
          style: ButtonStyle(
            shape: WidgetStateProperty.all(
              const StadiumBorder(),
            ),
            side: WidgetStateProperty.resolveWith((states) {
              return BorderSide(
                color: scheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5),
                width: 1,
              );
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return scheme.primaryContainer;
              }
              return scheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.35 : 0.5);
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return scheme.onPrimaryContainer;
              }
              return scheme.onSurfaceVariant;
            }),
            textStyle: WidgetStateProperty.resolveWith((states) {
              return TextStyle(
                fontSize: 14,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w500,
              );
            }),
          ),
        ),
      );
    }
  }
}


