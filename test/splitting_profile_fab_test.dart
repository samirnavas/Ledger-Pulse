import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/widgets/splitting_fab.dart';

void main() {
  testWidgets('SplittingProfileFab renders Edit Profile in collapsed state', (tester) async {
    bool editCalled = false;
    bool saveCalled = false;
    bool cancelCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: SplittingProfileFab(
            isEditing: false,
            onEdit: () => editCalled = true,
            onSave: () => saveCalled = true,
            onCancel: () => cancelCalled = true,
          ),
        ),
      ),
    );

    // Initial state: "Edit Profile" is displayed
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Save Changes'), findsNothing);

    // Tapping Edit Profile invokes onEdit
    await tester.tap(find.text('Edit Profile'));
    expect(editCalled, isTrue);
    expect(saveCalled, isFalse);
    expect(cancelCalled, isFalse);
  });

  testWidgets('SplittingProfileFab smoothly splits into Cancel and Save Changes when isEditing is true', (tester) async {
    bool isEditing = false;
    bool editCalled = false;
    bool saveCalled = false;
    bool cancelCalled = false;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              floatingActionButton: SplittingProfileFab(
                isEditing: isEditing,
                onEdit: () {
                  editCalled = true;
                  setState(() => isEditing = true);
                },
                onSave: () => saveCalled = true,
                onCancel: () {
                  cancelCalled = true;
                  setState(() => isEditing = false);
                },
              ),
            ),
          );
        },
      ),
    );

    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);

    // Tap Edit to trigger split
    await tester.tap(find.text('Edit Profile'));
    expect(editCalled, isTrue);

    // Animate splitting forward
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Both Cancel and Save Changes should now be present
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);

    // Tap Save Changes invokes onSave
    await tester.tap(find.text('Save Changes'));
    expect(saveCalled, isTrue);

    // Tap Cancel invokes onCancel and recombines back
    await tester.tap(find.text('Cancel'));
    expect(cancelCalled, isTrue);

    // Animate combining back
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // After combining, only Edit Profile is present
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });
}
