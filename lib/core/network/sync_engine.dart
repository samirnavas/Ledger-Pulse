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

/// Test double / in-memory remote store for verifying push/pull/wipe-restore cycles
class FakeRemoteSyncBackend {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {};

  void upsert(String table, String id, Map<String, dynamic> data, {bool isDeleted = false}) {
    tables.putIfAbsent(table, () => {})[id] = {
      ...data,
      'id': id,
      'is_deleted': isDeleted,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  List<Map<String, dynamic>> getTableRows(String table, {String? companyId}) {
    final map = tables[table];
    if (map == null) return [];
    final list = map.values.toList();
    if (companyId == null) return list;
    return list.where((r) => r['company_id'] == companyId || r['companyId'] == companyId).toList();
  }

  void clear() {
    tables.clear();
  }
}

class SyncEngine {
  final AppDatabase db;
  final SupabaseClient? _explicitClient;
  final http.Client _httpClient;
  final bool simulateSyncForTesting;
  final FakeRemoteSyncBackend? fakeRemoteStore;
  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();
  SyncStatus _currentStatus = SyncStatus.idle;

  SyncEngine({
    required this.db,
    SupabaseClient? supabaseClient,
    http.Client? httpClient,
    this.simulateSyncForTesting = false,
    this.fakeRemoteStore,
  })  : _explicitClient = supabaseClient,
        _httpClient = httpClient ?? http.Client();

  SupabaseClient? get supabaseClient {
    if (_explicitClient != null) return _explicitClient;
    return _getSafeSupabaseClient();
  }

  static SupabaseClient? _getSafeSupabaseClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static bool _toBool(dynamic val, {bool defaultValue = false}) {
    if (val == null) return defaultValue;
    if (val is bool) return val;
    if (val is num) return val != 0;
    if (val is String) {
      final lower = val.toLowerCase().trim();
      return lower == 'true' || lower == '1' || lower == 't';
    }
    return defaultValue;
  }

  SyncStatus get currentStatus => _currentStatus;
  Stream<SyncStatus> get statusStream => _statusController.stream;

  void setStatus(SyncStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  bool get isRemoteConfigured {
    final client = supabaseClient;
    return client != null && SupabaseConfig.isConfigured;
  }

  /// Fast reachability probe to check if the Supabase endpoint is live.
  Future<bool> isRemoteReachable() async {
    if (simulateSyncForTesting) return true;
    if (!isRemoteConfigured) return false;
    try {
      final uri = Uri.parse('${SupabaseConfig.url}/rest/v1/');
      final response = await _httpClient.get(
        uri,
        headers: {
          'apikey': SupabaseConfig.anonKey,
        },
      ).timeout(const Duration(milliseconds: 3500));
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// One-time repair: Reset records marked syncStatus = error back to pending.
  Future<void> _repairFailedSyncRecords() async {
    try {
      await (db.update(db.vouchers)..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .write(const VouchersCompanion(syncStatus: Value(SyncRecordStatus.pending)));
      await (db.update(db.budgets)..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .write(const BudgetsCompanion(syncStatus: Value(SyncRecordStatus.pending)));
      await (db.update(db.recurringRules)..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .write(const RecurringRulesCompanion(syncStatus: Value(SyncRecordStatus.pending)));
      await (db.update(db.accounts)..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .write(const AccountsCompanion(syncStatus: Value(SyncRecordStatus.pending)));
      await (db.update(db.journals)..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .write(const JournalsCompanion(syncStatus: Value(SyncRecordStatus.pending)));
      await (db.update(db.journalLines)..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .write(const JournalLinesCompanion(syncStatus: Value(SyncRecordStatus.pending)));
    } catch (e) {
      debugPrint('SyncEngine repair failed records notice: $e');
    }
  }

  /// Write a derived list of the user's company ids and names into user_profiles.companies_json
  /// (write-only, never read back as source of truth locally).
  Future<void> _deriveAndSyncUserProfileCompaniesJson() async {
    try {
      final activeCompanies = await (db.select(db.companies)..where((t) => t.isDeleted.equals(false))).get();
      if (activeCompanies.isEmpty) return;

      final derivedList = activeCompanies.map((c) => {
        'id': c.id,
        'name': c.name,
        'legal_name': c.legalName,
        'mode': c.mode,
      }).toList();
      final jsonStr = jsonEncode(derivedList);

      await db.customStatement(
        'UPDATE user_profiles SET companies_json = ? WHERE is_deleted = 0',
        [jsonStr],
      );
    } catch (e) {
      debugPrint('SyncEngine write-only companies_json error: $e');
    }
  }

  int _tableOrder(String table) {
    switch (table) {
      case 'companies':
        return 1;
      case 'user_profiles':
      case 'profiles':
        return 2;
      case 'accounts':
        return 3;
      case 'parties':
        return 4;
      case 'vouchers':
        return 5;
      case 'journals':
        return 6;
      case 'journal_lines':
        return 7;
      case 'ledger_entries':
        return 8;
      case 'budgets':
        return 9;
      case 'recurring_rules':
        return 10;
      default:
        return 99;
    }
  }

  /// Pushes un-synced mutations from SyncOutbox to Supabase.
  /// Also auto-queues any local records that are marked as pending.
  Future<SyncResult> pushQueue({String? companyId}) async {
    setStatus(SyncStatus.syncing);
    try {
      // 1. Repair any previously failed sync records
      await _repairFailedSyncRecords();

      // 2. Write-only derived company IDs to user_profiles.companies_json
      await _deriveAndSyncUserProfileCompaniesJson();

      // 3. Auto-queue unsynced local records
      await _queueUnsyncedLocalRecords(companyId);

      final query = db.select(db.syncOutbox)
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
      final allRows = await query.get();

      final rows = companyId == null
          ? allRows
          : allRows.where((r) => r.companyId == companyId).toList();

      if (rows.isEmpty) {
        setStatus(SyncStatus.idle);
        return SyncResult(
          success: true,
          itemsPushed: 0,
          timestamp: DateTime.now(),
        );
      }

      // Respect parent-before-child ordering: accounts -> journals -> journal_lines etc.
      rows.sort((a, b) {
        final orderA = _tableOrder(a.tableName);
        final orderB = _tableOrder(b.tableName);
        if (orderA != orderB) return orderA.compareTo(orderB);
        return a.createdAt.compareTo(b.createdAt);
      });

      // In unit-test simulation mode, process through fake remote store if available
      if (simulateSyncForTesting) {
        for (final row in rows) {
          if (fakeRemoteStore != null) {
            final payloadMap = jsonDecode(row.payload) as Map<String, dynamic>;
            final formatted = _formatPayloadForTable(row.tableName, payloadMap);
            fakeRemoteStore!.upsert(
              row.tableName,
              row.recordId,
              formatted,
              isDeleted: row.mutationType.toUpperCase() == 'DELETE',
            );
          }
          await (db.delete(db.syncOutbox)..where((t) => t.id.equals(row.id))).go();
          await _updateLocalRecordSyncStatus(row.tableName, row.recordId, SyncRecordStatus.synced);
        }
        setStatus(SyncStatus.success);
        return SyncResult(
          success: true,
          itemsPushed: rows.length,
          timestamp: DateTime.now(),
        );
      }

      final client = supabaseClient;
      if (!isRemoteConfigured) {
        debugPrint('SyncEngine pushQueue: Remote not configured. Preserving ${rows.length} items in local outbox.');
        setStatus(SyncStatus.idle);
        return SyncResult(
          success: true,
          itemsPushed: 0,
          timestamp: DateTime.now(),
        );
      }

      final reachable = await isRemoteReachable();
      if (!reachable) {
        debugPrint('SyncEngine pushQueue: Remote host unreachable / offline. Preserving ${rows.length} items in local outbox.');
        setStatus(SyncStatus.idle);
        return SyncResult(
          success: true,
          itemsPushed: 0,
          timestamp: DateTime.now(),
        );
      }

      int pushedCount = 0;
      for (final row in rows) {
        try {
          bool remoteOk = false;
          final payloadMap = jsonDecode(row.payload) as Map<String, dynamic>;

          // 1. Attempt RPC call 'sync_mutation'
          try {
            final rpcRes = await client!.rpc(
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
              await client!.from(row.tableName).upsert(formattedPayload);
              remoteOk = true;
            } else if (row.mutationType.toUpperCase() == 'DELETE') {
              await client!
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
            debugPrint('SyncEngine: Push unacknowledged for item ${row.id}, keeping pending.');
          }
        } catch (itemErr) {
          final errStr = itemErr.toString().toLowerCase();
          final isNetworkIssue = errStr.contains('socketexception') ||
              errStr.contains('failed host lookup') ||
              errStr.contains('connection refused') ||
              errStr.contains('clientexception') ||
              errStr.contains('postgrestexception') ||
              errStr.contains('network is unreachable') ||
              errStr.contains('timeout');

          if (isNetworkIssue) {
            debugPrint('SyncEngine network notice during push: $itemErr. Keeping outbox items pending for retry.');
            break; // Stop trying subsequent items while offline; keep them as pending
          } else {
            debugPrint('Error pushing outbox item ${row.id}: $itemErr');
            await _updateLocalRecordSyncStatus(row.tableName, row.recordId, SyncRecordStatus.error);
            // Non-fatal for the whole batch; continue with next item
          }
        }
      }

      setStatus(pushedCount > 0 ? SyncStatus.success : SyncStatus.idle);
      return SyncResult(
        success: true,
        itemsPushed: pushedCount,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      final isNetwork = errStr.contains('socketexception') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('clientexception') ||
          errStr.contains('postgrestexception');
      if (isNetwork) {
        setStatus(SyncStatus.idle);
        return SyncResult(
          success: true,
          itemsPushed: 0,
          errorMessage: 'Offline: Remote host unreachable',
          timestamp: DateTime.now(),
        );
      }
      setStatus(SyncStatus.error);
      return SyncResult(
        success: false,
        errorMessage: e.toString(),
        timestamp: DateTime.now(),
      );
    }
  }

  /// Pulls remote companies, accounts, parties, ledger entries, vouchers, journals, budgets,
  /// and recurring rules from Supabase into local SQLite.
  Future<SyncResult> pullChanges({String? companyId}) async {
    if (simulateSyncForTesting && fakeRemoteStore == null) {
      setStatus(SyncStatus.success);
      return SyncResult(success: true, itemsPulled: 0, timestamp: DateTime.now());
    }

    final client = supabaseClient;
    final usingFake = simulateSyncForTesting && fakeRemoteStore != null;

    if (!usingFake) {
      if (client == null || !SupabaseConfig.isConfigured) {
        setStatus(SyncStatus.idle);
        return SyncResult(success: true, itemsPulled: 0, timestamp: DateTime.now());
      }

      final reachable = await isRemoteReachable();
      if (!reachable) {
        debugPrint('SyncEngine pullChanges: Remote host unreachable / offline. Skipping remote pull.');
        setStatus(SyncStatus.idle);
        return SyncResult(success: true, itemsPulled: 0, timestamp: DateTime.now());
      }
    }

    setStatus(SyncStatus.syncing);
    int pulledCount = 0;

    try {
      // 1. Pull Remote Companies
      try {
        final dynamic rawCompanies = usingFake
            ? fakeRemoteStore!.getTableRows('companies')
            : await client!.from('companies').select();

        for (final c in (rawCompanies as List)) {
          final map = c as Map<String, dynamic>;
          final compId = map['id'] as String;
          final name = map['name'] as String? ?? 'Ledger Pulse Enterprise';
          final legalName = (map['legal_name'] ?? map['legalName'] ?? name) as String;
          final gstin = map['gstin'] as String?;
          final stateCode = (map['state_code'] ?? map['stateCode']) as String?;
          final dealerType = (map['dealer_type'] ?? map['dealerType']) as String? ?? 'regular';
          final currencyCode = (map['currency_code'] ?? map['currencyCode']) as String? ?? 'INR';
          final address = map['address'] as String?;
          final email = map['email'] as String?;
          final phone = (map['phone_number'] ?? map['phoneNumber']) as String?;
          final logoUrl = (map['logo_url'] ?? map['logoUrl']) as String?;
          final signatureUrl = (map['signature_url'] ?? map['signatureUrl']) as String?;
          final signatoryName = (map['signatory_name'] ?? map['signatoryName']) as String?;
          final bankName = (map['bank_name'] ?? map['bankName']) as String?;
          final bankAccountNumber = (map['bank_account_number'] ?? map['bankAccountNumber']) as String?;
          final bankIfsc = (map['bank_ifsc'] ?? map['bankIfsc']) as String?;
          final upiId = (map['upi_id'] ?? map['upiId']) as String?;

          final isCloudSyncEnabled = _toBool(map['is_cloud_sync_enabled'] ?? map['isCloudSyncEnabled'], defaultValue: true);
          final isDropboxSyncEnabled = _toBool(map['is_dropbox_sync_enabled'] ?? map['isDropboxSyncEnabled'], defaultValue: false);
          final isActive = _toBool(map['is_active'] ?? map['isActive'], defaultValue: true);
          final mode = map['mode'] as String? ?? 'ledger';

          // Handle enabled_modules as JSON array or string
          final dynamic rawModules = map['enabled_modules'] ??
              map['enabled_modules_json'] ??
              map['enabledModules'] ??
              map['enabledModulesJson'];
          String? enabledModulesJson;
          if (rawModules != null) {
            if (rawModules is List) {
              enabledModulesJson = jsonEncode(rawModules);
            } else if (rawModules is String && rawModules.trim().isNotEmpty && rawModules != 'null') {
              enabledModulesJson = rawModules;
            }
          }

          final isDeleted = _toBool(map['is_deleted'] ?? map['isDeleted'], defaultValue: false);
          final createdAtStr = map['created_at'] as String?;
          final updatedAtStr = map['updated_at'] as String?;

          await db.into(db.companies).insertOnConflictUpdate(
            CompaniesCompanion(
              id: Value(compId),
              name: Value(name),
              legalName: Value(legalName),
              gstin: Value(gstin),
              stateCode: Value(stateCode),
              dealerType: Value(dealerType),
              currencyCode: Value(currencyCode),
              address: Value(address),
              email: Value(email),
              phoneNumber: Value(phone),
              logoUrl: Value(logoUrl),
              signatureUrl: Value(signatureUrl),
              signatoryName: Value(signatoryName),
              bankName: Value(bankName),
              bankAccountNumber: Value(bankAccountNumber),
              bankIfsc: Value(bankIfsc),
              upiId: Value(upiId),
              isCloudSyncEnabled: Value(isCloudSyncEnabled),
              isDropboxSyncEnabled: Value(isDropboxSyncEnabled),
              isActive: Value(isActive),
              mode: Value(mode),
              enabledModulesJson: Value(enabledModulesJson),
              isDeleted: Value(isDeleted),
              createdAt: Value(createdAtStr != null ? DateTime.parse(createdAtStr) : DateTime.now()),
              updatedAt: Value(updatedAtStr != null ? DateTime.parse(updatedAtStr) : DateTime.now()),
              syncStatus: const Value(SyncRecordStatus.synced),
            ),
          );
          pulledCount++;
        }
      } catch (compErr) {
        debugPrint('SyncEngine pull companies notice: $compErr');
      }

      // 2. Pull Remote User Profiles
      try {
        final dynamic remoteProfiles = usingFake
            ? fakeRemoteStore!.getTableRows('user_profiles')
            : await client!.from('user_profiles').select();

        for (final p in (remoteProfiles as List)) {
          final map = p as Map<String, dynamic>;
          final profId = map['id'] as String;
          final name = map['name'] as String? ?? 'User';
          final phone = (map['phone_number'] ?? map['phoneNumber']) as String? ?? '';
          final email = map['email'] as String? ?? '';
          final businessName = (map['business_name'] ?? map['businessName']) as String?;
          final address = map['address'] as String?;
          final gstin = map['gstin'] as String?;
          final businessType = (map['business_type'] ?? map['businessType']) as String?;
          final bankName = (map['bank_name'] ?? map['bankName']) as String?;
          final bankAccountNumber = (map['bank_account_number'] ?? map['bankAccountNumber']) as String?;
          final bankIfsc = (map['bank_ifsc'] ?? map['bankIfsc']) as String?;
          final upiId = (map['upi_id'] ?? map['upiId']) as String?;
          final activeCompanyId = (map['active_company_id'] ?? map['activeCompanyId']) as String? ?? 'cmp_default';
          final role = map['role'] as String? ?? 'admin';
          final companiesJson = map['companies_json'] != null
              ? (map['companies_json'] is String ? map['companies_json'] as String : jsonEncode(map['companies_json']))
              : (map['companies'] != null ? jsonEncode(map['companies']) : null);
          final isDeleted = _toBool(map['is_deleted'] ?? map['isDeleted'], defaultValue: false);
          final createdAtStr = map['created_at'] as String?;
          final updatedAtStr = map['updated_at'] as String?;

          await db.into(db.userProfiles).insertOnConflictUpdate(
            UserProfilesCompanion(
              id: Value(profId),
              name: Value(name),
              phoneNumber: Value(phone),
              email: Value(email),
              businessName: Value(businessName),
              address: Value(address),
              gstin: Value(gstin),
              businessType: Value(businessType),
              bankName: Value(bankName),
              bankAccountNumber: Value(bankAccountNumber),
              bankIfsc: Value(bankIfsc),
              upiId: Value(upiId),
              activeCompanyId: Value(activeCompanyId),
              role: Value(role),
              companiesJson: Value(companiesJson),
              isDeleted: Value(isDeleted),
              createdAt: Value(createdAtStr != null ? DateTime.parse(createdAtStr) : DateTime.now()),
              updatedAt: Value(updatedAtStr != null ? DateTime.parse(updatedAtStr) : DateTime.now()),
              syncStatus: const Value(SyncRecordStatus.synced),
            ),
          );
          pulledCount++;
        }
      } catch (profErr) {
        debugPrint('SyncEngine pull user_profiles notice: $profErr');
      }

      // Determine all company IDs to pull child records for
      final targetCompanyIds = <String>{};
      if (companyId != null && companyId.isNotEmpty) {
        targetCompanyIds.add(companyId);
      } else {
        final localComps = await (db.select(db.companies)..where((t) => t.isDeleted.equals(false))).get();
        for (final comp in localComps) {
          targetCompanyIds.add(comp.id);
        }
      }
      if (targetCompanyIds.isEmpty) {
        targetCompanyIds.add('cmp_default');
      }

      for (final effCompanyId in targetCompanyIds) {
        // 3. Pull Remote Accounts (Parent of vouchers & journal lines)
        try {
          final dynamic remoteAccounts = usingFake
              ? fakeRemoteStore!.getTableRows('accounts', companyId: effCompanyId)
              : await client!.from('accounts').select().eq('company_id', effCompanyId);

          for (final a in (remoteAccounts as List)) {
            final map = a as Map<String, dynamic>;
            final aId = map['id'] as String;
            final code = map['code'] as String? ?? '';
            final aName = map['name'] as String? ?? '';
            final type = map['type'] as String? ?? 'asset';
            final parentId = (map['parent_account_id'] ?? map['parentAccountId']) as String?;
            final isSystem = _toBool(map['is_system'] ?? map['isSystem'], defaultValue: false);
            final isActive = _toBool(map['is_active'] ?? map['isActive'], defaultValue: true);
            final description = map['description'] as String?;
            final balance = ((map['current_balance_in_cents'] ?? map['currentBalanceInCents']) as num?)?.toInt() ?? 0;
            final isDeleted = _toBool(map['is_deleted'] ?? map['isDeleted'], defaultValue: false);
            final createdAtStr = map['created_at'] as String?;
            final updatedAtStr = map['updated_at'] as String?;

            await db.into(db.accounts).insertOnConflictUpdate(
              AccountsCompanion(
                id: Value(aId),
                companyId: Value(effCompanyId),
                code: Value(code),
                name: Value(aName),
                type: Value(type),
                parentAccountId: Value(parentId),
                isSystem: Value(isSystem),
                isActive: Value(isActive),
                description: Value(description),
                currentBalanceInCents: Value(balance),
                isDeleted: Value(isDeleted),
                createdAt: Value(createdAtStr != null ? DateTime.parse(createdAtStr) : DateTime.now()),
                updatedAt: Value(updatedAtStr != null ? DateTime.parse(updatedAtStr) : DateTime.now()),
                syncStatus: const Value(SyncRecordStatus.synced),
              ),
            );
            pulledCount++;
          }
        } catch (accErr) {
          debugPrint('SyncEngine pull accounts notice: $accErr');
        }

        // 4. Pull Remote Parties
        try {
          final dynamic remoteParties = usingFake
              ? fakeRemoteStore!.getTableRows('parties', companyId: effCompanyId)
              : await client!.from('parties').select().eq('company_id', effCompanyId);

          for (final p in (remoteParties as List)) {
            final map = p as Map<String, dynamic>;
            final partyId = map['id'] as String;
            final remoteName = map['name'] as String? ?? '';
            final phone = (map['phone_number'] ?? map['phoneNumber']) as String? ?? '';
            final typeStr = map['type'] as String? ?? 'customer';
            final netBalance = ((map['net_balance_in_cents'] ?? map['netBalanceInCents']) as num?)?.toInt() ?? 0;
            final lastUpdatedStr = (map['last_updated'] ?? map['lastUpdated']) as String?;
            final isDeleted = _toBool(map['is_deleted'] ?? map['isDeleted'], defaultValue: false);
            final lastUpdated = lastUpdatedStr != null ? DateTime.parse(lastUpdatedStr) : DateTime.now();

            String name = remoteName;
            if (name.trim().isEmpty) {
              final existing = await (db.select(db.parties)
                    ..where((t) => t.id.equals(partyId) & t.companyId.equals(effCompanyId)))
                  .getSingleOrNull();
              if (existing != null && existing.name.trim().isNotEmpty) {
                name = existing.name;
              }
            }

            await db.into(db.parties).insertOnConflictUpdate(
              PartiesCompanion(
                id: Value(partyId),
                companyId: Value(effCompanyId),
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
        } catch (partyErr) {
          debugPrint('SyncEngine pull parties notice: $partyErr');
        }

        // 5. Pull Remote Ledger Entries
        try {
          final dynamic remoteEntries = usingFake
              ? fakeRemoteStore!.getTableRows('ledger_entries', companyId: effCompanyId)
              : await client!.from('ledger_entries').select().eq('company_id', effCompanyId);

          for (final e in (remoteEntries as List)) {
            final map = e as Map<String, dynamic>;
            final entryId = map['id'] as String;
            final partyId = (map['party_id'] ?? map['partyId']) as String? ?? '';
            final amountInCents = ((map['amount_in_cents'] ?? map['amountInCents']) as num?)?.toInt() ?? 0;
            final typeStr = map['type'] as String? ?? 'gave';
            final dateStr = map['date'] as String?;
            final date = dateStr != null ? DateTime.parse(dateStr) : DateTime.now();
            final note = map['note'] as String?;
            final receiptPhotoUrl = (map['receipt_photo_url'] ?? map['receiptPhotoUrl']) as String?;
            final isVoided = _toBool(map['is_voided'] ?? map['isVoided'], defaultValue: false);
            final isDeleted = _toBool(map['is_deleted'] ?? map['isDeleted'], defaultValue: false);

            await db.into(db.ledgerEntries).insertOnConflictUpdate(
              LedgerEntriesCompanion(
                id: Value(entryId),
                companyId: Value(effCompanyId),
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
        } catch (entryErr) {
          debugPrint('SyncEngine pull ledger_entries notice: $entryErr');
        }

        // 6. Pull Remote Vouchers
        try {
          final dynamic remoteVouchers = usingFake
              ? fakeRemoteStore!.getTableRows('vouchers', companyId: effCompanyId)
              : await client!.from('vouchers').select().eq('company_id', effCompanyId);

          for (final v in (remoteVouchers as List)) {
            final map = v as Map<String, dynamic>;
            final vId = map['id'] as String;
            final vNum = (map['voucher_number'] ?? map['voucherNumber']) as String? ?? 'VCH-001';
            final type = map['type'] as String? ?? 'sales';
            final dateStr = map['date'] as String?;
            final dueDateStr = (map['due_date'] ?? map['dueDate']) as String?;
            final partyId = (map['party_id'] ?? map['partyId']) as String?;
            final partyName = (map['party_name'] ?? map['partyName']) as String?;
            final status = map['status'] as String? ?? 'posted';
            final paymentMode = (map['payment_mode'] ?? map['paymentMode']) as String? ?? 'cash';
            final subtotal = ((map['subtotal_in_cents'] ?? map['subtotalInCents']) as num?)?.toInt() ?? 0;
            final tax = ((map['tax_in_cents'] ?? map['taxInCents']) as num?)?.toInt() ?? 0;
            final discount = ((map['discount_in_cents'] ?? map['discountInCents']) as num?)?.toInt() ?? 0;
            final total = ((map['total_amount_in_cents'] ?? map['totalAmountInCents']) as num?)?.toInt() ?? 0;
            final narration = map['narration'] as String?;
            final refNum = (map['reference_number'] ?? map['referenceNumber']) as String?;
            final srcId = (map['source_voucher_id'] ?? map['sourceVoucherId']) as String?;
            final receiptUrl = (map['receipt_photo_url'] ?? map['receiptPhotoUrl']) as String?;
            final itemsJson = map['items_json'] != null
                ? (map['items_json'] is String ? map['items_json'] as String : jsonEncode(map['items_json']))
                : (map['itemsJson'] != null
                    ? (map['itemsJson'] is String ? map['itemsJson'] as String : jsonEncode(map['itemsJson']))
                    : null);
            final categoryAccountId = (map['category_account_id'] ?? map['categoryAccountId']) as String?;
            final walletAccountId = (map['wallet_account_id'] ?? map['walletAccountId']) as String?;
            final toWalletAccountId = (map['to_wallet_account_id'] ?? map['toWalletAccountId']) as String?;
            final isDeleted = _toBool(map['is_deleted'] ?? map['isDeleted'], defaultValue: false);
            final createdAtStr = map['created_at'] as String?;
            final updatedAtStr = map['updated_at'] as String?;

            await db.into(db.vouchers).insertOnConflictUpdate(
              VouchersCompanion(
                id: Value(vId),
                companyId: Value(effCompanyId),
                voucherNumber: Value(vNum),
                type: Value(type),
                date: Value(dateStr != null ? DateTime.parse(dateStr) : DateTime.now()),
                dueDate: Value(dueDateStr != null ? DateTime.parse(dueDateStr) : null),
                partyId: Value(partyId),
                partyName: Value(partyName),
                status: Value(status),
                paymentMode: Value(paymentMode),
                subtotalInCents: Value(subtotal),
                taxInCents: Value(tax),
                discountInCents: Value(discount),
                totalAmountInCents: Value(total),
                narration: Value(narration),
                referenceNumber: Value(refNum),
                sourceVoucherId: Value(srcId),
                receiptPhotoUrl: Value(receiptUrl),
                itemsJson: Value(itemsJson),
                categoryAccountId: Value(categoryAccountId),
                walletAccountId: Value(walletAccountId),
                toWalletAccountId: Value(toWalletAccountId),
                isDeleted: Value(isDeleted),
                createdAt: Value(createdAtStr != null ? DateTime.parse(createdAtStr) : DateTime.now()),
                updatedAt: Value(updatedAtStr != null ? DateTime.parse(updatedAtStr) : DateTime.now()),
                syncStatus: const Value(SyncRecordStatus.synced),
              ),
            );
            pulledCount++;
          }
        } catch (vErr) {
          debugPrint('SyncEngine pull vouchers notice: $vErr');
        }

        // 7. Pull Remote Journals
        try {
          final dynamic remoteJournals = usingFake
              ? fakeRemoteStore!.getTableRows('journals', companyId: effCompanyId)
              : await client!.from('journals').select().eq('company_id', effCompanyId);

          for (final j in (remoteJournals as List)) {
            final map = j as Map<String, dynamic>;
            final jId = map['id'] as String;
            final jNum = (map['journal_number'] ?? map['journalNumber']) as String? ?? 'JRN-001';
            final voucherId = (map['voucher_id'] ?? map['voucherId']) as String?;
            final dateStr = map['date'] as String?;
            final narration = map['narration'] as String?;
            final totalAmount = ((map['total_amount_in_cents'] ?? map['totalAmountInCents']) as num?)?.toInt() ?? 0;
            final status = map['status'] as String? ?? 'posted';
            final isDeleted = _toBool(map['is_deleted'] ?? map['isDeleted'], defaultValue: false);
            final createdAtStr = map['created_at'] as String?;
            final updatedAtStr = map['updated_at'] as String?;

            await db.into(db.journals).insertOnConflictUpdate(
              JournalsCompanion(
                id: Value(jId),
                companyId: Value(effCompanyId),
                journalNumber: Value(jNum),
                voucherId: Value(voucherId),
                date: Value(dateStr != null ? DateTime.parse(dateStr) : DateTime.now()),
                narration: Value(narration),
                totalAmountInCents: Value(totalAmount),
                status: Value(status),
                isDeleted: Value(isDeleted),
                createdAt: Value(createdAtStr != null ? DateTime.parse(createdAtStr) : DateTime.now()),
                updatedAt: Value(updatedAtStr != null ? DateTime.parse(updatedAtStr) : DateTime.now()),
                syncStatus: const Value(SyncRecordStatus.synced),
              ),
            );
            pulledCount++;
          }
        } catch (jErr) {
          debugPrint('SyncEngine pull journals notice: $jErr');
        }

        // 8. Pull Remote Journal Lines
        try {
          final dynamic remoteLines = usingFake
              ? fakeRemoteStore!.getTableRows('journal_lines', companyId: effCompanyId)
              : await client!.from('journal_lines').select().eq('company_id', effCompanyId);

          for (final jl in (remoteLines as List)) {
            final map = jl as Map<String, dynamic>;
            final jlId = map['id'] as String;
            final journalId = (map['journal_id'] ?? map['journalId']) as String;
            final accountId = (map['account_id'] ?? map['accountId']) as String;
            final partyId = (map['party_id'] ?? map['partyId']) as String?;
            final debit = ((map['debit_in_cents'] ?? map['debitInCents']) as num?)?.toInt() ?? 0;
            final credit = ((map['credit_in_cents'] ?? map['creditInCents']) as num?)?.toInt() ?? 0;
            final narration = map['narration'] as String?;
            final isDeleted = _toBool(map['is_deleted'] ?? map['isDeleted'], defaultValue: false);
            final createdAtStr = map['created_at'] as String?;
            final updatedAtStr = map['updated_at'] as String?;

            await db.into(db.journalLines).insertOnConflictUpdate(
              JournalLinesCompanion(
                id: Value(jlId),
                companyId: Value(effCompanyId),
                journalId: Value(journalId),
                accountId: Value(accountId),
                partyId: Value(partyId),
                debitInCents: Value(debit),
                creditInCents: Value(credit),
                narration: Value(narration),
                isDeleted: Value(isDeleted),
                createdAt: Value(createdAtStr != null ? DateTime.parse(createdAtStr) : DateTime.now()),
                updatedAt: Value(updatedAtStr != null ? DateTime.parse(updatedAtStr) : DateTime.now()),
                syncStatus: const Value(SyncRecordStatus.synced),
              ),
            );
            pulledCount++;
          }
        } catch (jlErr) {
          debugPrint('SyncEngine pull journal_lines notice: $jlErr');
        }

        // 9. Pull Remote Budgets
        try {
          final dynamic remoteBudgets = usingFake
              ? fakeRemoteStore!.getTableRows('budgets', companyId: effCompanyId)
              : await client!.from('budgets').select().eq('company_id', effCompanyId);

          for (final b in (remoteBudgets as List)) {
            final map = b as Map<String, dynamic>;
            final bId = map['id'] as String;
            final categoryAccountId = (map['category_account_id'] ?? map['categoryAccountId']) as String? ?? '';
            final periodType = (map['period_type'] ?? map['periodType']) as String? ?? 'monthly';
            final amountInCents = ((map['amount_in_cents'] ?? map['amountInCents']) as num?)?.toInt() ?? 0;
            final startDateStr = (map['start_date'] ?? map['startDate']) as String?;
            final rollover = _toBool(map['rollover_enabled'] ?? map['rolloverEnabled'], defaultValue: false);
            final isActive = _toBool(map['is_active'] ?? map['isActive'], defaultValue: true);
            final isDeleted = _toBool(map['is_deleted'] ?? map['isDeleted'], defaultValue: false);
            final createdAtStr = map['created_at'] as String?;
            final updatedAtStr = map['updated_at'] as String?;

            await db.into(db.budgets).insertOnConflictUpdate(
              BudgetsCompanion(
                id: Value(bId),
                companyId: Value(effCompanyId),
                categoryAccountId: Value(categoryAccountId),
                periodType: Value(periodType),
                amountInCents: Value(amountInCents),
                startDate: Value(startDateStr != null ? DateTime.parse(startDateStr) : DateTime.now()),
                rolloverEnabled: Value(rollover),
                isActive: Value(isActive),
                isDeleted: Value(isDeleted),
                createdAt: Value(createdAtStr != null ? DateTime.parse(createdAtStr) : DateTime.now()),
                updatedAt: Value(updatedAtStr != null ? DateTime.parse(updatedAtStr) : DateTime.now()),
                syncStatus: const Value(SyncRecordStatus.synced),
              ),
            );
            pulledCount++;
          }
        } catch (bErr) {
          debugPrint('SyncEngine pull budgets notice: $bErr');
        }

        // 10. Pull Remote Recurring Rules
        try {
          final dynamic remoteRules = usingFake
              ? fakeRemoteStore!.getTableRows('recurring_rules', companyId: effCompanyId)
              : await client!.from('recurring_rules').select().eq('company_id', effCompanyId);

          for (final r in (remoteRules as List)) {
            final map = r as Map<String, dynamic>;
            final rId = map['id'] as String;
            final templateJson = map['template_json'] != null
                ? (map['template_json'] is String ? map['template_json'] as String : jsonEncode(map['template_json']))
                : (map['templateJson'] != null
                    ? (map['templateJson'] is String ? map['templateJson'] as String : jsonEncode(map['templateJson']))
                    : '{}');
            final intervalType = (map['interval_type'] ?? map['intervalType']) as String? ?? 'monthly';
            final intervalCount = ((map['interval_count'] ?? map['intervalCount']) as num?)?.toInt() ?? 1;
            final nextRunStr = (map['next_run_date'] ?? map['nextRunDate']) as String?;
            final endStr = (map['end_date'] ?? map['endDate']) as String?;
            final isActive = _toBool(map['is_active'] ?? map['isActive'], defaultValue: true);
            final isDeleted = _toBool(map['is_deleted'] ?? map['isDeleted'], defaultValue: false);
            final createdAtStr = map['created_at'] as String?;
            final updatedAtStr = map['updated_at'] as String?;

            await db.into(db.recurringRules).insertOnConflictUpdate(
              RecurringRulesCompanion(
                id: Value(rId),
                companyId: Value(effCompanyId),
                templateJson: Value(templateJson),
                intervalType: Value(intervalType),
                intervalCount: Value(intervalCount),
                nextRunDate: Value(nextRunStr != null ? DateTime.parse(nextRunStr) : DateTime.now()),
                endDate: Value(endStr != null ? DateTime.parse(endStr) : null),
                isActive: Value(isActive),
                isDeleted: Value(isDeleted),
                createdAt: Value(createdAtStr != null ? DateTime.parse(createdAtStr) : DateTime.now()),
                updatedAt: Value(updatedAtStr != null ? DateTime.parse(updatedAtStr) : DateTime.now()),
                syncStatus: const Value(SyncRecordStatus.synced),
              ),
            );
            pulledCount++;
          }
        } catch (rErr) {
          debugPrint('SyncEngine pull recurring_rules notice: $rErr');
        }
      }

      setStatus(pulledCount > 0 ? SyncStatus.success : SyncStatus.idle);
      return SyncResult(
        success: true,
        itemsPulled: pulledCount,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint('SyncEngine.pullChanges notice: $e');
      final errStr = e.toString().toLowerCase();
      final isNetwork = errStr.contains('socketexception') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('clientexception') ||
          errStr.contains('postgrestexception');
      if (isNetwork) {
        setStatus(SyncStatus.idle);
        return SyncResult(
          success: true,
          itemsPulled: pulledCount,
          timestamp: DateTime.now(),
        );
      }
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

    final isSuccess = pushRes.success && pullRes.success;
    final totalPushed = pushRes.itemsPushed;
    final totalPulled = pullRes.itemsPulled;

    setStatus(isSuccess ? SyncStatus.success : SyncStatus.error);

    return SyncResult(
      success: isSuccess,
      itemsPushed: totalPushed,
      itemsPulled: totalPulled,
      timestamp: DateTime.now(),
      errorMessage: pushRes.errorMessage ?? pullRes.errorMessage,
    );
  }

  Future<void> _queueUnsyncedLocalRecords(String? companyId) async {
    try {
      // 1. Find companies with pending sync status that are not in outbox
      final pendingCompanies = await (db.select(db.companies)
            ..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();

      for (final c in pendingCompanies) {
        final existingOutbox = await (db.select(db.syncOutbox)
              ..where((t) => t.recordId.equals(c.id))
              ..limit(1))
            .getSingleOrNull();
        if (existingOutbox == null) {
          List<dynamic>? modulesList;
          if (c.enabledModulesJson != null && c.enabledModulesJson!.trim().isNotEmpty) {
            try {
              final decoded = jsonDecode(c.enabledModulesJson!);
              if (decoded is List) modulesList = decoded;
            } catch (_) {}
          }

          await db.into(db.syncOutbox).insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              id: 'outbox_comp_${c.id}_${DateTime.now().millisecondsSinceEpoch}',
              targetTable: 'companies',
              recordId: c.id,
              mutationType: c.isDeleted ? 'DELETE' : 'UPSERT',
              payload: jsonEncode({
                'id': c.id,
                'name': c.name,
                'legalName': c.legalName,
                'gstin': c.gstin,
                'stateCode': c.stateCode,
                'dealerType': c.dealerType,
                'currencyCode': c.currencyCode,
                'address': c.address,
                'email': c.email,
                'phoneNumber': c.phoneNumber,
                'logoUrl': c.logoUrl,
                'signatureUrl': c.signatureUrl,
                'signatoryName': c.signatoryName,
                'bankName': c.bankName,
                'bankAccountNumber': c.bankAccountNumber,
                'bankIfsc': c.bankIfsc,
                'upiId': c.upiId,
                'isCloudSyncEnabled': c.isCloudSyncEnabled,
                'isDropboxSyncEnabled': c.isDropboxSyncEnabled,
                'isActive': c.isActive,
                'mode': c.mode,
                'enabled_modules': modulesList,
                'enabledModules': modulesList,
                'isDeleted': c.isDeleted,
                'companyId': c.id,
              }),
            ),
          );
        }
      }

      // 2. Find user profiles with pending sync status that are not in outbox
      final pendingProfiles = await (db.select(db.userProfiles)
            ..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();

      for (final p in pendingProfiles) {
        final existingOutbox = await (db.select(db.syncOutbox)
              ..where((t) => t.recordId.equals(p.id))
              ..limit(1))
            .getSingleOrNull();
        if (existingOutbox == null) {
          await db.into(db.syncOutbox).insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              id: 'outbox_prof_${p.id}_${DateTime.now().millisecondsSinceEpoch}',
              targetTable: 'user_profiles',
              recordId: p.id,
              mutationType: 'UPSERT',
              payload: jsonEncode({
                'id': p.id,
                'name': p.name,
                'phoneNumber': p.phoneNumber,
                'email': p.email,
                'businessName': p.businessName,
                'address': p.address,
                'gstin': p.gstin,
                'businessType': p.businessType,
                'bankName': p.bankName,
                'bankAccountNumber': p.bankAccountNumber,
                'bankIfsc': p.bankIfsc,
                'upiId': p.upiId,
                'activeCompanyId': p.activeCompanyId,
                'role': p.role,
                'isDeleted': p.isDeleted,
                'companyId': p.activeCompanyId,
              }),
            ),
          );
        }
      }

      // 3. Find accounts with pending sync status (parent of vouchers and journal lines)
      final pendingAccounts = await (db.select(db.accounts)
            ..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();

      for (final a in pendingAccounts) {
        final existing = await (db.select(db.syncOutbox)
              ..where((t) => t.recordId.equals(a.id))
              ..limit(1))
            .getSingleOrNull();
        if (existing == null) {
          await db.into(db.syncOutbox).insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              id: 'outbox_acc_${a.id}_${DateTime.now().millisecondsSinceEpoch}',
              targetTable: 'accounts',
              recordId: a.id,
              mutationType: a.isDeleted ? 'DELETE' : 'UPSERT',
              payload: jsonEncode({
                'id': a.id,
                'companyId': a.companyId,
                'code': a.code,
                'name': a.name,
                'type': a.type,
                'parentAccountId': a.parentAccountId,
                'isSystem': a.isSystem,
                'isActive': a.isActive,
                'description': a.description,
                'currentBalanceInCents': a.currentBalanceInCents,
                'isDeleted': a.isDeleted,
              }),
            ),
          );
        }
      }

      // 4. Find parties with pending sync status that are not in outbox
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

      // 5. Find vouchers with pending sync status that are not in outbox
      final pendingVouchers = await (db.select(db.vouchers)
            ..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();

      for (final v in pendingVouchers) {
        final existing = await (db.select(db.syncOutbox)
              ..where((t) => t.recordId.equals(v.id))
              ..limit(1))
            .getSingleOrNull();
        if (existing == null) {
          await db.into(db.syncOutbox).insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              id: 'outbox_vch_${v.id}_${DateTime.now().millisecondsSinceEpoch}',
              targetTable: 'vouchers',
              recordId: v.id,
              mutationType: v.isDeleted ? 'DELETE' : 'UPSERT',
              payload: jsonEncode({
                'id': v.id,
                'voucherNumber': v.voucherNumber,
                'type': v.type,
                'date': v.date.toIso8601String(),
                'dueDate': v.dueDate?.toIso8601String(),
                'partyId': v.partyId,
                'partyName': v.partyName,
                'status': v.status,
                'paymentMode': v.paymentMode,
                'subtotalInCents': v.subtotalInCents,
                'taxInCents': v.taxInCents,
                'discountInCents': v.discountInCents,
                'totalAmountInCents': v.totalAmountInCents,
                'narration': v.narration,
                'referenceNumber': v.referenceNumber,
                'sourceVoucherId': v.sourceVoucherId,
                'receiptPhotoUrl': v.receiptPhotoUrl,
                'itemsJson': v.itemsJson,
                'categoryAccountId': v.categoryAccountId,
                'walletAccountId': v.walletAccountId,
                'toWalletAccountId': v.toWalletAccountId,
                'companyId': v.companyId,
                'isDeleted': v.isDeleted,
              }),
            ),
          );
        }
      }

      // 6. Find journals with pending sync status (parent of journal lines)
      final pendingJournals = await (db.select(db.journals)
            ..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();

      for (final j in pendingJournals) {
        final existing = await (db.select(db.syncOutbox)
              ..where((t) => t.recordId.equals(j.id))
              ..limit(1))
            .getSingleOrNull();
        if (existing == null) {
          await db.into(db.syncOutbox).insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              id: 'outbox_jrn_${j.id}_${DateTime.now().millisecondsSinceEpoch}',
              targetTable: 'journals',
              recordId: j.id,
              mutationType: j.isDeleted ? 'DELETE' : 'UPSERT',
              payload: jsonEncode({
                'id': j.id,
                'companyId': j.companyId,
                'journalNumber': j.journalNumber,
                'voucherId': j.voucherId,
                'date': j.date.toIso8601String(),
                'narration': j.narration,
                'totalAmountInCents': j.totalAmountInCents,
                'status': j.status,
                'isDeleted': j.isDeleted,
              }),
            ),
          );
        }
      }

      // 7. Find journal lines with pending sync status
      final pendingJournalLines = await (db.select(db.journalLines)
            ..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();

      for (final jl in pendingJournalLines) {
        final existing = await (db.select(db.syncOutbox)
              ..where((t) => t.recordId.equals(jl.id))
              ..limit(1))
            .getSingleOrNull();
        if (existing == null) {
          await db.into(db.syncOutbox).insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              id: 'outbox_jline_${jl.id}_${DateTime.now().millisecondsSinceEpoch}',
              targetTable: 'journal_lines',
              recordId: jl.id,
              mutationType: jl.isDeleted ? 'DELETE' : 'UPSERT',
              payload: jsonEncode({
                'id': jl.id,
                'companyId': jl.companyId,
                'journalId': jl.journalId,
                'accountId': jl.accountId,
                'partyId': jl.partyId,
                'debitInCents': jl.debitInCents,
                'creditInCents': jl.creditInCents,
                'narration': jl.narration,
                'isDeleted': jl.isDeleted,
              }),
            ),
          );
        }
      }

      // 8. Find ledger entries with pending sync status that are not in outbox
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

      // 9. Find budgets with pending sync status that are not in outbox
      final pendingBudgets = await (db.select(db.budgets)
            ..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();

      for (final b in pendingBudgets) {
        final existing = await (db.select(db.syncOutbox)
              ..where((t) => t.recordId.equals(b.id))
              ..limit(1))
            .getSingleOrNull();
        if (existing == null) {
          await db.into(db.syncOutbox).insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              id: 'outbox_bdg_${b.id}_${DateTime.now().millisecondsSinceEpoch}',
              targetTable: 'budgets',
              recordId: b.id,
              mutationType: b.isDeleted ? 'DELETE' : 'UPSERT',
              payload: jsonEncode({
                'id': b.id,
                'categoryAccountId': b.categoryAccountId,
                'periodType': b.periodType,
                'amountInCents': b.amountInCents,
                'startDate': b.startDate.toIso8601String(),
                'rolloverEnabled': b.rolloverEnabled,
                'isActive': b.isActive,
                'companyId': b.companyId,
                'isDeleted': b.isDeleted,
              }),
            ),
          );
        }
      }

      // 10. Find recurring rules with pending sync status that are not in outbox
      final pendingRules = await (db.select(db.recurringRules)
            ..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();

      for (final r in pendingRules) {
        final existing = await (db.select(db.syncOutbox)
              ..where((t) => t.recordId.equals(r.id))
              ..limit(1))
            .getSingleOrNull();
        if (existing == null) {
          await db.into(db.syncOutbox).insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              id: 'outbox_rcr_${r.id}_${DateTime.now().millisecondsSinceEpoch}',
              targetTable: 'recurring_rules',
              recordId: r.id,
              mutationType: r.isDeleted ? 'DELETE' : 'UPSERT',
              payload: jsonEncode({
                'id': r.id,
                'templateJson': r.templateJson,
                'intervalType': r.intervalType,
                'intervalCount': r.intervalCount,
                'nextRunDate': r.nextRunDate.toIso8601String(),
                'endDate': r.endDate?.toIso8601String(),
                'isActive': r.isActive,
                'companyId': r.companyId,
                'isDeleted': r.isDeleted,
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
      } else if (key == 'legalName') {
        map['legal_name'] = val;
      } else if (key == 'stateCode') {
        map['state_code'] = val;
      } else if (key == 'dealerType') {
        map['dealer_type'] = val;
      } else if (key == 'currencyCode') {
        map['currency_code'] = val;
      } else if (key == 'logoUrl') {
        map['logo_url'] = val;
      } else if (key == 'signatureUrl') {
        map['signature_url'] = val;
      } else if (key == 'signatoryName') {
        map['signatory_name'] = val;
      } else if (key == 'bankName') {
        map['bank_name'] = val;
      } else if (key == 'bankAccountNumber') {
        map['bank_account_number'] = val;
      } else if (key == 'bankIfsc') {
        map['bank_ifsc'] = val;
      } else if (key == 'upiId') {
        map['upi_id'] = val;
      } else if (key == 'businessName') {
        map['business_name'] = val;
      } else if (key == 'businessType') {
        map['business_type'] = val;
      } else if (key == 'activeCompanyId') {
        map['active_company_id'] = val;
      } else if (key == 'companiesJson' || key == 'companies') {
        map['companies_json'] = val;
      } else if (key == 'isCloudSyncEnabled') {
        map['is_cloud_sync_enabled'] = val;
      } else if (key == 'isDropboxSyncEnabled') {
        map['is_dropbox_sync_enabled'] = val;
      } else if (key == 'isActive') {
        map['is_active'] = val;
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
      } else if (key == 'mode') {
        map['mode'] = val ?? 'ledger';
      } else if (key == 'enabledModules' || key == 'enabled_modules' || key == 'enabledModulesJson') {
        if (val == null) {
          map['enabled_modules'] = null;
        } else if (val is List) {
          map['enabled_modules'] = val;
        } else if (val is String && val.trim().isNotEmpty) {
          try {
            final dec = jsonDecode(val);
            map['enabled_modules'] = dec is List ? dec : null;
          } catch (_) {
            map['enabled_modules'] = null;
          }
        } else {
          map['enabled_modules'] = null;
        }
      } else if (key == 'categoryAccountId') {
        map['category_account_id'] = val;
      } else if (key == 'walletAccountId') {
        map['wallet_account_id'] = val;
      } else if (key == 'toWalletAccountId') {
        map['to_wallet_account_id'] = val;
      } else if (key == 'voucherNumber') {
        map['voucher_number'] = val;
      } else if (key == 'dueDate') {
        map['due_date'] = val;
      } else if (key == 'partyName') {
        map['party_name'] = val;
      } else if (key == 'paymentMode') {
        map['payment_mode'] = val;
      } else if (key == 'subtotalInCents') {
        map['subtotal_in_cents'] = val;
      } else if (key == 'taxInCents') {
        map['tax_in_cents'] = val;
      } else if (key == 'discountInCents') {
        map['discount_in_cents'] = val;
      } else if (key == 'totalAmountInCents') {
        map['total_amount_in_cents'] = val;
      } else if (key == 'referenceNumber') {
        map['reference_number'] = val;
      } else if (key == 'sourceVoucherId') {
        map['source_voucher_id'] = val;
      } else if (key == 'itemsJson') {
        if (val is String && val.trim().isNotEmpty) {
          try {
            map['items_json'] = jsonDecode(val);
          } catch (_) {
            map['items_json'] = val;
          }
        } else {
          map['items_json'] = val;
        }
      } else if (key == 'periodType') {
        map['period_type'] = val;
      } else if (key == 'startDate') {
        map['start_date'] = val;
      } else if (key == 'rolloverEnabled') {
        map['rollover_enabled'] = val;
      } else if (key == 'templateJson') {
        if (val is String && val.trim().isNotEmpty) {
          try {
            map['template_json'] = jsonDecode(val);
          } catch (_) {
            map['template_json'] = val;
          }
        } else {
          map['template_json'] = val;
        }
      } else if (key == 'intervalType') {
        map['interval_type'] = val;
      } else if (key == 'intervalCount') {
        map['interval_count'] = val;
      } else if (key == 'nextRunDate') {
        map['next_run_date'] = val;
      } else if (key == 'endDate') {
        map['end_date'] = val;
      } else if (key == 'parentAccountId') {
        map['parent_account_id'] = val;
      } else if (key == 'isSystem') {
        map['is_system'] = val;
      } else if (key == 'currentBalanceInCents') {
        map['current_balance_in_cents'] = val;
      } else if (key == 'journalNumber') {
        map['journal_number'] = val;
      } else if (key == 'voucherId') {
        map['voucher_id'] = val;
      } else if (key == 'journalId') {
        map['journal_id'] = val;
      } else if (key == 'accountId') {
        map['account_id'] = val;
      } else if (key == 'debitInCents') {
        map['debit_in_cents'] = val;
      } else if (key == 'creditInCents') {
        map['credit_in_cents'] = val;
      } else if (key != 'runningBalanceInCents' && key != 'owner_id' && key != 'ownerId') {
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
      } else if (tableName == 'user_profiles' || tableName == 'profiles') {
        await (db.update(db.userProfiles)..where((t) => t.id.equals(recordId))).write(
          UserProfilesCompanion(syncStatus: Value(status)),
        );
      } else if (tableName == 'vouchers') {
        await (db.update(db.vouchers)..where((t) => t.id.equals(recordId))).write(
          VouchersCompanion(syncStatus: Value(status)),
        );
      } else if (tableName == 'budgets') {
        await (db.update(db.budgets)..where((t) => t.id.equals(recordId))).write(
          BudgetsCompanion(syncStatus: Value(status)),
        );
      } else if (tableName == 'recurring_rules') {
        await (db.update(db.recurringRules)..where((t) => t.id.equals(recordId))).write(
          RecurringRulesCompanion(syncStatus: Value(status)),
        );
      } else if (tableName == 'accounts') {
        await (db.update(db.accounts)..where((t) => t.id.equals(recordId))).write(
          AccountsCompanion(syncStatus: Value(status)),
        );
      } else if (tableName == 'journals') {
        await (db.update(db.journals)..where((t) => t.id.equals(recordId))).write(
          JournalsCompanion(syncStatus: Value(status)),
        );
      } else if (tableName == 'journal_lines') {
        await (db.update(db.journalLines)..where((t) => t.id.equals(recordId))).write(
          JournalLinesCompanion(syncStatus: Value(status)),
        );
      }
    } catch (e) {
      debugPrint('Failed to update sync record status for $tableName:$recordId: $e');
    }
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
