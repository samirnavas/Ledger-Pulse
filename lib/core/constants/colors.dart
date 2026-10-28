import 'package:flutter/material.dart';

class AppColors {
  // Brand / Semantic Colors per specification
  static const Color receivableGreen = Color(0xFF16A34A);
  static const Color receivableGreenLight = Color(0xFFDCFCE7);
  static const Color receivableGreenDark = Color(0xFF14532D);

  static const Color payableRed = Color(0xFFDC2626);
  static const Color payableRedLight = Color(0xFFFEE2E2);
  static const Color payableRedDark = Color(0xFF7F1D1D);

  // Neutral Surfaces
  static const Color surfaceLight = Color(0xFFF8FAFC);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color surfaceCardLight = Color(0xFFFFFFFF);
  static const Color surfaceCardM3 = Color(0xFFF1F5F9);

  static const Color surfaceDark = Color(0xFF000000);
  static const Color surfaceCardDark = Color(0xFF141414);

  // Borders & Dividers
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderDark = Color(0xFF27272A);

  // Text Colors
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF64748B);
  static const Color textMutedLight = Color(0xFF94A3B8);

  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textMutedDark = Color(0xFF64748B);

  // Accent / Primary Brand (Electric Indigo / Sapphire)
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color primaryBlueLight = Color(0xFFDBEAFE);
  static const Color primaryBlueDark = Color(0xFF1D4ED8);

  // Cupertino specific system tints
  static const Color cupertinoSystemBackground = Color(0xFFF2F2F7);
  static const Color cupertinoGroupedBackground = Color(0xFFFFFFFF);
  static const Color cupertinoBarBackground = Color(0xCCF8FAFC);

  // Semantic Transaction Colors (Income, Expense, Transfer)
  static const Color incomeLight = Color(0xFF16A34A);
  static const Color incomeDark = Color(0xFF4ADE80);

  static const Color expenseLight = Color(0xFFDC2626);
  static const Color expenseDark = Color(0xFFF87171);

  static const Color transferLight = Color(0xFF2563EB);
  static const Color transferDark = Color(0xFF60A5FA);

  static Color income(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? incomeDark : incomeLight;

  static Color expense(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? expenseDark : expenseLight;

  static Color transfer(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? transferDark : transferLight;
}

extension SemanticColorScheme on ColorScheme {
  Color get income => brightness == Brightness.dark ? AppColors.incomeDark : AppColors.incomeLight;
  Color get expense => brightness == Brightness.dark ? AppColors.expenseDark : AppColors.expenseLight;
  Color get transfer => brightness == Brightness.dark ? AppColors.transferDark : AppColors.transferLight;
}
