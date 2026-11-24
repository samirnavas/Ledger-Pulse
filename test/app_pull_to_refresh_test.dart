import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paypr/core/widgets/app_pull_to_refresh.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'Pull stays fixed, arms once, and refreshes only on release ($platform)',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final completed = Completer<void>();
        var refreshes = 0;
        var haptics = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'HapticFeedback.vibrate') haptics++;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(
              appBar: AppBar(title: const Text('Refresh test')),
              body: AppPullToRefresh(
                onRefresh: () {
                  refreshes++;
                  return completed.future;
                },
                child: ListView.builder(
                  controller: controller,
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: 50,
                  itemBuilder: (_, i) =>
                      SizedBox(height: 60, child: Text('Row $i')),
                ),
              ),
            ),
          ),
        );
        final gesture = await tester.startGesture(const Offset(200, 120));
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump();
        final indicator = find.byKey(const Key('pull_refresh_indicator'));
        final bodyTop = tester.getTopLeft(find.byType(AppPullToRefresh)).dy;
        expect(tester.getTopLeft(indicator).dy, lessThan(bodyTop));
        expect(tester.getBottomLeft(indicator).dy, greaterThan(bodyTop));
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump();
        expect(controller.offset, 0);
        expect(refreshes, 0);
        expect(haptics, 0);
        await gesture.moveBy(const Offset(0, 100));
        await tester.pump();
        expect(haptics, 1);
        final armedPosition = tester.getTopLeft(indicator);
        expect(armedPosition.dy, bodyTop + 40);
        await gesture.moveBy(const Offset(0, -140));
        await tester.pump();
        expect(controller.offset, 0);
        expect(indicator, findsNothing);
        expect(refreshes, 0);
        expect(haptics, 1);
        await gesture.up();
        await tester.pump();
        expect(refreshes, 0);
        expect(indicator, findsNothing);
        final nextPull = await tester.startGesture(const Offset(200, 120));
        await nextPull.moveBy(const Offset(0, 180));
        await tester.pump();
        expect(refreshes, 0);
        expect(haptics, 2);
        expect(tester.getTopLeft(indicator), armedPosition);
        await nextPull.moveBy(const Offset(0, 50));
        await tester.pump();
        expect(tester.getTopLeft(indicator), armedPosition);
        expect(haptics, 2);
        await nextPull.up();
        await tester.pump();
        expect(refreshes, 1);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        completed.complete();
        await tester.pumpAndSettle();
        expect(indicator, findsNothing);
        expect(controller.offset, 0);
        // A short pull is canceled; it must not refresh or vibrate.
        await tester.drag(find.byType(ListView), const Offset(0, 60));
        await tester.pumpAndSettle();
        expect(refreshes, 1);
        expect(haptics, 2);
        // Normal scrolling is restored once the pull has ended.
        await tester.drag(find.byType(ListView), const Offset(0, -250));
        await tester.pumpAndSettle();
        expect(controller.offset, greaterThan(0));
      },
    );
  }
}
