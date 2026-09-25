import 'dart:io' show Platform;
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/supabase_config.dart';
import 'core/constants/strings.dart';
import 'core/theme/android_theme.dart';
import 'core/theme/ios_theme.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (SupabaseConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        // ignore: deprecated_member_use
        anonKey: SupabaseConfig.anonKey,
      );
    } catch (e) {
      debugPrint('Supabase init notice: $e');
    }
  }
  runApp(
    const ProviderScope(
      child: LedgerPulseApp(),
    ),
  );
}

class LedgerPulseApp extends ConsumerWidget {
  const LedgerPulseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = !kIsWeb && Platform.isIOS;
    final themeMode = ref.watch(appThemeModeProvider);

    if (isIos) {
      final isDark = themeMode == ThemeMode.dark;
      return CupertinoApp(
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        theme: isDark ? IosTheme.darkTheme : IosTheme.lightTheme,
        home: const SplashScreen(),
      );
    }

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        const Color fallbackSeed = Color(0xFF006C4C);
        final lightScheme = lightDynamic ??
            ColorScheme.fromSeed(
              seedColor: fallbackSeed,
              brightness: Brightness.light,
            );
        final darkScheme = darkDynamic ??
            ColorScheme.fromSeed(
              seedColor: fallbackSeed,
              brightness: Brightness.dark,
            );

        return MaterialApp(
          title: AppStrings.appName,
          debugShowCheckedModeBanner: false,
          theme: AndroidTheme.getLight(lightScheme),
          darkTheme: AndroidTheme.getDark(darkScheme),
          themeMode: themeMode,
          home: const SplashScreen(),
        );
      },
    );
  }
}
