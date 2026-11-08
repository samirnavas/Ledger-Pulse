import 'dart:io';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/domain/models/workspace_profile_header.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_controller.dart';
import '../sync/support/fake_remote_gateway.dart';

/// Test double extending [FakeGateway] to record the exact sequence of remote table calls.
class RecordingRemoteGateway extends FakeGateway {
  final List<({String table, String id, Map<String, dynamic> row})> upsertLog = [];
  bool shouldFailNextUpsert = false;
  int upsertAttemptCount = 0;

  @override
  Future<Map<String, dynamic>?> upsertRow({
    required String table,
    required Map<String, dynamic> row,
  }) async {
    upsertAttemptCount++;
    if (shouldFailNextUpsert) {
      throw const SocketException('Simulated network connectivity drop');
    }
    final id = (row['id'] ?? row['record_id'])?.toString() ?? 'unknown';
    upsertLog.add((table: table, id: id, row: Map<String, dynamic>.from(row)));
    return super.upsertRow(table: table, row: row);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUserUuid = 'b736b4a2-9d3e-4b2a-88fa-123456789abc';
  const otherUserUuid = 'c847c5b3-0e4f-5c3b-99ab-234567890def';

  late AppDatabase db;
  late RecordingRemoteGateway remoteGateway;
  late SyncEngine syncEngine;
  late DriftProfileRepository profileRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    remoteGateway = RecordingRemoteGateway();
    syncEngine = SyncEngine(
      db: db,
      gateway: remoteGateway,
      simulateSyncForTesting: true,
    );
    profileRepo = DriftProfileRepository(
      db: db,
      syncEngine: syncEngine,
    );
  });

  tearDown(() async {
    syncEngine.dispose();
    await db.close();
  });

  group('Profile Creation and Supabase Persistence Tests', () {
    test('1. Local profile creation sets pending syncStatus and creates membership atomically', () async {
      final profile = await profileRepo.createProfile(
        name: 'Apex Innovations',
        type: ProfileType.ledger,
        accountId: testUserUuid,
      );

      // Verify company row in Drift
      final companyRow = await (db.select(db.companies)..where((c) => c.id.equals(profile.id))).getSingle();
      expect(companyRow.name, equals('Apex Innovations'));
      expect(companyRow.mode, equals('ledger'));
      expect(companyRow.ownerId, equals(testUserUuid));
      expect(companyRow.syncStatus, equals(SyncRecordStatus.pending));

      // Verify membership row in Drift
      final membershipRows = await (db.select(db.sharedMemberships)
            ..where((m) => m.profileId.equals(profile.id)))
          .get();
      expect(membershipRows.length, equals(1));
      final mem = membershipRows.first;
      expect(mem.accountId, equals(testUserUuid));
      expect(mem.role, equals('owner'));
    });

    test('2. Correct owner UUID persistence and rejection of invalid identities', () async {
      // Rejects null or empty accountId
      expect(
        () => profileRepo.createProfile(
          name: 'Invalid Profile',
          type: ProfileType.expense,
          accountId: null,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => profileRepo.createProfile(
          name: 'Invalid Profile',
          type: ProfileType.expense,
          accountId: '',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Rejects non-UUID strings (e.g. phone, email, or synthetic IDs like 'usr_default')
      expect(
        () => profileRepo.createProfile(
          name: 'Invalid Profile',
          type: ProfileType.expense,
          accountId: 'usr_default',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => profileRepo.createProfile(
          name: 'Invalid Profile',
          type: ProfileType.expense,
          accountId: 'user@example.com',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => profileRepo.createProfile(
          name: 'Invalid Profile',
          type: ProfileType.expense,
          accountId: '+919876543210',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Accepts valid UUID and persists it
      final profile = await profileRepo.createProfile(
        name: 'Valid UUID Profile',
        type: ProfileType.expense,
        accountId: testUserUuid,
      );

      final row = await (db.select(db.companies)..where((c) => c.id.equals(profile.id))).getSingle();
      expect(row.ownerId, equals(testUserUuid));
    });

    test('3. Correct membership creation with valid UUID id and owner role', () async {
      final profile = await profileRepo.createProfile(
        name: 'Personal Wallet',
        type: ProfileType.expense,
        accountId: testUserUuid,
      );

      final mem = await (db.select(db.sharedMemberships)..where((m) => m.profileId.equals(profile.id))).getSingle();
      expect(mem.profileId, equals(profile.id));
      expect(mem.accountId, equals(testUserUuid));
      expect(mem.role, equals('owner'));

      // Verify mem.id is a valid UUID format (not 'mem_timestamp')
      final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
      expect(uuidRegex.hasMatch(mem.id), isTrue);
    });

    test('4 & 5. Profile and membership upload to Supabase', () async {
      final profile = await profileRepo.createProfile(
        name: 'Cloud Venture',
        type: ProfileType.ledger,
        accountId: testUserUuid,
      );

      // Push outbox to remote
      final result = await syncEngine.pushQueue(companyId: profile.id);
      expect(result.status, equals(SyncEngineStatus.success));

      // Verify remote gateway received the companies row
      final remoteCompanies = remoteGateway.tables['companies'];
      expect(remoteCompanies, isNotNull);
      expect(remoteCompanies!.containsKey(profile.id), isTrue);
      final remoteCompRow = remoteCompanies[profile.id]!;
      expect(remoteCompRow['name'], equals('Cloud Venture'));
      expect(remoteCompRow['mode'], equals('ledger'));
      expect(remoteCompRow['owner_id'], equals(testUserUuid));

      // Verify remote gateway received the shared_memberships row
      final remoteMemberships = remoteGateway.tables['shared_memberships'];
      expect(remoteMemberships, isNotNull);
      final memEntries = remoteMemberships!.values.where((m) => m['profile_id'] == profile.id);
      expect(memEntries.length, equals(1));
      final remoteMem = memEntries.first;
      expect(remoteMem['account_id'], equals(testUserUuid));
      expect(remoteMem['role'], equals('owner'));
    });

    test('6. Profile-before-membership ordering is strictly enforced', () async {
      final profile = await profileRepo.createProfile(
        name: 'Strict Order Firm',
        type: ProfileType.ledger,
        accountId: testUserUuid,
      );

      // Verify outbox queue order in SQLite
      final outboxEntries = await (db.select(db.syncOutbox)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
      final tableOrder = outboxEntries.map((e) => e.targetTable).toList();

      final companyIndex = tableOrder.indexOf('companies');
      final membershipIndex = tableOrder.indexOf('shared_memberships');
      expect(companyIndex, isNot(equals(-1)));
      expect(membershipIndex, isNot(equals(-1)));
      expect(companyIndex, lessThan(membershipIndex), reason: 'companies MUST be enqueued before shared_memberships');

      // Now push queue and verify remote gateway execution order
      remoteGateway.upsertLog.clear();
      await syncEngine.pushQueue(companyId: profile.id);

      final logTables = remoteGateway.upsertLog.map((e) => e.table).toList();
      final remoteCompanyIndex = logTables.indexOf('companies');
      final remoteMembershipIndex = logTables.indexOf('shared_memberships');

      expect(remoteCompanyIndex, isNot(equals(-1)));
      expect(remoteMembershipIndex, isNot(equals(-1)));
      expect(
        remoteCompanyIndex,
        lessThan(remoteMembershipIndex),
        reason: 'Supabase gateway MUST receive companies write BEFORE shared_memberships write',
      );
    });

    test('7 & 9. Correct synced/pending status transitions and retry after network failure', () async {
      final profile = await profileRepo.createProfile(
        name: 'Retry Ledger',
        type: ProfileType.ledger,
        accountId: testUserUuid,
      );

      // Initial state is pending
      var compRow = await (db.select(db.companies)..where((c) => c.id.equals(profile.id))).getSingle();
      expect(compRow.syncStatus, equals(SyncRecordStatus.pending));

      // Simulate network failure
      remoteGateway.shouldFailNextUpsert = true;
      final failedResult = await syncEngine.pushQueue(companyId: profile.id);
      expect(failedResult.status, equals(SyncEngineStatus.partial));

      // Local company must still be pending - NOT marked synced!
      compRow = await (db.select(db.companies)..where((c) => c.id.equals(profile.id))).getSingle();
      expect(compRow.syncStatus, equals(SyncRecordStatus.pending));

      // Outbox entries must still exist with attempt counter incremented
      var pendingOutbox = await (db.select(db.syncOutbox)).get();
      expect(pendingOutbox.isNotEmpty, isTrue);
      expect(pendingOutbox.first.attempts, greaterThanOrEqualTo(1));

      // Network restored: clear failure and reset nextAttemptAt for immediate retry
      remoteGateway.shouldFailNextUpsert = false;
      await (db.update(db.syncOutbox)).write(const SyncOutboxCompanion(nextAttemptAt: Value(null)));

      final retryResult = await syncEngine.pushQueue(companyId: profile.id);
      expect(retryResult.status, equals(SyncEngineStatus.success));

      // Now local company must be marked synced!
      compRow = await (db.select(db.companies)..where((c) => c.id.equals(profile.id))).getSingle();
      expect(compRow.syncStatus, equals(SyncRecordStatus.synced));

      // Outbox must be empty
      pendingOutbox = await (db.select(db.syncOutbox)).get();
      expect(pendingOutbox.isEmpty, isTrue);
    });

    test('8. Idempotent retry: Repeated sync does not create duplicate profiles or memberships', () async {
      final profile = await profileRepo.createProfile(
        name: 'Idempotent Biz',
        type: ProfileType.ledger,
        accountId: testUserUuid,
      );

      await syncEngine.pushQueue(companyId: profile.id);

      final initialRemoteCompCount = remoteGateway.tables['companies']!.length;
      final initialRemoteMemCount = remoteGateway.tables['shared_memberships']!.length;

      // Manually trigger queueing of local records again
      await syncEngine.pushQueue(companyId: profile.id);

      expect(remoteGateway.tables['companies']!.length, equals(initialRemoteCompCount));
      expect(remoteGateway.tables['shared_memberships']!.length, equals(initialRemoteMemCount));
    });

    test('10. Offline profile creation followed by successful synchronization', () async {
      // Simulate completely offline state: gateway throws network exception
      remoteGateway.simulateNetworkError = true;

      final profile = await profileRepo.createProfile(
        name: 'Offline Market',
        type: ProfileType.expense,
        accountId: testUserUuid,
      );

      // Locally available immediately despite network drop
      final accessibleOffline = await profileRepo.getAccessibleProfiles(testUserUuid);
      expect(accessibleOffline.any((p) => p.id == profile.id), isTrue);

      final localRow = await (db.select(db.companies)..where((c) => c.id.equals(profile.id))).getSingle();
      expect(localRow.syncStatus, equals(SyncRecordStatus.pending));

      // Bring connection back online
      remoteGateway.simulateNetworkError = false;
      await (db.update(db.syncOutbox)).write(const SyncOutboxCompanion(nextAttemptAt: Value(null)));

      final syncResult = await syncEngine.pushQueue(companyId: profile.id);
      expect(syncResult.status, equals(SyncEngineStatus.success));

      // Status transitioned to synced on confirmation
      final syncedRow = await (db.select(db.companies)..where((c) => c.id.equals(profile.id))).getSingle();
      expect(syncedRow.syncStatus, equals(SyncRecordStatus.synced));

      // Remote backend has verified copy
      expect(remoteGateway.tables['companies']!.containsKey(profile.id), isTrue);
    });

    test('11. Loading profiles using the authenticated UUID (never email or phone)', () async {
      final userProfile = await profileRepo.createProfile(
        name: 'User Workspace',
        type: ProfileType.expense,
        accountId: testUserUuid,
      );

      final otherProfile = await profileRepo.createProfile(
        name: 'Other Workspace',
        type: ProfileType.ledger,
        accountId: otherUserUuid,
      );

      // Querying with testUserUuid returns userProfile only
      final userProfiles = await profileRepo.getAccessibleProfiles(testUserUuid);
      expect(userProfiles.length, equals(1));
      expect(userProfiles.first.id, equals(userProfile.id));

      // Querying with otherUserUuid returns otherProfile only
      final otherProfiles = await profileRepo.getAccessibleProfiles(otherUserUuid);
      expect(otherProfiles.length, equals(1));
      expect(otherProfiles.first.id, equals(otherProfile.id));

      // Querying with email or phone returns empty list
      expect(await profileRepo.getAccessibleProfiles('test@example.com'), isEmpty);
      expect(await profileRepo.getAccessibleProfiles('+919876543210'), isEmpty);
      expect(await profileRepo.getAccessibleProfiles(''), isEmpty);
    });

    test('12. Multiple profiles belonging to one account preserve canonical types', () async {
      final expProfile = await profileRepo.createProfile(
        name: 'Personal Expenses',
        type: ProfileType.expense,
        accountId: testUserUuid,
      );

      final ledProfile = await profileRepo.createProfile(
        name: 'Business Ledger',
        type: ProfileType.ledger,
        accountId: testUserUuid,
      );

      final profiles = await profileRepo.getAccessibleProfiles(testUserUuid);
      expect(profiles.length, equals(2));

      final loadedExp = profiles.firstWhere((p) => p.id == expProfile.id);
      final loadedLed = profiles.firstWhere((p) => p.id == ledProfile.id);

      expect(loadedExp.type, equals(ProfileType.expense));
      expect(loadedLed.type, equals(ProfileType.ledger));
    });
  });
}
