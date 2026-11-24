import 'dart:async';
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
import 'core/services/widget_entry_service.dart';
import 'core/theme/android_theme.dart';
import 'core/theme/app_color_theme.dart';
import 'core/theme/ios_theme.dart';
import 'data/models/company_mode.dart';
import 'presentation/expense/quick_add_transaction_sheet.dart';
import 'package:home_widget/home_widget.dart';
import 'presentation/providers/auth_providers.dart';
import 'presentation/providers/company_providers.dart';
import 'presentation/providers/expense_providers.dart';
import 'presentation/providers/budget_providers.dart';
import 'presentation/providers/profile_session_controller.dart';
import 'presentation/providers/profile_session_state.dart';
import 'presentation/providers/recurring_providers.dart';
import 'presentation/providers/sync_providers.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/providers/widget_sync_provider.dart';
import 'presentation/splash/splash_screen.dart';

@pragma('vm:entry-point')
Future<void> widgetEntryMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WidgetEntryService.start();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  SharedPreferences? sharedPreferences;
  try {
    sharedPreferences = await SharedPreferences.getInstance();
  } catch (e) {
    if (kDebugMode) {
      debugPrint('SharedPreferences init notice: $e');
    }
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
      if (kDebugMode) {
        debugPrint('WidgetSyncService init notice: $e');
      }
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
      if (kDebugMode) {
        debugPrint('Supabase init notice: $e');
      }
    }
  }
  runApp(
    ProviderScope(
      overrides: [
        if (sharedPreferences != null)
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const PayprApp(),
    ),
  );
}

class PayprApp extends ConsumerStatefulWidget {
  static final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

  const PayprApp({super.key});

  @override
  ConsumerState<PayprApp> createState() => _PayprAppState();
}

class _PayprAppState extends ConsumerState<PayprApp> {
  AppLifecycleListener? _lifecycleListener;
  Timer? _recurringTimer;
  String? _widgetEntryRevision;

  Future<void> _refreshWidgetEntries() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final revision = await HomeWidget.getWidgetData<String>(
      WidgetEntryService.revisionKey,
    );
    if (!mounted || revision == null || revision == _widgetEntryRevision) return;
    _widgetEntryRevision = revision;
    ref.invalidate(expenseRepositoryProvider);
    ref.invalidate(budgetRepositoryProvider);
  }

  Future<void> _processRecurringIfDue() async {
    try {
      final company = ref.read(activeCompanyProvider);
      if (company.mode == CompanyMode.expenseTracker &&
          company.isModuleEnabled(AppModule.recurring)) {
        await ref.read(recurringServiceProvider).generateDue(DateTime.now());
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Background recurring check failed: $e');
      }
    }
  }

  void _startRecurringChecks() {
    _recurringTimer?.cancel();
    _recurringTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _processRecurringIfDue(),
    );
    _processRecurringIfDue();
  }

  void _stopRecurringChecks() {
    _recurringTimer?.cancel();
    _recurringTimer = null;
  }

  @override
  void initState() {
    super.initState();
    // Setup app lifecycle listener to auto-sync each time app is opened / resumed from background
    _lifecycleListener = AppLifecycleListener(
      onResume: () async {
        await _refreshWidgetEntries();
        if (!mounted) return;
        ref.read(syncControllerProvider.notifier).autoSyncOnAppOpen();
        if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
          _startRecurringChecks();
        }
      },
      onHide: _stopRecurringChecks,
    );

    // Setup widget click handler for deep linking safely after the initial frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Trigger automatic synchronization on initial app launch (cold start)
      ref.read(syncControllerProvider.notifier).autoSyncOnAppOpen();
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _startRecurringChecks();
      }

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        WidgetSyncService.initialize(
          onWidgetClick: (uri) async {
            final companyId = uri.queryParameters['company_id'];
            final quickAdd = uri.queryParameters['action'] == 'quick_add';
            for (var attempt = 0; attempt < 40 && mounted; attempt++) {
              final session = ref.read(profileSessionProvider);
              if (!SplashScreen.isSplashActive &&
                  session is! LoadingProfilesSessionState &&
                  session is! SessionInitializingState) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            if (!mounted || SplashScreen.isSplashActive) return;
            final navigator = PayprApp.rootNavigatorKey.currentState;
            if (navigator == null || QuickAddTransactionSheet.isSheetOpen) return;
            // Leave open editors and their drafts in place when a widget is tapped.
            if (navigator.canPop()) return;

            final session = ref.read(profileSessionProvider);
            if (session is! ActiveProfileReadySessionState) return;
            if (companyId != null && companyId != session.activeProfile.id) {
              final target = session.availableProfiles
                  .where((workspace) => workspace.id == companyId)
                  .firstOrNull;
              if (target == null) return;
              await ref.read(profileSessionProvider.notifier).switchProfile(target);
            }
            if (!mounted) return;
            final company = ref.read(activeCompanyProvider);
            if (companyId != null && company.id != companyId) return;
            if (quickAdd && company.isExpense && navigator.mounted && !navigator.canPop()) {
              await QuickAddTransactionSheet.show(navigator.context);
            }
            final moduleParam = uri.queryParameters['module'] ??
                (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null);
            if (moduleParam != null) {
              final module = AppModule.fromName(moduleParam);
              if (module != null) {
                final company = ref.read(activeCompanyProvider);
                if (!company.isModuleEnabled(module)) {
                  if (kDebugMode) {
                    debugPrint('Deep link ignored: module ${module.name} is disabled');
                  }
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
    _stopRecurringChecks();
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
    ref.watch(widgetEntryContextProvider);
    // Keep data synchronized automatically each time the app opens or switches company
    ref.watch(autoSyncProvider);

    final isIos = !kIsWeb && Platform.isIOS;
    final themeMode = ref.watch(appThemeModeProvider);
    final dynamicColorEnabled = ref.watch(dynamicColorEnabledProvider);

    if (isIos) {
      final isDark = themeMode == ThemeMode.dark ||
          (themeMode == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);
      return CupertinoApp(
        navigatorKey: PayprApp.rootNavigatorKey,
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
          navigatorKey: PayprApp.rootNavigatorKey,
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

