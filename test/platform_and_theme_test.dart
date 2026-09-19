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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';
import 'package:ledger_pulse/presentation/home/add_party_dialog.dart';
import 'package:ledger_pulse/presentation/ledger/add_entry_bottom_sheet.dart';
import 'package:ledger_pulse/data/mock/mock_ledger_repository.dart';
import 'package:ledger_pulse/presentation/home/party_list_tab.dart';
import 'package:ledger_pulse/presentation/ledger/party_ledger_screen.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
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
      expect(theme.cardTheme.color, equals(theme.colorScheme.surfaceContainer));
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

  group('Draggable Modal Sheets & PopScope Navigation Tests', () {
    testWidgets('AddPartyDialog renders DraggableScrollableSheet and PopScope with clean state', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: Colors.transparent,
                      barrierColor: Colors.black54,
                      builder: (context) => const AddPartyDialog(
                        initialType: PartyType.customer,
                      ),
                    );
                  },
                  child: const Text('Open Add Party'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Add Party'));
      await tester.pumpAndSettle();

      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is PopScope), findsWidgets);
      expect(find.text('Add New Customer'), findsOneWidget);
      expect(find.byIcon(Icons.contacts_rounded), findsOneWidget);

      // Verify DraggableScrollableSheet configuration
      final sheet = tester.widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet));
      expect(sheet.initialChildSize, equals(0.42));
      expect(sheet.minChildSize, equals(0.25));
      expect(sheet.maxChildSize, equals(0.88));
      expect(sheet.shouldCloseOnMinExtent, isTrue);
      expect(sheet.snap, isTrue);
      expect(sheet.expand, isFalse);

      // Close cleanly when inputs are empty via back navigation / maybePop
      final dynamic navState = tester.state(find.byType(Navigator));
      navState.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('Add New Customer'), findsNothing);
    });

    testWidgets('AddPartyDialog prompts discard confirmation when inputs are dirty', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: Colors.transparent,
                      barrierColor: Colors.black.withValues(alpha: 0.3),
                      builder: (context) => const AddPartyDialog(
                        initialType: PartyType.customer,
                      ),
                    );
                  },
                  child: const Text('Open Add Party'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Add Party'));
      await tester.pumpAndSettle();

      // Enter name so form becomes dirty
      await tester.enterText(find.byType(TextField).first, 'John Doe');
      await tester.pumpAndSettle();

      // Trigger back navigation -> should trigger discard confirmation dialog
      final dynamic navState = tester.state(find.byType(Navigator));
      navState.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      expect(find.text('Keep Editing'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);

      // Tap Keep Editing -> dialog dismisses, sheet remains open
      await tester.tap(find.text('Keep Editing'));
      await tester.pumpAndSettle();

      expect(find.text('Discard unsaved changes?'), findsNothing);
      expect(find.text('Add New Customer'), findsOneWidget);

      // Trigger back navigation again and choose Discard
      navState.maybePop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.text('Add New Customer'), findsNothing);
    });

    testWidgets('AddEntryBottomSheet renders DraggableScrollableSheet and PopScope', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: Colors.transparent,
                      barrierColor: Colors.black.withValues(alpha: 0.3),
                      builder: (context) => const AddEntryBottomSheet(
                        partyId: 'p1',
                        partyName: 'Alice',
                        initialType: EntryType.gave,
                      ),
                    );
                  },
                  child: const Text('Open Add Entry'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Add Entry'));
      await tester.pumpAndSettle();

      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is PopScope), findsWidgets);
      expect(find.text('YOU GAVE'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);

      final sheet = tester.widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet));
      expect(sheet.initialChildSize, equals(0.55));
      expect(sheet.minChildSize, equals(0.25));
      expect(sheet.maxChildSize, equals(0.95));
      expect(sheet.shouldCloseOnMinExtent, isTrue);
      expect(sheet.snap, isTrue);
      expect(sheet.expand, isFalse);

      // Close cleanly when clean
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsNothing);
    });

    testWidgets('AddEntryBottomSheet prompts discard confirmation when amount entered', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: Colors.transparent,
                      barrierColor: Colors.black.withValues(alpha: 0.3),
                      builder: (context) => const AddEntryBottomSheet(
                        partyId: 'p1',
                        partyName: 'Alice',
                        initialType: EntryType.gave,
                      ),
                    );
                  },
                  child: const Text('Open Add Entry'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Add Entry'));
      await tester.pumpAndSettle();

      // Tap preset chip +₹500 to dirty the form
      await tester.tap(find.text('+₹500'));
      await tester.pumpAndSettle();

      // Tap close -> confirmation dialog appears
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Discard unsaved changes?'), findsOneWidget);

      // Tap Discard
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsNothing);
    });
  });

  group('Native Material 3 Expressive Component Tests on Android', () {
    testWidgets('PartyListTab renders M3 SearchBar and squircle avatars on Android', (WidgetTester tester) async {
      final repo = MockLedgerRepository();
      addTearDown(repo.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ledgerRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: AndroidTheme.getTheme(),
            home: const Scaffold(
              body: PartyListTab(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. M3 SearchBar is present with elevation 0 and leading search icon
      expect(find.byType(SearchBar), findsOneWidget);
      final searchBar = tester.widget<SearchBar>(find.byType(SearchBar));
      expect(searchBar.elevation?.resolve({}), equals(0));
      expect(searchBar.leading, isA<Icon>());

      // 2. Squircle avatars (Container with rounded rect decoration, not CircleAvatar)
      expect(find.byType(CircleAvatar), findsNothing);
      expect(find.text('RS'), findsOneWidget); // Rahul Sharma initials
    });

    testWidgets('AddEntryBottomSheet renders FilledButton.tonal keypad and ActionChips on Android', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AndroidTheme.getTheme(),
            home: const Scaffold(
              body: AddEntryBottomSheet(
                partyId: 'p1',
                partyName: 'Alice',
                initialType: EntryType.gave,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Keypad buttons (12) + 1 Submit AdaptiveButton = 13 FilledButtons
      expect(find.byType(FilledButton), findsNWidgets(13));

      // Preset chips must be ActionChip
      expect(find.byType(ActionChip), findsNWidgets(4)); // +₹100, +₹500, +₹1000, +₹5000
    });

    testWidgets('AddPartyDialog standardizes input fields with M3 OutlineInputBorder', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AndroidTheme.getTheme(),
            home: const Scaffold(
              body: AddPartyDialog(
                initialType: PartyType.customer,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final textFields = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(textFields.length, equals(2));

      for (final tf in textFields) {
        final decoration = tf.decoration;
        expect(decoration?.filled, isTrue);
        expect(decoration?.border, isA<OutlineInputBorder>());
        expect(decoration?.enabledBorder, isA<OutlineInputBorder>());
        expect(decoration?.focusedBorder, isA<OutlineInputBorder>());

        final border = decoration?.border as OutlineInputBorder;
        expect(border.borderRadius, equals(BorderRadius.circular(16)));
      }
    });

    testWidgets('PartyLedgerScreen renders M3 Squircle avatar on Android', (WidgetTester tester) async {
      final repo = MockLedgerRepository();
      addTearDown(repo.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ledgerRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: AndroidTheme.getTheme(),
            home: const Scaffold(
              body: PartyLedgerScreen(partyId: 'party_1'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('RS'), findsOneWidget); // Rahul Sharma squircle avatar initials
    });
  });
}

