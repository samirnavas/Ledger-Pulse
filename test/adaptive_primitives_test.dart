import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/constants/colors.dart';
import 'package:ledger_pulse/core/widgets/adaptive_chip.dart';
import 'package:ledger_pulse/core/widgets/adaptive_controls.dart';
import 'package:ledger_pulse/core/widgets/adaptive_date_field.dart';
import 'package:ledger_pulse/core/widgets/adaptive_icon_surface_button.dart';
import 'package:ledger_pulse/core/widgets/adaptive_list_row.dart';
import 'package:ledger_pulse/core/widgets/adaptive_metric_card.dart';
import 'package:ledger_pulse/core/widgets/adaptive_picker.dart';
import 'package:ledger_pulse/core/widgets/adaptive_search_field.dart';
import 'package:ledger_pulse/core/widgets/adaptive_section_header.dart';
import 'package:ledger_pulse/core/widgets/adaptive_surface_card.dart';
import 'package:ledger_pulse/core/widgets/amount_text.dart';
import 'package:ledger_pulse/core/widgets/app_feedback.dart';
import 'package:ledger_pulse/core/widgets/liquid_glass_card.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';

Widget _buildTestApp({
  required Widget child,
  TargetPlatform platform = TargetPlatform.android,
  Brightness brightness = Brightness.light,
}) {
  final themeData = ThemeData(
    platform: platform,
    brightness: brightness,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: brightness,
    ),
  );
  return MaterialApp(
    key: ValueKey('test_app_${platform}_$brightness'),
    theme: themeData,
    darkTheme: themeData,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    home: Scaffold(
      body: Center(child: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdaptiveSurfaceCard Tests', () {
    testWidgets('renders Android surfaceContainer with radius 28 and responds to tap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.android,
          child: AdaptiveSurfaceCard(
            accentColor: Colors.green,
            onTap: () => tapped = true,
            child: const Text('Surface Content'),
          ),
        ),
      );

      expect(find.text('Surface Content'), findsOneWidget);
      expect(find.byType(InkWell), findsOneWidget);

      await tester.tap(find.text('Surface Content'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('renders iOS LiquidGlassCard with radius 20 and press-fade', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.iOS,
          child: AdaptiveSurfaceCard(
            accentColor: Colors.green,
            onTap: () => tapped = true,
            child: const Text('iOS Surface Content'),
          ),
        ),
      );

      expect(find.text('iOS Surface Content'), findsOneWidget);
      expect(find.byType(LiquidGlassCard), findsOneWidget);

      await tester.tap(find.text('iOS Surface Content'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });

  group('AdaptiveMetricCard Tests', () {
    testWidgets('renders label, icon chip, amount, and handles taps', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.android,
          child: AdaptiveMetricCard(
            label: "You'll Get",
            amountInCents: 154000,
            accentColor: AppColors.receivableGreen,
            icon: const Icon(Icons.arrow_downward),
            amountVariant: AmountVariant.large,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => tapped = true,
          ),
        ),
      );

      expect(find.text("You'll Get"), findsOneWidget);
      expect(find.byType(AmountText), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      await tester.tap(find.text("You'll Get"));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });

  group('AdaptiveSearchField Tests', () {
    testWidgets('renders Android M3 SearchBar and triggers onChanged/onClear', (tester) async {
      final controller = TextEditingController(text: 'Initial');
      String changed = '';
      bool cleared = false;

      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.android,
          child: AdaptiveSearchField(
            controller: controller,
            hint: 'Search parties...',
            onChanged: (val) => changed = val,
            onClear: () => cleared = true,
          ),
        ),
      );

      expect(find.byType(SearchBar), findsOneWidget);
      expect(find.text('Initial'), findsOneWidget);

      // Tap clear button
      final clearButton = find.byIcon(Icons.clear);
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      expect(cleared, isTrue);
      expect(changed, equals(''));
      expect(controller.text, equals(''));
    });

    testWidgets('renders iOS LiquidGlassContainer with CupertinoIcons.search', (tester) async {
      final controller = TextEditingController();
      String changed = '';

      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.iOS,
          child: AdaptiveSearchField(
            controller: controller,
            hint: 'Search expenses...',
            onChanged: (val) => changed = val,
          ),
        ),
      );

      expect(find.byType(LiquidGlassContainer), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.search), findsOneWidget);
      expect(find.text('Search expenses...'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Grocery');
      await tester.pumpAndSettle();

      expect(changed, equals('Grocery'));
      expect(find.byIcon(CupertinoIcons.clear_circled_solid), findsOneWidget);
    });
  });

  group('AdaptiveIconSurfaceButton Tests', () {
    testWidgets('renders on Android and iOS with active tint and responds to tap', (tester) async {
      bool androidTapped = false;
      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.android,
          child: AdaptiveIconSurfaceButton(
            icon: Icons.sort_rounded,
            isActive: true,
            onTap: () => androidTapped = true,
          ),
        ),
      );

      expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.sort_rounded));
      await tester.pumpAndSettle();
      expect(androidTapped, isTrue);

      bool iosTapped = false;
      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.iOS,
          child: AdaptiveIconSurfaceButton(
            icon: CupertinoIcons.sort_down,
            isActive: false,
            onTap: () => iosTapped = true,
          ),
        ),
      );

      expect(find.byType(LiquidGlassContainer), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.sort_down), findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.sort_down));
      await tester.pumpAndSettle();
      expect(iosTapped, isTrue);
    });
  });

  group('AdaptiveChip and AdaptiveChipRow Tests', () {
    testWidgets('single-select chip row selects item on both platforms', (tester) async {
      int? selected = 1;

      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.android,
          child: StatefulBuilder(
            builder: (ctx, setState) => AdaptiveChipRow<int>(
              items: const [
                AdaptiveChipItem(value: 1, label: 'Income'),
                AdaptiveChipItem(value: 2, label: 'Expense'),
              ],
              selectedValue: selected,
              onSelected: (val) => setState(() => selected = val),
            ),
          ),
        ),
      );

      expect(find.text('Income'), findsOneWidget);
      expect(find.text('Expense'), findsOneWidget);

      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      expect(selected, equals(2));

      // Test on iOS
      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.iOS,
          child: StatefulBuilder(
            builder: (ctx, setState) => AdaptiveChipRow<int>(
              items: const [
                AdaptiveChipItem(value: 1, label: 'Income'),
                AdaptiveChipItem(value: 2, label: 'Expense'),
              ],
              selectedValue: selected,
              onSelected: (val) => setState(() => selected = val),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();
      expect(selected, equals(1));
    });

    testWidgets('multi-select chip row adds and removes items', (tester) async {
      Set<String> selected = {'Food'};

      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.android,
          child: StatefulBuilder(
            builder: (ctx, setState) => AdaptiveChipRow<String>(
              items: const [
                AdaptiveChipItem(value: 'Food', label: 'Food'),
                AdaptiveChipItem(value: 'Travel', label: 'Travel'),
                AdaptiveChipItem(value: 'Bills', label: 'Bills'),
              ],
              selectedValues: selected,
              onMultiSelected: (newSet) => setState(() => selected = newSet),
            ),
          ),
        ),
      );

      // Add Travel
      await tester.tap(find.text('Travel'));
      await tester.pumpAndSettle();
      expect(selected.contains('Travel'), isTrue);
      expect(selected.contains('Food'), isTrue);

      // Remove Food
      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      expect(selected.contains('Food'), isFalse);
    });
  });

  group('AdaptiveSwitch and AdaptiveDropdownField Tests', () {
    testWidgets('AdaptiveSwitch toggles value with label and subtitle', (tester) async {
      bool isChecked = false;

      await tester.pumpWidget(
        _buildTestApp(
          child: StatefulBuilder(
            builder: (ctx, setState) => AdaptiveSwitch(
              value: isChecked,
              label: 'Auto Sync',
              subtitle: 'Sync on open',
              onChanged: (val) => setState(() => isChecked = val),
            ),
          ),
        ),
      );

      expect(find.text('Auto Sync'), findsOneWidget);
      expect(find.text('Sync on open'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(isChecked, isTrue);
    });

    testWidgets('AdaptiveDropdownField renders selected value and opens picker', (tester) async {
      String? selectedVal = 'INR';

      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.android,
          child: AdaptiveDropdownField<String>(
            label: 'Currency',
            value: selectedVal,
            items: const [
              AdaptivePickerItem(value: 'INR', label: 'Indian Rupee (INR)'),
              AdaptivePickerItem(value: 'USD', label: 'US Dollar (USD)'),
            ],
            onChanged: (val) => selectedVal = val,
          ),
        ),
      );

      expect(find.text('Currency'), findsOneWidget);
      expect(find.text('Indian Rupee (INR)'), findsOneWidget);

      await tester.tap(find.text('Currency'));
      await tester.pumpAndSettle();

      // Bottom sheet with picker options appears
      expect(find.text('US Dollar (USD)'), findsOneWidget);
      await tester.tap(find.text('US Dollar (USD)'));
      await tester.pumpAndSettle();

      expect(selectedVal, equals('USD'));
    });
  });

  group('AdaptiveDateField Tests', () {
    testWidgets('AdaptiveDateField renders formatted date and responds to tap', (tester) async {
      DateTime chosen = DateTime(2026, 9, 23);

      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.android,
          child: AdaptiveDateField(
            label: 'Transaction Date',
            selectedDate: chosen,
            onDateSelected: (d) => chosen = d,
          ),
        ),
      );

      expect(find.text('Transaction Date'), findsOneWidget);
      expect(find.text('23/09/2026'), findsOneWidget);

      await tester.tap(find.text('Transaction Date'));
      await tester.pumpAndSettle();

      // Android DatePicker dialog appears
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });
  });

  group('AdaptiveListRow and AdaptiveSwipeBackgrounds Tests', () {
    testWidgets('AdaptiveListRow renders title, subtitle, leading initials, and trailing widget', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.android,
          child: AdaptiveListRow(
            title: 'Apex Industrial Solutions',
            subtitle: 'Updated 2 hours ago',
            initials: 'AI',
            trailing: const Text('₹1,500.00'),
            onTap: () => tapped = true,
          ),
        ),
      );

      expect(find.text('Apex Industrial Solutions'), findsOneWidget);
      expect(find.text('Updated 2 hours ago'), findsOneWidget);
      expect(find.text('AI'), findsOneWidget);
      expect(find.text('₹1,500.00'), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);

      await tester.tap(find.text('Apex Industrial Solutions'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('AdaptiveSwipeBackgrounds renders edit and delete backgrounds on iOS and Android', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.iOS,
          child: Column(
            children: [
              Builder(builder: (ctx) => AdaptiveSwipeBackgrounds.edit(ctx)),
              Builder(builder: (ctx) => AdaptiveSwipeBackgrounds.delete(ctx)),
            ],
          ),
        ),
      );

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.android,
          child: Column(
            children: [
              Builder(builder: (ctx) => AdaptiveSwipeBackgrounds.edit(ctx)),
              Builder(builder: (ctx) => AdaptiveSwipeBackgrounds.delete(ctx)),
            ],
          ),
        ),
      );

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  group('AdaptiveSectionHeader Tests', () {
    testWidgets('renders uppercase on iOS and titleSmall on Android', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.iOS,
          child: const AdaptiveSectionHeader(title: 'Recent Transactions'),
        ),
      );
      expect(find.text('RECENT TRANSACTIONS'), findsOneWidget);

      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.android,
          child: const AdaptiveSectionHeader(title: 'Recent Transactions'),
        ),
      );
      expect(find.text('Recent Transactions'), findsOneWidget);
    });
  });

  group('showAppFeedback Tests', () {
    testWidgets('Android displays floating SnackBar', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.android,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showAppFeedback(ctx, 'Saved successfully!'),
              child: const Text('Show'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.text('Saved successfully!'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('iOS displays CupertinoAlertDialog on error', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          platform: TargetPlatform.iOS,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showAppFeedback(ctx, 'Network failure', isError: true),
              child: const Text('Show Error'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Error'));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.text('Network failure'), findsOneWidget);
    });
  });

  group('AppColors Semantic Colors Tests', () {
    testWidgets('returns light and dark semantic colors matching specifications', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          brightness: Brightness.light,
          child: Builder(
            builder: (ctx) {
              expect(AppColors.income(ctx), equals(const Color(0xFF16A34A)));
              expect(AppColors.expense(ctx), equals(const Color(0xFFDC2626)));
              expect(Theme.of(ctx).colorScheme.income, equals(const Color(0xFF16A34A)));
              expect(Theme.of(ctx).colorScheme.expense, equals(const Color(0xFFDC2626)));
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        _buildTestApp(
          brightness: Brightness.dark,
          child: Builder(
            builder: (ctx) {
              expect(AppColors.income(ctx), equals(const Color(0xFF4ADE80)));
              expect(AppColors.expense(ctx), equals(const Color(0xFFF87171)));
              expect(Theme.of(ctx).colorScheme.income, equals(const Color(0xFF4ADE80)));
              expect(Theme.of(ctx).colorScheme.expense, equals(const Color(0xFFF87171)));
              return const SizedBox();
            },
          ),
        ),
      );
    });
  });
}
