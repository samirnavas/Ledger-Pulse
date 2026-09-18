import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/theme/android_theme.dart';
import 'package:ledger_pulse/core/widgets/liquid_glass_card.dart';
import 'package:ledger_pulse/core/widgets/adaptive_button.dart';
import 'package:ledger_pulse/core/widgets/adaptive_segmented_control.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';

void main() {
  group('AndroidTheme M3 Expressive Tests', () {
    test('AndroidTheme has 0 card elevation and 24px border radius', () {
      final theme = AndroidTheme.getTheme();

      expect(theme.useMaterial3, isTrue);
      expect(theme.cardTheme.elevation, equals(0));

      final shape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, equals(BorderRadius.circular(24)));
      expect(theme.cardTheme.color, equals(theme.colorScheme.surfaceContainerLow));
      expect(theme.floatingActionButtonTheme.elevation, equals(0));
    });
  });

  group('real_liquid_glass and LiquidGlassCard Widget Tests', () {
    testWidgets('LiquidGlassContainer renders with blur and border', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiquidGlassContainer(
              borderRadius: 24,
              blur: 24,
              child: Text('Real Liquid Glass Direct'),
            ),
          ),
        ),
      );

      expect(find.text('Real Liquid Glass Direct'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('LiquidGlassCard renders child content and backdrop filter', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiquidGlassCard(
              child: Text('Frosted Glass Content'),
            ),
          ),
        ),
      );

      expect(find.text('Frosted Glass Content'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.byType(ClipRRect), findsOneWidget);

      final backdropFilter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(backdropFilter.filter, equals(ImageFilter.blur(sigmaX: 24, sigmaY: 24)));
    });

    testWidgets('LiquidGlassCard responds to onTap callback', (WidgetTester tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiquidGlassCard(
              onTap: () => tapped = true,
              child: const Text('Tap Me'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tap Me'));
      expect(tapped, isTrue);
    });
  });

  group('AdaptiveButton and SegmentedControl Tests', () {
    testWidgets('AdaptiveButton fires onPressed callback', (WidgetTester tester) async {
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveButton(
              onPressed: () => pressed = true,
              child: const Text('Press Button'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Press Button'));
      expect(pressed, isTrue);
    });

    testWidgets('AdaptiveSegmentedControl triggers onValueChanged', (WidgetTester tester) async {
      String selected = 'one';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveSegmentedControl<String>(
              groupValue: selected,
              children: const {
                'one': Text('Tab 1'),
                'two': Text('Tab 2'),
              },
              onValueChanged: (val) => selected = val,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tab 2'));
      await tester.pumpAndSettle();
      expect(selected, equals('two'));
    });
  });
}
