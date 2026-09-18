import 'dart:io' show Platform;
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/strings.dart';
import 'core/theme/android_theme.dart';
import 'core/theme/ios_theme.dart';
import 'presentation/splash/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

    if (isIos) {
      return CupertinoApp(
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        theme: IosTheme.lightTheme,
        home: const SplashScreen(),
      );
    }

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: AppStrings.appName,
          debugShowCheckedModeBanner: false,
          theme: AndroidTheme.getLight(lightDynamic),
          darkTheme: AndroidTheme.getDark(darkDynamic),
          themeMode: ThemeMode.system,
          home: const SplashScreen(),
        );
      },
    );
  }
}

