import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/core/widgets/liquid_glass_card.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';
import 'package:ledger_pulse/data/repositories/supabase_auth_repository.dart';
import 'package:ledger_pulse/presentation/widgets/adaptive_sync_indicator.dart';
import 'package:uuid/uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Supabase Migration & Drift Outbox Pattern Unit Tests', () {
    late AppDatabase db;
    late DriftLedgerRepository repo;
    late SyncEngine syncEngine;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftLedgerRepository(
        db: db,
        autoSync: false,
        currentCompanyId: 'cmp_outbox_test',
        currentUserId: 'usr_supabase_uuid',
      );
      syncEngine = SyncEngine(db: db);
    });

    tearDown(() async {
      repo.dispose();
      syncEngine.dispose();
      await db.close();
    });

    test('Directive 1: Tables enforce UUID v4 and outbox tracking columns', () async {
      final generatedPartyId = const Uuid().v4();
      final newParty = Party(
        id: generatedPartyId,
        name: 'UUID Test Merchant',
        phoneNumber: '+91 98888 12345',
        type: PartyType.customer,
        netBalanceInCents: 5000,
        lastUpdated: DateTime.now(),
      );

      final uuidRegex = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      );
      expect(uuidRegex.hasMatch(generatedPartyId), isTrue);

      await repo.addParty(newParty);

      final row = await (db.select(db.parties)..where((t) => t.id.equals(generatedPartyId))).getSingle();
      expect(row.id, equals(generatedPartyId));
      expect(row.isDeleted, isFalse);
      expect(row.syncStatus, equals(SyncRecordStatus.pending));
      expect(row.updatedAt, isNotNull);
    });

    test('Directive 3: Write operations execute atomic local write + SyncOutbox insertion', () async {
      bool streamFired = false;
      repo.repositoryUpdatesStream.listen((_) => streamFired = true);

      final entryId = const Uuid().v4();
      const partyId = 'party_target_101';

      // Seed party first
      await repo.addParty(
        Party(
          id: partyId,
          name: 'Target Party',
          phoneNumber: '+91 99999 88888',
          type: PartyType.customer,
          netBalanceInCents: 0,
          lastUpdated: DateTime.now(),
        ),
      );

      // Add entry - must execute in a single SQL transaction
      await repo.addEntry(
        LedgerEntry(
          id: entryId,
          partyId: partyId,
          amountInCents: 75000,
          type: EntryType.gave,
          date: DateTime.now(),
          note: 'Offline invoice payment',
        ),
      );

      // Stream must fire immediately for real-time UI without waiting for network
      expect(streamFired, isTrue);

      // Verify local entry table was updated
      final localEntry = await (db.select(db.ledgerEntries)..where((t) => t.id.equals(entryId))).getSingle();
      expect(localEntry.amountInCents, equals(75000));
      expect(localEntry.syncStatus, equals(SyncRecordStatus.pending));
      expect(localEntry.isDeleted, isFalse);

      // Verify SyncOutbox table contains corresponding row
      final outboxItems = await (db.select(db.syncOutbox)..where((t) => t.recordId.equals(entryId))).get();
      expect(outboxItems.length, equals(1));
      final outboxRow = outboxItems.first;
      expect(outboxRow.targetTable, equals('ledger_entries'));
      expect(outboxRow.mutationType, equals('INSERT'));

      final payloadMap = jsonDecode(outboxRow.payload) as Map<String, dynamic>;
      expect(payloadMap['id'], equals(entryId));
      expect(payloadMap['amountInCents'], equals(75000));
      expect(payloadMap['companyId'], equals('cmp_outbox_test'));
    });

    test('Directive 4: pushQueue() formats mutations and removes outbox row upon success', () async {
      // 1. Add party and entry to populate SyncOutbox
      final partyId = const Uuid().v4();
      await repo.addParty(
        Party(
          id: partyId,
          name: 'Sync Push Party',
          phoneNumber: '+91 97777 66666',
          type: PartyType.supplier,
          netBalanceInCents: 0,
          lastUpdated: DateTime.now(),
        ),
      );

      final initialPendingCount = await syncEngine.getPendingCount();
      expect(initialPendingCount, greaterThanOrEqualTo(1));

      // 2. Trigger pushQueue()
      final syncResult = await syncEngine.pushQueue(companyId: 'cmp_outbox_test');
      expect(syncResult.success, isTrue);
      expect(syncResult.itemsPushed, greaterThanOrEqualTo(1));

      // 3. Confirm that upon success, the outbox row is completely removed from SyncOutbox
      final remainingCount = await syncEngine.getPendingCount();
      expect(remainingCount, equals(0));

      // 4. Confirm the local table record was transitioned to synced
      final syncedParty = await (db.select(db.parties)..where((t) => t.id.equals(partyId))).getSingle();
      expect(syncedParty.syncStatus, equals(SyncRecordStatus.synced));
    });

    test('Directive 2: SupabaseAuthRepository manages session token and user ID scoping', () async {
      final authRepo = SupabaseAuthRepository();

      expect(authRepo.isAuthenticated, isFalse);

      // Verify OTP flow with mock/demo code
      await authRepo.sendOtp('+91 98765 43210');
      final verified = await authRepo.verifyOtp('+91 98765 43210', '123456');

      expect(verified, isTrue);
      expect(authRepo.isAuthenticated, isTrue);
      expect(authRepo.currentUserId, isNotNull);
      expect(authRepo.currentSessionToken, isNotNull);

      // Setting repo context scopes local queries with authenticated user ID
      repo.setContext(userId: authRepo.currentUserId);
      expect(repo.currentUserId, equals(authRepo.currentUserId));

      await authRepo.logout();
      expect(authRepo.isAuthenticated, isFalse);
      expect(authRepo.currentUserId, isNull);
    });

    testWidgets('UI/UX Constraint: AdaptiveSyncIndicator adheres to iOS & Android guidelines', (tester) async {
      // Test iOS rendering: Exclusively uses LiquidGlassCard and Cupertino icons
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: const Scaffold(
              body: Center(
                child: AdaptiveSyncIndicator(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LiquidGlassCard), findsOneWidget);
      expect(find.byType(Icon), findsOneWidget);

      // Test Android rendering: Uses Material 3 styling
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData(
              platform: TargetPlatform.android,
              useMaterial3: true,
            ),
            home: const Scaffold(
              body: Center(
                child: AdaptiveSyncIndicator(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Container), findsWidgets);
      expect(find.byType(LiquidGlassCard), findsNothing);
    });
  });
}
