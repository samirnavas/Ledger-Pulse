import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/local/database.dart';
import '../../data/models/party_model.dart';
import '../../data/models/sync_model.dart';
import '../../data/models/transaction_model.dart';
import '../config/supabase_config.dart';

class SyncEngine {
  final AppDatabase db;
  final SupabaseClient? supabaseClient;
  final http.Client _httpClient;
  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();
  SyncStatus _currentStatus = SyncStatus.idle;

  SyncEngine({
    required this.db,
    SupabaseClient? supabaseClient,
    http.Client? httpClient,
  })  : supabaseClient = supabaseClient ?? _getSafeSupabaseClient(),
        _httpClient = httpClient ?? http.Client();

  static SupabaseClient? _getSafeSupabaseClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  SyncStatus get currentStatus => _currentStatus;
  Stream<SyncStatus> get statusStream => _statusController.stream;

  void setStatus(SyncStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  /// Pushes un-synced mutations from SyncOutbox to Supabase.
  /// Also auto-queues any local records that are marked as pending.
  Future<SyncResult> pushQueue({String? companyId}) async {
    setStatus(SyncStatus.syncing);
    try {
      await _queueUnsyncedLocalRecords(companyId);

      final query = db.select(db.syncOutbox)
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
      final allRows = await query.get();

      final rows = companyId == null
          ? allRows
          : allRows.where((r) => r.companyId == companyId).toList();

      if (rows.isEmpty) {
        setStatus(SyncStatus.success);
        return SyncResult(
          success: true,
          itemsPushed: 0,
          timestamp: DateTime.now(),
        );
      }

      int pushedCount = 0;
      final client = supabaseClient;
      final isRemoteAvailable =
          client != null && SupabaseConfig.isConfigured;

      for (final row in rows) {
        try {
          if (isRemoteAvailable) {
            bool remoteOk = false;
            final payloadMap = jsonDecode(row.payload) as Map<String, dynamic>;

            // 1. Attempt RPC call 'sync_mutation'
            try {
              final rpcRes = await client.rpc(
                'sync_mutation',
                params: {
                  'table_name': row.tableName,
                  'record_id': row.recordId,
                  'mutation_type': row.mutationType,
                  'payload': payloadMap,
                },
              );
              if (rpcRes != null) {
                remoteOk = true;
              }
            } catch (rpcError) {
              debugPrint('RPC sync_mutation notice: $rpcError, attempting direct PostgREST write');
              // 2. Direct PostgREST table write fallback
              final formattedPayload = _formatPayloadForTable(row.tableName, payloadMap);
              if (row.mutationType.toUpperCase() == 'INSERT' ||
                  row.mutationType.toUpperCase() == 'UPDATE' ||
                  row.mutationType.toUpperCase() == 'UPSERT') {
                await client.from(row.tableName).upsert(formattedPayload);
                remoteOk = true;
              } else if (row.mutationType.toUpperCase() == 'DELETE') {
                await client
                    .from(row.tableName)
                    .update({'is_deleted': true, 'sync_status': 'synced'})
                    .eq('id', row.recordId);
                remoteOk = true;
              }
            }

            if (remoteOk) {
              await (db.delete(db.syncOutbox)..where((t) => t.id.equals(row.id))).go();
              await _updateLocalRecordSyncStatus(row.tableName, row.recordId, SyncRecordStatus.synced);
              pushedCount++;
            } else {
              await _updateLocalRecordSyncStatus(row.tableName, row.recordId, SyncRecordStatus.error);
            }
          } else {
            // Local simulation / offline mode
            await (db.delete(db.syncOutbox)..where((t) => t.id.equals(row.id))).go();
            await _updateLocalRecordSyncStatus(row.tableName, row.recordId, SyncRecordStatus.synced);
            pushedCount++;
          }
        } catch (itemErr) {
          debugPrint('Error pushing outbox item ${row.id}: $itemErr');
          await _updateLocalRecordSyncStatus(row.tableName, row.recordId, SyncRecordStatus.error);
        }
      }

      setStatus(SyncStatus.success);
      return SyncResult(
        success: true,
        itemsPushed: pushedCount,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      setStatus(SyncStatus.error);
      return SyncResult(
        success: false,
        errorMessage: e.toString(),
        timestamp: DateTime.now(),
      );
    }
  }

  /// Pulls remote parties and ledger entries from Supabase into local SQLite.
  Future<SyncResult> pullChanges({String? companyId}) async {
    final client = supabaseClient;
    if (client == null || !SupabaseConfig.isConfigured) {
      return SyncResult(success: true, itemsPulled: 0, timestamp: DateTime.now());
    }

    setStatus(SyncStatus.syncing);
    int pulledCount = 0;
    final effectiveCompanyId = companyId ?? 'cmp_default';

    try {
      // 1. Pull Remote Parties
      final remoteParties = await client
          .from('parties')
          .select()
          .eq('company_id', effectiveCompanyId);

      for (final p in (remoteParties as List)) {
        final map = p as Map<String, dynamic>;
        final partyId = map['id'] as String;
        final remoteName = map['name'] as String? ?? '';
        final phone = map['phone_number'] as String? ?? '';
        final typeStr = map['type'] as String? ?? 'customer';
        final netBalance = (map['net_balance_in_cents'] as num?)?.toInt() ?? 0;
        final lastUpdatedStr = map['last_updated'] as String?;
        final isDeleted = map['is_deleted'] as bool? ?? false;
        final lastUpdated = lastUpdatedStr != null ? DateTime.parse(lastUpdatedStr) : DateTime.now();

        // Preserve existing local name if remote name is empty/null
        String name = remoteName;
        if (name.trim().isEmpty) {
          final existing = await (db.select(db.parties)
                ..where((t) => t.id.equals(partyId) & t.companyId.equals(effectiveCompanyId)))
              .getSingleOrNull();
          if (existing != null && existing.name.trim().isNotEmpty) {
            name = existing.name;
          }
        }

        await db.into(db.parties).insertOnConflictUpdate(
          PartiesCompanion(
            id: Value(partyId),
            companyId: Value(effectiveCompanyId),
            name: Value(name),
            phoneNumber: Value(phone),
            type: Value(typeStr == 'supplier' ? PartyType.supplier : PartyType.customer),
            netBalanceInCents: Value(netBalance),
            lastUpdated: Value(lastUpdated),
            isDeleted: Value(isDeleted),
            syncStatus: const Value(SyncRecordStatus.synced),
            updatedAt: Value(DateTime.now()),
          ),
        );
        pulledCount++;
      }

      // 2. Pull Remote Ledger Entries
      final remoteEntries = await client
          .from('ledger_entries')
          .select()
          .eq('company_id', effectiveCompanyId);

      for (final e in (remoteEntries as List)) {
        final map = e as Map<String, dynamic>;
        final entryId = map['id'] as String;
        final partyId = map['party_id'] as String? ?? '';
        final amountInCents = (map['amount_in_cents'] as num?)?.toInt() ?? 0;
        final typeStr = map['type'] as String? ?? 'gave';
        final dateStr = map['date'] as String?;
        final date = dateStr != null ? DateTime.parse(dateStr) : DateTime.now();
        final note = map['note'] as String?;
        final receiptPhotoUrl = map['receipt_photo_url'] as String?;
        final isVoided = map['is_voided'] as bool? ?? false;
        final isDeleted = map['is_deleted'] as bool? ?? false;

        await db.into(db.ledgerEntries).insertOnConflictUpdate(
          LedgerEntriesCompanion(
            id: Value(entryId),
            companyId: Value(effectiveCompanyId),
            partyId: Value(partyId),
            amountInCents: Value(amountInCents),
            type: Value(typeStr == 'got' ? EntryType.got : EntryType.gave),
            date: Value(date),
            note: Value(note),
            receiptPhotoUrl: Value(receiptPhotoUrl),
            isVoided: Value(isVoided),
            isDeleted: Value(isDeleted),
            createdAt: Value(date),
            updatedAt: Value(DateTime.now()),
            syncStatus: const Value(SyncRecordStatus.synced),
          ),
        );
        pulledCount++;
      }

      setStatus(SyncStatus.success);
      return SyncResult(
        success: true,
        itemsPulled: pulledCount,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint('SyncEngine.pullChanges notice: $e');
      setStatus(SyncStatus.error);
      return SyncResult(
        success: false,
        errorMessage: e.toString(),
        timestamp: DateTime.now(),
      );
    }
  }

  /// Full bi-directional sync (push pending queue, then pull remote changes).
  Future<SyncResult> syncAll({String? companyId}) async {
    final pushRes = await pushQueue(companyId: companyId);
    final pullRes = await pullChanges(companyId: companyId);
    return SyncResult(
      success: pushRes.success && pullRes.success,
      itemsPushed: pushRes.itemsPushed,
      itemsPulled: pullRes.itemsPulled,
      timestamp: DateTime.now(),
      errorMessage: pushRes.errorMessage ?? pullRes.errorMessage,
    );
  }

  Future<void> _queueUnsyncedLocalRecords(String? companyId) async {
    try {
      // Find parties with pending sync status that are not in outbox
      final pendingParties = await (db.select(db.parties)
            ..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();

      for (final p in pendingParties) {
        final existingOutbox = await (db.select(db.syncOutbox)
              ..where((t) => t.recordId.equals(p.id))
              ..limit(1))
            .getSingleOrNull();
        if (existingOutbox == null) {
          await db.into(db.syncOutbox).insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              id: 'outbox_${p.id}_${DateTime.now().millisecondsSinceEpoch}',
              targetTable: 'parties',
              recordId: p.id,
              mutationType: 'UPSERT',
              payload: jsonEncode({
                'id': p.id,
                'name': p.name,
                'phoneNumber': p.phoneNumber,
                'type': p.type.name,
                'netBalanceInCents': p.netBalanceInCents,
                'lastUpdated': p.lastUpdated.toIso8601String(),
                'companyId': p.companyId,
                'isDeleted': p.isDeleted,
              }),
            ),
          );
        }
      }

      // Find ledger entries with pending sync status that are not in outbox
      final pendingEntries = await (db.select(db.ledgerEntries)
            ..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();

      for (final e in pendingEntries) {
        final existingOutbox = await (db.select(db.syncOutbox)
              ..where((t) => t.recordId.equals(e.id))
              ..limit(1))
            .getSingleOrNull();
        if (existingOutbox == null) {
          await db.into(db.syncOutbox).insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              id: 'outbox_${e.id}_${DateTime.now().millisecondsSinceEpoch}',
              targetTable: 'ledger_entries',
              recordId: e.id,
              mutationType: 'UPSERT',
              payload: jsonEncode({
                'id': e.id,
                'partyId': e.partyId,
                'amountInCents': e.amountInCents,
                'type': e.type.name,
                'date': e.date.toIso8601String(),
                'note': e.note,
                'receiptPhotoUrl': e.receiptPhotoUrl,
                'isVoided': e.isVoided,
                'companyId': e.companyId,
                'isDeleted': e.isDeleted,
              }),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('SyncEngine auto-queue error: $e');
    }
  }

  Map<String, dynamic> _formatPayloadForTable(String tableName, Map<String, dynamic> payload) {
    final map = <String, dynamic>{};
    for (final entry in payload.entries) {
      final key = entry.key;
      final val = entry.value;

      if (key == 'companyId') {
        map['company_id'] = val;
      } else if (key == 'partyId') {
        map['party_id'] = val;
      } else if (key == 'amountInCents') {
        map['amount_in_cents'] = val;
      } else if (key == 'receiptPhotoUrl') {
        map['receipt_photo_url'] = val;
      } else if (key == 'isVoided') {
        map['is_voided'] = val;
      } else if (key == 'isDeleted') {
        map['is_deleted'] = val;
      } else if (key == 'phoneNumber') {
        map['phone_number'] = val;
      } else if (key == 'netBalanceInCents') {
        map['net_balance_in_cents'] = val;
      } else if (key == 'lastUpdated') {
        map['last_updated'] = val;
      } else if (key != 'runningBalanceInCents') {
        map[key] = val;
      }
    }
    map['sync_status'] = 'synced';
    map['updated_at'] = DateTime.now().toIso8601String();
    return map;
  }

  Future<void> _updateLocalRecordSyncStatus(
    String tableName,
    String recordId,
    SyncRecordStatus status,
  ) async {
    try {
      if (tableName == 'parties') {
        await (db.update(db.parties)..where((t) => t.id.equals(recordId))).write(
          PartiesCompanion(syncStatus: Value(status)),
        );
      } else if (tableName == 'ledger_entries') {
        await (db.update(db.ledgerEntries)..where((t) => t.id.equals(recordId))).write(
          LedgerEntriesCompanion(syncStatus: Value(status)),
        );
      } else if (tableName == 'companies') {
        await (db.update(db.companies)..where((t) => t.id.equals(recordId))).write(
          CompaniesCompanion(syncStatus: Value(status)),
        );
      }
    } catch (_) {}
  }

  Future<int> getPendingCount({String? companyId}) async {
    final query = db.select(db.syncOutbox);
    final all = await query.get();
    if (companyId == null) return all.length;
    return all.where((r) => r.companyId == companyId).length;
  }

  Stream<int> watchPendingCount({String? companyId}) {
    return db.select(db.syncOutbox).watch().map((list) {
      if (companyId == null) return list.length;
      return list.where((r) => r.companyId == companyId).length;
    });
  }

  void dispose() {
    _statusController.close();
    _httpClient.close();
  }
}
