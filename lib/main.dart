import 'dart:io' show Platform;
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/supabase_config.dart';
import 'core/constants/strings.dart';
import 'core/services/widget_sync_service.dart';
import 'core/theme/android_theme.dart';
import 'core/theme/ios_theme.dart';
import 'presentation/providers/auth_providers.dart';
import 'presentation/providers/company_providers.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/providers/widget_sync_provider.dart';
import 'presentation/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  SharedPreferences? sharedPreferences;
  try {
    sharedPreferences = await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint('SharedPreferences init notice: $e');
  }

  // Initialize Home Screen Widget bridge & App Groups
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      await WidgetSyncService.initialize();
    } catch (e) {
      debugPrint('WidgetSyncService init notice: $e');
    }
  }

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
    ProviderScope(
      overrides: [
        if (sharedPreferences != null)
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const LedgerPulseApp(),
    ),
  );
}

class LedgerPulseApp extends ConsumerStatefulWidget {
  const LedgerPulseApp({super.key});

  @override
  ConsumerState<LedgerPulseApp> createState() => _LedgerPulseAppState();
}

class _LedgerPulseAppState extends ConsumerState<LedgerPulseApp> {
  @override
  void initState() {
    super.initState();
    // Setup widget click handler for deep linking safely after the initial frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        WidgetSyncService.initialize(
          onWidgetClick: (uri) {
            final companyId = uri.queryParameters['company_id'];
            if (companyId != null && companyId.isNotEmpty) {
              ref.read(companyControllerProvider.notifier).selectCompany(companyId);
            }
          },
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keep native home screen widget synced with active company & business totals
    ref.watch(widgetSyncProvider);

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

