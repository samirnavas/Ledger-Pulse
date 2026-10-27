import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../data/models/transaction_model.dart';

/// Type Switcher: You Gave vs You Got segmented control.
class EntryTypeSwitcher extends StatelessWidget {
  final EntryType entryType;
  final ValueChanged<EntryType> onTypeChanged;

  const EntryTypeSwitcher({
    super.key,
    required this.entryType,
    required this.onTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isGave = entryType == EntryType.gave;

    return Container(
      decoration: BoxDecoration(
        color: isIos
            ? CupertinoColors.systemGrey5
            : Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                onTypeChanged(EntryType.gave);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isGave ? AppColors.payableRed : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isGave
                      ? [
                          BoxShadow(
                            color: AppColors.payableRed.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    '- You Gave',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isGave
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                onTypeChanged(EntryType.got);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: !isGave ? AppColors.receivableGreen : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: !isGave
                      ? [
                          BoxShadow(
                            color: AppColors.receivableGreen.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    '+ You Got',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: !isGave
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
