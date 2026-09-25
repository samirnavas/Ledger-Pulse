import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifier managing the active application ThemeMode (Light, Dark, or System/Auto).
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    return ThemeMode.system;
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
  }

  void setLight() => state = ThemeMode.light;
  void setDark() => state = ThemeMode.dark;
  void setAuto() => state = ThemeMode.system;
}

/// Global provider for the application theme mode.
final appThemeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
