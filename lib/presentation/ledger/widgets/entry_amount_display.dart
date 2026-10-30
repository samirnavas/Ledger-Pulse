import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../core/utils/currency_formatter.dart';

/// Typographic Amount Display with touchable keypad trigger or embedded device keyboard input.
class EntryAmountDisplay extends StatelessWidget {
  final String amountString;
  final Color themeColor;
  final String? errorMessage;
  final String currencyCode;
  final String? title;
  final VoidCallback? onTap;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool showKeypadIcon;
  final Key? textFieldKey;

  const EntryAmountDisplay({
    super.key,
    required this.amountString,
    required this.themeColor,
    this.errorMessage,
    this.currencyCode = 'INR',
    this.title,
    this.onTap,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.autofocus = false,
    this.showKeypadIcon = false,
    this.textFieldKey,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final currencySymbol = CurrencyFormatter.getSymbol(currencyCode);
    final displayAmount = amountString.isEmpty ? '0' : amountString;

    Widget amountWidget;
    if (controller != null) {
      amountWidget = IntrinsicWidth(
        child: TextField(
          key: textFieldKey,
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          onChanged: onChanged,
          style: TextStyle(
            fontSize: displayAmount.length > 6 ? 34 : 42,
            fontWeight: FontWeight.w900,
            color: themeColor,
            letterSpacing: 0.5,
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
            hintText: '0',
            hintStyle: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              color: themeColor.withValues(alpha: 0.5),
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
    } else {
      amountWidget = Text(
        displayAmount,
        style: TextStyle(
          fontSize: displayAmount.length > 6 ? 34 : 42,
          fontWeight: FontWeight.w900,
          color: themeColor,
          letterSpacing: 0.5,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    Widget boxContent = Container(
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
            crossAxisAlignment: CrossAxisAlignment.center,
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
                child: amountWidget,
              ),
              if (onTap != null && showKeypadIcon) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.dialpad_rounded,
                  size: 22,
                  color: themeColor.withValues(alpha: 0.7),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (onTap != null) {
      boxContent = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: boxContent,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        boxContent,
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

