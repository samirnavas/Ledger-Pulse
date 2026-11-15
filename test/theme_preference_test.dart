import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';
import 'package:ledger_pulse/presentation/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeModeNotifier Local Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Defaults to ThemeMode.system when no preference is saved', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final mode = container.read(appThemeModeProvider);
      expect(mode, equals(ThemeMode.system));
    });

    test('Loads pre-existing saved preference (dark)', () async {
      SharedPreferences.setMockInitialValues({
        'user_preferred_theme_mode': 'dark',
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final mode = container.read(appThemeModeProvider);
      expect(mode, equals(ThemeMode.dark));
    });

    test('Loads pre-existing saved preference (light)', () async {
      SharedPreferences.setMockInitialValues({
        'user_preferred_theme_mode': 'light',
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final mode = container.read(appThemeModeProvider);
      expect(mode, equals(ThemeMode.light));
    });

    test('Persists mode change to SharedPreferences when setDark, setLight, setAuto called', () async {
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(appThemeModeProvider.notifier);

      // Set to Dark
      notifier.setDark();
      expect(container.read(appThemeModeProvider), equals(ThemeMode.dark));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(prefs.getString('user_preferred_theme_mode'), equals('dark'));

      // Set to Light
      notifier.setLight();
      expect(container.read(appThemeModeProvider), equals(ThemeMode.light));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(prefs.getString('user_preferred_theme_mode'), equals('light'));

      // Set to System / Auto
      notifier.setAuto();
      expect(container.read(appThemeModeProvider), equals(ThemeMode.system));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(prefs.getString('user_preferred_theme_mode'), equals('system'));
    });
  });
}
