import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import 'focus_nav_repro_test_support.dart';

void main() {
  setUp(setUpFocusNavReproTests);
  tearDown(tearDownFocusNavReproTests);

  registerDropdownChipAndClearTabStopsTests();
  registerEnterOnDropdownClearTests();
  registerEnterOnDropdownChipTests();
}

void registerDropdownChipAndClearTabStopsTests() {
  testWidgets('Dropdown chip and clear are Tab stops with rings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: M3ETheme(
          data: M3EThemeData.light(),
          child: Scaffold(
            body: M3EDropdownMenu<String>(
              items: const <M3EDropdownItem<String>>[
                M3EDropdownItem(value: 'one', label: 'One', selected: true),
                M3EDropdownItem(value: 'two', label: 'Two', selected: true),
              ],
              fieldStyle: const M3EDropdownFieldStyle(showClearIcon: true),
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    M3EFocusInteraction.instance.noteKeyboardHighlight();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);

    var ringStops = 0;
    for (var i = 0; i < 6; i++) {
      final FocusNode? primary = FocusManager.instance.primaryFocus;
      if (primary != null &&
          primary.canRequestFocus &&
          M3EFocusRing.shouldShow(primary)) {
        ringStops++;
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
    }

    expect(
      ringStops,
      greaterThanOrEqualTo(2),
      reason: 'Expected multiple field/chip/clear ring stops, got $ringStops',
    );
    expect(find.text('One'), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsOneWidget);
  });
}

void registerEnterOnDropdownClearTests() {
  testWidgets('Enter on dropdown clear removes all selections', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: M3ETheme(
          data: M3EThemeData.light(),
          child: Scaffold(
            body: M3EDropdownMenu<String>(
              items: const <M3EDropdownItem<String>>[
                M3EDropdownItem(value: 'one', label: 'One', selected: true),
                M3EDropdownItem(value: 'two', label: 'Two', selected: true),
              ],
              fieldStyle: const M3EDropdownFieldStyle(showClearIcon: true),
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('One'), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsOneWidget);

    M3EFocusInteraction.instance.noteKeyboardHighlight();

    var foundClear = false;
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      final Element iconEl = find.byIcon(Icons.clear).evaluate().first;
      final FocusableActionDetector? detector = iconEl
          .findAncestorWidgetOfExactType<FocusableActionDetector>();
      final FocusNode? node = detector?.focusNode;
      if (node != null && node.hasPrimaryFocus) {
        foundClear = true;
        break;
      }
    }
    expect(foundClear, isTrue, reason: 'Tab should reach the clear control');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);

    expect(find.text('One'), findsNothing);
    expect(find.byIcon(Icons.clear), findsNothing);
  });
}

void registerEnterOnDropdownChipTests() {
  testWidgets('Enter on dropdown chip removes that selection', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: M3ETheme(
          data: M3EThemeData.light(),
          child: Scaffold(
            body: M3EDropdownMenu<String>(
              items: const <M3EDropdownItem<String>>[
                M3EDropdownItem(value: 'one', label: 'One', selected: true),
                M3EDropdownItem(value: 'two', label: 'Two', selected: true),
              ],
              fieldStyle: const M3EDropdownFieldStyle(showClearIcon: true),
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    M3EFocusInteraction.instance.noteKeyboardHighlight();

    var foundChip = false;
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      final Element chipText = find.text('One').evaluate().first;
      final FocusableActionDetector? detector = chipText
          .findAncestorWidgetOfExactType<FocusableActionDetector>();
      final FocusNode? node = detector?.focusNode;
      if (node != null && node.hasPrimaryFocus) {
        foundChip = true;
        break;
      }
    }
    expect(foundChip, isTrue, reason: 'Tab should reach the One chip');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);

    expect(find.text('One'), findsNothing);
    expect(find.text('Two'), findsOneWidget);
  });
}
