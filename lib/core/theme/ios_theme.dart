import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/colors.dart';

class IosTheme {
  static CupertinoThemeData get lightTheme {
    return const CupertinoThemeData(
      brightness: Brightness.light,
      primaryColor: AppColors.primaryBlue,
      scaffoldBackgroundColor: Color(0xFFF1F5F9),
      barBackgroundColor: AppColors.cupertinoBarBackground,
      textTheme: CupertinoTextThemeData(
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
    return const CupertinoThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.primaryBlue,
      scaffoldBackgroundColor: Color(0xFF0F172A),
      barBackgroundColor: Color(0xCC1E293B),
      textTheme: CupertinoTextThemeData(
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
