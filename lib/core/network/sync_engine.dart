import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/database.dart';
import '../../data/local/outbox_helper.dart';
import '../../data/models/account_model.dart';
import '../../data/models/company_mode.dart';
import '../../data/models/party_model.dart';
import '../../data/models/transaction_model.dart';
import '../config/supabase_config.dart';
import 'sync_codec.dart';

enum SyncEngineStatus { idle, syncing, success, partial, error }

typedef SyncStatus = SyncEngineStatus;

class SyncResult {
  final SyncEngineStatus status;
  final Map<String, String> tableErrors;
  final int pushedCount;
  final int pulledCount;
  final String? errorMessage;
  final DateTime timestamp;

  SyncResult({
    SyncEngineStatus? status,
    bool? success,
    this.tableErrors = const {},
    int? pushedCount,
    int? itemsPushed,
    int? pulledCount,
    int? itemsPulled,
    this.errorMessage,
    DateTime? timestamp,
  }) : status =
           status ??
           ((success == false)
               ? SyncEngineStatus.error
               : SyncEngineStatus.success),
       pushedCount = pushedCount ?? itemsPushed ?? 0,
       pulledCount = pulledCount ?? itemsPulled ?? 0,
       timestamp = timestamp ?? DateTime.now();

  bool get isSuccess => status == SyncEngineStatus.success;
  bool get success => isSuccess;
  int get itemsPushed => pushedCount;
  int get itemsPulled => pulledCount;
}

/// Internal sentinel exception thrown when a session is invalidated while a transaction is in-flight.
class _SessionInvalidatedException implements Exception {
  const _SessionInvalidatedException();
  @override
  String toString() => 'Session was invalidated during database transaction';
}

/// Internal result of scanning and queueing local pending mutations into the sync outbox.
class _EnqueueOutcome {
  final Map<String, String> errors;
  final Set<String> failedKeys;
  const _EnqueueOutcome({required this.errors, required this.failedKeys});
}

/// Abstract remote backend gateway for pushing/pulling rows.
abstract class RemoteGateway {
  Future<Map<String, dynamic>?> upsertRow({
    required String table,
    required Map<String, dynamic> row,
  });

  Future<List<Map<String, dynamic>>> pullRows({
    required String table,
    required String companyId,
    String? activeUserId,
    DateTime? cursor,
    int pageSize = 500,
    int offset = 0,
    DateTime? afterUpdatedAt,
    String? afterId,
  });
}

/// Supabase PostgREST Gateway implementation for production sync.
class SupabaseGateway implements RemoteGateway {
  final SupabaseClient client;

  SupabaseGateway(this.client);

  @override
  Future<Map<String, dynamic>?> upsertRow({
    required String table,
    required Map<String, dynamic> row,
  }) async {
    final response = await client
        .from(table)
        .upsert(row)
        .select()
        .maybeSingle();
    return response;
  }

  @override
  Future<List<Map<String, dynamic>>> pullRows({
    required String table,
    required String companyId,
    String? activeUserId,
    DateTime? cursor,
    int pageSize = 500,
    int offset = 0,
    DateTime? afterUpdatedAt,
    String? afterId,
  }) async {
    var query = client.from(table).select();

    if (table == 'companies') {
      query = query.eq('id', companyId);
    } else if (table == 'user_profiles') {
      if (activeUserId != null && activeUserId.isNotEmpty) {
        query = query.eq('id', activeUserId);
      }
    } else if (table == 'shared_memberships' || table.startsWith('exp_')) {
      query = query.eq('profile_id', companyId);
    } else {
      query = query.eq('company_id', companyId);
    }

    if (afterUpdatedAt != null && afterId != null) {
      query = query.or(
        'updated_at.gt.${encodeTime(afterUpdatedAt)},and(updated_at.eq.${encodeTime(afterUpdatedAt)},id.gt.$afterId)',
      );
    } else if (afterUpdatedAt != null) {
      query = query.gt('updated_at', encodeTime(afterUpdatedAt));
    } else if (afterId != null) {
      query = query.gt('id', afterId);
    } else if (cursor != null) {
      query = query.gte('updated_at', encodeTime(cursor));
    }

    final transform = query
        .order('updated_at', ascending: true)
        .order('id', ascending: true)
        .limit(pageSize);

    final List<dynamic> responseList = await transform;

    return responseList.cast<Map<String, dynamic>>();
  }
}

/// Snake_case <-> CamelCase Converters
String _toSnakeCase(String input) {
  return input.replaceAllMapped(
    RegExp(r'([A-Z])'),
    (match) => '_${match.group(1)!.toLowerCase()}',
  );
}

String _toCamelCase(String input) {
  return input.replaceAllMapped(
    RegExp(r'_([a-z])'),
    (match) => match.group(1)!.toUpperCase(),
  );
}

Map<String, dynamic> mapToSnakeCase(
  Map<String, dynamic> source, {
  Set<String> ignoreKeys = const {},
}) {
  final result = <String, dynamic>{};
  source.forEach((key, value) {
    if (ignoreKeys.contains(key)) return;
    final snakeKey = _toSnakeCase(key);
    result[snakeKey] = value;
  });
  return result;
}

Map<String, dynamic> mapToCamelCase(
  Map<String, dynamic> source, {
  Set<String> ignoreKeys = const {},
}) {
  final result = <String, dynamic>{};
  source.forEach((key, value) {
    if (ignoreKeys.contains(key)) return;
    final camelKey = _toCamelCase(key);
    result[camelKey] = value;
  });
  return result;
}

/// Table Descriptor for Table-Driven Sync Engine
class SyncTable<TData, TCompanion> {
  final String name;
  final List<String> parentTables;
  final String primaryKeyColumn;

  final Map<String, dynamic> Function(dynamic row) toRemote;
  final TCompanion Function(Map<String, dynamic> map) fromRemote;
  final Set<String> localOnlyColumns;

  const SyncTable({
    required this.name,
    this.parentTables = const [],
    this.primaryKeyColumn = 'id',
    required this.toRemote,
    required this.fromRemote,
    this.localOnlyColumns = const {'sync_status', 'syncStatus'},
  });
}

class SyncEngine {
  final AppDatabase db;
  final RemoteGateway gateway;
  final bool simulateSyncForTesting;
  final String? activeUserId;
  final int pageSize;

  final StreamController<SyncEngineStatus> _statusController =
      StreamController<SyncEngineStatus>.broadcast();
  SyncEngineStatus _currentStatus = SyncEngineStatus.idle;

  Completer<void>? _syncLock;
  Timer? _debounceTimer;

  SyncEngine({
    required this.db,
    RemoteGateway? gateway,
    RemoteGateway? fakeRemoteStore,
    SupabaseClient? supabaseClient,
    this.simulateSyncForTesting = false,
    this.activeUserId,
    this.pageSize = 500,
  }) : gateway =
           gateway ??
           fakeRemoteStore ??
           (supabaseClient != null
               ? SupabaseGateway(supabaseClient)
               : (_getSafeSupabaseClient() != null
                     ? SupabaseGateway(_getSafeSupabaseClient()!)
                     : _NoOpGateway()));

  RemoteGateway? get fakeRemoteStore => gateway;

  static SupabaseClient? _getSafeSupabaseClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  int _sessionGeneration = 0;
  bool _isDisposed = false;

  int get sessionGeneration => _sessionGeneration;
  bool get isDisposed => _isDisposed;

  /// Invalidates any in-flight sync operations so their results and database writes are discarded.
  void invalidateSession() {
    _sessionGeneration++;
  }

  bool _isSessionStale(int expectedGeneration) =>
      _isDisposed || _sessionGeneration != expectedGeneration;

  @visibleForTesting
  Future<void> Function()? onBeforeMarkSynced;

  @visibleForTesting
  Future<void> Function()? onInsideMarkSyncedTransaction;

  @visibleForTesting
  Future<void> Function()? onInsideMarkErrorTransaction;

  @visibleForTesting
  Future<void> Function()? onBeforeApplyRemoteRows;

  @visibleForTesting
  Future<void> Function(String table, String recordId, int rowIndex)? onInsidePullRow;

  @visibleForTesting
  Future<void> Function()? onBeforePersistCursor;

  @visibleForTesting
  Future<void> Function()? onInsideCursorTransaction;

  @visibleForTesting
  Future<void> Function(String companyId, String accountId, int index)? onInsideAccountBalanceRecalculation;

  @visibleForTesting
  Future<void> Function(String profileId, String walletId, int index)? onInsideWalletBalanceRecalculation;

  @visibleForTesting
  Future<void> Function(String table, String recordId)? onEnqueueMutation;

  SyncEngineStatus get currentStatus => _currentStatus;
  Stream<SyncEngineStatus> get statusStream => _statusController.stream;

  void dispose() {
    _isDisposed = true;
    _sessionGeneration++;
    _debounceTimer?.cancel();
    _statusController.close();
  }

