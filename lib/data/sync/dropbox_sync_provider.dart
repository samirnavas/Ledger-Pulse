import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import '../local/database.dart';
import '../models/party_model.dart';
import '../models/sync_model.dart';
import '../models/transaction_model.dart';
import 'sync_engine.dart';

class DropboxSyncProvider extends SyncEngine {
  final String? dropboxAccessToken;
  final http.Client _client;

  DropboxSyncProvider({
    required AppDatabase db,
    this.dropboxAccessToken,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        super(db);

  @override
  Future<SyncResult> syncCompany(String companyId) async {
    setStatus(SyncStatus.syncing);
    try {
      final pushResult = await pushPendingOutbox(companyId);
      final pullResult = await pullRemoteChanges(companyId);

      setStatus(SyncStatus.success);
      return SyncResult(
        success: true,
        itemsPushed: pushResult.itemsPushed,
        itemsPulled: pullResult.itemsPulled,
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

  /// Exports local company state snapshot and uploads to Dropbox.
  @override
  Future<SyncResult> pushPendingOutbox(String companyId) async {
    final pending = await getPendingOutboxItems(companyId);
    
    final parties = await (db.select(db.parties)..where((t) => t.companyId.equals(companyId))).get();
    final entries = await (db.select(db.ledgerEntries)..where((t) => t.companyId.equals(companyId))).get();

    final snapshot = {
      'companyId': companyId,
      'exportedAt': DateTime.now().toIso8601String(),
      'version': '1.0',
      'parties': parties.map((p) => {
        'id': p.id,
        'companyId': p.companyId,
        'name': p.name,
        'phoneNumber': p.phoneNumber,
        'type': p.type.name,
        'netBalanceInCents': p.netBalanceInCents,
        'lastUpdated': p.lastUpdated.toIso8601String(),
        'isDeleted': p.isDeleted,
      }).toList(),
      'entries': entries.map((e) => {
        'id': e.id,
        'companyId': e.companyId,
        'partyId': e.partyId,
        'amountInCents': e.amountInCents,
        'type': e.type.name,
        'date': e.date.toIso8601String(),
        'note': e.note,
        'receiptPhotoUrl': e.receiptPhotoUrl,
        'isVoided': e.isVoided,
      }).toList(),
    };

    final snapshotJson = jsonEncode(snapshot);

    if (dropboxAccessToken != null && dropboxAccessToken!.isNotEmpty && !dropboxAccessToken!.contains('mock')) {
      final uri = Uri.parse('https://content.dropboxapi.com/2/files/upload');
      final path = '/ludgerpulse/backups/company_${companyId}_snapshot.json';

      final response = await _client.post(
        uri,
        headers: {
          'Authorization': 'Bearer $dropboxAccessToken',
          'Dropbox-API-Arg': jsonEncode({
            'path': path,
            'mode': 'overwrite',
            'autorename': false,
            'mute': false,
          }),
          'Content-Type': 'application/octet-stream',
        },
        body: utf8.encode(snapshotJson),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        for (final item in pending) {
          await markItemSuccess(item.id);
        }
      } else {
        throw Exception('Dropbox upload failed: ${response.statusCode} - ${response.body}');
      }
    } else {
      // Mock/Local backup storage mode
      for (final item in pending) {
        await markItemSuccess(item.id);
      }
    }

    return SyncResult(
      success: true,
      itemsPushed: pending.length,
      timestamp: DateTime.now(),
    );
  }

  /// Downloads latest company snapshot from Dropbox and merges with local records.
  @override
  Future<SyncResult> pullRemoteChanges(String companyId) async {
    int pulled = 0;
    if (dropboxAccessToken != null && dropboxAccessToken!.isNotEmpty && !dropboxAccessToken!.contains('mock')) {
      final uri = Uri.parse('https://content.dropboxapi.com/2/files/download');
      final path = '/ludgerpulse/backups/company_${companyId}_snapshot.json';

      final response = await _client.post(
        uri,
        headers: {
          'Authorization': 'Bearer $dropboxAccessToken',
          'Dropbox-API-Arg': jsonEncode({'path': path}),
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        pulled = await _mergeSnapshot(companyId, data);
      }
    }
    return SyncResult(
      success: true,
      itemsPulled: pulled,
      timestamp: DateTime.now(),
    );
  }

  Future<int> _mergeSnapshot(String companyId, Map<String, dynamic> data) async {
    int count = 0;
    if (data['parties'] is List) {
      for (final p in data['parties']) {
        final partyMap = p as Map<String, dynamic>;
        final partyId = partyMap['id'] as String;
        final lastUpdated = DateTime.parse(partyMap['lastUpdated'] as String);

        final existing = await (db.select(db.parties)
              ..where((t) => t.id.equals(partyId) & t.companyId.equals(companyId)))
            .getSingleOrNull();

        if (existing == null || lastUpdated.isAfter(existing.lastUpdated)) {
          await db.into(db.parties).insertOnConflictUpdate(
                PartiesCompanion.insert(
                  id: partyId,
                  companyId: Value(companyId),
                  name: partyMap['name'] as String,
                  phoneNumber: partyMap['phoneNumber'] as String,
                  type: PartyType.values.byName(partyMap['type'] as String),
                  netBalanceInCents: Value(partyMap['netBalanceInCents'] as int),
                  lastUpdated: lastUpdated,
                  isDeleted: Value(partyMap['isDeleted'] as bool? ?? false),
                ),
              );
          count++;
        }
      }
    }

    if (data['entries'] is List) {
      for (final e in data['entries']) {
        final entryMap = e as Map<String, dynamic>;
        final entryId = entryMap['id'] as String;

        await db.into(db.ledgerEntries).insertOnConflictUpdate(
              LedgerEntriesCompanion.insert(
                id: entryId,
                companyId: Value(companyId),
                partyId: entryMap['partyId'] as String,
                amountInCents: entryMap['amountInCents'] as int,
                type: EntryType.values.byName(entryMap['type'] as String),
                date: DateTime.parse(entryMap['date'] as String),
                note: Value(entryMap['note'] as String?),
                receiptPhotoUrl: Value(entryMap['receiptPhotoUrl'] as String?),
                isVoided: Value(entryMap['isVoided'] as bool? ?? false),
              ),
            );
        count++;
      }
    }

    return count;
  }
}
