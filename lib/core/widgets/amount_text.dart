import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/typography.dart';
import '../utils/currency_formatter.dart';

enum AmountVariant {
  large,
  medium,
  small,
}

class AmountText extends StatelessWidget {
  final int amountInCents;
  final AmountVariant variant;
  final bool showSign;
  final bool absolute;
  final Color? overrideColor;
  final bool isReceivablePositive; // If true: >0 is Green, <0 is Red.

  const AmountText({
    super.key,
    required this.amountInCents,
    this.variant = AmountVariant.medium,
    this.showSign = false,
    this.absolute = false,
    this.overrideColor,
    this.isReceivablePositive = true,
  });

  @override
  Widget build(BuildContext context) {
    Color textColor;
    if (overrideColor != null) {
      textColor = overrideColor!;
    } else if (amountInCents == 0) {
      textColor = AppColors.textSecondaryLight;
    } else if (isReceivablePositive) {
      textColor = amountInCents > 0 ? AppColors.receivableGreen : AppColors.payableRed;
    } else {
      textColor = amountInCents > 0 ? AppColors.payableRed : AppColors.receivableGreen;
    }

    TextStyle style;
    switch (variant) {
      case AmountVariant.large:
        style = AppTypography.amountLarge.copyWith(color: textColor);
        break;
      case AmountVariant.medium:
        style = AppTypography.amountMedium.copyWith(color: textColor);
        break;
      case AmountVariant.small:
        style = AppTypography.amountSmall.copyWith(color: textColor);
        break;
    }

    final formatted = CurrencyFormatter.format(
      amountInCents,
      showSign: showSign,
      absolute: absolute,
    );

    return Text(
      formatted,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
