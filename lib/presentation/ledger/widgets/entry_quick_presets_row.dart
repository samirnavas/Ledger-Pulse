import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../data/models/transaction_model.dart';

/// Row of quick preset amount chips (+₹100, +₹500, +₹1000, +₹5000).
/// On Android: Material 3 ActionChip.
/// On iOS: RealLiquidGlass with Cupertino styling.
class EntryQuickPresetsRow extends StatelessWidget {
  final ValueChanged<int> onAddPreset;
  final EntryType? entryType;
  final Color? themeColor;
  final String currencySymbol;
  final List<int> presets;

  const EntryQuickPresetsRow({
    super.key,
    required this.onAddPreset,
    this.entryType,
    this.themeColor,
    this.currencySymbol = '₹',
    this.presets = const [100, 500, 1000, 5000],
  });

  Widget _buildQuickPresetChip(BuildContext context, int amount) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final isGave = entryType == EntryType.gave;
    final effectiveThemeColor = themeColor ??
        (isGave ? AppColors.payableRed : AppColors.receivableGreen);

    if (isIos) {
      return Expanded(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onAddPreset(amount);
          },
          child: RealLiquidGlass(
            borderRadius: 22,
            glassColor: effectiveThemeColor.withValues(alpha: isDark ? 0.18 : 0.1),
            borderColor: effectiveThemeColor.withValues(alpha: isDark ? 0.35 : 0.25),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Center(
                child: Text(
                  '+$currencySymbol$amount',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: effectiveThemeColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ActionChip(
          onPressed: () {
            HapticFeedback.lightImpact();
            onAddPreset(amount);
          },
          label: Center(
            child: Text(
              '+$currencySymbol$amount',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: effectiveThemeColor,
              ),
            ),
          ),
          side: BorderSide(
            color: isDark
                ? const Color(0xFF282828)
                : Theme.of(context).colorScheme.outlineVariant,
          ),
          backgroundColor: isDark
              ? const Color(0xFF1E1E1E)
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          shape: const StadiumBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: presets
          .map((amount) => _buildQuickPresetChip(context, amount))
          .toList(),
    );
  }
}
