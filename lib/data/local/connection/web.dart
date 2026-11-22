import 'package:drift/drift.dart';
// ignore: deprecated_member_use
import 'package:drift/web.dart';
import 'connection.dart';

QueryExecutor openConnection([String uid = 'usr_default']) {
  final sanitizedUid = sanitizeDatabaseIdentifier(uid);
  final developmentNamespace = developmentDatabaseNamespace();
  final databaseName = developmentNamespace == null
      ? 'ledger_pulse_$sanitizedUid'
      : 'ledger_pulse.dev.$developmentNamespace.$sanitizedUid';
  return WebDatabase(databaseName, logStatements: false);
}
