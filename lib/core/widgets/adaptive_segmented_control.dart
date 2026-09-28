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
      final entries = children.entries.toList();
      final selectedIndex = entries.indexWhere((e) => e.key == groupValue);

      return Container(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          children: List.generate(entries.length, (index) {
            final entry = entries[index];
            final isSelected = index == selectedIndex;
            final borderRadius = _getM3ExpressiveCornerRadius(
              index,
              entries.length,
              selectedIndex,
            );

            final containerBg = isSelected
                ? (isDark ? scheme.primary : scheme.onSurface)
                : (isDark
                    ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
                    : scheme.secondaryContainer.withValues(alpha: 0.7));

            final fgColor = isSelected
                ? (isDark ? scheme.onPrimary : scheme.surface)
                : (isDark ? scheme.onSurface : scheme.onSecondaryContainer);

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onValueChanged(entry.key);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    height: 44,
                    decoration: BoxDecoration(
                      color: containerBg,
                      borderRadius: borderRadius,
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: scheme.shadow.withValues(alpha: 0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: DefaultTextStyle(
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: fgColor,
                        ),
                        child: entry.value,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      );
    }
  }

  static BorderRadius _getM3ExpressiveCornerRadius(int index, int total, int selectedIndex) {
    const double fullRadius = 9999.0;
    const double innerRadius = 4.0;
    const double neighborRadius = 8.0;

    if (index == selectedIndex) {
      return BorderRadius.circular(fullRadius);
    }

    final bool isFirstInGroup = (index == 0);
    final bool isLeftNeighborSelected = (selectedIndex == index - 1);
    final double leftRadius = isFirstInGroup
        ? fullRadius
        : (isLeftNeighborSelected ? neighborRadius : innerRadius);

    final bool isLastInGroup = (index == total - 1);
    final bool isRightNeighborSelected = (selectedIndex == index + 1);
    final double rightRadius = isLastInGroup
        ? fullRadius
        : (isRightNeighborSelected ? neighborRadius : innerRadius);

    return BorderRadius.only(
      topLeft: Radius.circular(leftRadius),
      bottomLeft: Radius.circular(leftRadius),
      topRight: Radius.circular(rightRadius),
      bottomRight: Radius.circular(rightRadius),
    );
  }
}


