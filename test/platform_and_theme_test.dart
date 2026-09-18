import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/theme/android_theme.dart';
import 'package:ledger_pulse/core/widgets/liquid_glass_card.dart';
import 'package:ledger_pulse/core/utils/adaptive_page_route.dart';
import 'package:ledger_pulse/core/widgets/adaptive_bottom_nav.dart';
import 'package:ledger_pulse/core/widgets/adaptive_button.dart';
import 'package:ledger_pulse/core/widgets/adaptive_segmented_control.dart';
import 'package:ledger_pulse/core/widgets/empty_state_view.dart';
import 'package:ledger_pulse/core/widgets/skeleton_list_tile.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';
import 'package:shimmer/shimmer.dart';

void main() {
  group('AndroidTheme M3 Expressive Tests', () {
    test('AndroidTheme has 0 card elevation and 28px border radius', () {
      final theme = AndroidTheme.getTheme();

      expect(theme.useMaterial3, isTrue);
      expect(theme.cardTheme.elevation, equals(0));

      final shape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, equals(BorderRadius.circular(28)));
      expect(theme.cardTheme.color, equals(theme.colorScheme.surfaceContainerLow));
      expect(theme.floatingActionButtonTheme.elevation, equals(2));

      // Predictive back page transitions theme check
      final builders = theme.pageTransitionsTheme.builders;
      expect(builders[TargetPlatform.android], isA<PredictiveBackPageTransitionsBuilder>());
      expect(builders[TargetPlatform.iOS], isA<CupertinoPageTransitionsBuilder>());
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

  group('AdaptiveBottomNav Tests', () {
    testWidgets('AdaptiveBottomNav renders NavigationBar on Android', (WidgetTester tester) async {
      int selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Scaffold(
            bottomNavigationBar: AdaptiveBottomNav(
              currentIndex: selected,
              onTap: (val) => selected = val,
            ),
          ),
        ),
      );

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Customers'), findsOneWidget);
      expect(find.text('Suppliers'), findsOneWidget);

      await tester.tap(find.text('Suppliers'));
      expect(selected, equals(1));
    });

    testWidgets('AdaptiveBottomNav renders RealLiquidGlass CupertinoTabBar on iOS', (WidgetTester tester) async {
      int selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            bottomNavigationBar: AdaptiveBottomNav(
              currentIndex: selected,
              onTap: (val) => selected = val,
            ),
          ),
        ),
      );

      expect(find.byType(CupertinoTabBar), findsOneWidget);
      expect(find.byType(RealLiquidGlass), findsOneWidget);
      expect(find.text('Customers'), findsOneWidget);
      expect(find.text('Suppliers'), findsOneWidget);

      await tester.tap(find.text('Suppliers'));
      expect(selected, equals(1));
    });
  });

  group('SkeletonLoader Tests', () {
    testWidgets('SkeletonListTile renders with Shimmer effect', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SkeletonListTile(),
          ),
        ),
      );

      expect(find.byType(SkeletonListTile), findsOneWidget);
      expect(find.byType(Shimmer), findsOneWidget);
    });

    testWidgets('SkeletonLedgerTile renders with Shimmer effect', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SkeletonLedgerTile(),
          ),
        ),
      );

      expect(find.byType(SkeletonLedgerTile), findsOneWidget);
      expect(find.byType(Shimmer), findsOneWidget);
    });
  });

  group('AdaptivePageRoute Tests', () {
    testWidgets('createAdaptivePageRoute creates a route that pushes and pops smoothly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    createAdaptivePageRoute(
                      builder: (context) => const Scaffold(
                        body: Text('Second Screen'),
                      ),
                      transitionType: SharedAxisTransitionType.horizontal,
                    ),
                  );
                },
                child: const Text('Go Next'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Go Next'), findsOneWidget);
      await tester.tap(find.text('Go Next'));
      await tester.pumpAndSettle();

      expect(find.text('Second Screen'), findsOneWidget);
    });
  });

  group('EmptyStateView Tests', () {
    testWidgets('EmptyStateView renders title and subtitle properly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateView(
              title: 'No Customers Found',
              subtitle: 'Add your first customer to get started.',
              icon: Icons.people_outline_rounded,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Customers Found'), findsOneWidget);
      expect(find.text('Add your first customer to get started.'), findsOneWidget);
      expect(find.byIcon(Icons.people_outline_rounded), findsOneWidget);
    });

    testWidgets('EmptyStateView renders action button if provided', (WidgetTester tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateView(
              title: 'No Transactions',
              subtitle: 'Start recording credit and debit entries.',
              actionLabel: '+ Add Entry',
              onActionPressed: () => pressed = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('+ Add Entry'), findsOneWidget);
      await tester.tap(find.text('+ Add Entry'));
      expect(pressed, isTrue);
    });
  });

  group('AdaptiveButton Micro-Interactions Tests', () {
    testWidgets('AdaptiveButton renders and supports tap action with spring animation wrapper', (WidgetTester tester) async {
      bool clicked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveButton(
              onPressed: () => clicked = true,
              child: const Text('Save'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsOneWidget);
      expect(find.byType(AnimatedScale), findsOneWidget);

      await tester.tap(find.text('Save'));
      expect(clicked, isTrue);
    });
  });
}
