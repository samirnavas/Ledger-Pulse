import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/models/audit_log_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late AuditService auditService;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    auditService = AuditService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Statutory Audit Trail (FR-CMP-05) Tests', () {
    test('JSON diff computation calculates additions, modifications, and removals accurately', () {
      final oldMap = {'name': 'Alice', 'phone': '12345', 'balance': 100};
      final newMap = {'name': 'Alice Corp', 'phone': '12345', 'balance': 250};

      final diff = AuditService.computeDiff(oldMap, newMap);
      expect(diff, isNotNull);
      expect(diff, contains('"name":{"old":"Alice","new":"Alice Corp"}'));
      expect(diff, contains('"balance":{"old":100,"new":250}'));
      expect(diff, isNot(contains('phone'))); // phone was unchanged
    });

    test('Audit records create a verified cryptographic SHA-256 blockchain-style chain', () async {
      const companyId = 'cmp_test_1';
      const userId = 'usr_admin_1';

      // 1. Record Insert
      final log1 = await auditService.recordLog(
        companyId: companyId,
        userId: userId,
        entityType: 'party',
        entityId: 'party_1',
        action: AuditAction.insert,
        newState: {'id': 'party_1', 'name': 'Bob Customer'},
      );

      expect(log1.previousChecksum, equals('GENESIS_$companyId'));
      expect(log1.verifyIntegrity(), isTrue);

      // 2. Record Update
      final log2 = await auditService.recordLog(
        companyId: companyId,
        userId: userId,
        entityType: 'party',
        entityId: 'party_1',
        action: AuditAction.update,
        oldState: {'id': 'party_1', 'name': 'Bob Customer'},
        newState: {'id': 'party_1', 'name': 'Bob Customer Updated'},
      );

      expect(log2.previousChecksum, equals(log1.checksum));
      expect(log2.verifyIntegrity(), isTrue);

      // 3. Record Delete/Void
      final log3 = await auditService.recordLog(
        companyId: companyId,
        userId: userId,
        entityType: 'ledger_entry',
        entityId: 'entry_1',
        action: AuditAction.voided,
        oldState: {'id': 'entry_1', 'amountInCents': 5000},
        newState: {'id': 'entry_1', 'isVoided': true},
      );

      expect(log3.previousChecksum, equals(log2.checksum));
      expect(log3.verifyIntegrity(), isTrue);

      // 4. Verify full chain integrity
      final isChainValid = await auditService.verifyChainIntegrity(companyId);
      expect(isChainValid, isTrue);

      final allLogs = await auditService.getAuditLogs(companyId: companyId);
      expect(allLogs.length, equals(3));
    });

    test('Chain integrity fails when an audit log entry is tampered with', () async {
      const companyId = 'cmp_tamper_test';
      const userId = 'usr_test';

      await auditService.recordLog(
        companyId: companyId,
        userId: userId,
        entityType: 'party',
        entityId: 'p1',
        action: AuditAction.insert,
        newState: {'name': 'Original'},
      );

      final log2 = await auditService.recordLog(
        companyId: companyId,
        userId: userId,
        entityType: 'party',
        entityId: 'p1',
        action: AuditAction.update,
        oldState: {'name': 'Original'},
        newState: {'name': 'Modified'},
      );

      // Malicious direct database tampering: modify checksum or data
      await (db.update(db.auditLogs)..where((t) => t.id.equals(log2.id))).write(
        const AuditLogsCompanion(
          checksum: drift.Value('tampered_fake_checksum_12345'),
        ),
      );

      final isChainValid = await auditService.verifyChainIntegrity(companyId);
      expect(isChainValid, isFalse);
    });
  });
}
