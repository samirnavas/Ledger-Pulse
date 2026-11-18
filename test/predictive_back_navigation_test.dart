import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/theme/android_theme.dart';
import 'package:ledger_pulse/core/utils/adaptive_page_route.dart';

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> sendBackGestureStart({
    required double touchX,
    required double touchY,
    required int swipeEdge, // 0 = left, 1 = right
  }) async {
    final ByteData message = const StandardMethodCodec().encodeMethodCall(
      MethodCall('startBackGesture', <String, dynamic>{
        'touchOffset': <double>[touchX, touchY],
        'progress': 0.0,
        'swipeEdge': swipeEdge,
      }),
    );
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/backgesture',
      message,
      (ByteData? _) {},
    );
  }

  Future<void> sendBackGestureUpdate({
    required double x,
    required double y,
    required double progress,
    required int swipeEdge,
  }) async {
    final ByteData message = const StandardMethodCodec().encodeMethodCall(
      MethodCall('updateBackGestureProgress', <String, dynamic>{
        'touchOffset': <double>[x, y],
        'progress': progress,
        'swipeEdge': swipeEdge,
      }),
    );
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/backgesture',
      message,
      (ByteData? _) {},
    );
  }

  Future<void> sendBackGestureCommit() async {
    final ByteData message = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('commitBackGesture'),
    );
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/backgesture',
      message,
      (ByteData? _) {},
    );
  }

  Future<void> sendBackGestureCancel() async {
    final ByteData message = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('cancelBackGesture'),
    );
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/backgesture',
      message,
      (ByteData? _) {},
    );
  }

  group('Android Native Predictive Back Navigation Tests', () {
    for (final brightness in Brightness.values) {
      for (final fadeThrough in [false, true]) {
        testWidgets('interactive progress, cancellation and commit: $brightness, fade=$fadeThrough', (tester) async {
          late PageRoute<void> route;
          await tester.pumpWidget(MaterialApp(
            theme: AndroidTheme.getTheme(brightness: brightness),
            home: Builder(builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  route = createAdaptivePageRoute<void>(
                    useFadeThrough: fadeThrough,
                    settings: const RouteSettings(name: '/detail', arguments: 'kept'),
                    builder: (_) => const Scaffold(body: Text('Gesture destination')),
                  ) as PageRoute<void>;
                  Navigator.of(context).push(route);
                },
                child: const Text('Open gesture destination'),
              ),
            )),
          ));
          await tester.tap(find.text('Open gesture destination'));
          await tester.pumpAndSettle();
          expect(route.settings.arguments, 'kept');
          expect(route.popGestureEnabled, isTrue);
          await sendBackGestureStart(touchX: 5, touchY: 300, swipeEdge: 0);
          await tester.pump();
          expect(route.popGestureInProgress, isTrue);
          await sendBackGestureUpdate(x: 160, y: 300, progress: 0.4, swipeEdge: 0);
          await tester.pump();
          expect(route.animation!.value, closeTo(0.6, 0.001));
          await sendBackGestureCancel();
          await tester.pumpAndSettle();
          expect(route.isCurrent, isTrue);
          expect(route.animation!.value, 1);
          expect(route.popGestureInProgress, isFalse);
          await sendBackGestureStart(touchX: 795, touchY: 300, swipeEdge: 1);
          await tester.pump();
          await sendBackGestureUpdate(x: 500, y: 300, progress: 0.6, swipeEdge: 1);
          await tester.pump();
          expect(route.animation!.value, closeTo(0.4, 0.001));
          await sendBackGestureCommit();
          await tester.pumpAndSettle();
          expect(find.text('Gesture destination'), findsNothing);
          expect(find.text('Open gesture destination'), findsOneWidget);
        });
      }
    }

    testWidgets('Predictive back - slow back gesture commits pop and reveals previous route', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AndroidTheme.lightTheme,
          home: Scaffold(
            appBar: AppBar(title: const Text('Origin Screen')),
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    createAdaptivePageRoute(
                      builder: (ctx) => Scaffold(
                        appBar: AppBar(title: const Text('Detail Screen')),
                        body: const Text('Detail Content'),
                      ),
                    ),
                  );
                },
                child: const Text('Open Detail'),
              ),
            ),
          ),
        ),
      );

      // Verify on origin screen
      expect(find.text('Origin Screen'), findsOneWidget);
      await tester.tap(find.text('Open Detail'));
      await tester.pumpAndSettle();

      // Verify on detail screen
      expect(find.text('Detail Screen'), findsOneWidget);
      expect(find.text('Detail Content'), findsOneWidget);

      // Simulate left edge gesture start (swipeEdge: 0)
      await sendBackGestureStart(touchX: 5.0, touchY: 300.0, swipeEdge: 0);
      await tester.pump();

      // Detail screen still visible during gesture
      expect(find.text('Detail Content'), findsOneWidget);

      // Slowly drag across
      for (double p = 0.1; p <= 0.6; p += 0.1) {
        await sendBackGestureUpdate(
          x: 20.0 + (p * 200.0),
          y: 300.0,
          progress: p,
          swipeEdge: 0,
        );
        await tester.pump();
      }

      // Commit gesture
      await sendBackGestureCommit();
      await tester.pumpAndSettle();

      // Route popped back to Origin Screen
      expect(find.text('Origin Screen'), findsOneWidget);
      expect(find.text('Detail Screen'), findsNothing);
      expect(find.text('Detail Content'), findsNothing);
    });

    testWidgets('Predictive back - gesture cancellation smoothly restores current screen', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AndroidTheme.lightTheme,
          home: Scaffold(
            appBar: AppBar(title: const Text('Origin Screen')),
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    createAdaptivePageRoute(
                      builder: (ctx) => Scaffold(
                        appBar: AppBar(title: const Text('Detail Screen')),
                        body: const Text('Active Screen Content'),
                      ),
                    ),
                  );
                },
                child: const Text('Open Detail'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Detail'));
      await tester.pumpAndSettle();

      expect(find.text('Detail Screen'), findsOneWidget);

      // Start gesture
      await sendBackGestureStart(touchX: 5.0, touchY: 300.0, swipeEdge: 0);
      await tester.pump();

      // Drag partially
      await sendBackGestureUpdate(x: 50.0, y: 300.0, progress: 0.25, swipeEdge: 0);
      await tester.pump();

      // User reverses drag and cancels
      await sendBackGestureCancel();
      await tester.pumpAndSettle();

      // Screen remains un-popped and fully restored
      expect(find.text('Detail Screen'), findsOneWidget);
      expect(find.text('Active Screen Content'), findsOneWidget);
    });

    testWidgets('Predictive back - right edge gesture works identically', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AndroidTheme.lightTheme,
          home: Scaffold(
            appBar: AppBar(title: const Text('Origin Screen')),
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    createAdaptivePageRoute(
                      builder: (ctx) => Scaffold(
                        appBar: AppBar(title: const Text('Right Swipe Detail')),
                        body: const Text('Right Edge Content'),
                      ),
                    ),
                  );
                },
                child: const Text('Open Detail'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Detail'));
      await tester.pumpAndSettle();

      expect(find.text('Right Swipe Detail'), findsOneWidget);

      // Start gesture from right edge (swipeEdge: 1)
      await sendBackGestureStart(touchX: 395.0, touchY: 300.0, swipeEdge: 1);
      await tester.pump();

      // Drag from right to left
      await sendBackGestureUpdate(x: 250.0, y: 300.0, progress: 0.5, swipeEdge: 1);
      await tester.pump();

      // Commit
      await sendBackGestureCommit();
      await tester.pumpAndSettle();

      expect(find.text('Origin Screen'), findsOneWidget);
      expect(find.text('Right Swipe Detail'), findsNothing);
    });

    testWidgets('App-bar back button and 3-button navigation pop smoothly without gesture tracking', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AndroidTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    createAdaptivePageRoute(
                      builder: (ctx) => Scaffold(
                        appBar: AppBar(
                          title: const Text('Nested Screen'),
                          leading: const BackButton(),
                        ),
                        body: const Text('Nested Body'),
                      ),
                    ),
                  );
                },
                child: const Text('Go Nested'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go Nested'));
      await tester.pumpAndSettle();

      expect(find.text('Nested Screen'), findsOneWidget);

      // Tap AppBar back button (simulating 3-button or app-bar back)
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Go Nested'), findsOneWidget);
      expect(find.text('Nested Screen'), findsNothing);
    });

    testWidgets('PopScope prevents predictive pop when form is dirty / canPop is false', (WidgetTester tester) async {
      bool canPopForm = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AndroidTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    createAdaptivePageRoute(
                      builder: (ctx) => PopScope(
                        canPop: canPopForm,
                        child: const Scaffold(
                          body: Text('Protected Form Screen'),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open Form'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Form'));
      await tester.pumpAndSettle();

      expect(find.text('Protected Form Screen'), findsOneWidget);

      // Route's popGestureEnabled must be false because canPop is false
      final ModalRoute<dynamic>? modalRoute = ModalRoute.of(tester.element(find.text('Protected Form Screen')));
      expect(modalRoute?.popGestureEnabled, isFalse);

      // Attempt gesture
      await sendBackGestureStart(touchX: 5.0, touchY: 300.0, swipeEdge: 0);
      await tester.pump();
      await sendBackGestureCommit();
      await tester.pumpAndSettle();

      // Form remains open and protected!
      expect(find.text('Protected Form Screen'), findsOneWidget);
    });

    testWidgets('Predictive back preserves scroll position and state on previous destination', (WidgetTester tester) async {
      final ScrollController scrollController = ScrollController();

      await tester.pumpWidget(
        MaterialApp(
          theme: AndroidTheme.lightTheme,
          home: Scaffold(
            body: ListView.builder(
              controller: scrollController,
              itemCount: 50,
              itemBuilder: (context, index) {
                if (index == 5) {
                  return ElevatedButton(
                    key: const Key('item_5_button'),
                    onPressed: () {
                      Navigator.of(context).push(
                        createAdaptivePageRoute(
                          builder: (ctx) => const Scaffold(
                            body: Text('Transaction 5 Details'),
                          ),
                        ),
                      );
                    },
                    child: const Text('Item 5'),
                  );
                }
                return SizedBox(
                  height: 60,
                  child: ListTile(title: Text('List Item $index')),
                );
              },
            ),
          ),
        ),
      );

      // Scroll down
      scrollController.jumpTo(120.0);
      await tester.pumpAndSettle();
      final double scrolledOffset = scrollController.offset;
      expect(scrolledOffset, equals(120.0));

      // Push details
      await tester.tap(find.byKey(const Key('item_5_button')));
      await tester.pumpAndSettle();
      expect(find.text('Transaction 5 Details'), findsOneWidget);

      // Pop via predictive gesture
      await sendBackGestureStart(touchX: 5.0, touchY: 300.0, swipeEdge: 0);
      await tester.pump();
      await sendBackGestureUpdate(x: 150.0, y: 300.0, progress: 0.5, swipeEdge: 0);
      await tester.pump();
      await sendBackGestureCommit();
      await tester.pumpAndSettle();

      // Details popped, scroll position perfectly preserved
      expect(find.text('Transaction 5 Details'), findsNothing);
      expect(scrollController.offset, equals(scrolledOffset));
    });

    testWidgets('Nested navigation pops only the top-most route during back gesture', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AndroidTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    createAdaptivePageRoute(
                      builder: (ctx) => Scaffold(
                        body: Builder(
                          builder: (nestedCtx) => ElevatedButton(
                            onPressed: () {
                              Navigator.of(nestedCtx).push(
                                createAdaptivePageRoute(
                                  builder: (_) => const Scaffold(body: Text('Level 3 Screen')),
                                ),
                              );
                            },
                            child: const Text('To Level 3'),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('To Level 2'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('To Level 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('To Level 3'));
      await tester.pumpAndSettle();

      expect(find.text('Level 3 Screen'), findsOneWidget);

      // Predictive back from Level 3
      await sendBackGestureStart(touchX: 5.0, touchY: 300.0, swipeEdge: 0);
      await tester.pump();
      await sendBackGestureUpdate(x: 150.0, y: 300.0, progress: 0.5, swipeEdge: 0);
      await tester.pump();
      await sendBackGestureCommit();
      await tester.pumpAndSettle();

      // Only Level 3 popped, Level 2 is visible
      expect(find.text('Level 3 Screen'), findsNothing);
      expect(find.text('To Level 3'), findsOneWidget);
    });

    test('Light and Dark Android themes both configure PredictiveBackPageTransitionsBuilder', () {
      final lightTheme = AndroidTheme.getLight();
      final darkTheme = AndroidTheme.getDark();

      expect(
        lightTheme.pageTransitionsTheme.builders[TargetPlatform.android],
        isA<PredictiveBackPageTransitionsBuilder>(),
      );
      expect(
        darkTheme.pageTransitionsTheme.builders[TargetPlatform.android],
        isA<PredictiveBackPageTransitionsBuilder>(),
      );
    });

    testWidgets('iOS Cupertino navigation regression check', (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      try {
        final route = createAdaptivePageRoute<void>(
          useFadeThrough: true,
          builder: (_) => const CupertinoPageScaffold(
            navigationBar: CupertinoNavigationBar(middle: Text('iOS Destination')),
            child: SafeArea(child: Center(child: Text('iOS Body'))),
          ),
        );

        // Verify route is CupertinoPageRoute on iOS
        expect(route, isA<CupertinoPageRoute<void>>());

        await tester.pumpWidget(
          CupertinoApp(
            home: CupertinoPageScaffold(
              navigationBar: const CupertinoNavigationBar(middle: Text('iOS Root')),
              child: SafeArea(
                child: Center(
                  child: Builder(
                    builder: (context) => CupertinoButton(
                      onPressed: () => Navigator.of(context).push(route),
                      child: const Text('Push iOS Route'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text('Push iOS Route'), findsOneWidget);
        await tester.tap(find.text('Push iOS Route'));
        await tester.pumpAndSettle();

        expect(find.text('iOS Destination'), findsOneWidget);
        expect(find.text('iOS Body'), findsOneWidget);

        // Native iOS interactive edge-swipe back test (drag across screen past dismiss threshold)
        final TestGesture gesture = await tester.startGesture(const Offset(5.0, 300.0));
        await tester.pump();
        await gesture.moveBy(const Offset(500.0, 0.0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.text('iOS Destination'), findsNothing);
        expect(find.text('Push iOS Route'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
