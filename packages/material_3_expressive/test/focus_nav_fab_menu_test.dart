import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import 'focus_nav_repro_test_support.dart';

void main() {
  setUp(setUpFocusNavReproTests);
  tearDown(tearDownFocusNavReproTests);

  registerFabMenuTabVisitsEveryItemTests();
  registerFabMenuEscapeClosesOpenMenuTests();
  registerFabEnterActivatesWhenFocusedTests();
}

void registerFabMenuTabVisitsEveryItemTests() {
  testWidgets('FAB menu Tab visits every item (not FocusScope oscillation)', (
    WidgetTester tester,
  ) async {
    const labels = <String>['Image', 'Video', 'Audio', 'Document'];
    await pumpFabMenuApp(tester, labels: labels);

    await tester.tap(find.byType(M3EFab));
    await tester.pumpAndSettle();
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }

    final FocusScopeNode menuScope = findFabMenuScope()!;
    final Set<FocusNode> itemNodes = menuScope.traversalDescendants
        .where((FocusNode n) => n.canRequestFocus && !n.skipTraversal)
        .toSet();
    expect(itemNodes, hasLength(labels.length));

    // Opening moves focus into the menu (scope skips parent Tab traversal).
    expect(
      itemNodes.contains(FocusManager.instance.primaryFocus),
      isTrue,
      reason: 'Open should focus a menu item, not the trigger FAB',
    );

    final visited = <FocusNode>{FocusManager.instance.primaryFocus!};
    for (var i = 0; i < labels.length + 1; i++) {
      await pumpFocusNavTab(tester);
      final FocusNode? primary = FocusManager.instance.primaryFocus;
      expect(
        primary?.debugLabel,
        isNot('M3EFabMenu'),
        reason: 'FocusScope must skipTraversal so Tab walks items',
      );
      expect(
        itemNodes.contains(primary),
        isTrue,
        reason: 'Tab should stay on menu item nodes, got $primary',
      );
      visited.add(primary!);
    }

    expect(
      visited,
      unorderedEquals(itemNodes),
      reason: 'Tab must reach every FAB menu item node',
    );
  });
}

void registerFabMenuEscapeClosesOpenMenuTests() {
  testWidgets('FAB menu Escape closes open menu', (WidgetTester tester) async {
    await pumpFabMenuApp(tester, labels: const <String>['Image', 'Video']);

    await tester.tap(find.byType(M3EFab));
    await tester.pumpAndSettle();
    expect(find.text('Image'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);

    expect(find.text('Image'), findsNothing);
  });
}

void registerFabEnterActivatesWhenFocusedTests() {
  testWidgets('FAB Enter activates when focused', (WidgetTester tester) async {
    var pressed = 0;
    final focusNode = FocusNode(debugLabel: 'fab');
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: M3ETheme(
          data: M3EThemeData.light(),
          child: Scaffold(
            floatingActionButton: M3EFab(
              focusNode: focusNode,
              icon: const Icon(Icons.add),
              onPressed: () => pressed++,
            ),
          ),
        ),
      ),
    );

    M3EFocusInteraction.instance.noteKeyboardHighlight();
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(focusNode.hasPrimaryFocus, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 48));

    // Press scale should be running (same path as pointer press).
    final transforms = tester.widgetList<Transform>(
      find.descendant(
        of: find.byType(M3EFab),
        matching: find.byType(Transform),
      ),
    );
    final bool scaled = transforms.any((Transform t) {
      final double scale = t.transform.storage[0];
      return (scale - 1.0).abs() > 0.001;
    });
    expect(scaled, isTrue, reason: 'Enter should play FAB press scale');

    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(pressed, 1);
  });
}
