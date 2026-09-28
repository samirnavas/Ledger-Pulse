import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/theme/android_theme.dart';
import 'package:ledger_pulse/core/utils/adaptive_page_route.dart';
import 'package:ledger_pulse/core/widgets/draggable_modal_sheet.dart';
import 'package:ledger_pulse/presentation/reports/pdf_export_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Predictive Back & AdaptivePageRoute Tests', () {
    test('AdaptivePageRoute extends MaterialPageRoute and supports predictive back', () {
      final route = createAdaptivePageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Target Page')),
      );

      // Verify route is a MaterialPageRoute (which incorporates MaterialRouteTransitionMixin)
      expect(route, isA<MaterialPageRoute<void>>());
      expect(route, isA<AdaptivePageRoute<void>>());
    });

    test('createAdaptivePageRoute with useFadeThrough returns PageRouteBuilder', () {
      final route = createAdaptivePageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Splash Target')),
        useFadeThrough: true,
      );

      expect(route, isA<PageRouteBuilder<void>>());
    });

    testWidgets('ForegroundPageShadowTransition applies elevation drop shadow when animation is active', (tester) async {
      final animationController = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 300),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AndroidTheme.lightTheme,
          home: Scaffold(
            body: ForegroundPageShadowTransition(
              animation: animationController,
              child: const Text('Foreground Page Content'),
            ),
          ),
        ),
      );

      expect(find.text('Foreground Page Content'), findsOneWidget);

      // Animate controller to simulate route entry / active transition / predictive back
      animationController.value = 0.8;
      await tester.pump();

      // Find DecoratedBox with drop shadows
      final decoratedBoxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
      final shadowBox = decoratedBoxes.firstWhere(
        (box) => box.decoration is BoxDecoration && (box.decoration as BoxDecoration).boxShadow != null && (box.decoration as BoxDecoration).boxShadow!.isNotEmpty,
      );

      final boxDec = shadowBox.decoration as BoxDecoration;
      expect(boxDec.boxShadow, isNotNull);
      expect(boxDec.boxShadow!.length, greaterThanOrEqualTo(2));
      expect(boxDec.boxShadow!.first.blurRadius, greaterThan(0));

      animationController.dispose();
    });

    testWidgets('BackgroundExposureTransition reduces background page exposure when secondaryAnimation is active', (tester) async {
      final secondaryController = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 300),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AndroidTheme.lightTheme,
          home: Scaffold(
            body: BackgroundExposureTransition(
              secondaryAnimation: secondaryController,
              child: const Text('Background Content'),
            ),
          ),
        ),
      );

      expect(find.text('Background Content'), findsOneWidget);
      // At 0.0, no dark scrim overlay is active
      Finder scrimFinder() => find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color.a > 0 && widget.color.r == 0 && widget.color.g == 0 && widget.color.b == 0,
      );

      expect(scrimFinder(), findsNothing);

      // Animate secondary to simulate a foreground route pushing or predictive back preview
      secondaryController.value = 0.5;
      await tester.pump();

      // Now a dark ColoredBox scrim is present to decrease exposure
      expect(scrimFinder(), findsOneWidget);
      final coloredBox = tester.widget<ColoredBox>(scrimFinder());
      expect(coloredBox.color.a, greaterThan(0));

      secondaryController.dispose();
    });

    testWidgets('AdaptivePageRoute delegates to PredictiveBackPageTransitionsBuilder on Android', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AndroidTheme.lightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    createAdaptivePageRoute(
                      builder: (_) => const Scaffold(body: Text('Page 2')),
                    ),
                  );
                },
                child: const Text('Go to Page 2'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Go to Page 2'), findsOneWidget);
      await tester.tap(find.text('Go to Page 2'));
      await tester.pumpAndSettle();

      expect(find.text('Page 2'), findsOneWidget);

      // Verify back navigation works cleanly
      Navigator.of(tester.element(find.text('Page 2'))).pop();
      await tester.pumpAndSettle();

      expect(find.text('Go to Page 2'), findsOneWidget);
      expect(find.text('Page 2'), findsNothing);
    });
  });

  group('Draggable Modal Sheet Tests', () {
    testWidgets('DraggableModalSheet renders with ModalDragHandle, snapping, and dismiss extent', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AndroidTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAdaptiveDraggableModal(
                    context: context,
                    initialChildSize: 0.6,
                    minChildSize: 0.25,
                    maxChildSize: 0.95,
                    snapSizes: const [0.6, 0.95],
                    builder: (context, scrollController) {
                      return ListView(
                        controller: scrollController,
                        children: const [
                          ListTile(title: Text('Modal Item 1')),
                          ListTile(title: Text('Modal Item 2')),
                        ],
                      );
                    },
                  );
                },
                child: const Text('Open Draggable Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Draggable Modal'));
      await tester.pumpAndSettle();

      expect(find.byType(DraggableModalSheet), findsOneWidget);
      expect(find.byType(ModalDragHandle), findsOneWidget);
      expect(find.text('Modal Item 1'), findsOneWidget);

      final sheet = tester.widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet));
      expect(sheet.initialChildSize, equals(0.6));
      expect(sheet.minChildSize, equals(0.25));
      expect(sheet.maxChildSize, equals(0.95));
      expect(sheet.snap, isTrue);
      expect(sheet.shouldCloseOnMinExtent, isTrue);
      expect(sheet.expand, isFalse);

      // Tap drag handle for haptic feedback
      await tester.tap(find.byType(ModalDragHandle));
      await tester.pump();

      // Dismiss modal cleanly via Navigator pop
      Navigator.of(tester.element(find.text('Modal Item 1'))).pop();
      await tester.pumpAndSettle();

      expect(find.byType(DraggableModalSheet), findsNothing);
    });

    testWidgets('PdfExportModal renders inside a DraggableScrollableSheet with ModalDragHandle', (tester) async {
      final tempFile = File('${Directory.systemTemp.path}/test_statement.pdf');
      if (!tempFile.existsSync()) {
        tempFile.writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: AndroidTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PdfExportModal.show(
                    context: context,
                    pdfBytes: Uint8List.fromList([1, 2, 3]),
                    file: tempFile,
                    fileName: 'test_statement.pdf',
                    partyName: 'Bob Builder',
                    periodLabel: 'All Time',
                  );
                },
                child: const Text('Show PDF Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show PDF Modal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(PdfExportModal), findsOneWidget);
      expect(find.byType(ModalDragHandle), findsOneWidget);
      expect(find.text('Account Statement PDF'), findsOneWidget);

      final sheet = tester.widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet));
      expect(sheet.initialChildSize, equals(0.85));
      expect(sheet.minChildSize, equals(0.35));
      expect(sheet.maxChildSize, equals(0.95));
      expect(sheet.snap, isTrue);
      expect(sheet.shouldCloseOnMinExtent, isTrue);

      // Close modal
      Navigator.of(tester.element(find.text('Account Statement PDF'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(PdfExportModal), findsNothing);
    });
  });
}
