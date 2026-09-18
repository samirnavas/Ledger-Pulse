import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/colors.dart';
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
              onValueChanged(val);
            }
          },
          backgroundColor: CupertinoColors.systemGrey5,
          thumbColor: CupertinoColors.white,
        ),
      );
    } else {
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
              onValueChanged(newSelection.first);
            }
          },
          style: ButtonStyle(
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppColors.primaryBlueLight;
              }
              return Colors.transparent;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppColors.primaryBlueDark;
              }
              return AppColors.textSecondaryLight;
            }),
          ),
        ),
      );
    }
  }
}
