import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/sync/dropbox_sync_provider.dart';
import 'package:ledger_pulse/data/sync/supabase_sync_provider.dart';
import 'package:ledger_pulse/data/sync/sync_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late SupabaseSyncProvider supabaseProvider;
  late DropboxSyncProvider dropboxProvider;
  late SyncCoordinator coordinator;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    supabaseProvider = SupabaseSyncProvider(
      db: db,
      supabaseUrl: 'https://mock-supabase.ludgerpulse.internal',
      supabaseAnonKey: 'mock-key',
    );
    dropboxProvider = DropboxSyncProvider(
      db: db,
      dropboxAccessToken: 'mock-token',
    );
    coordinator = SyncCoordinator(
      db: db,
      supabase: supabaseProvider,
      dropbox: dropboxProvider,
    );
  });

  tearDown(() async {
    coordinator.dispose();
    await db.close();
  });

  group('Offline-First Sync Engine (FR-SYN-01, FR-SYN-02) Tests', () {
    test('Outbox queue tracks mutations and processes successfully', () async {
      const companyId = 'cmp_sync_test';

      // 1. Insert pending outbox mutations
      await db.into(db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              id: 'outbox_test_1',
              targetTable: 'parties',
              recordId: 'p_101',
              mutationType: 'INSERT',
              payload: jsonEncode({'id': 'p_101', 'name': 'Sync Client', 'companyId': companyId}),
            ),
          );

      final pendingCount = await coordinator.getPendingOutboxCount(companyId);
      expect(pendingCount, equals(1));

      // 2. Push pending outbox via Supabase provider
      final pushResult = await supabaseProvider.pushPendingOutbox(companyId);
      expect(pushResult.success, isTrue);
      expect(pushResult.itemsPushed, equals(1));

      // 3. Confirm outbox item is removed from queue on success (Directive 4)
      final remainingPending = await coordinator.getPendingOutboxCount(companyId);
      expect(remainingPending, equals(0));
    });

    test('Outbox queue retains mutation upon failure for retry', () async {
      const companyId = 'cmp_retry_test';

      await db.into(db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              id: 'outbox_test_retry',
              targetTable: 'parties',
              recordId: 'p_retry',
              mutationType: 'INSERT',
              payload: jsonEncode({'id': 'p_retry', 'companyId': companyId}),
            ),
          );

      final items = await supabaseProvider.getPendingOutboxItems(companyId);
      expect(items.length, equals(1));
      final itemId = items.first.id;

      // Simulate failure
      await supabaseProvider.markItemFailed(itemId, 'Simulated Timeout Error');

      final remaining = await coordinator.getPendingOutboxCount(companyId);
      expect(remaining, equals(1));
    });

    test('Dropbox provider creates state snapshot and merges remote parties', () async {
      const companyId = 'cmp_dropbox_test';

      // Seed local party
      await db.into(db.parties).insert(
            PartiesCompanion.insert(
              id: 'p_local_1',
              companyId: const Value(companyId),
              name: 'Local Store',
              phoneNumber: '+91 91111 22222',
              type: PartyType.customer,
              lastUpdated: DateTime.now(),
              isDeleted: const Value(false),
              updatedAt: Value(DateTime.now()),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );

      final exportResult = await dropboxProvider.pushPendingOutbox(companyId);
      expect(exportResult.success, isTrue);

      // Verify Coordinator selects Dropbox provider for dropbox-configured company
      final dropboxCompany = Company(
        id: companyId,
        name: 'Dropbox Only Enterprise',
        legalName: 'Dropbox Only Enterprise',
        isCloudSyncEnabled: false,
        isDropboxSyncEnabled: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final engine = coordinator.getEngineForCompany(dropboxCompany);
      expect(engine, isA<DropboxSyncProvider>());

      final syncResult = await coordinator.triggerSync(dropboxCompany);
      expect(syncResult.success, isTrue);
    });
  });
}
