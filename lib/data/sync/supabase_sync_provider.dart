import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import '../../core/config/supabase_config.dart';
import '../local/database.dart';
import '../models/party_model.dart';
import '../models/sync_model.dart';
import '../models/transaction_model.dart';
import 'sync_engine.dart';

class SupabaseSyncProvider extends SyncEngine {
  final String supabaseUrl;
  final String supabaseAnonKey;
  final http.Client _client;

  SupabaseSyncProvider({
    required AppDatabase db,
    String? supabaseUrl,
    String? supabaseAnonKey,
    http.Client? client,
  })  : supabaseUrl = supabaseUrl ?? SupabaseConfig.url,
        supabaseAnonKey = supabaseAnonKey ?? SupabaseConfig.anonKey,
        _client = client ?? http.Client(),
        super(db);

  @override
  Future<SyncResult> syncCompany(String companyId) async {
    setStatus(SyncStatus.syncing);
    try {
      final pushResult = await pushPendingOutbox(companyId);
      final pullResult = await pullRemoteChanges(companyId);

      final totalPushed = pushResult.itemsPushed;
      final totalPulled = pullResult.itemsPulled;

      setStatus(SyncStatus.success);
      return SyncResult(
        success: true,
        itemsPushed: totalPushed,
        itemsPulled: totalPulled,
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

  @override
  Future<SyncResult> pushPendingOutbox(String companyId) async {
    final pending = await getPendingOutboxItems(companyId);
    if (pending.isEmpty) {
      return SyncResult(success: true, itemsPushed: 0, timestamp: DateTime.now());
    }

    int pushedCount = 0;

    for (final item in pending) {
      try {
        // If real endpoint configured, execute REST HTTP request
        if (!supabaseUrl.contains('mock')) {
          final uri = Uri.parse('$supabaseUrl/rest/v1/rpc/sync_mutation');
          final response = await _client.post(
            uri,
            headers: {
              'apikey': supabaseAnonKey,
              'Authorization': 'Bearer $supabaseAnonKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(item.toMap()),
          );

          if (response.statusCode >= 200 && response.statusCode < 300) {
            await markItemSuccess(item.id);
            pushedCount++;
          } else {
            await markItemFailed(item.id, 'HTTP ${response.statusCode}: ${response.body}');
          }
        } else {
          // Simulation for offline/mock backend
          await markItemSuccess(item.id);
          pushedCount++;
        }
      } catch (e) {
        await markItemFailed(item.id, e.toString());
      }
    }

    return SyncResult(
      success: true,
      itemsPushed: pushedCount,
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<SyncResult> pullRemoteChanges(String companyId) async {
    // Pull delta changes from Supabase PostgreSQL tables
    int pulledCount = 0;
    try {
      if (!supabaseUrl.contains('mock')) {
        final uri = Uri.parse('$supabaseUrl/rest/v1/rpc/get_company_deltas?company_id=$companyId');
        final response = await _client.get(
          uri,
          headers: {
            'apikey': supabaseAnonKey,
            'Authorization': 'Bearer $supabaseAnonKey',
          },
        );

        if (response.statusCode == 200) {
          final Map<String, dynamic> body = jsonDecode(response.body);
          if (body['parties'] is List) {
            for (final p in body['parties']) {
              final party = Party.fromMap(p as Map<String, dynamic>);
              await _applyRemoteParty(companyId, party);
              pulledCount++;
            }
          }
          if (body['entries'] is List) {
            for (final e in body['entries']) {
              final entry = LedgerEntry.fromMap(e as Map<String, dynamic>);
              await _applyRemoteEntry(companyId, entry);
              pulledCount++;
            }
          }
        }
      }
    } catch (_) {
      // In offline scenario or unconfigured remote, keep existing local state
    }

    return SyncResult(
      success: true,
      itemsPulled: pulledCount,
      timestamp: DateTime.now(),
    );
  }

  Future<void> _applyRemoteParty(String companyId, Party party) async {
    final existing = await (db.select(db.parties)
          ..where((t) => t.id.equals(party.id) & t.companyId.equals(companyId)))
        .getSingleOrNull();

    // Last-Write-Wins (LWW) conflict resolution
    if (existing == null || party.lastUpdated.isAfter(existing.lastUpdated)) {
      await db.into(db.parties).insertOnConflictUpdate(
            PartiesCompanion.insert(
              id: party.id,
              companyId: Value(companyId),
              name: party.name,
              phoneNumber: party.phoneNumber,
              type: party.type,
              netBalanceInCents: Value(party.netBalanceInCents),
              lastUpdated: party.lastUpdated,
            ),
          );
    }
  }

  Future<void> _applyRemoteEntry(String companyId, LedgerEntry entry) async {
    await db.into(db.ledgerEntries).insertOnConflictUpdate(
          LedgerEntriesCompanion.insert(
            id: entry.id,
            companyId: Value(companyId),
            partyId: entry.partyId,
            amountInCents: entry.amountInCents,
            type: entry.type,
            date: entry.date,
            note: Value(entry.note),
            receiptPhotoUrl: Value(entry.receiptPhotoUrl),
            isVoided: Value(entry.isVoided),
            createdAt: Value(entry.date),
          ),
        );
  }
}
