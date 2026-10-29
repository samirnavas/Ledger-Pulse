import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../core/utils/currency_formatter.dart';

/// Giant Typographic Amount Display (No system keyboard popup).
class EntryAmountDisplay extends StatelessWidget {
  final String amountString;
  final Color themeColor;
  final String? errorMessage;
  final String currencyCode;
  final String? title;

  const EntryAmountDisplay({
    super.key,
    required this.amountString,
    required this.themeColor,
    this.errorMessage,
    this.currencyCode = 'INR',
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final rawAmountDouble = double.tryParse(amountString) ?? 0.0;
    final rawAmountCents = (rawAmountDouble * 100).round();
    final formattedDisplay = CurrencyFormatter.format(rawAmountCents, currencyCode: currencyCode);
    final currencySymbol = CurrencyFormatter.getSymbol(currencyCode);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isIos
                ? (isDark
                    ? CupertinoColors.systemBackground.darkColor
                    : CupertinoColors.white)
                : Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: errorMessage != null
                  ? AppColors.payableRed
                  : themeColor.withValues(
                      alpha: isDark ? 0.4 : 0.3,
                    ),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              if (title != null) ...[
                Text(
                  title!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFA1A1AA)
                        : AppColors.textMutedLight,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    currencySymbol,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: themeColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      amountString,
                      style: TextStyle(
                        fontSize: amountString.length > 6 ? 34 : 42,
                        fontWeight: FontWeight.w900,
                        color: themeColor,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (rawAmountCents > 0)
                Text(
                  formattedDisplay,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFA1A1AA)
                        : AppColors.textMutedLight,
                  ),
                ),
            ],
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 6),
          Center(
            child: Text(
              errorMessage!,
              style: const TextStyle(
                color: AppColors.payableRed,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