  void setStatus(SyncEngineStatus status) {
    if (_isDisposed) return;
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  bool get isRemoteConfigured {
    return SupabaseConfig.isConfigured || simulateSyncForTesting;
  }

  static int tableDependencyRank(String table) {
    switch (table) {
      case 'user_profiles':
        return 0;
      case 'companies':
        return 1;
      case 'shared_memberships':
        return 2;
      case 'accounts':
        return 3;
      case 'parties':
        return 4;
      case 'tax_rates':
        return 5;
      case 'budgets':
        return 6;
      case 'recurring_rules':
        return 7;
      case 'vouchers':
        return 8;
      case 'journals':
        return 9;
      case 'journal_lines':
        return 10;
      case 'exp_wallets':
        return 11;
      case 'exp_categories':
        return 12;
      case 'exp_budgets':
        return 13;
      case 'exp_recurring_rules':
        return 14;
      case 'exp_transactions':
        return 15;
      case 'inventory_items':
        return 16;
      case 'stock_ledger':
        return 17;
      case 'audit_logs':
        return 18;
      default:
        return 99;
    }
  }

  Future<T> _synchronizedSync<T>(Future<T> Function() action) async {
    if (_isDisposed) {
      if (T == SyncResult) {
        return SyncResult(
          status: SyncEngineStatus.idle,
          tableErrors: {'sync': 'SyncEngine is disposed'},
        ) as T;
      }
      throw StateError('SyncEngine is disposed');
    }
    while (_syncLock != null) {
      await _syncLock!.future;
      if (_isDisposed) {
        if (T == SyncResult) {
          return SyncResult(
            status: SyncEngineStatus.idle,
            tableErrors: {'sync': 'SyncEngine is disposed'},
          ) as T;
        }
        throw StateError('SyncEngine is disposed');
      }
    }
    final completer = Completer<void>();
    _syncLock = completer;
    try {
      if (_isDisposed) {
        if (T == SyncResult) {
          return SyncResult(
            status: SyncEngineStatus.idle,
            tableErrors: {'sync': 'SyncEngine is disposed'},
          ) as T;
        }
        throw StateError('SyncEngine is disposed');
      }
      return await action();
    } finally {
      _syncLock = null;
      completer.complete();
    }
  }

  void triggerBackgroundSync({
    String? companyId,
    Duration debounceDelay = const Duration(milliseconds: 1500),
  }) {
    if (_isDisposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, () async {
      if (_isDisposed) return;
      try {
        await db.customSelect('SELECT 1').getSingle();
        await syncAll(companyId: companyId ?? 'cmp_default');
      } catch (_) {
        // DB closed or unmounted; ignore background sync trigger
      }
    });
  }

  Future<int> getPendingCount({String? companyId}) async {
    final rows = await (db.select(db.syncOutbox)).get();
    return rows.length;
  }

  Stream<int> watchPendingCount() {
    return db.select(db.syncOutbox).watch().map((rows) => rows.length);
  }

  Stream<int> watchFailed() {
    return db
        .select(db.syncOutbox)
        .watch()
        .map((rows) => rows.where((r) => r.lastError != null).length);
  }

  /// One-time cleanup of corrupted or non-JSON outbox rows
  Future<void> _cleanupCorruptedOutbox() async {
    try {
      final rows = await (db.select(db.syncOutbox)).get();
      for (final row in rows) {
        bool isValidJson = false;
        try {
          jsonDecode(row.payload);
          isValidJson = true;
        } catch (_) {}

        if (!realTableNames.contains(row.targetTable) || !isValidJson) {
          await (db.delete(
            db.syncOutbox,
          )..where((t) => t.id.equals(row.id))).go();
        }
      }
    } catch (e) {
      debugPrint('SyncEngine _cleanupCorruptedOutbox error: $e');
    }
  }

  /// Determines whether a queued mutation belongs to the workspace currently being synchronized.
  static bool _recordBelongsToWorkspace({
    required String targetTable,
    required Map<String, dynamic> payloadMap,
    required String companyId,
    String? activeUserId,
  }) {
    final bool isGuest =
        (activeUserId == null || activeUserId.isEmpty || activeUserId == 'usr_default');
    if (isGuest && companyId == 'cmp_default') {
      return true;
    }
    switch (targetTable) {
      case 'companies':
        final id = payloadMap['id']?.toString();
        return id == companyId;

      case 'user_profiles':
        if (activeUserId == null || activeUserId.isEmpty) return false;
        final id = payloadMap['id']?.toString();
        return id == activeUserId;

      case 'shared_memberships':
      case 'exp_wallets':
      case 'exp_categories':
      case 'exp_transactions':
      case 'exp_budgets':
      case 'exp_recurring_rules':
        final profileId =
            (payloadMap['profile_id'] ?? payloadMap['profileId'])?.toString();
        return profileId == companyId;

      case 'accounts':
      case 'parties':
      case 'vouchers':
      case 'journals':
      case 'journal_lines':
      case 'ledger_entries':
      case 'budgets':
      case 'recurring_rules':
      case 'inventory_items':
      case 'stock_ledger':
      case 'audit_logs':
        final rowCompanyId =
            (payloadMap['company_id'] ?? payloadMap['companyId'])?.toString();
        return rowCompanyId == companyId;

      default:
        return false;
    }
  }

  /// Queues any domain records with syncStatus == pending into sync_outbox if missing
  Future<_EnqueueOutcome> _queueUnsyncedLocalRecords(String companyId) async {
    final enqueueErrors = <String, String>{};
    final failedKeys = <String>{};
    final currentUserId = activeUserId;
    final bool isGuest =
        (currentUserId == null || currentUserId.isEmpty || currentUserId == 'usr_default');
    final bool allowAllCompanies = isGuest && companyId == 'cmp_default';

    Future<void> safeEnqueue({
      AppDatabase? db,
      required String table,
      required String recordId,
      required String type,
      required Map<String, dynamic> fullRowMap,
    }) async {
      try {
        if (onEnqueueMutation != null) {
          await onEnqueueMutation!(table, recordId);
        }
        await enqueueMutation(
          db: db ?? this.db,
          table: table,
          recordId: recordId,
          type: type,
          fullRowMap: fullRowMap,
        );
      } catch (e) {
        debugPrint('Failed to enqueue sync outbox mutation for $table:$recordId: $e');
        final key = '$table:$recordId';
        failedKeys.add(key);
        enqueueErrors[key] = e.toString();
      }
    }

    try {
      // 1. Companies (scoped to the requested companyId if not allowAllCompanies)
      final pendingCompaniesQuery = db.select(db.companies)
        ..where(
          (t) =>
              (!allowAllCompanies
                  ? t.id.equals(companyId)
                  : const Constant(true)) &
              t.syncStatus.equalsValue(SyncRecordStatus.pending),
        );
      final pendingCompanies = await pendingCompaniesQuery.get();
      for (final c in pendingCompanies) {
        await safeEnqueue(
          db: db,
          table: 'companies',
          recordId: c.id,
          type: 'UPSERT',
          fullRowMap: {
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
            'enabledModulesJson': c.enabledModulesJson,
            'createdAt': encodeTime(c.createdAt),
            'updatedAt': encodeTime(c.updatedAt),
            'isDeleted': c.isDeleted,
            'revision': c.revision,
            'ownerId': c.ownerId,
            'owner_id': c.ownerId,
          },
        );

        // Enqueue shared_memberships for this profile immediately after the profile
        final memberships = await (db.select(db.sharedMemberships)
              ..where((t) => t.profileId.equals(c.id)))
            .get();
        for (final m in memberships) {
          await safeEnqueue(
            db: db,
            table: 'shared_memberships',
            recordId: m.id,
            type: 'UPSERT',
            fullRowMap: {
              'id': m.id,
              'profile_id': m.profileId,
              'account_id': m.accountId,
              'role': m.role,
              'joined_at': encodeTime(m.joinedAt),
              'updated_at': encodeTime(m.updatedAt),
            },
          );
        }
      }

      // 2. UserProfiles (scoped to active authenticated user session)
      final pendingProfilesQuery = db.select(db.userProfiles)
        ..where(
          (t) =>
              (activeUserId != null
                  ? t.id.equals(activeUserId!)
                  : (companyId == 'cmp_default'
                      ? const Constant(true)
                      : const Constant(false))) &
              t.syncStatus.equalsValue(SyncRecordStatus.pending),
        );
      final pendingProfiles = await pendingProfilesQuery.get();
      for (final p in pendingProfiles) {
        await safeEnqueue(
          db: db,
          table: 'user_profiles',
          recordId: p.id,
          type: 'UPSERT',
          fullRowMap: {
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
            'companiesJson': p.companiesJson,
            'isDeleted': p.isDeleted,
            'createdAt': encodeTime(p.createdAt),
            'updatedAt': encodeTime(p.updatedAt),
            'revision': p.revision,
            'ownerId': p.id,
            'owner_id': p.id,
          },
        );
      }

      // 3. Parties
      final pendingParties =
          await (db.select(db.parties)..where(
                (t) =>
                    t.companyId.equals(companyId) &
                    t.syncStatus.equalsValue(SyncRecordStatus.pending),
              ))
              .get();
      for (final p in pendingParties) {
        await safeEnqueue(
          db: db,
          table: 'parties',
          recordId: p.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': p.id,
            'companyId': p.companyId,
            'name': p.name,
            'phoneNumber': p.phoneNumber,
            'type': p.type.name,
            'netBalanceInCents': p.netBalanceInCents,
            'lastUpdated': encodeTime(p.lastUpdated),
            'isDeleted': p.isDeleted,
            'updatedAt': encodeTime(p.updatedAt),
            'revision': p.revision,
          },
        );
      }

      // 4. LedgerEntries
      final pendingEntries =
          await (db.select(db.ledgerEntries)..where(
                (t) =>
                    t.companyId.equals(companyId) &
                    t.syncStatus.equalsValue(SyncRecordStatus.pending),
              ))
              .get();
      for (final e in pendingEntries) {
        await safeEnqueue(
          db: db,
          table: 'ledger_entries',
          recordId: e.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': e.id,
            'companyId': e.companyId,
            'partyId': e.partyId,
            'amountInCents': e.amountInCents,
            'type': e.type.name,
            'date': encodeTime(e.date),
            'note': e.note,
            'receiptPhotoUrl': e.receiptPhotoUrl,
            'isVoided': e.isVoided,
            'createdAt': encodeTime(e.createdAt),
            'updatedAt': encodeTime(e.updatedAt),
            'isDeleted': e.isDeleted,
            'revision': e.revision,
          },
        );
      }

      // 5. Vouchers
      final pendingVouchers =
          await (db.select(db.vouchers)..where(
                (t) =>
                    t.companyId.equals(companyId) &
                    t.syncStatus.equalsValue(SyncRecordStatus.pending),
              ))
              .get();
      for (final v in pendingVouchers) {
        await safeEnqueue(
          db: db,
          table: 'vouchers',
          recordId: v.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': v.id,
            'companyId': v.companyId,
            'voucherNumber': v.voucherNumber,
            'type': v.type,
            'date': encodeTime(v.date),
            'dueDate': v.dueDate != null ? encodeTime(v.dueDate!) : null,
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
            'createdAt': encodeTime(v.createdAt),
            'updatedAt': encodeTime(v.updatedAt),
            'isDeleted': v.isDeleted,
            'revision': v.revision,
          },
        );
      }

