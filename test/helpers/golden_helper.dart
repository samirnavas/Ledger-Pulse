import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/theme/android_theme.dart';

/// Helper function to capture a clean Golden UI snapshot of any page or widget.
///
/// [tester] - The [WidgetTester] instance provided by [testWidgets].
/// [page] - The page or widget you want to preview.
/// [goldenName] - The filename for the output PNG image (saved in `test/previews/goldens/`).
/// [overrides] - Optional Riverpod provider overrides if the page depends on specific providers.
/// [size] - Logical screen resolution (defaults to standard mobile dimensions: 390x844).
/// [theme] - Optional custom light ThemeData (defaults to [AndroidTheme.getLight()]).
/// [darkTheme] - Optional custom dark ThemeData (defaults to [AndroidTheme.getDark()]).
Future<void> expectPageGolden(
  WidgetTester tester, {
  required Widget page,
  required String goldenName,
  List<dynamic> overrides = const [],
  Size size = const Size(390, 844),
  ThemeData? theme,
  ThemeData? darkTheme,
}) async {
  // Set target physical resolution and pixel density for crisp screenshot rendering
  tester.view.physicalSize = size * 3.0;
  tester.view.devicePixelRatio = 3.0;

  // Reset binding view after test completes
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  // Pump the widget hierarchy wrapped in Riverpod ProviderScope & MaterialApp
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? AndroidTheme.getLight(),
        darkTheme: darkTheme ?? AndroidTheme.getDark(),
        themeMode: ThemeMode.light,
        home: page,
      ),
    ),
  );

  // Wait for all UI animations, layouts, and frame settling
  await tester.pumpAndSettle();

  // Compare/generate PNG golden image under test/previews/goldens/
  await expectLater(
    find.byWidget(page),
    matchesGoldenFile('goldens/$goldenName.png'),
  );
}
