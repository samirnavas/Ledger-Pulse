import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paypr/core/theme/android_theme.dart';
import 'package:paypr/core/theme/app_color_theme.dart';
import 'package:paypr/core/theme/ios_theme.dart';

void main() {
  test('Fallback matches the captured phone palette in both appearances', () {
    expect(AppColorTheme.light.primary, const Color(0xFF005EB3));
    expect(AppColorTheme.light.secondary, const Color(0xFF565D7E));
    expect(AppColorTheme.light.primaryContainer, const Color(0xFFD5E3FF));
    expect(AppColorTheme.dark.primary, const Color(0xFFA7C8FF));
    expect(AppColorTheme.dark.secondary, const Color(0xFFBEC5EB));
    expect(AppColorTheme.dark.primaryContainer, const Color(0xFF004689));
    expect(
      AndroidTheme.getLight().colorScheme.primary,
      AppColorTheme.light.primary,
    );
    expect(
      AndroidTheme.getDark().colorScheme.primary,
      AppColorTheme.dark.primary,
    );
    expect(IosTheme.lightTheme.primaryColor, AppColorTheme.light.primary);
    expect(IosTheme.darkTheme.primaryColor, AppColorTheme.dark.primary);
  });

  test('An available dynamic palette still overrides the fixed fallback', () {
    final dynamic = ColorScheme.fromSeed(seedColor: Colors.orange);
    expect(AndroidTheme.getLight(dynamic).colorScheme.primary, dynamic.primary);
  });
}