      // 6. Accounts
      final pendingAccounts =
          await (db.select(db.accounts)..where(
                (t) =>
                    t.companyId.equals(companyId) &
                    t.syncStatus.equalsValue(SyncRecordStatus.pending),
              ))
              .get();
      for (final a in pendingAccounts) {
        await safeEnqueue(
          db: db,
          table: 'accounts',
          recordId: a.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': a.id,
            'companyId': a.companyId,
            'code': a.code,
            'name': a.name,
            'type': a.type,
            'kind': a.kind,
            'parentAccountId': a.parentAccountId,
            'isSystem': a.isSystem,
            'isActive': a.isActive,
            'description': a.description,
            'currentBalanceInCents': a.currentBalanceInCents,
            'createdAt': encodeTime(a.createdAt),
            'updatedAt': encodeTime(a.updatedAt),
            'isDeleted': a.isDeleted,
            'revision': a.revision,
            'ownerId': activeUserId ?? _getSafeSupabaseClient()?.auth.currentUser?.id,
            'owner_id': activeUserId ?? _getSafeSupabaseClient()?.auth.currentUser?.id,
          },
        );
      }

      // 7. Journals
      final pendingJournals =
          await (db.select(db.journals)..where(
                (t) =>
                    t.companyId.equals(companyId) &
                    t.syncStatus.equalsValue(SyncRecordStatus.pending),
              ))
              .get();
      for (final j in pendingJournals) {
        await safeEnqueue(
          db: db,
          table: 'journals',
          recordId: j.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': j.id,
            'companyId': j.companyId,
            'journalNumber': j.journalNumber,
            'voucherId': j.voucherId,
            'date': encodeTime(j.date),
            'narration': j.narration,
            'totalAmountInCents': j.totalAmountInCents,
            'status': j.status,
            'createdAt': encodeTime(j.createdAt),
            'updatedAt': encodeTime(j.updatedAt),
            'isDeleted': j.isDeleted,
            'revision': j.revision,
          },
        );
      }

      // 8. JournalLines
      final pendingLines =
          await (db.select(db.journalLines)..where(
                (t) =>
                    t.companyId.equals(companyId) &
                    t.syncStatus.equalsValue(SyncRecordStatus.pending),
              ))
              .get();
      for (final l in pendingLines) {
        await safeEnqueue(
          db: db,
          table: 'journal_lines',
          recordId: l.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': l.id,
            'companyId': l.companyId,
            'journalId': l.journalId,
            'accountId': l.accountId,
            'partyId': l.partyId,
            'debitInCents': l.debitInCents,
            'creditInCents': l.creditInCents,
            'narration': l.narration,
            'createdAt': encodeTime(l.createdAt),
            'updatedAt': encodeTime(l.updatedAt),
            'isDeleted': l.isDeleted,
            'revision': l.revision,
          },
        );
      }

      // 9. Budgets
      final pendingBudgets =
          await (db.select(db.budgets)..where(
                (t) =>
                    t.companyId.equals(companyId) &
                    t.syncStatus.equalsValue(SyncRecordStatus.pending),
              ))
              .get();
      for (final b in pendingBudgets) {
        await safeEnqueue(
          db: db,
          table: 'budgets',
          recordId: b.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': b.id,
            'companyId': b.companyId,
            'categoryAccountId': b.categoryAccountId,
            'periodType': b.periodType,
            'amountInCents': b.amountInCents,
            'startDate': encodeTime(b.startDate),
            'rolloverEnabled': b.rolloverEnabled,
            'isActive': b.isActive,
            'createdAt': encodeTime(b.createdAt),
            'updatedAt': encodeTime(b.updatedAt),
            'isDeleted': b.isDeleted,
            'revision': b.revision,
          },
        );
      }

      // 10. RecurringRules
      final pendingRules =
          await (db.select(db.recurringRules)..where(
                (t) =>
                    t.companyId.equals(companyId) &
                    t.syncStatus.equalsValue(SyncRecordStatus.pending),
              ))
              .get();
      for (final r in pendingRules) {
        await safeEnqueue(
          db: db,
          table: 'recurring_rules',
          recordId: r.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': r.id,
            'companyId': r.companyId,
            'templateJson': r.templateJson,
            'intervalType': r.intervalType,
            'intervalCount': r.intervalCount,
            'nextRunDate': encodeTime(r.nextRunDate),
            'endDate': r.endDate != null ? encodeTime(r.endDate!) : null,
            'isActive': r.isActive,
            'createdAt': encodeTime(r.createdAt),
            'updatedAt': encodeTime(r.updatedAt),
            'isDeleted': r.isDeleted,
            'revision': r.revision,
          },
        );
      }

      // 11. ExpenseWallets
      final pendingWallets = await (db.select(db.expenseWallets)
            ..where((t) =>
                t.profileId.equals(companyId) &
                t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();
      for (final w in pendingWallets) {
        await safeEnqueue(
          db: db,
          table: 'exp_wallets',
          recordId: w.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': w.id,
            'profile_id': w.profileId,
            'name': w.name,
            'wallet_type': w.walletType,
            'currency_code': w.currencyCode,
            'starting_balance_in_cents': w.startingBalanceInCents,
            'current_balance_in_cents': w.currentBalanceInCents,
            'color_hex': w.colorHex,
            'icon_name': w.iconName,
            'is_archived': w.isArchived,
            'created_at': encodeTime(w.createdAt),
            'updated_at': encodeTime(w.updatedAt),
            'is_deleted': w.isDeleted,
            'revision': w.revision,
          },
        );
      }

      // 12. ExpenseCategories
      final pendingCategories = await (db.select(db.expenseCategories)
            ..where((t) =>
                t.profileId.equals(companyId) &
                t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();
      for (final c in pendingCategories) {
        await safeEnqueue(
          db: db,
          table: 'exp_categories',
          recordId: c.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': c.id,
            'profile_id': c.profileId,
            'name': c.name,
            'category_type': c.categoryType,
            'parent_category_id': c.parentCategoryId,
            'icon_name': c.iconName,
            'color_hex': c.colorHex,
            'is_system': c.isSystem,
            'created_at': encodeTime(c.createdAt),
            'updated_at': encodeTime(c.updatedAt),
            'is_deleted': c.isDeleted,
            'revision': c.revision,
          },
        );
      }

      // 13. ExpenseBudgets
      final pendingExpBudgets = await (db.select(db.expenseBudgets)
            ..where((t) =>
                t.profileId.equals(companyId) &
                t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();
      for (final b in pendingExpBudgets) {
        await safeEnqueue(
          db: db,
          table: 'exp_budgets',
          recordId: b.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': b.id,
            'profile_id': b.profileId,
            'category_id': b.categoryId,
            'period_type': b.periodType,
            'amount_in_cents': b.amountInCents,
            'start_date': encodeTime(b.startDate),
            'end_date': b.endDate != null ? encodeTime(b.endDate!) : null,
            'alert_threshold_percent': b.alertThresholdPercent,
            'created_at': encodeTime(b.createdAt),
            'updated_at': encodeTime(b.updatedAt),
            'is_deleted': b.isDeleted,
            'revision': b.revision,
          },
        );
      }

      // 14. ExpenseRecurringRules
      final pendingExpRecurring = await (db.select(db.expenseRecurringRules)
            ..where((t) =>
                t.profileId.equals(companyId) &
                t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();
      for (final r in pendingExpRecurring) {
        await safeEnqueue(
          db: db,
          table: 'exp_recurring_rules',
          recordId: r.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': r.id,
            'profile_id': r.profileId,
            'template_json': r.templateJson,
            'interval_type': r.intervalType,
            'interval_count': r.intervalCount,
            'next_run_date': encodeTime(r.nextRunDate),
            'end_date': r.endDate != null ? encodeTime(r.endDate!) : null,
            'is_active': r.isActive,
            'created_at': encodeTime(r.createdAt),
            'updated_at': encodeTime(r.updatedAt),
            'is_deleted': r.isDeleted,
            'revision': r.revision,
          },
        );
      }

      // 15. ExpenseTransactions
      final pendingExpTxns = await (db.select(db.expenseTransactions)
            ..where((t) =>
                t.profileId.equals(companyId) &
                t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();
      for (final tx in pendingExpTxns) {
        await safeEnqueue(
          db: db,
          table: 'exp_transactions',
          recordId: tx.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': tx.id,
            'profile_id': tx.profileId,
            'transaction_type': tx.transactionType,
            'amount_in_cents': tx.amountInCents,
            'wallet_id': tx.walletId,
            'to_wallet_id': tx.toWalletId,
            'category_id': tx.categoryId,
            'transaction_date': encodeTime(tx.transactionDate),
            'note': tx.note,
            'payee_or_payer': tx.payeeOrPayer,
            'reference_number': tx.referenceNumber,
            'receipt_photo_url': tx.receiptPhotoUrl,
            'is_cleared': tx.isCleared,
            'created_at': encodeTime(tx.createdAt),
            'updated_at': encodeTime(tx.updatedAt),
            'is_deleted': tx.isDeleted,
            'revision': tx.revision,
          },
        );
      }

      // 16. InventoryItems
      final pendingItems = await (db.select(db.inventoryItems)
            ..where((t) =>
                t.companyId.equals(companyId) &
                t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();
      for (final item in pendingItems) {
        await safeEnqueue(
          db: db,
          table: 'inventory_items',
          recordId: item.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': item.id,
            'company_id': item.companyId,
            'sku': item.sku,
            'name': item.name,
            'description': item.description,
            'unit': item.unit,
            'hsn_code': item.hsnCode,
            'tax_rate_percent': item.taxRatePercent,
            'purchase_price_in_cents': item.purchasePriceInCents,
            'selling_price_in_cents': item.sellingPriceInCents,
            'current_stock_quantity': item.currentStockQuantity,
            'minimum_stock_alert': item.minimumStockAlert,
            'is_active': item.isActive,
            'created_at': encodeTime(item.createdAt),
            'updated_at': encodeTime(item.updatedAt),
            'is_deleted': item.isDeleted,
            'revision': item.revision,
          },
        );
      }

      // 17. StockLedger
      final pendingStock = await (db.select(db.stockLedger)
            ..where((t) =>
                t.companyId.equals(companyId) &
                t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();
      for (final sl in pendingStock) {
        await safeEnqueue(
          db: db,
          table: 'stock_ledger',
          recordId: sl.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': sl.id,
            'company_id': sl.companyId,
            'item_id': sl.itemId,
            'voucher_id': sl.voucherId,
            'date': encodeTime(sl.date),
            'quantity': sl.quantity,
            'unit_cost_in_cents': sl.unitCostInCents,
            'total_cost_in_cents': sl.totalCostInCents,
            'running_stock_quantity': sl.runningStockQuantity,
            'transaction_type': sl.transactionType,
            'note': sl.note,
            'created_at': encodeTime(sl.createdAt),
            'updated_at': encodeTime(sl.updatedAt),
            'is_deleted': sl.isDeleted,
            'revision': sl.revision,
          },
        );
      }

      // 18. AuditLogs
      final pendingAudit = await (db.select(db.auditLogs)
            ..where((t) =>
                t.companyId.equals(companyId) &
                t.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .get();
      for (final al in pendingAudit) {
        await safeEnqueue(
          db: db,
          table: 'audit_logs',
          recordId: al.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': al.id,
            'company_id': al.companyId,
            'user_id': al.userId,
            'action': al.action,
            'entity_type': al.entityType,
            'entity_id': al.entityId,
            'timestamp': encodeTime(al.timestamp),
            'old_state_json': al.oldStateJson,
            'new_state_json': al.newStateJson,
            'diff_json': al.diffJson,
            'checksum': al.checksum,
            'previous_checksum': al.previousChecksum,
            'updated_at': encodeTime(al.updatedAt),
            'is_deleted': al.isDeleted,
            'revision': al.revision,
          },
        );
      }
    } catch (e) {
      debugPrint('SyncEngine _queueUnsyncedLocalRecords error: $e');
      enqueueErrors['outbox_queue'] = e.toString();
    }
    return _EnqueueOutcome(errors: enqueueErrors, failedKeys: failedKeys);
  }

  /// Pushes queued outbox mutations to remote backend.
  Future<SyncResult> pushQueue({String? companyId}) async {
    final cid = companyId ?? 'cmp_default';
    return _synchronizedSync(() async {
      return _pushQueueInternal(companyId: cid);
    });
  }

  Future<void> _repairFailedSyncRecords({required String companyId}) async {
    try {
      final permanentOutbox = await (db.select(db.syncOutbox)
            ..where((t) => t.lastError.isNotNull() & t.nextAttemptAt.isNull()))
          .get();
      final permanentKeys =
          permanentOutbox.map((r) => '${r.targetTable}:${r.recordId}').toSet();

      // Vouchers
      final errVouchers = await (db.select(db.vouchers)
            ..where((t) =>
                (companyId != 'cmp_default'
                    ? t.companyId.equals(companyId)
                    : const Constant(true)) &
                t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .get();
      for (final v in errVouchers) {
        if (!permanentKeys.contains('vouchers:${v.id}')) {
          await (db.update(db.vouchers)..where((t) => t.id.equals(v.id))).write(
            const VouchersCompanion(syncStatus: Value(SyncRecordStatus.pending)),
          );
        }
      }

      // Budgets
      final errBudgets = await (db.select(db.budgets)
            ..where((t) =>
                (companyId != 'cmp_default'
                    ? t.companyId.equals(companyId)
                    : const Constant(true)) &
                t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .get();
      for (final b in errBudgets) {
        if (!permanentKeys.contains('budgets:${b.id}')) {
          await (db.update(db.budgets)..where((t) => t.id.equals(b.id))).write(
            const BudgetsCompanion(syncStatus: Value(SyncRecordStatus.pending)),
          );
        }
      }

      // RecurringRules
      final errRules = await (db.select(db.recurringRules)
            ..where((t) =>
                (companyId != 'cmp_default'
                    ? t.companyId.equals(companyId)
                    : const Constant(true)) &
                t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .get();
      for (final r in errRules) {
        if (!permanentKeys.contains('recurring_rules:${r.id}')) {
          await (db.update(db.recurringRules)..where((t) => t.id.equals(r.id))).write(
            const RecurringRulesCompanion(syncStatus: Value(SyncRecordStatus.pending)),
          );
        }
      }

      // Accounts
      final errAccounts = await (db.select(db.accounts)
            ..where((t) =>
                (companyId != 'cmp_default'
                    ? t.companyId.equals(companyId)
                    : const Constant(true)) &
                t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .get();
      for (final a in errAccounts) {
        if (!permanentKeys.contains('accounts:${a.id}')) {
          await (db.update(db.accounts)..where((t) => t.id.equals(a.id))).write(
            const AccountsCompanion(syncStatus: Value(SyncRecordStatus.pending)),
          );
        }
      }

      // Parties
      final errParties = await (db.select(db.parties)
            ..where((t) =>
                (companyId != 'cmp_default'
                    ? t.companyId.equals(companyId)
                    : const Constant(true)) &
                t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .get();
      for (final p in errParties) {
        if (!permanentKeys.contains('parties:${p.id}')) {
          await (db.update(db.parties)..where((t) => t.id.equals(p.id))).write(
            const PartiesCompanion(syncStatus: Value(SyncRecordStatus.pending)),
          );
        }
      }

      // LedgerEntries
      final errEntries = await (db.select(db.ledgerEntries)
            ..where((t) =>
                (companyId != 'cmp_default'
                    ? t.companyId.equals(companyId)
                    : const Constant(true)) &
                t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .get();
      for (final l in errEntries) {
        if (!permanentKeys.contains('ledger_entries:${l.id}')) {
          await (db.update(db.ledgerEntries)..where((t) => t.id.equals(l.id))).write(
            const LedgerEntriesCompanion(syncStatus: Value(SyncRecordStatus.pending)),
          );
        }
      }

      // Journals
      final errJournals = await (db.select(db.journals)
            ..where((t) =>
                (companyId != 'cmp_default'
                    ? t.companyId.equals(companyId)
                    : const Constant(true)) &
                t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .get();
      for (final j in errJournals) {
        if (!permanentKeys.contains('journals:${j.id}')) {
          await (db.update(db.journals)..where((t) => t.id.equals(j.id))).write(
            const JournalsCompanion(syncStatus: Value(SyncRecordStatus.pending)),
          );
        }
      }

      // JournalLines
      final errLines = await (db.select(db.journalLines)
            ..where((t) =>
                (companyId != 'cmp_default'
                    ? t.companyId.equals(companyId)
                    : const Constant(true)) &
                t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .get();
      for (final jl in errLines) {
        if (!permanentKeys.contains('journal_lines:${jl.id}')) {
          await (db.update(db.journalLines)..where((t) => t.id.equals(jl.id))).write(
            const JournalLinesCompanion(syncStatus: Value(SyncRecordStatus.pending)),
          );
        }
      }

      // ExpenseWallets
      final errWallets = await (db.select(db.expenseWallets)
            ..where((t) =>
                (companyId != 'cmp_default'
                    ? t.profileId.equals(companyId)
                    : const Constant(true)) &
                t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .get();
      for (final w in errWallets) {
        if (!permanentKeys.contains('exp_wallets:${w.id}')) {
          await (db.update(db.expenseWallets)..where((t) => t.id.equals(w.id))).write(
            const ExpenseWalletsCompanion(syncStatus: Value(SyncRecordStatus.pending)),
          );
        }
      }

      // ExpenseCategories
      final errCategories = await (db.select(db.expenseCategories)
            ..where((t) =>
                (companyId != 'cmp_default'
                    ? t.profileId.equals(companyId)
                    : const Constant(true)) &
                t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .get();
      for (final c in errCategories) {
        if (!permanentKeys.contains('exp_categories:${c.id}')) {
          await (db.update(db.expenseCategories)..where((t) => t.id.equals(c.id))).write(
            const ExpenseCategoriesCompanion(syncStatus: Value(SyncRecordStatus.pending)),
          );
        }
      }

      // ExpenseTransactions
      final errTxns = await (db.select(db.expenseTransactions)
            ..where((t) =>
                (companyId != 'cmp_default'
                    ? t.profileId.equals(companyId)
                    : const Constant(true)) &
                t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .get();
      for (final tx in errTxns) {
        if (!permanentKeys.contains('exp_transactions:${tx.id}')) {
          await (db.update(db.expenseTransactions)..where((t) => t.id.equals(tx.id))).write(
            const ExpenseTransactionsCompanion(syncStatus: Value(SyncRecordStatus.pending)),
          );
        }
      }

      // ExpenseBudgets
      final errExpBudgets = await (db.select(db.expenseBudgets)
            ..where((t) =>
                (companyId != 'cmp_default'
                    ? t.profileId.equals(companyId)
                    : const Constant(true)) &
                t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .get();
      for (final eb in errExpBudgets) {
        if (!permanentKeys.contains('exp_budgets:${eb.id}')) {
          await (db.update(db.expenseBudgets)..where((t) => t.id.equals(eb.id))).write(
            const ExpenseBudgetsCompanion(syncStatus: Value(SyncRecordStatus.pending)),
          );
        }
      }

      // ExpenseRecurringRules
      final errExpRules = await (db.select(db.expenseRecurringRules)
            ..where((t) =>
                (companyId != 'cmp_default'
                    ? t.profileId.equals(companyId)
                    : const Constant(true)) &
                t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .get();
      for (final er in errExpRules) {
        if (!permanentKeys.contains('exp_recurring_rules:${er.id}')) {
          await (db.update(db.expenseRecurringRules)..where((t) => t.id.equals(er.id))).write(
            const ExpenseRecurringRulesCompanion(syncStatus: Value(SyncRecordStatus.pending)),
          );
        }
      }

      // InventoryItems
      final errItems = await (db.select(db.inventoryItems)
            ..where((t) =>
                (companyId != 'cmp_default'
                    ? t.companyId.equals(companyId)
                    : const Constant(true)) &
                t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .get();
      for (final it in errItems) {
        if (!permanentKeys.contains('inventory_items:${it.id}')) {
          await (db.update(db.inventoryItems)..where((t) => t.id.equals(it.id))).write(
            const InventoryItemsCompanion(syncStatus: Value(SyncRecordStatus.pending)),
          );
        }
      }

      // StockLedger
      final errStock = await (db.select(db.stockLedger)
            ..where((t) =>
                (companyId != 'cmp_default'
                    ? t.companyId.equals(companyId)
                    : const Constant(true)) &
                t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .get();
      for (final sl in errStock) {
        if (!permanentKeys.contains('stock_ledger:${sl.id}')) {
          await (db.update(db.stockLedger)..where((t) => t.id.equals(sl.id))).write(
            const StockLedgerCompanion(syncStatus: Value(SyncRecordStatus.pending)),
          );
        }
      }

      // AuditLogs
      final errAudit = await (db.select(db.auditLogs)
            ..where((t) =>
                (companyId != 'cmp_default'
                    ? t.companyId.equals(companyId)
                    : const Constant(true)) &
                t.syncStatus.equalsValue(SyncRecordStatus.error)))
          .get();
      for (final al in errAudit) {
        if (!permanentKeys.contains('audit_logs:${al.id}')) {
          await (db.update(db.auditLogs)..where((t) => t.id.equals(al.id))).write(
            const AuditLogsCompanion(syncStatus: Value(SyncRecordStatus.pending)),
          );
        }
      }
    } catch (e) {
      debugPrint('SyncEngine repair failed records notice: $e');
    }
  }

  Future<SyncResult> _pushQueueInternal({required String companyId}) async {
    final currentGeneration = _sessionGeneration;
    if (_isDisposed || _sessionGeneration != currentGeneration) {
      return SyncResult(
        status: SyncEngineStatus.idle,
        tableErrors: {'aborted': 'Engine was disposed or session invalidated'},
      );
    }

    setStatus(SyncEngineStatus.syncing);
    await _cleanupCorruptedOutbox();
    await _repairFailedSyncRecords(companyId: companyId);
    final enqueueOutcome = await _queueUnsyncedLocalRecords(companyId);
    final enqueueErrors = enqueueOutcome.errors;
    final failedEnqueueKeys = enqueueOutcome.failedKeys;

    if (_isDisposed || _sessionGeneration != currentGeneration) {
      return SyncResult(
        status: SyncEngineStatus.idle,
        tableErrors: {'aborted': 'Engine was disposed or session invalidated'},
      );
    }

    final tableErrors = <String, String>{};
    tableErrors.addAll(enqueueErrors);

    final now = DateTime.now();
    // Exclude permanent failures (lastError is not null AND nextAttemptAt is null)
    final query = db.select(db.syncOutbox)
      ..where(
        (t) =>
            (t.lastError.isNull() & t.nextAttemptAt.isNull()) |
            (t.nextAttemptAt.isNotNull() &
                t.nextAttemptAt.isSmallerOrEqual(Variable(now))),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

    final outboxRows = await query.get();
    if (outboxRows.isEmpty) {
      final status =
          tableErrors.isEmpty ? SyncEngineStatus.success : SyncEngineStatus.partial;
      setStatus(status);
      return SyncResult(
        status: status,
        tableErrors: tableErrors,
        pushedCount: 0,
      );
    }

    outboxRows.sort((a, b) {
      final rankA = tableDependencyRank(a.targetTable);
      final rankB = tableDependencyRank(b.targetTable);
      if (rankA != rankB) {
        return rankA.compareTo(rankB);
      }
      return a.createdAt.compareTo(b.createdAt);
    });

    int pushedCount = 0;

    for (final outboxRow in outboxRows) {
      if (_isDisposed || _sessionGeneration != currentGeneration) break;

      final rowKey = '${outboxRow.targetTable}:${outboxRow.recordId}';

      // If the latest local mutation for this record failed to enqueue during this push,
      // DO NOT upload this stale outbox row. Preserve it for recovery, do not mark local synced,
      // and do not delete the outbox row.
      if (failedEnqueueKeys.contains(rowKey)) {
        tableErrors[outboxRow.targetTable] = enqueueErrors[rowKey] ??
            'Latest local mutation failed to enqueue for $rowKey; upload skipped';
        continue;
      }

      final payloadMap =
          jsonDecode(outboxRow.payload) as Map<String, dynamic>;

      // Workspace scoping: Skip rows belonging to other workspaces
      if (!_recordBelongsToWorkspace(
        targetTable: outboxRow.targetTable,
        payloadMap: payloadMap,
        companyId: companyId,
        activeUserId: activeUserId,
      )) {
        continue;
      }

      try {
        final remoteMap = mapToSnakeCase(
          payloadMap,
          ignoreKeys: {'sync_status', 'syncStatus'},
        );

        final response = await gateway.upsertRow(
          table: outboxRow.targetTable,
          row: remoteMap,
        );

        // Session generation check immediately after awaiting remote call
        if (_isDisposed || _sessionGeneration != currentGeneration) {
          break;
        }

        final recordRevision = (payloadMap['revision'] as int?) ?? 0;
        final bool markedSynced = await _markRecordSyncedIfUnchanged(
          table: outboxRow.targetTable,
          recordId: outboxRow.recordId,
          pushedRevision: recordRevision,
          expectedGeneration: currentGeneration,
          remoteResponse: response,
          outboxId: outboxRow.id,
        );

        if (_isDisposed || _sessionGeneration != currentGeneration) break;

        if (markedSynced) {
          pushedCount++;
        }
      } catch (e) {
        if (_isDisposed || _sessionGeneration != currentGeneration) break;

        final errStr = e.toString();
        tableErrors[outboxRow.targetTable] = errStr;

        final isPermanent4xx = _isPermanentError(e);
        final newAttempts = outboxRow.attempts + 1;
        const maxRetries = 5;

        if (isPermanent4xx || newAttempts >= maxRetries) {
          final finalErr = isPermanent4xx
              ? 'Permanent failure: $errStr'
              : 'Exceeded retry limit ($maxRetries attempts): $errStr';

          if (_isSessionStale(currentGeneration)) break;
          await _recordPermanentFailure(
            table: outboxRow.targetTable,
            recordId: outboxRow.recordId,
            outboxId: outboxRow.id,
            newAttempts: newAttempts,
            finalErr: finalErr,
            expectedGeneration: currentGeneration,
          );
        } else {
          final delaySeconds =
              (1 << (newAttempts > 6 ? 6 : newAttempts)).clamp(1, 300);
          final nextAttempt = DateTime.now().add(
            Duration(seconds: delaySeconds),
          );

          if (_isSessionStale(currentGeneration)) break;
          await _recordTemporaryFailure(
            outboxId: outboxRow.id,
            newAttempts: newAttempts,
            tempErr: 'Temporary failure (attempt $newAttempts): $errStr',
            nextAttempt: nextAttempt,
            expectedGeneration: currentGeneration,
          );
        }
      }
    }

    if (_isDisposed || _sessionGeneration != currentGeneration) {
      return SyncResult(
        status: SyncEngineStatus.idle,
        tableErrors: {'aborted': 'Session invalidated during push'},
        pushedCount: pushedCount,
      );
    }

    final SyncEngineStatus finalStatus;
    if (tableErrors.isNotEmpty) {
      finalStatus = SyncEngineStatus.partial;
    } else {
      finalStatus = SyncEngineStatus.success;
    }
    setStatus(finalStatus);

    return SyncResult(
      status: finalStatus,
      tableErrors: tableErrors,
      pushedCount: pushedCount,
    );
  }

  bool _isPermanentError(dynamic error) {
    if (error is PostgrestException) {
      final code = error.code ?? '';
      if (code.startsWith('23') ||
          code.startsWith('42') ||
          code.startsWith('P')) {
        return true;
      }
      final statusCode = int.tryParse(error.code ?? '');
      if (statusCode != null &&
          statusCode >= 400 &&
          statusCode < 500 &&
          statusCode != 408 &&
          statusCode != 429) {
        return true;
      }
    }
    final msg = error.toString().toLowerCase();
    return msg.contains('violates') ||
        msg.contains('duplicate key') ||
        msg.contains('foreign key') ||
        msg.contains('constraint') ||
        msg.contains('400') ||
        msg.contains('401') ||
        msg.contains('403') ||
        msg.contains('404') ||
        msg.contains('409') ||
        msg.contains('422') ||
        msg.contains('bad request') ||
        msg.contains('unauthorized') ||
        msg.contains('forbidden') ||
        msg.contains('schema error');
  }

  Future<bool> _markRecordSyncedIfUnchanged({
    required String table,
    required String recordId,
    required int pushedRevision,
    required int expectedGeneration,
    Map<String, dynamic>? remoteResponse,
    String? outboxId,
  }) async {
    if (_isSessionStale(expectedGeneration)) return false;

    if (onBeforeMarkSynced != null) {
      await onBeforeMarkSynced!();
    }
    if (_isSessionStale(expectedGeneration)) return false;

    try {
      return await db.transaction<bool>(() async {
        if (_isSessionStale(expectedGeneration)) {
          throw const _SessionInvalidatedException();
        }

        final now = DateTime.now();
        bool updated = false;


    if (table == 'vouchers') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.vouchers,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.vouchers,
        )..where((t) => t.id.equals(recordId))).write(
          VouchersCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'accounts') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.accounts,
        )..where((t) => t.id.equals(recordId))).write(
          AccountsCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'parties') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.parties,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.parties,
        )..where((t) => t.id.equals(recordId))).write(
          PartiesCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'ledger_entries') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.ledgerEntries,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.ledgerEntries,
        )..where((t) => t.id.equals(recordId))).write(
          LedgerEntriesCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'journals') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.journals,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.journals,
        )..where((t) => t.id.equals(recordId))).write(
          JournalsCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'journal_lines') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.journalLines,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.journalLines,
        )..where((t) => t.id.equals(recordId))).write(
          JournalLinesCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'budgets') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.budgets,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.budgets,
        )..where((t) => t.id.equals(recordId))).write(
          BudgetsCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'recurring_rules') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.recurringRules,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.recurringRules,
        )..where((t) => t.id.equals(recordId))).write(
          RecurringRulesCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'companies') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.companies,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.companies,
        )..where((t) => t.id.equals(recordId))).write(
          CompaniesCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'user_profiles') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.userProfiles,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.userProfiles,
        )..where((t) => t.id.equals(recordId))).write(
          UserProfilesCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'exp_wallets') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.expenseWallets,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.expenseWallets,
        )..where((t) => t.id.equals(recordId))).write(
          ExpenseWalletsCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'exp_categories') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.expenseCategories,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.expenseCategories,
        )..where((t) => t.id.equals(recordId))).write(
          ExpenseCategoriesCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'exp_transactions') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.expenseTransactions,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.expenseTransactions,
        )..where((t) => t.id.equals(recordId))).write(
          ExpenseTransactionsCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'exp_budgets') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.expenseBudgets,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.expenseBudgets,
        )..where((t) => t.id.equals(recordId))).write(
          ExpenseBudgetsCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'exp_recurring_rules') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.expenseRecurringRules,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.expenseRecurringRules,
        )..where((t) => t.id.equals(recordId))).write(
          ExpenseRecurringRulesCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'inventory_items') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.inventoryItems,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.inventoryItems,
        )..where((t) => t.id.equals(recordId))).write(
          InventoryItemsCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'stock_ledger') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.stockLedger,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.stockLedger,
        )..where((t) => t.id.equals(recordId))).write(
          StockLedgerCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'audit_logs') {
      if (_isSessionStale(expectedGeneration)) return false;
      final local = await (db.select(
        db.auditLogs,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (_isSessionStale(expectedGeneration)) return false;
      if (local != null && local.revision == pushedRevision) {
        if (_isSessionStale(expectedGeneration)) return false;
        await (db.update(
          db.auditLogs,
        )..where((t) => t.id.equals(recordId))).write(
          AuditLogsCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
        if (!_isSessionStale(expectedGeneration)) updated = true;
      } else if (local == null) {
        if (!_isSessionStale(expectedGeneration)) updated = true;
      }
    } else if (table == 'shared_memberships') {
      if (!_isSessionStale(expectedGeneration)) {
        updated = true;
      }
    }

        if (_isSessionStale(expectedGeneration)) {
          throw const _SessionInvalidatedException();
        }

        if (onInsideMarkSyncedTransaction != null) {
          await onInsideMarkSyncedTransaction!();
        }

        if (_isSessionStale(expectedGeneration)) {
          throw const _SessionInvalidatedException();
        }

        if (updated && outboxId != null) {
          await (db.delete(
            db.syncOutbox,
          )..where((t) => t.id.equals(outboxId))).go();
        }

        if (_isSessionStale(expectedGeneration)) {
          throw const _SessionInvalidatedException();
        }

        return updated;
      });
    } on _SessionInvalidatedException {
      return false;
    } catch (e) {
      debugPrint('Error marking record synced: $e');
      return false;
    }
  }

  Future<void> _recordPermanentFailure({
    required String table,
    required String recordId,
    required String outboxId,
    required int newAttempts,
    required String finalErr,
    required int expectedGeneration,
  }) async {
    if (_isSessionStale(expectedGeneration)) return;

    try {
      await db.transaction(() async {
        if (_isSessionStale(expectedGeneration)) {
          throw const _SessionInvalidatedException();
        }

        await (db.update(db.syncOutbox)
              ..where((t) => t.id.equals(outboxId)))
            .write(SyncOutboxCompanion(
              attempts: Value(newAttempts),
              lastError: Value(finalErr),
              nextAttemptAt: const Value(null),
            ));

        if (_isSessionStale(expectedGeneration)) {
          throw const _SessionInvalidatedException();
        }

        await _markRecordErrorInternal(
          table: table,
          recordId: recordId,
          expectedGeneration: expectedGeneration,
        );

        if (onInsideMarkErrorTransaction != null) {
          await onInsideMarkErrorTransaction!();
        }

        if (_isSessionStale(expectedGeneration)) {
          throw const _SessionInvalidatedException();
        }
      });
    } on _SessionInvalidatedException {
      // Rolled back cleanly due to stale session
    } catch (e) {
      debugPrint('Error in _recordPermanentFailure: $e');
    }
  }

  Future<void> _recordTemporaryFailure({
    required String outboxId,
    required int newAttempts,
    required String tempErr,
    required DateTime nextAttempt,
    required int expectedGeneration,
  }) async {
    if (_isSessionStale(expectedGeneration)) return;

    try {
      await db.transaction(() async {
        if (_isSessionStale(expectedGeneration)) {
          throw const _SessionInvalidatedException();
        }

        await (db.update(
          db.syncOutbox,
        )..where((t) => t.id.equals(outboxId))).write(
          SyncOutboxCompanion(
            attempts: Value(newAttempts),
            lastError: Value(tempErr),
            nextAttemptAt: Value(nextAttempt),
          ),
        );

        if (_isSessionStale(expectedGeneration)) {
          throw const _SessionInvalidatedException();
        }
      });
    } on _SessionInvalidatedException {
      // Rolled back cleanly due to stale session
    } catch (e) {
      debugPrint('Error in _recordTemporaryFailure: $e');
    }
  }

  @visibleForTesting
  Future<void> markRecordErrorForTesting({
    required String table,
    required String recordId,
    required int expectedGeneration,
  }) async {
    if (_isSessionStale(expectedGeneration)) return;
    try {
      await db.transaction(() async {
        if (_isSessionStale(expectedGeneration)) {
          throw const _SessionInvalidatedException();
        }
        await _markRecordErrorInternal(
          table: table,
          recordId: recordId,
          expectedGeneration: expectedGeneration,
        );
      });
    } on _SessionInvalidatedException {
      // Rolled back cleanly
    } catch (e) {
      debugPrint('Error in markRecordErrorForTesting: $e');
    }
  }

  Future<void> _markRecordErrorInternal({
    required String table,
    required String recordId,
    required int expectedGeneration,
  }) async {
    if (_isSessionStale(expectedGeneration)) return;

    if (table == 'vouchers') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(db.vouchers)..where((t) => t.id.equals(recordId))).write(
        const VouchersCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'accounts') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(db.accounts)..where((t) => t.id.equals(recordId))).write(
        const AccountsCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'parties') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(db.parties)..where((t) => t.id.equals(recordId))).write(
        const PartiesCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'ledger_entries') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(
        db.ledgerEntries,
      )..where((t) => t.id.equals(recordId))).write(
        const LedgerEntriesCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'journals') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(db.journals)..where((t) => t.id.equals(recordId))).write(
        const JournalsCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'journal_lines') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(
        db.journalLines,
      )..where((t) => t.id.equals(recordId))).write(
        const JournalLinesCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'budgets') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(db.budgets)..where((t) => t.id.equals(recordId))).write(
        const BudgetsCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'recurring_rules') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(
        db.recurringRules,
      )..where((t) => t.id.equals(recordId))).write(
        const RecurringRulesCompanion(
          syncStatus: Value(SyncRecordStatus.error),
        ),
      );
    } else if (table == 'companies') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(
        db.companies,
      )..where((t) => t.id.equals(recordId))).write(
        const CompaniesCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'user_profiles') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(
        db.userProfiles,
      )..where((t) => t.id.equals(recordId))).write(
        const UserProfilesCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'exp_wallets') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(
        db.expenseWallets,
      )..where((t) => t.id.equals(recordId))).write(
        const ExpenseWalletsCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'exp_categories') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(
        db.expenseCategories,
      )..where((t) => t.id.equals(recordId))).write(
        const ExpenseCategoriesCompanion(
          syncStatus: Value(SyncRecordStatus.error),
        ),
      );
    } else if (table == 'exp_transactions') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(
        db.expenseTransactions,
      )..where((t) => t.id.equals(recordId))).write(
        const ExpenseTransactionsCompanion(
          syncStatus: Value(SyncRecordStatus.error),
        ),
      );
    } else if (table == 'exp_budgets') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(
        db.expenseBudgets,
      )..where((t) => t.id.equals(recordId))).write(
        const ExpenseBudgetsCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'exp_recurring_rules') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(
        db.expenseRecurringRules,
      )..where((t) => t.id.equals(recordId))).write(
        const ExpenseRecurringRulesCompanion(
          syncStatus: Value(SyncRecordStatus.error),
        ),
      );
    } else if (table == 'inventory_items') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(
        db.inventoryItems,
      )..where((t) => t.id.equals(recordId))).write(
        const InventoryItemsCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'stock_ledger') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(
        db.stockLedger,
      )..where((t) => t.id.equals(recordId))).write(
        const StockLedgerCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'audit_logs') {
      if (_isSessionStale(expectedGeneration)) return;
      await (db.update(
        db.auditLogs,
      )..where((t) => t.id.equals(recordId))).write(
        const AuditLogsCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    }
  }

  /// Table Descriptors for Table-Driven Pull Operations
  static final List<SyncTable> syncTables = [
    // 1. Companies (Top level)
    SyncTable<CompanyTableData, CompaniesCompanion>(
      name: 'companies',
      toRemote: (row) => mapToSnakeCase(row.toJson()),
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return CompaniesCompanion(
          id: Value(c['id'] as String),
          name: Value(c['name'] as String? ?? ''),
          legalName: Value(c['legalName'] as String? ?? ''),
          gstin: Value(c['gstin'] as String?),
          stateCode: Value(c['stateCode'] as String?),
          dealerType: Value(c['dealerType'] as String? ?? 'regular'),
          currencyCode: Value(c['currencyCode'] as String? ?? 'INR'),
          address: Value(c['address'] as String?),
          email: Value(c['email'] as String?),
          phoneNumber: Value(c['phoneNumber'] as String?),
          logoUrl: Value(c['logoUrl'] as String?),
          signatureUrl: Value(c['signatureUrl'] as String?),
          signatoryName: Value(c['signatoryName'] as String?),
          bankName: Value(c['bankName'] as String?),
          bankAccountNumber: Value(c['bankAccountNumber'] as String?),
          bankIfsc: Value(c['bankIfsc'] as String?),
          upiId: Value(c['upiId'] as String?),
          isCloudSyncEnabled: Value(
            c['isCloudSyncEnabled'] == true || c['isCloudSyncEnabled'] == 1,
          ),
          isDropboxSyncEnabled: Value(
            c['isDropboxSyncEnabled'] == true || c['isDropboxSyncEnabled'] == 1,
          ),
          isActive: Value(
            c['isActive'] == null ||
                c['isActive'] == true ||
                c['isActive'] == 1,
          ),
          mode: Value(
            (c['mode'] != null && c['mode'].toString().isNotEmpty)
                ? CompanyMode.fromName(c['mode'].toString()).canonicalValue
                : CompanyMode.ledger.canonicalValue,
          ),
          enabledModulesJson: Value(c['enabledModulesJson'] as String?),
          ownerId: Value(c['ownerId'] as String?),
          createdAt: Value(decodeTime(c['createdAt'])),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
    ),

    // SharedMemberships
    SyncTable<SharedMembershipTableData, SharedMembershipsCompanion>(
      name: 'shared_memberships',
      parentTables: ['companies'],
      toRemote: (row) => mapToSnakeCase(row.toJson()),
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return SharedMembershipsCompanion(
          id: Value(c['id'] as String),
          profileId: Value(c['profileId'] as String),
          accountId: Value(c['accountId'] as String),
          role: Value(c['role'] as String? ?? 'viewer'),
          joinedAt: Value(decodeTime(c['joinedAt'] ?? c['joined_at'])),
          updatedAt: Value(decodeTime(c['updatedAt'] ?? c['updated_at'])),
        );
      },
    ),

    // 2. UserProfiles
    SyncTable<UserProfileTableData, UserProfilesCompanion>(
      name: 'user_profiles',
      toRemote: (row) => mapToSnakeCase(row.toJson()),
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return UserProfilesCompanion(
          id: Value(c['id'] as String),
          name: Value(c['name'] as String? ?? ''),
          phoneNumber: Value(c['phoneNumber'] as String? ?? ''),
          email: Value(c['email'] as String? ?? ''),
          businessName: Value(c['businessName'] as String?),
          address: Value(c['address'] as String?),
          gstin: Value(c['gstin'] as String?),
          businessType: Value(c['businessType'] as String?),
          bankName: Value(c['bankName'] as String?),
          bankAccountNumber: Value(c['bankAccountNumber'] as String?),
          bankIfsc: Value(c['bankIfsc'] as String?),
          upiId: Value(c['upiId'] as String?),
          activeCompanyId: Value(
            c['activeCompanyId'] as String? ?? 'cmp_default',
          ),
          role: Value(c['role'] as String? ?? 'admin'),
          companiesJson: Value(c['companiesJson'] as String?),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          createdAt: Value(decodeTime(c['createdAt'])),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
    ),

    // 3. Accounts
    SyncTable<AccountTableData, AccountsCompanion>(
      name: 'accounts',
      parentTables: ['companies'],
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return AccountsCompanion(
          id: Value(c['id'] as String),
          companyId: Value(c['companyId'] as String? ?? 'cmp_default'),
          code: Value(c['code'] as String? ?? '1000'),
          name: Value(c['name'] as String? ?? ''),
          type: Value(c['type'] as String? ?? 'asset'),
          parentAccountId: Value(c['parentAccountId'] as String?),
          isSystem: Value(c['isSystem'] == true || c['isSystem'] == 1),
          isActive: Value(
            c['isActive'] == null ||
                c['isActive'] == true ||
                c['isActive'] == 1,
          ),
          description: Value(c['description'] as String?),
          currentBalanceInCents: Value(
            (c['currentBalanceInCents'] as int?) ?? 0,
          ),
          createdAt: Value(decodeTime(c['createdAt'])),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
      toRemote: (row) => mapToSnakeCase(
        row.toJson(),
        ignoreKeys: {'currentBalanceInCents', 'current_balance_in_cents'},
      ),
    ),

    // 4. Parties
    SyncTable<PartyTableData, PartiesCompanion>(
      name: 'parties',
      parentTables: ['companies'],
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return PartiesCompanion(
          id: Value(c['id'] as String),
          companyId: Value(c['companyId'] as String? ?? 'cmp_default'),
          name: Value(c['name'] as String? ?? ''),
          phoneNumber: Value(c['phoneNumber'] as String? ?? ''),
          type: Value(
            PartyType.values.firstWhere(
              (e) => e.name == c['type'],
              orElse: () => PartyType.customer,
            ),
          ),
          netBalanceInCents: Value((c['netBalanceInCents'] as int?) ?? 0),
          lastUpdated: Value(decodeTime(c['lastUpdated'] ?? c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
      toRemote: (row) => mapToSnakeCase(
        row.toJson(),
        ignoreKeys: {'netBalanceInCents', 'net_balance_in_cents'},
      ),
    ),

    // 5. AuditLogs
    SyncTable<AuditLogTableData, AuditLogsCompanion>(
      name: 'audit_logs',
      parentTables: ['companies'],
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return AuditLogsCompanion(
          id: Value(c['id'] as String),
          companyId: Value(c['companyId'] as String? ?? 'cmp_default'),
          userId: Value(c['userId'] as String? ?? 'usr_default'),
          entityType: Value(c['entityType'] as String? ?? ''),
          entityId: Value(c['entityId'] as String? ?? ''),
          action: Value(c['action'] as String? ?? ''),
          timestamp: Value(decodeTime(c['timestamp'])),
          oldStateJson: Value(c['oldStateJson'] as String?),
          newStateJson: Value(c['newStateJson'] as String?),
          diffJson: Value(c['diffJson'] as String?),
          checksum: Value(c['checksum'] as String? ?? ''),
          previousChecksum: Value(c['previousChecksum'] as String?),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
      toRemote: (row) => mapToSnakeCase(row.toJson()),
    ),

    // 6. InventoryItems
    SyncTable<InventoryItemTableData, InventoryItemsCompanion>(
      name: 'inventory_items',
      parentTables: ['companies'],
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return InventoryItemsCompanion(
          id: Value(c['id'] as String),
          companyId: Value(c['companyId'] as String? ?? 'cmp_default'),
          sku: Value(c['sku'] as String? ?? ''),
          name: Value(c['name'] as String? ?? ''),
          description: Value(c['description'] as String?),
          unit: Value(c['unit'] as String? ?? 'PCS'),
          purchasePriceInCents: Value((c['purchasePriceInCents'] as int?) ?? 0),
          sellingPriceInCents: Value((c['sellingPriceInCents'] as int?) ?? 0),
          currentStockQuantity: Value(
            (c['currentStockQuantity'] as num?)?.toDouble() ?? 0.0,
          ),
          minimumStockAlert: Value(
            (c['minimumStockAlert'] as num?)?.toDouble() ?? 5.0,
          ),
          hsnCode: Value(c['hsnCode'] as String?),
          taxRatePercent: Value(
            (c['taxRatePercent'] as num?)?.toDouble() ?? 0.0,
          ),
          isActive: Value(
            c['isActive'] == null ||
                c['isActive'] == true ||
                c['isActive'] == 1,
          ),
          createdAt: Value(decodeTime(c['createdAt'])),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
      toRemote: (row) => mapToSnakeCase(row.toJson()),
    ),

    // 7. Vouchers
    SyncTable<VoucherTableData, VouchersCompanion>(
      name: 'vouchers',
      parentTables: ['companies', 'parties'],
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return VouchersCompanion(
          id: Value(c['id'] as String),
          companyId: Value(c['companyId'] as String? ?? 'cmp_default'),
          voucherNumber: Value(c['voucherNumber'] as String? ?? 'VCH-0'),
          type: Value(c['type'] as String? ?? 'expense'),
          date: Value(decodeTime(c['date'])),
          dueDate: Value(
            c['dueDate'] != null ? decodeTime(c['dueDate']) : null,
          ),
          partyId: Value(c['partyId'] as String?),
          partyName: Value(c['partyName'] as String?),
          status: Value(c['status'] as String? ?? 'posted'),
          paymentMode: Value(c['paymentMode'] as String? ?? 'cash'),
          subtotalInCents: Value((c['subtotalInCents'] as int?) ?? 0),
          taxInCents: Value((c['taxInCents'] as int?) ?? 0),
          discountInCents: Value((c['discountInCents'] as int?) ?? 0),
          totalAmountInCents: Value((c['totalAmountInCents'] as int?) ?? 0),
          narration: Value(c['narration'] as String?),
          referenceNumber: Value(c['referenceNumber'] as String?),
          sourceVoucherId: Value(c['sourceVoucherId'] as String?),
          receiptPhotoUrl: Value(c['receiptPhotoUrl'] as String?),
          itemsJson: Value(c['itemsJson'] as String?),
          categoryAccountId: Value(c['categoryAccountId'] as String?),
          walletAccountId: Value(c['walletAccountId'] as String?),
          toWalletAccountId: Value(c['toWalletAccountId'] as String?),
          createdAt: Value(decodeTime(c['createdAt'])),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
      toRemote: (row) => mapToSnakeCase(row.toJson()),
    ),

    // 8. Journals
    SyncTable<JournalTableData, JournalsCompanion>(
      name: 'journals',
      parentTables: ['companies', 'vouchers'],
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return JournalsCompanion(
          id: Value(c['id'] as String),
          companyId: Value(c['companyId'] as String? ?? 'cmp_default'),
          journalNumber: Value(c['journalNumber'] as String? ?? 'JNL-0'),
          voucherId: Value(c['voucherId'] as String?),
          date: Value(decodeTime(c['date'])),
          narration: Value(c['narration'] as String?),
          totalAmountInCents: Value((c['totalAmountInCents'] as int?) ?? 0),
          status: Value(c['status'] as String? ?? 'posted'),
          createdAt: Value(decodeTime(c['createdAt'])),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
      toRemote: (row) => mapToSnakeCase(row.toJson()),
    ),

    // 9. JournalLines
    SyncTable<JournalLineTableData, JournalLinesCompanion>(
      name: 'journal_lines',
      parentTables: ['journals', 'accounts'],
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return JournalLinesCompanion(
          id: Value(c['id'] as String),
          companyId: Value(c['companyId'] as String? ?? 'cmp_default'),
          journalId: Value(c['journalId'] as String? ?? ''),
          accountId: Value(c['accountId'] as String? ?? ''),
          partyId: Value(c['partyId'] as String?),
          debitInCents: Value((c['debitInCents'] as int?) ?? 0),
          creditInCents: Value((c['creditInCents'] as int?) ?? 0),
          narration: Value(c['narration'] as String?),
          createdAt: Value(decodeTime(c['createdAt'])),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
      toRemote: (row) => mapToSnakeCase(row.toJson()),
    ),

    // 10. StockLedger
    SyncTable<StockLedgerTableData, StockLedgerCompanion>(
      name: 'stock_ledger',
      parentTables: ['inventory_items', 'vouchers'],
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return StockLedgerCompanion(
          id: Value(c['id'] as String),
          companyId: Value(c['companyId'] as String? ?? 'cmp_default'),
          itemId: Value(c['itemId'] as String? ?? ''),
          voucherId: Value(c['voucherId'] as String?),
          transactionType: Value(c['transactionType'] as String? ?? 'inward'),
          quantity: Value((c['quantity'] as num?)?.toDouble() ?? 0.0),
          unitCostInCents: Value((c['unitCostInCents'] as int?) ?? 0),
          totalCostInCents: Value((c['totalCostInCents'] as int?) ?? 0),
          runningStockQuantity: Value(
            (c['runningStockQuantity'] as num?)?.toDouble() ?? 0.0,
          ),
          date: Value(decodeTime(c['date'])),
          note: Value(c['note'] as String?),
          createdAt: Value(decodeTime(c['createdAt'])),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
      toRemote: (row) => mapToSnakeCase(row.toJson()),
    ),

    // 11. LedgerEntries
    SyncTable<LedgerEntryTableData, LedgerEntriesCompanion>(
      name: 'ledger_entries',
      parentTables: ['parties'],
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return LedgerEntriesCompanion(
          id: Value(c['id'] as String),
          companyId: Value(c['companyId'] as String? ?? 'cmp_default'),
          partyId: Value(c['partyId'] as String? ?? ''),
          amountInCents: Value((c['amountInCents'] as int?) ?? 0),
          type: Value(
            EntryType.values.firstWhere(
              (e) => e.name == c['type'],
              orElse: () => EntryType.gave,
            ),
          ),
          date: Value(decodeTime(c['date'])),
          note: Value(c['note'] as String?),
          receiptPhotoUrl: Value(c['receiptPhotoUrl'] as String?),
          isVoided: Value(c['isVoided'] == true || c['isVoided'] == 1),
          createdAt: Value(decodeTime(c['createdAt'])),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
      toRemote: (row) => mapToSnakeCase(row.toJson()),
    ),

    // 12. Budgets
    SyncTable<BudgetTableData, BudgetsCompanion>(
      name: 'budgets',
      parentTables: ['companies', 'accounts'],
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return BudgetsCompanion(
          id: Value(c['id'] as String),
          companyId: Value(c['companyId'] as String? ?? 'cmp_default'),
          categoryAccountId: Value(c['categoryAccountId'] as String? ?? ''),
          periodType: Value(c['periodType'] as String? ?? 'monthly'),
          amountInCents: Value((c['amountInCents'] as int?) ?? 0),
          startDate: Value(decodeTime(c['startDate'])),
          rolloverEnabled: Value(
            c['rolloverEnabled'] == true || c['rolloverEnabled'] == 1,
          ),
          isActive: Value(
            c['isActive'] == null ||
                c['isActive'] == true ||
                c['isActive'] == 1,
          ),
          createdAt: Value(decodeTime(c['createdAt'])),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
      toRemote: (row) => mapToSnakeCase(row.toJson()),
    ),

    // 13. RecurringRules
    SyncTable<RecurringRuleTableData, RecurringRulesCompanion>(
      name: 'recurring_rules',
      parentTables: ['companies'],
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return RecurringRulesCompanion(
          id: Value(c['id'] as String),
          companyId: Value(c['companyId'] as String? ?? 'cmp_default'),
          templateJson: Value(c['templateJson'] as String? ?? '{}'),
          intervalType: Value(c['intervalType'] as String? ?? 'monthly'),
          intervalCount: Value((c['intervalCount'] as int?) ?? 1),
          nextRunDate: Value(decodeTime(c['nextRunDate'])),
          endDate: Value(
            c['endDate'] != null ? decodeTime(c['endDate']) : null,
          ),
          isActive: Value(
            c['isActive'] == null ||
                c['isActive'] == true ||
                c['isActive'] == 1,
          ),
          createdAt: Value(decodeTime(c['createdAt'])),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
      toRemote: (row) => mapToSnakeCase(row.toJson()),
    ),

    // 14. ExpenseWallets
    SyncTable<ExpenseWalletTableData, ExpenseWalletsCompanion>(
      name: 'exp_wallets',
      parentTables: ['companies'],
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return ExpenseWalletsCompanion(
          id: Value(c['id'] as String),
          profileId: Value(
            (c['profileId'] ?? c['companyId']) as String? ?? 'cmp_default',
          ),
          name: Value(c['name'] as String? ?? ''),
          walletType: Value(c['walletType'] as String? ?? 'cash'),
          currencyCode: Value(c['currencyCode'] as String? ?? 'INR'),
          startingBalanceInCents: Value(
            (c['startingBalanceInCents'] as int?) ?? 0,
          ),
          currentBalanceInCents: Value(
            (c['currentBalanceInCents'] as int?) ?? 0,
          ),
          colorHex: Value(c['colorHex'] as String?),
          iconName: Value(c['iconName'] as String?),
          isArchived: Value(c['isArchived'] == true || c['isArchived'] == 1),
          createdAt: Value(decodeTime(c['createdAt'])),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
      toRemote: (row) => mapToSnakeCase(row.toJson()),
    ),

    // 15. ExpenseCategories
    SyncTable<ExpenseCategoryTableData, ExpenseCategoriesCompanion>(
      name: 'exp_categories',
      parentTables: ['companies'],
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return ExpenseCategoriesCompanion(
          id: Value(c['id'] as String),
          profileId: Value(
            (c['profileId'] ?? c['companyId']) as String? ?? 'cmp_default',
          ),
          name: Value(c['name'] as String? ?? ''),
          categoryType: Value(c['categoryType'] as String? ?? 'expense'),
          parentCategoryId: Value(c['parentCategoryId'] as String?),
          iconName: Value(c['iconName'] as String?),
          colorHex: Value(c['colorHex'] as String?),
          isSystem: Value(c['isSystem'] == true || c['isSystem'] == 1),
          createdAt: Value(decodeTime(c['createdAt'])),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
      toRemote: (row) => mapToSnakeCase(row.toJson()),
    ),

    // 16. ExpenseBudgets
    SyncTable<ExpenseBudgetTableData, ExpenseBudgetsCompanion>(
      name: 'exp_budgets',
      parentTables: ['companies', 'exp_categories'],
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return ExpenseBudgetsCompanion(
          id: Value(c['id'] as String),
          profileId: Value(
            (c['profileId'] ?? c['companyId']) as String? ?? 'cmp_default',
          ),
          categoryId: Value(c['categoryId'] as String?),
          periodType: Value(c['periodType'] as String? ?? 'monthly'),
          amountInCents: Value((c['amountInCents'] as int?) ?? 0),
          startDate: Value(decodeTime(c['startDate'])),
          endDate: Value(c['endDate'] != null ? decodeTime(c['endDate']) : null),
          alertThresholdPercent: Value(
            (c['alertThresholdPercent'] as int?) ?? 80,
          ),
          createdAt: Value(decodeTime(c['createdAt'])),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
      toRemote: (row) => mapToSnakeCase(row.toJson()),
    ),

    // 17. ExpenseRecurringRules
    SyncTable<ExpenseRecurringRuleTableData, ExpenseRecurringRulesCompanion>(
      name: 'exp_recurring_rules',
      parentTables: ['companies'],
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return ExpenseRecurringRulesCompanion(
          id: Value(c['id'] as String),
          profileId: Value(
            (c['profileId'] ?? c['companyId']) as String? ?? 'cmp_default',
          ),
          templateJson: Value(c['templateJson'] as String? ?? '{}'),
          intervalType: Value(c['intervalType'] as String? ?? 'monthly'),
          intervalCount: Value((c['intervalCount'] as int?) ?? 1),
          nextRunDate: Value(decodeTime(c['nextRunDate'])),
          endDate: Value(c['endDate'] != null ? decodeTime(c['endDate']) : null),
          isActive: Value(
            c['isActive'] == null ||
                c['isActive'] == true ||
                c['isActive'] == 1,
          ),
          createdAt: Value(decodeTime(c['createdAt'])),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
      toRemote: (row) => mapToSnakeCase(row.toJson()),
    ),

    // 18. ExpenseTransactions
    SyncTable<ExpenseTransactionTableData, ExpenseTransactionsCompanion>(
      name: 'exp_transactions',
      parentTables: ['companies', 'exp_wallets', 'exp_categories'],
      fromRemote: (map) {
        final c = mapToCamelCase(map);
        return ExpenseTransactionsCompanion(
          id: Value(c['id'] as String),
          profileId: Value(
            (c['profileId'] ?? c['companyId']) as String? ?? 'cmp_default',
          ),
          transactionType: Value(c['transactionType'] as String? ?? 'expense'),
          amountInCents: Value((c['amountInCents'] as int?) ?? 0),
          walletId: Value(c['walletId'] as String? ?? ''),
          toWalletId: Value(c['toWalletId'] as String?),
          categoryId: Value(c['categoryId'] as String?),
          transactionDate: Value(decodeTime(c['transactionDate'])),
          note: Value(c['note'] as String?),
          payeeOrPayer: Value(c['payeeOrPayer'] as String?),
          referenceNumber: Value(c['referenceNumber'] as String?),
          receiptPhotoUrl: Value(c['receiptPhotoUrl'] as String?),
          isCleared: Value(
            c['isCleared'] == null ||
                c['isCleared'] == true ||
                c['isCleared'] == 1,
          ),
          createdAt: Value(decodeTime(c['createdAt'])),
          updatedAt: Value(decodeTime(c['updatedAt'])),
          isDeleted: Value(c['isDeleted'] == true || c['isDeleted'] == 1),
          syncStatus: const Value(SyncRecordStatus.synced),
          revision: Value((c['revision'] as int?) ?? 0),
          remoteUpdatedAt: Value(
            decodeTime(c['updatedAt'] ?? c['remoteUpdatedAt']),
          ),
        );
      },
      toRemote: (row) => mapToSnakeCase(row.toJson()),
    ),
  ];

  /// Pulls changes from remote backend for [companyId] in FK-safe topological order.
  Future<SyncResult> pullChanges({String? companyId}) async {
    final cid = companyId ?? 'cmp_default';
    return _synchronizedSync(() async {
      return _pullChangesInternal(companyId: cid);
    });
  }

  Future<SyncResult> _pullChangesInternal({required String companyId}) async {
    final currentGeneration = _sessionGeneration;
    if (_isDisposed || _sessionGeneration != currentGeneration) {
      return SyncResult(
        status: SyncEngineStatus.idle,
        tableErrors: {'aborted': 'Engine was disposed or session invalidated'},
      );
    }

    setStatus(SyncEngineStatus.syncing);
    final tableErrors = <String, String>{};
    int totalPulled = 0;

    for (final table in syncTables) {
      if (_isDisposed || _sessionGeneration != currentGeneration) break;

      try {
        final syncStateRow =
            await (db.select(db.syncState)..where(
                  (t) =>
                      t.targetTable.equals(table.name) &
                      t.companyId.equals(companyId),
                ))
                .getSingleOrNull();

        final cursor = syncStateRow?.lastPulledAt;
        DateTime? maxRemoteUpdatedAt = cursor;
        DateTime? earliestSkippedUpdatedAt;

        DateTime? afterUpdatedAt;
        String? afterId;
        final pullPageSize = pageSize;
        bool tablePullCompleted = false;

        while (true) {
          if (_isSessionStale(currentGeneration)) break;

          final remoteRows = await gateway.pullRows(
            table: table.name,
            companyId: companyId,
            activeUserId: activeUserId,
            cursor: cursor,
            pageSize: pullPageSize,
            afterUpdatedAt: afterUpdatedAt,
            afterId: afterId,
          );

          if (_isSessionStale(currentGeneration)) break;

          if (remoteRows.isEmpty) {
            tablePullCompleted = true;
            break;
          }

          if (onBeforeApplyRemoteRows != null) {
            await onBeforeApplyRemoteRows!();
          }

          if (_isSessionStale(currentGeneration)) break;

          int pagePulledCount = 0;
          try {
            await db.transaction(() async {
              if (_isSessionStale(currentGeneration)) {
                throw const _SessionInvalidatedException();
              }

              for (int i = 0; i < remoteRows.length; i++) {
                final remoteMap = remoteRows[i];
                if (_isSessionStale(currentGeneration)) {
                  throw const _SessionInvalidatedException();
                }

                final remoteUpdatedStr =
                    remoteMap['updated_at'] ??
                    remoteMap['updatedAt'] ??
                    remoteMap['created_at'];
                final dt = remoteUpdatedStr != null
                    ? decodeTime(remoteUpdatedStr)
                    : null;

                final recordId = (remoteMap['id'] ?? remoteMap['record_id'])
                    ?.toString();
                if (recordId == null) continue;

                final isPendingLocal = await _isRecordPendingLocal(
                  table.name,
                  recordId,
                );
                if (isPendingLocal) {
                  // Conflict resolution: protect un-pushed local edits.
                  // Track earliest skipped row so cursor does not advance past it.
                  if (dt != null) {
                    if (earliestSkippedUpdatedAt == null ||
                        dt.isBefore(earliestSkippedUpdatedAt!)) {
                      earliestSkippedUpdatedAt = dt;
                    }
                  }
                  continue;
                }

                if (dt != null) {
                  if (maxRemoteUpdatedAt == null ||
                      dt.isAfter(maxRemoteUpdatedAt!)) {
                    maxRemoteUpdatedAt = dt;
                  }
                }

                final isDeleted =
                    remoteMap['is_deleted'] == true ||
                    remoteMap['is_deleted'] == 1;

                if (isDeleted) {
                  await _applySoftDeleteLocally(
                    table.name,
                    recordId,
                    maxRemoteUpdatedAt,
                  );
                } else {
                  final companion = table.fromRemote(remoteMap);
                  await _applyRemoteUpsertLocally(table.name, companion);
                }

                if (onInsidePullRow != null) {
                  await onInsidePullRow!(table.name, recordId, i);
                }

                if (_isSessionStale(currentGeneration)) {
                  throw const _SessionInvalidatedException();
                }

                pagePulledCount++;
              }

              if (_isSessionStale(currentGeneration)) {
                throw const _SessionInvalidatedException();
              }
            });
            totalPulled += pagePulledCount;
          } on _SessionInvalidatedException {
            tablePullCompleted = false;
            break;
          }

          if (_isSessionStale(currentGeneration)) break;

          if (remoteRows.length < pullPageSize) {
            tablePullCompleted = true;
            break;
          }

          final lastRow = remoteRows.last;
          final lastUpdatedStr =
              lastRow['updated_at'] ??
              lastRow['updatedAt'] ??
              lastRow['created_at'];
          afterUpdatedAt =
              lastUpdatedStr != null ? decodeTime(lastUpdatedStr) : null;
          afterId = (lastRow['id'] ?? lastRow['record_id'])?.toString();
        }

        if (_isSessionStale(currentGeneration)) break;

        // Recalculate balances BEFORE cursor advancement if needed for this table
        if (tablePullCompleted && !_isSessionStale(currentGeneration)) {
          if (table.name == 'journals' || table.name == 'journal_lines') {
            try {
              await _recalculateAccountBalances(companyId, currentGeneration);
            } on _SessionInvalidatedException {
              tablePullCompleted = false;
              break;
            } catch (e) {
              tablePullCompleted = false;
              rethrow;
            }
          } else if (table.name == 'exp_transactions') {
            try {
              await _recalculateWalletBalances(companyId, currentGeneration);
            } on _SessionInvalidatedException {
              tablePullCompleted = false;
              break;
            } catch (e) {
              tablePullCompleted = false;
              rethrow;
            }
          }
        }

        if (_isSessionStale(currentGeneration)) break;

        // Advance cursor only if pull and recalculation completed without error or interruption
        if (tablePullCompleted && !_isSessionStale(currentGeneration)) {
          DateTime? safeNewCursor = maxRemoteUpdatedAt;
          if (earliestSkippedUpdatedAt != null) {
            if (safeNewCursor == null ||
                earliestSkippedUpdatedAt!.isBefore(safeNewCursor)) {
              safeNewCursor = earliestSkippedUpdatedAt;
            }
          }

          if (safeNewCursor != null) {
            if (onBeforePersistCursor != null) {
              await onBeforePersistCursor!();
            }
            if (_isSessionStale(currentGeneration)) break;

            try {
              await db.transaction(() async {
                if (_isSessionStale(currentGeneration)) {
                  throw const _SessionInvalidatedException();
                }

                await db
                    .into(db.syncState)
                    .insertOnConflictUpdate(
                      SyncStateCompanion(
                        targetTable: Value(table.name),
                        companyId: Value(companyId),
                        lastPulledAt: Value(safeNewCursor),
                      ),
                    );

                if (onInsideCursorTransaction != null) {
                  await onInsideCursorTransaction!();
                }

                if (_isSessionStale(currentGeneration)) {
                  throw const _SessionInvalidatedException();
                }
              });
            } on _SessionInvalidatedException {
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Error pulling table ${table.name}: $e');
        tableErrors[table.name] = e.toString();
        // Do NOT advance cursor for failed table
      }
      if (_isDisposed || _sessionGeneration != currentGeneration) break;
    }

    if (_isDisposed || _sessionGeneration != currentGeneration) {
      return SyncResult(
        status: SyncEngineStatus.idle,
        tableErrors: {'aborted': 'Session invalidated during pull'},
        pulledCount: totalPulled,
      );
    }

    final SyncEngineStatus finalStatus;
    if (tableErrors.isNotEmpty) {
      finalStatus = SyncEngineStatus.partial;
    } else {
      finalStatus = SyncEngineStatus.success;
    }
    setStatus(finalStatus);

    return SyncResult(
      status: finalStatus,
      tableErrors: tableErrors,
      pulledCount: totalPulled,
    );
  }

  Future<bool> _isRecordPendingLocal(String table, String recordId) async {
    if (table == 'vouchers') {
      final r = await (db.select(
        db.vouchers,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'accounts') {
      final r = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'parties') {
      final r = await (db.select(
        db.parties,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'ledger_entries') {
      final r = await (db.select(
        db.ledgerEntries,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'journals') {
      final r = await (db.select(
        db.journals,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'journal_lines') {
      final r = await (db.select(
        db.journalLines,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'budgets') {
      final r = await (db.select(
        db.budgets,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'recurring_rules') {
      final r = await (db.select(
        db.recurringRules,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'companies') {
      final r = await (db.select(
        db.companies,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'user_profiles') {
      final r = await (db.select(
        db.userProfiles,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'shared_memberships') {
      final outboxItem = await (db.select(db.syncOutbox)
            ..where((t) =>
                t.targetTable.equals('shared_memberships') &
                t.recordId.equals(recordId)))
          .getSingleOrNull();
      return outboxItem != null;
    } else if (table == 'inventory_items') {
      final r = await (db.select(
        db.inventoryItems,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'stock_ledger') {
      final r = await (db.select(
        db.stockLedger,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'audit_logs') {
      final r = await (db.select(
        db.auditLogs,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'exp_wallets') {
      final r = await (db.select(
        db.expenseWallets,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'exp_categories') {
      final r = await (db.select(
        db.expenseCategories,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'exp_transactions') {
      final r = await (db.select(
        db.expenseTransactions,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'exp_budgets') {
      final r = await (db.select(
        db.expenseBudgets,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    } else if (table == 'exp_recurring_rules') {
      final r = await (db.select(
        db.expenseRecurringRules,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      return r != null && r.syncStatus != SyncRecordStatus.synced;
    }
    return false;
  }

  Future<void> _applySoftDeleteLocally(
    String table,
    String recordId,
    DateTime? remoteUpdatedAt,
  ) async {
    final dt = remoteUpdatedAt ?? DateTime.now();

    if (table == 'vouchers') {
      await (db.update(db.vouchers)..where((t) => t.id.equals(recordId))).write(
        VouchersCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'accounts') {
      await (db.update(db.accounts)..where((t) => t.id.equals(recordId))).write(
        AccountsCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'parties') {
      await (db.update(db.parties)..where((t) => t.id.equals(recordId))).write(
        PartiesCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'ledger_entries') {
      await (db.update(
        db.ledgerEntries,
      )..where((t) => t.id.equals(recordId))).write(
        LedgerEntriesCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'journals') {
      await (db.update(db.journals)..where((t) => t.id.equals(recordId))).write(
        JournalsCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'journal_lines') {
      await (db.update(
        db.journalLines,
      )..where((t) => t.id.equals(recordId))).write(
        JournalLinesCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'budgets') {
      await (db.update(db.budgets)..where((t) => t.id.equals(recordId))).write(
        BudgetsCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'recurring_rules') {
      await (db.update(
        db.recurringRules,
      )..where((t) => t.id.equals(recordId))).write(
        RecurringRulesCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'companies') {
      await (db.update(db.companies)..where((t) => t.id.equals(recordId))).write(
        CompaniesCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'user_profiles') {
      await (db.update(
        db.userProfiles,
      )..where((t) => t.id.equals(recordId))).write(
        UserProfilesCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'exp_wallets') {
      await (db.update(
        db.expenseWallets,
      )..where((t) => t.id.equals(recordId))).write(
        ExpenseWalletsCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'exp_categories') {
      await (db.update(
        db.expenseCategories,
      )..where((t) => t.id.equals(recordId))).write(
        ExpenseCategoriesCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'exp_transactions') {
      await (db.update(
        db.expenseTransactions,
      )..where((t) => t.id.equals(recordId))).write(
        ExpenseTransactionsCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'exp_budgets') {
      await (db.update(
        db.expenseBudgets,
      )..where((t) => t.id.equals(recordId))).write(
        ExpenseBudgetsCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'exp_recurring_rules') {
      await (db.update(
        db.expenseRecurringRules,
      )..where((t) => t.id.equals(recordId))).write(
        ExpenseRecurringRulesCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'inventory_items') {
      await (db.update(
        db.inventoryItems,
      )..where((t) => t.id.equals(recordId))).write(
        InventoryItemsCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'stock_ledger') {
      await (db.update(
        db.stockLedger,
      )..where((t) => t.id.equals(recordId))).write(
        StockLedgerCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    } else if (table == 'audit_logs') {
      await (db.update(
        db.auditLogs,
      )..where((t) => t.id.equals(recordId))).write(
        AuditLogsCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.synced),
          remoteUpdatedAt: Value(dt),
        ),
      );
    }
  }

  Future<void> _applyRemoteUpsertLocally(
    String table,
    dynamic companion,
  ) async {
    if (table == 'vouchers') {
      await db
          .into(db.vouchers)
          .insertOnConflictUpdate(companion as VouchersCompanion);
    } else if (table == 'accounts') {
      await db
          .into(db.accounts)
          .insertOnConflictUpdate(companion as AccountsCompanion);
    } else if (table == 'parties') {
      await db
          .into(db.parties)
          .insertOnConflictUpdate(companion as PartiesCompanion);
    } else if (table == 'ledger_entries') {
      await db
          .into(db.ledgerEntries)
          .insertOnConflictUpdate(companion as LedgerEntriesCompanion);
    } else if (table == 'journals') {
      await db
          .into(db.journals)
          .insertOnConflictUpdate(companion as JournalsCompanion);
    } else if (table == 'journal_lines') {
      await db
          .into(db.journalLines)
          .insertOnConflictUpdate(companion as JournalLinesCompanion);
    } else if (table == 'budgets') {
      await db
          .into(db.budgets)
          .insertOnConflictUpdate(companion as BudgetsCompanion);
    } else if (table == 'recurring_rules') {
      await db
          .into(db.recurringRules)
          .insertOnConflictUpdate(companion as RecurringRulesCompanion);
    } else if (table == 'companies') {
      await db
          .into(db.companies)
          .insertOnConflictUpdate(companion as CompaniesCompanion);
    } else if (table == 'user_profiles') {
      await db
          .into(db.userProfiles)
          .insertOnConflictUpdate(companion as UserProfilesCompanion);
    } else if (table == 'shared_memberships') {
      await db
          .into(db.sharedMemberships)
          .insertOnConflictUpdate(companion as SharedMembershipsCompanion);
    } else if (table == 'inventory_items') {
      await db
          .into(db.inventoryItems)
          .insertOnConflictUpdate(companion as InventoryItemsCompanion);
    } else if (table == 'stock_ledger') {
      await db
          .into(db.stockLedger)
          .insertOnConflictUpdate(companion as StockLedgerCompanion);
    } else if (table == 'audit_logs') {
      await db
          .into(db.auditLogs)
          .insertOnConflictUpdate(companion as AuditLogsCompanion);
    } else if (table == 'exp_wallets') {
      await db
          .into(db.expenseWallets)
          .insertOnConflictUpdate(companion as ExpenseWalletsCompanion);
    } else if (table == 'exp_categories') {
      await db
          .into(db.expenseCategories)
          .insertOnConflictUpdate(companion as ExpenseCategoriesCompanion);
    } else if (table == 'exp_transactions') {
      await db
          .into(db.expenseTransactions)
          .insertOnConflictUpdate(companion as ExpenseTransactionsCompanion);
    } else if (table == 'exp_budgets') {
      await db
          .into(db.expenseBudgets)
          .insertOnConflictUpdate(companion as ExpenseBudgetsCompanion);
    } else if (table == 'exp_recurring_rules') {
      await db
          .into(db.expenseRecurringRules)
          .insertOnConflictUpdate(companion as ExpenseRecurringRulesCompanion);
    }
  }

  Future<void> _recalculateWalletBalances(
    String profileId, [
    int? expectedGeneration,
  ]) async {
    final gen = expectedGeneration ?? _sessionGeneration;
    if (_isSessionStale(gen)) {
      throw const _SessionInvalidatedException();
    }

    await db.transaction(() async {
      if (_isSessionStale(gen)) {
        throw const _SessionInvalidatedException();
      }

      final wallets = await (db.select(db.expenseWallets)
            ..where((t) => t.profileId.equals(profileId)))
          .get();

      final txns = await (db.select(db.expenseTransactions)
            ..where((t) =>
                t.profileId.equals(profileId) & t.isDeleted.equals(false)))
          .get();

      for (int i = 0; i < wallets.length; i++) {
        if (_isSessionStale(gen)) {
          throw const _SessionInvalidatedException();
        }

        final wallet = wallets[i];

        if (onInsideWalletBalanceRecalculation != null) {
          await onInsideWalletBalanceRecalculation!(profileId, wallet.id, i);
        }

        if (_isSessionStale(gen)) {
          throw const _SessionInvalidatedException();
        }

        int balance = wallet.startingBalanceInCents;
        for (final tx in txns) {
          final type = tx.transactionType.toLowerCase();
          if (tx.walletId == wallet.id) {
            if (type == 'expense' || type == 'transfer') {
              balance -= tx.amountInCents;
            } else if (type == 'income') {
              balance += tx.amountInCents;
            }
          }
          if (tx.toWalletId == wallet.id && type == 'transfer') {
            balance += tx.amountInCents;
          }
        }

        if (wallet.currentBalanceInCents != balance) {
          await (db.update(db.expenseWallets)..where((t) => t.id.equals(wallet.id)))
              .write(
            ExpenseWalletsCompanion(
              currentBalanceInCents: Value(balance),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }

        if (_isSessionStale(gen)) {
          throw const _SessionInvalidatedException();
        }
      }

      if (_isSessionStale(gen)) {
        throw const _SessionInvalidatedException();
      }
    });
  }

  Future<void> _recalculateAccountBalances(
    String companyId, [
    int? expectedGeneration,
  ]) async {
    final gen = expectedGeneration ?? _sessionGeneration;
    if (_isSessionStale(gen)) {
      throw const _SessionInvalidatedException();
    }

    await db.transaction(() async {
      if (_isSessionStale(gen)) {
        throw const _SessionInvalidatedException();
      }

      final companyAccounts = await (db.select(
        db.accounts,
      )..where((t) => t.companyId.equals(companyId))).get();

      for (int i = 0; i < companyAccounts.length; i++) {
        if (_isSessionStale(gen)) {
          throw const _SessionInvalidatedException();
        }

        final acc = companyAccounts[i];

        if (onInsideAccountBalanceRecalculation != null) {
          await onInsideAccountBalanceRecalculation!(companyId, acc.id, i);
        }

        if (_isSessionStale(gen)) {
          throw const _SessionInvalidatedException();
        }

        final query =
            db.select(db.journalLines).join([
              innerJoin(
                db.journals,
                db.journals.id.equalsExp(db.journalLines.journalId),
              ),
            ])..where(
              db.journalLines.accountId.equals(acc.id) &
                  db.journalLines.companyId.equals(companyId) &
                  db.journalLines.isDeleted.equals(false) &
                  db.journals.status.equals('posted'),
            );
        final lines = await query.get();
        int debit = 0;
        int credit = 0;
        for (final r in lines) {
          final line = r.readTable(db.journalLines);
          debit += line.debitInCents;
          credit += line.creditInCents;
        }
        final accountType = AccountType.values.firstWhere(
          (e) => e.name.toLowerCase() == acc.type.toLowerCase(),
          orElse: () => AccountType.asset,
        );
        final net = accountType.isDebitNormal
            ? (debit - credit)
            : (credit - debit);

        if (acc.currentBalanceInCents != net) {
          await (db.update(db.accounts)..where((t) => t.id.equals(acc.id))).write(
            AccountsCompanion(
              currentBalanceInCents: Value(net),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }

        if (_isSessionStale(gen)) {
          throw const _SessionInvalidatedException();
        }
      }

      if (_isSessionStale(gen)) {
        throw const _SessionInvalidatedException();
      }
    });
  }

  /// Triggers full sync (push followed by pull)
  Future<SyncResult> syncAll({String? companyId}) async {
    final cid = (companyId != null && companyId.isNotEmpty)
        ? companyId
        : 'cmp_default';
    return _synchronizedSync(() async {
      setStatus(SyncEngineStatus.syncing);
      final pushResult = await _pushQueueInternal(companyId: cid);
      final pullResult = await _pullChangesInternal(companyId: cid);

      final combinedErrors = <String, String>{
        ...pushResult.tableErrors,
        ...pullResult.tableErrors,
      };

      final totalPushed = pushResult.pushedCount;
      final totalPulled = pullResult.pulledCount;

      if (pushResult.status == SyncEngineStatus.idle ||
          pullResult.status == SyncEngineStatus.idle) {
        return SyncResult(
          status: SyncEngineStatus.idle,
          tableErrors: combinedErrors,
          pushedCount: totalPushed,
          pulledCount: totalPulled,
        );
      }

      final SyncEngineStatus finalStatus;
      if (combinedErrors.isNotEmpty) {
        finalStatus = SyncEngineStatus.partial;
      } else {
        finalStatus = SyncEngineStatus.success;
      }

      setStatus(finalStatus);
      return SyncResult(
        status: finalStatus,
        tableErrors: combinedErrors,
        pushedCount: totalPushed,
        pulledCount: totalPulled,
      );
    });
  }
}

class _NoOpGateway implements RemoteGateway {
  @override
  Future<Map<String, dynamic>?> upsertRow({
    required String table,
    required Map<String, dynamic> row,
  }) async {
    return row;
  }

  @override
  Future<List<Map<String, dynamic>>> pullRows({
    required String table,
    required String companyId,
    String? activeUserId,
    DateTime? cursor,
    int pageSize = 500,
    int offset = 0,
    DateTime? afterUpdatedAt,
    String? afterId,
  }) async {
    return [];
  }
}
