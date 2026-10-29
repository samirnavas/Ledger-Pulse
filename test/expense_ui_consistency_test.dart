import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Prompt UI-8 Expense UI Consistency Guard-Rail Test', () {
    final expenseDir = Directory('lib/presentation/expense');

    test('All files under lib/presentation/expense/ use adaptive primitives', () {
      expect(expenseDir.existsSync(), isTrue,
          reason: 'lib/presentation/expense/ directory must exist');

      final dartFiles = expenseDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      expect(dartFiles, isNotEmpty,
          reason: 'There must be dart files in lib/presentation/expense/');

      final forbiddenPatterns = <String, RegExp>{
        'MaterialPageRoute': RegExp(r'\bMaterialPageRoute\b'),
        'Scaffold(': RegExp(r'(?<!Adaptive)Scaffold\('),
        'AppBar(': RegExp(r'\bAppBar\('),
        'AlertDialog(': RegExp(r'(?<!Adaptive)AlertDialog\('),
        'FloatingActionButton': RegExp(r'\bFloatingActionButton\b'),
        'SegmentedButton': RegExp(r'\bSegmentedButton\b'),
        'DropdownButtonFormField': RegExp(r'\bDropdownButtonFormField\b'),
        'SnackBar(': RegExp(r'\bSnackBar\('),
        'Color(0x': RegExp(r'Color\(0x[0-9a-fA-F]{8}\)'),
      };

      final violations = <String>[];

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        final relativePath = file.path.replaceAll('\\', '/');

        forbiddenPatterns.forEach((patternName, regex) {
          final matches = regex.allMatches(content);
          for (final match in matches) {
            // Find line number
            final lineNum = content.substring(0, match.start).split('\n').length;
            final matchedText = match.group(0);
            violations.add(
                '$relativePath:$lineNum -> Found forbidden non-adaptive API "$patternName" ("$matchedText")');
          }
        });
      }

      if (violations.isNotEmpty) {
        fail(
            'Expense UI Consistency Check Failed! Found ${violations.length} non-adaptive API usage(s):\n'
            '${violations.join('\n')}\n\n'
            'Guidelines:\n'
            '- Replace MaterialPageRoute with createAdaptivePageRoute()\n'
            '- Replace Scaffold( with AdaptiveScaffold(\n'
            '- Replace AppBar( with AdaptiveScaffold / CupertinoNavigationBar\n'
            '- Replace AlertDialog( with AdaptiveConfirmDialog / showAdaptivePicker\n'
            '- Replace FloatingActionButton with SpringMorphingFab\n'
            '- Replace SegmentedButton with AdaptiveSegmentedControl\n'
            '- Replace DropdownButtonFormField with AdaptiveDropdownField\n'
            '- Replace SnackBar( with showAppFeedback()\n'
            '- Replace hardcoded Color(0x...) hex literals with AppColors / theme.colorScheme\n');
      }
    });
  });
}
