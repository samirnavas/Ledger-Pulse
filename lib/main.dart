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
import 'core/theme/app_color_theme.dart';
import 'core/theme/ios_theme.dart';
import 'data/models/company_mode.dart';
import 'presentation/expense/quick_add_transaction_sheet.dart';
import 'package:home_widget/home_widget.dart';
import 'presentation/providers/auth_providers.dart';
import 'presentation/providers/company_providers.dart';
import 'presentation/providers/profile_session_controller.dart';
import 'presentation/providers/profile_session_state.dart';
import 'presentation/providers/recurring_providers.dart';
import 'presentation/providers/sync_providers.dart';
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
      await HomeWidget.setAppGroupId(WidgetSyncService.appGroupId);
      final initialWidgetUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initialWidgetUri?.queryParameters['action'] == 'quick_add') {
        SplashScreen.skipHold = true;
      }
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
  static final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

  const LedgerPulseApp({super.key});

  @override
  ConsumerState<LedgerPulseApp> createState() => _LedgerPulseAppState();
}

class _LedgerPulseAppState extends ConsumerState<LedgerPulseApp> {
  AppLifecycleListener? _lifecycleListener;

  Future<void> _processRecurringIfDue() async {
    try {
      final company = ref.read(activeCompanyProvider);
      if (company.mode == CompanyMode.expenseTracker &&
          company.isModuleEnabled(AppModule.recurring)) {
        await ref.read(recurringServiceProvider).generateDue(DateTime.now());
      }
    } catch (e) {
      debugPrint('Background recurring check failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    // Setup app lifecycle listener to auto-sync each time app is opened / resumed from background
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        ref.read(syncControllerProvider.notifier).autoSyncOnAppOpen();
        _processRecurringIfDue();
      },
    );

    // Setup widget click handler for deep linking safely after the initial frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Trigger automatic synchronization on initial app launch (cold start)
      ref.read(syncControllerProvider.notifier).autoSyncOnAppOpen();
      _processRecurringIfDue();

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        WidgetSyncService.initialize(
          onWidgetClick: (uri) {
            final companyId = uri.queryParameters['company_id'];
            if (companyId != null && companyId.isNotEmpty) {
              final activeCompany = ref.read(activeCompanyProvider);
              if (activeCompany.id != companyId) {
                ref.read(companyControllerProvider.notifier).selectCompany(companyId);
                final sessionState = ref.read(profileSessionProvider);
                if (sessionState is ActiveProfileReadySessionState) {
                  final match = sessionState.availableProfiles.where((p) => p.id == companyId).firstOrNull;
                  if (match != null && match.id != sessionState.activeProfile.id) {
                    ref.read(profileSessionProvider.notifier).switchProfile(match);
                  }
                }
              }
            }

            final actionParam = uri.queryParameters['action'];
            if (actionParam == 'quick_add') {
              void tryOpenQuickAdd([int attempts = 0]) {
                if (QuickAddTransactionSheet.isSheetOpen) return;

                // 1. Wait until splash screen has completed its transition and pushReplacement
                if (SplashScreen.isSplashActive && attempts < 40) {
                  Future.delayed(const Duration(milliseconds: 100), () => tryOpenQuickAdd(attempts + 1));
                  return;
                }

                // 2. Wait until profile session has finished loading workspaces
                final sessionState = ref.read(profileSessionProvider);
                if ((sessionState is LoadingProfilesSessionState || sessionState is SessionInitializingState) && attempts < 40) {
                  Future.delayed(const Duration(milliseconds: 100), () => tryOpenQuickAdd(attempts + 1));
                  return;
                }

                // 3. Ensure rootNavigatorKey has a mounted context ready to present modal
                final ctx = LedgerPulseApp.rootNavigatorKey.currentContext;
                if (ctx != null && ctx.mounted) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final readyCtx = LedgerPulseApp.rootNavigatorKey.currentContext;
                    if (readyCtx != null && readyCtx.mounted && !QuickAddTransactionSheet.isSheetOpen) {
                      QuickAddTransactionSheet.show(readyCtx);
                    }
                  });
                } else if (attempts < 40) {
                  Future.delayed(const Duration(milliseconds: 100), () => tryOpenQuickAdd(attempts + 1));
                }
              }
              WidgetsBinding.instance.addPostFrameCallback((_) => tryOpenQuickAdd());
            }

            final moduleParam = uri.queryParameters['module'] ??
                (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null);
            if (moduleParam != null) {
              final module = AppModule.fromName(moduleParam);
              if (module != null) {
                final company = ref.read(activeCompanyProvider);
                if (!company.isModuleEnabled(module)) {
                  debugPrint('Deep link ignored: module ${module.name} is disabled');
                  return;
                }
              }
            }
          },
        );
      }
    });
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Profiles load after the first frame; check again when the active workspace
    // becomes ready or the user switches companies.
    ref.listen(activeCompanyProvider, (previous, next) {
      if (previous?.id != next.id || previous?.mode != next.mode ||
          previous?.isModuleEnabled(AppModule.recurring) != next.isModuleEnabled(AppModule.recurring)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _processRecurringIfDue();
        });
      }
    });
    // Keep native home screen widget synced with active company & business totals
    ref.watch(widgetSyncProvider);
    // Keep data synchronized automatically each time the app opens or switches company
    ref.watch(autoSyncProvider);

    final isIos = !kIsWeb && Platform.isIOS;
    final themeMode = ref.watch(appThemeModeProvider);
    final dynamicColorEnabled = ref.watch(dynamicColorEnabledProvider);

    if (isIos) {
      final isDark = themeMode == ThemeMode.dark ||
          (themeMode == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);
      return CupertinoApp(
        navigatorKey: LedgerPulseApp.rootNavigatorKey,
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        theme: isDark ? IosTheme.darkTheme : IosTheme.lightTheme,
        builder: (context, child) => Theme(
          data: AndroidTheme.getTheme(
            dynamicColorScheme: isDark ? AppColorTheme.dark : AppColorTheme.light,
          ).copyWith(platform: TargetPlatform.iOS),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const SplashScreen(),
      );
    }

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final lightScheme = (dynamicColorEnabled ? lightDynamic : null) ?? AppColorTheme.light;
        final darkScheme = (dynamicColorEnabled ? darkDynamic : null) ?? AppColorTheme.dark;

        return MaterialApp(
          navigatorKey: LedgerPulseApp.rootNavigatorKey,
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

