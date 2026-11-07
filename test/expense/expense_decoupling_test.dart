import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Expense Domain Decoupling Architectural Guard-Rail Test', () {
    test('Pure Expense models, repositories, and domain files have 0 imports of Ledger infrastructure', () {
      final targets = [
        Directory('lib/data/models/expense'),
        File('lib/data/local/drift_expense_repository_v2.dart'),
        File('lib/domain/repositories/i_expense_repository.dart'),
      ];

      final forbiddenTokens = [
        'voucher_posting_engine.dart',
        'drift_voucher_repository.dart',
        'account_model.dart',
        'voucher_model.dart',
        'journal_model.dart',
        'VoucherPostingEngine',
        'DriftVoucherRepository',
        'VoucherModel',
        'AccountModel',
      ];

      final violations = <String>[];

      for (final target in targets) {
        if (target is Directory && target.existsSync()) {
          final files = target.listSync(recursive: true).whereType<File>();
          for (final f in files) {
            _checkFile(f, forbiddenTokens, violations);
          }
        } else if (target is File && target.existsSync()) {
          _checkFile(target, forbiddenTokens, violations);
        }
      }

      if (violations.isNotEmpty) {
        fail(
          'Expense domain is coupled to Ledger accounting infrastructure:\n'
          '${violations.join('\n')}',
        );
      }
    });
  });
}

void _checkFile(File file, List<String> forbiddenTokens, List<String> violations) {
  final content = file.readAsStringSync();
  final path = file.path.replaceAll('\\', '/');

  for (final token in forbiddenTokens) {
    if (content.contains(token)) {
      violations.add('$path -> contains forbidden Ledger reference "$token"');
    }
  }
}

