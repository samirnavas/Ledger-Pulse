import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/strings.dart';
import 'core/theme/android_theme.dart';
import 'core/theme/ios_theme.dart';
import 'presentation/auth/phone_input_screen.dart';
import 'presentation/home/dashboard_screen.dart';
import 'presentation/providers/auth_providers.dart';

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
    final authState = ref.watch(authControllerProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: AppStrings.appName,
          debugShowCheckedModeBanner: false,
          theme: AndroidTheme.getTheme(dynamicColorScheme: lightDynamic).copyWith(
            cupertinoOverrideTheme: IosTheme.lightTheme,
          ),
          darkTheme: AndroidTheme.getTheme(dynamicColorScheme: darkDynamic).copyWith(
            cupertinoOverrideTheme: IosTheme.lightTheme,
          ),
          themeMode: ThemeMode.light,
          home: authState.isAuthenticated
              ? const DashboardScreen()
              : const PhoneInputScreen(),
        );
      },
    );
  }
}
