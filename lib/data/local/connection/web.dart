import 'package:drift/drift.dart';
// ignore: deprecated_member_use
import 'package:drift/web.dart';
import 'connection.dart';

QueryExecutor openConnection([String uid = 'usr_default']) {
  final sanitizedUid = sanitizeDatabaseIdentifier(uid);
  return WebDatabase('ledger_pulse_$sanitizedUid', logStatements: false);
}
