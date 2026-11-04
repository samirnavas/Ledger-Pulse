import 'package:drift/drift.dart';
// ignore: deprecated_member_use
import 'package:drift/web.dart';

QueryExecutor openConnection([String uid = 'usr_default']) {
  final sanitizedUid = uid.isEmpty ? 'usr_default' : uid.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  return WebDatabase('ledger_pulse_$sanitizedUid', logStatements: false);
}
