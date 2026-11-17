import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import 'app_color_theme.dart';

class IosTheme {
  static CupertinoThemeData get lightTheme {
    return CupertinoThemeData(
      brightness: Brightness.light,
      primaryColor: AppColorTheme.light.primary,
      primaryContrastingColor: AppColorTheme.light.onPrimary,
      scaffoldBackgroundColor: AppColorTheme.light.surface,
      barBackgroundColor: AppColorTheme.light.surface.withValues(alpha: 0.8),
      textTheme: const CupertinoTextThemeData(
        primaryColor: AppColors.textPrimaryLight,
        textStyle: TextStyle(
          fontFamily: '.SF Pro Text',
          fontSize: 16,
          color: AppColors.textPrimaryLight,
        ),
        navTitleTextStyle: TextStyle(
          fontFamily: '.SF Pro Display',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryLight,
          letterSpacing: -0.4,
        ),
        navLargeTitleTextStyle: TextStyle(
          fontFamily: '.SF Pro Display',
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimaryLight,
          letterSpacing: -0.8,
        ),
      ),
    );
  }

  static CupertinoThemeData get darkTheme {
    return CupertinoThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColorTheme.dark.primary,
      primaryContrastingColor: AppColorTheme.dark.onPrimary,
      scaffoldBackgroundColor: Colors.black,
      barBackgroundColor: const Color(0xCC000000),
      textTheme: const CupertinoTextThemeData(
        primaryColor: Colors.white,
        textStyle: TextStyle(
          fontFamily: '.SF Pro Text',
          fontSize: 16,
          color: Colors.white,
        ),
        navTitleTextStyle: TextStyle(
          fontFamily: '.SF Pro Display',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: -0.4,
        ),
        navLargeTitleTextStyle: TextStyle(
          fontFamily: '.SF Pro Display',
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: -0.8,
        ),
      ),
    );
  }
}
