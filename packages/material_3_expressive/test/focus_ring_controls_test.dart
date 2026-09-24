import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import 'focus_ring_test_support.dart';

void main() {
  setUp(setUpFocusRingTests);
  tearDown(tearDownFocusRingTests);

  registerFocusRingDropdownEnterToggleTests();
  registerFocusRingDropdownTabTrapTests();
  registerFocusRingSearchBarKeyboardRingTests();
  registerFocusRingTabLeavesTextFieldTests();
  registerFocusRingTextFieldTypingWithRingTests();
  registerFocusRingTabReachesSearchBarTests();
}

void registerFocusRingDropdownEnterToggleTests() {
  testWidgets('dropdown Enter toggles when field focused', (
    WidgetTester tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: M3ETheme(
          data: M3EThemeData.light(),
          child: Scaffold(
            body: M3EDropdownMenu<String>(
              focusNode: focusNode,
              singleSelect: true,
              items: const <M3EDropdownItem<String>>[
                M3EDropdownItem(value: 'one', label: 'One'),
                M3EDropdownItem(value: 'two', label: 'Two'),
              ],
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    M3EFocusInteraction.instance.noteKeyboardHighlight();
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(focusNode.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('One'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });
}

void registerFocusRingDropdownTabTrapTests() {
  testWidgets('dropdown trap keeps Tab among field and panel', (
    WidgetTester tester,
  ) async {
    final outside = FocusNode(debugLabel: 'outside');
    addTearDown(outside.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: M3ETheme(
          data: M3EThemeData.light(),
          child: Scaffold(
            body: Column(
              children: <Widget>[
                M3EDropdownMenu<String>(
                  items: const <M3EDropdownItem<String>>[
                    M3EDropdownItem(value: 'one', label: 'One'),
                    M3EDropdownItem(value: 'two', label: 'Two'),
                  ],
                  onSelectionChanged: (_) {},
                ),
                M3EButton.filled(
                  focusNode: outside,
                  onPressed: () {},
                  child: const Text('Outside'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(M3EDropdownMenu<String>));
    await tester.pumpAndSettle();
    expect(find.text('One'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(outside.hasPrimaryFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });
}

void registerFocusRingSearchBarKeyboardRingTests() {
  testWidgets('search bar shows ring under keyboard modality', (
    WidgetTester tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: M3ETheme(
          data: M3EThemeData.light(),
          child: Scaffold(
            body: M3ESearchBar(focusNode: focusNode, hintText: 'Search'),
          ),
        ),
      ),
    );

    M3EFocusInteraction.instance.noteKeyboardHighlight();
    focusNode.requestFocus();
    await tester.pumpAndSettle();

    expect(focusNode.hasPrimaryFocus, isTrue);
    expect(M3EFocusRing.shouldShow(focusNode), isTrue);
    final rings = tester.widgetList<M3EFocusRing>(find.byType(M3EFocusRing));
    expect(rings.any((M3EFocusRing r) => r.focused), isTrue);
  });
}

void registerFocusRingTabLeavesTextFieldTests() {
  testWidgets('Tab leaves text field and clears its ring', (
    WidgetTester tester,
  ) async {
    final field = FocusNode(debugLabel: 'field');
    final next = FocusNode(debugLabel: 'next');
    addTearDown(field.dispose);
    addTearDown(next.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: M3ETheme(
          data: M3EThemeData.light(),
          child: Scaffold(
            body: Column(
              children: <Widget>[
                M3ETextField(focusNode: field, label: 'Name'),
                M3EButton.filled(
                  focusNode: next,
                  onPressed: () {},
                  child: const Text('Next'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    M3EFocusInteraction.instance.noteKeyboardHighlight();
    field.requestFocus();
    await tester.pumpAndSettle();
    expect(field.hasPrimaryFocus, isTrue);
    expect(M3EFocusRing.shouldShow(field), isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);

    expect(field.hasPrimaryFocus, isFalse);
    expect(M3EFocusRing.shouldShow(field), isFalse);
    expect(next.hasPrimaryFocus, isTrue);
  });
}

void registerFocusRingTextFieldTypingWithRingTests() {
  testWidgets('text field accepts typing while keyboard ring is shown', (
    WidgetTester tester,
  ) async {
    final field = FocusNode(debugLabel: 'field');
    addTearDown(field.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: M3ETheme(
          data: M3EThemeData.light(),
          child: Scaffold(
            body: M3ETextField(focusNode: field, label: 'Name'),
          ),
        ),
      ),
    );

    M3EFocusInteraction.instance.noteKeyboardHighlight();
    field.requestFocus();
    await tester.pumpAndSettle();
    expect(M3EFocusRing.shouldShow(field), isTrue);

    await tester.enterText(find.byType(EditableText), 'hello');
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);
    expect(field.hasPrimaryFocus, isTrue);
  });
}

void registerFocusRingTabReachesSearchBarTests() {
  testWidgets('Tab reaches idle search bar EditableText', (
    WidgetTester tester,
  ) async {
    final before = FocusNode(debugLabel: 'before');
    final search = FocusNode(debugLabel: 'search');
    addTearDown(before.dispose);
    addTearDown(search.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: M3ETheme(
          data: M3EThemeData.light(),
          child: Scaffold(
            body: Column(
              children: <Widget>[
                M3EButton.filled(
                  focusNode: before,
                  onPressed: () {},
                  child: const Text('Before'),
                ),
                M3ESearchBar(focusNode: search, hintText: 'Search'),
              ],
            ),
          ),
        ),
      ),
    );

    M3EFocusInteraction.instance.noteKeyboardHighlight();
    before.requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);

    expect(search.hasPrimaryFocus, isTrue);
    expect(M3EFocusRing.shouldShow(search), isTrue);
  });
}
