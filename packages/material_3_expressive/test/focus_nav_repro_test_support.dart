import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

void setUpFocusNavReproTests() {
  M3EFocusInteraction.resetForTest();
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
}

void tearDownFocusNavReproTests() {
  M3EFocusInteraction.resetForTest();
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
}

Future<void> pumpFocusNavTab(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
  await tester.pump();
  await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
  await tester.pumpAndSettle();
}

FocusScopeNode? findFabMenuScope() {
  FocusScopeNode? found;
  void walk(FocusNode node) {
    if (node is FocusScopeNode && node.debugLabel == 'M3EFabMenu') {
      found = node;
      return;
    }
    for (final FocusNode child in node.children) {
      walk(child);
      if (found != null) {
        return;
      }
    }
  }

  walk(FocusManager.instance.rootScope);
  return found;
}

Future<void> pumpFabMenuApp(
  WidgetTester tester, {
  required List<String> labels,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: M3ETheme(
        data: M3EThemeData.light(),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: M3EFabMenu(
              items: <M3EFabMenuItem>[
                for (final label in labels)
                  M3EFabMenuItem(
                    icon: const Icon(Icons.add),
                    label: label,
                    onPressed: () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> pumpSelectionDialogEnterApp(
  WidgetTester tester, {
  required void Function(List<String>?) onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: M3ETheme(
        data: M3EThemeData.light(),
        child: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: M3EButton.filled(
                onPressed: () async {
                  onResult(
                    await M3EDialog.showSelectionScreen(
                      context,
                      title: 'Plan',
                      options: const <String>['A', 'B', 'C'],
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    ),
  );
}

Future<void> pumpSelectionDialogShellOrderApp(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: M3ETheme(
        data: M3EThemeData.light(),
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Scaffold(
            body: Column(
              children: <Widget>[
                FocusTraversalOrder(
                  order: const NumericFocusOrder(0),
                  child: FocusTraversalGroup(
                    child: M3EButton.filled(
                      onPressed: () {},
                      child: const Text('Chrome'),
                    ),
                  ),
                ),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: Expanded(
                    child: Builder(
                      builder: (BuildContext context) {
                        return Center(
                          child: M3EButton.filled(
                            onPressed: () {
                              M3EDialog.showSelectionScreen(
                                context,
                                title: 'Plan',
                                options: const <String>[
                                  'Standard',
                                  'Pro',
                                  'Team',
                                ],
                              );
                            },
                            child: const Text('Open selection'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> pumpSearchBarTabApp(
  WidgetTester tester, {
  required FocusNode before,
  required FocusNode search,
  required TextEditingController controller,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: M3ETheme(
        data: M3EThemeData.light(),
        child: Scaffold(
          body: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              children: <Widget>[
                FocusTraversalOrder(
                  order: const NumericFocusOrder(0),
                  child: M3EButton.filled(
                    focusNode: before,
                    onPressed: () {},
                    child: const Text('Before'),
                  ),
                ),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: SizedBox(
                    width: 240,
                    child: M3ESearchBar(
                      focusNode: search,
                      controller: controller,
                      hintText: 'Search',
                      alignment: Alignment.center,
                    ),
                  ),
                ),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: M3EButton.filled(
                    onPressed: () {},
                    child: const Text('After'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
