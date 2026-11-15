import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_providers.dart';

const String _kThemePreferenceKey = 'user_preferred_theme_mode';

/// Notifier managing the active application ThemeMode (Light, Dark, or System/Auto),
/// persisting preferences locally in [SharedPreferences].
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return _loadSavedTheme(prefs);
  }

  static ThemeMode _loadSavedTheme(SharedPreferences? prefs) {
    if (prefs == null) return ThemeMode.system;
    final saved = prefs.getString(_kThemePreferenceKey);
    switch (saved) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
    _persistTheme(mode);
  }

  Future<void> _persistTheme(ThemeMode mode) async {
    try {
      final prefs = ref.read(sharedPreferencesProvider) ??
          await SharedPreferences.getInstance();
      String stringValue;
      switch (mode) {
        case ThemeMode.light:
          stringValue = 'light';
          break;
        case ThemeMode.dark:
          stringValue = 'dark';
          break;
        case ThemeMode.system:
          stringValue = 'system';
          break;
      }
      await prefs.setString(_kThemePreferenceKey, stringValue);
    } catch (e) {
      debugPrint('ThemeModeNotifier: failed to persist theme mode: $e');
    }
  }

  void setLight() => setThemeMode(ThemeMode.light);
  void setDark() => setThemeMode(ThemeMode.dark);
  void setAuto() => setThemeMode(ThemeMode.system);
}

/// Global provider for the application theme mode.
final appThemeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
