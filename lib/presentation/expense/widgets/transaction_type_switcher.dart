import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../data/models/voucher_model.dart';

/// Type Switcher: Expense, Income, Transfer segmented control.
/// Matches the look, feel, and animation of [EntryTypeSwitcher].
class TransactionTypeSwitcher extends StatelessWidget {
  final VoucherType selectedType;
  final ValueChanged<VoucherType> onTypeChanged;

  const TransactionTypeSwitcher({
    super.key,
    required this.selectedType,
    required this.onTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    final containerColor = isIos
        ? (isDark ? AppColors.borderDark : CupertinoColors.systemGrey5)
        : Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5);

    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildItem(
            context: context,
            type: VoucherType.expense,
            label: 'Expense',
            color: AppColors.expense(context),
            icon: isIos ? CupertinoIcons.arrow_up : Icons.arrow_upward_rounded,
          ),
          _buildItem(
            context: context,
            type: VoucherType.income,
            label: 'Income',
            color: AppColors.income(context),
            icon: isIos ? CupertinoIcons.arrow_down : Icons.arrow_downward_rounded,
          ),
          _buildItem(
            context: context,
            type: VoucherType.transfer,
            label: 'Transfer',
            color: Theme.of(context).colorScheme.primary,
            icon: isIos ? CupertinoIcons.arrow_right_arrow_left : Icons.swap_horiz_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildItem({
    required BuildContext context,
    required VoucherType type,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    final isSelected = selectedType == type;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onTypeChanged(type);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

