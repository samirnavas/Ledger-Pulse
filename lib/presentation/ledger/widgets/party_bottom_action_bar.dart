import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../core/widgets/adaptive_button.dart';

/// Floating gradient fade bottom action bar for PartyLedgerScreen with You Gave & You Got buttons.
class PartyBottomActionBar extends StatelessWidget {
  final VoidCallback onYouGave;
  final VoidCallback onYouGot;

  const PartyBottomActionBar({
    super.key,
    required this.onYouGave,
    required this.onYouGot,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final bgColor = isDark
        ? Colors.black
        : Theme.of(context).scaffoldBackgroundColor;

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        // 1. Non-interactive gradient background that fades the entries list
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    bgColor.withValues(alpha: 0.0),
                    bgColor.withValues(alpha: 0.45),
                    bgColor.withValues(alpha: 0.85),
                    bgColor,
                    bgColor,
                  ],
                  stops: const [0.0, 0.22, 0.45, 0.70, 1.0],
                ),
              ),
            ),
          ),
        ),

        // 2. Side-by-side [ - You Gave ] & [ + You Got ] Buttons
        Padding(
          padding: EdgeInsets.fromLTRB(16, 36, 16, 16 + bottomPadding),
          child: Row(
            children: [
              // - You Gave (Red)
              Expanded(
                child: AdaptiveButton(
                  onPressed: onYouGave,
                  type: AdaptiveButtonType.destructive,
                  height: 52,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isIos ? CupertinoIcons.arrow_up : Icons.arrow_upward_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        AppStrings.youGave,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // + You Got (Green)
              Expanded(
                child: AdaptiveButton(
                  onPressed: onYouGot,
                  type: AdaptiveButtonType.success,
                  height: 52,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isIos ? CupertinoIcons.arrow_down : Icons.arrow_downward_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        AppStrings.youGot,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
