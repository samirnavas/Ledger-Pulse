import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/typography.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../data/models/transaction_model.dart';

/// Top Header: Type Indicator & Party Name for AddEntryBottomSheet.
class EntryHeader extends StatelessWidget {
  final String partyName;
  final bool isEdit;
  final EntryType entryType;
  final Color themeColor;

  const EntryHeader({
    super.key,
    required this.partyName,
    required this.isEdit,
    required this.entryType,
    required this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isGave = entryType == EntryType.gave;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: themeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isEdit
                    ? (isIos ? CupertinoIcons.pencil : Icons.edit_outlined)
                    : (isGave
                        ? (isIos ? CupertinoIcons.arrow_up : Icons.arrow_upward_rounded)
                        : (isIos ? CupertinoIcons.arrow_down : Icons.arrow_downward_rounded)),
                size: 15,
                color: themeColor,
              ),
              const SizedBox(width: 4),
              Text(
                isEdit
                    ? 'EDIT ENTRY'
                    : (isGave ? 'YOU GAVE' : 'YOU GOT'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: themeColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            partyName,
            style: AppTypography.titleMedium.copyWith(fontSize: 15),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
