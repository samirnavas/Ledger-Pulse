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

/// Abstract remote backend gateway for pushing/pulling rows.
abstract class RemoteGateway {
  Future<Map<String, dynamic>?> upsertRow({
    required String table,
    required Map<String, dynamic> row,
  });

  Future<List<Map<String, dynamic>>> pullRows({
    required String table,
    required String companyId,
    DateTime? cursor,
    int pageSize = 500,
    int offset = 0,
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
    DateTime? cursor,
    int pageSize = 500,
    int offset = 0,
  }) async {
    var query = client.from(table).select();

    if (table != 'companies' && table != 'user_profiles') {
      if (table == 'shared_memberships' || table.startsWith('exp_')) {
        query = query.eq('profile_id', companyId);
      } else {
        query = query.eq('company_id', companyId);
      }
    }

    if (cursor != null) {
      query = query.gt('updated_at', encodeTime(cursor));
    }

    final List<dynamic> responseList = await query
        .order('updated_at', ascending: true)
        .range(offset, offset + pageSize - 1);

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

  bool _isDisposed = false;

  SyncEngineStatus get currentStatus => _currentStatus;
  Stream<SyncEngineStatus> get statusStream => _statusController.stream;

  void dispose() {
    _isDisposed = true;
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

  Future<T> _synchronizedSync<T>(Future<T> Function() action) async {
    if (_isDisposed) {
      return action();
    }
    while (_syncLock != null) {
      await _syncLock!.future;
    }
    final completer = Completer<void>();
    _syncLock = completer;
    try {
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

  /// Queues any domain records with syncStatus == pending into sync_outbox if missing
  Future<void> _queueUnsyncedLocalRecords(String companyId) async {
    try {
      // 1. Companies
      final pendingCompanies =
          await (db.select(db.companies)..where(
                (t) => t.syncStatus.equalsValue(SyncRecordStatus.pending),
              ))
              .get();
      for (final c in pendingCompanies) {
        await enqueueMutation(
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
          await enqueueMutation(
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

      // 2. UserProfiles
      final pendingProfiles =
          await (db.select(db.userProfiles)..where(
                (t) => t.syncStatus.equalsValue(SyncRecordStatus.pending),
              ))
              .get();
      for (final p in pendingProfiles) {
        await enqueueMutation(
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
        await enqueueMutation(
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
        await enqueueMutation(
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
        await enqueueMutation(
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
        await enqueueMutation(
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
            'ownerId': _getSafeSupabaseClient()?.auth.currentUser?.id,
            'owner_id': _getSafeSupabaseClient()?.auth.currentUser?.id,
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
        await enqueueMutation(
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
        await enqueueMutation(
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
        await enqueueMutation(
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
        await enqueueMutation(
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
    } catch (e) {
      debugPrint('SyncEngine _queueUnsyncedLocalRecords error: $e');
    }
  }

  /// Pushes queued outbox mutations to remote backend.
  Future<SyncResult> pushQueue({String? companyId}) async {
    final cid = companyId ?? 'cmp_default';
    return _synchronizedSync(() async {
      return _pushQueueInternal(companyId: cid);
    });
  }

  Future<void> _repairFailedSyncRecords() async {
    try {
      await (db.update(
        db.vouchers,
      )..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.error))).write(
        const VouchersCompanion(syncStatus: Value(SyncRecordStatus.pending)),
      );
      await (db.update(
        db.budgets,
      )..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.error))).write(
        const BudgetsCompanion(syncStatus: Value(SyncRecordStatus.pending)),
      );
      await (db.update(
        db.recurringRules,
      )..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.error))).write(
        const RecurringRulesCompanion(
          syncStatus: Value(SyncRecordStatus.pending),
        ),
      );
      await (db.update(
        db.accounts,
      )..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.error))).write(
        const AccountsCompanion(syncStatus: Value(SyncRecordStatus.pending)),
      );
      await (db.update(
        db.parties,
      )..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.error))).write(
        const PartiesCompanion(syncStatus: Value(SyncRecordStatus.pending)),
      );
      await (db.update(
        db.ledgerEntries,
      )..where((t) => t.syncStatus.equalsValue(SyncRecordStatus.error))).write(
        const LedgerEntriesCompanion(
          syncStatus: Value(SyncRecordStatus.pending),
        ),
      );
    } catch (e) {
      debugPrint('SyncEngine repair failed records notice: $e');
    }
  }

  Future<SyncResult> _pushQueueInternal({required String companyId}) async {
    setStatus(SyncEngineStatus.syncing);
    await _cleanupCorruptedOutbox();
    await _repairFailedSyncRecords();
    await _queueUnsyncedLocalRecords(companyId);

    final now = DateTime.now();
    final query = db.select(db.syncOutbox)
      ..where(
        (t) =>
            t.nextAttemptAt.isNull() |
            t.nextAttemptAt.isSmallerOrEqual(Variable(now)),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

    final outboxRows = await query.get();
    if (outboxRows.isEmpty) {
      setStatus(SyncEngineStatus.success);
      return SyncResult(status: SyncEngineStatus.success);
    }

    final tableErrors = <String, String>{};
    int pushedCount = 0;

    for (final outboxRow in outboxRows) {
      try {
        final payloadMap =
            jsonDecode(outboxRow.payload) as Map<String, dynamic>;
        final remoteMap = mapToSnakeCase(
          payloadMap,
          ignoreKeys: {'sync_status', 'syncStatus'},
        );

        final response = await gateway.upsertRow(
          table: outboxRow.targetTable,
          row: remoteMap,
        );

        pushedCount++;

        final recordRevision = (payloadMap['revision'] as int?) ?? 0;
        await _markRecordSyncedIfUnchanged(
          table: outboxRow.targetTable,
          recordId: outboxRow.recordId,
          pushedRevision: recordRevision,
          remoteResponse: response,
        );

        await (db.delete(
          db.syncOutbox,
        )..where((t) => t.id.equals(outboxRow.id))).go();
      } catch (e) {
        final errStr = e.toString();
        tableErrors[outboxRow.targetTable] = errStr;

        final isPermanent4xx = _isPermanentError(e);

        if (isPermanent4xx) {
          await (db.update(db.syncOutbox)
                ..where((t) => t.id.equals(outboxRow.id)))
              .write(SyncOutboxCompanion(lastError: Value(errStr)));
          await _markRecordError(
            table: outboxRow.targetTable,
            recordId: outboxRow.recordId,
          );
        } else {
          final newAttempts = outboxRow.attempts + 1;
          final delaySeconds = 1 << (newAttempts > 8 ? 8 : newAttempts);
          final nextAttempt = DateTime.now().add(
            Duration(seconds: delaySeconds),
          );

          await (db.update(
            db.syncOutbox,
          )..where((t) => t.id.equals(outboxRow.id))).write(
            SyncOutboxCompanion(
              attempts: Value(newAttempts),
              lastError: Value(errStr),
              nextAttemptAt: Value(nextAttempt),
            ),
          );
        }
      }
    }

    final finalStatus = tableErrors.isNotEmpty
        ? SyncEngineStatus.partial
        : SyncEngineStatus.success;
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
    }
    final msg = error.toString().toLowerCase();
    return msg.contains('violates') ||
        msg.contains('duplicate key') ||
        msg.contains('400') ||
        msg.contains('422');
  }

  Future<void> _markRecordSyncedIfUnchanged({
    required String table,
    required String recordId,
    required int pushedRevision,
    Map<String, dynamic>? remoteResponse,
  }) async {
    final now = DateTime.now();

    if (table == 'vouchers') {
      final local = await (db.select(
        db.vouchers,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (local != null && local.revision == pushedRevision) {
        await (db.update(
          db.vouchers,
        )..where((t) => t.id.equals(recordId))).write(
          VouchersCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
      }
    } else if (table == 'accounts') {
      final local = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (local != null && local.revision == pushedRevision) {
        await (db.update(
          db.accounts,
        )..where((t) => t.id.equals(recordId))).write(
          AccountsCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
      }
    } else if (table == 'parties') {
      final local = await (db.select(
        db.parties,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (local != null && local.revision == pushedRevision) {
        await (db.update(
          db.parties,
        )..where((t) => t.id.equals(recordId))).write(
          PartiesCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
      }
    } else if (table == 'ledger_entries') {
      final local = await (db.select(
        db.ledgerEntries,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (local != null && local.revision == pushedRevision) {
        await (db.update(
          db.ledgerEntries,
        )..where((t) => t.id.equals(recordId))).write(
          LedgerEntriesCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
      }
    } else if (table == 'journals') {
      final local = await (db.select(
        db.journals,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (local != null && local.revision == pushedRevision) {
        await (db.update(
          db.journals,
        )..where((t) => t.id.equals(recordId))).write(
          JournalsCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
      }
    } else if (table == 'journal_lines') {
      final local = await (db.select(
        db.journalLines,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (local != null && local.revision == pushedRevision) {
        await (db.update(
          db.journalLines,
        )..where((t) => t.id.equals(recordId))).write(
          JournalLinesCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
      }
    } else if (table == 'budgets') {
      final local = await (db.select(
        db.budgets,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (local != null && local.revision == pushedRevision) {
        await (db.update(
          db.budgets,
        )..where((t) => t.id.equals(recordId))).write(
          BudgetsCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
      }
    } else if (table == 'recurring_rules') {
      final local = await (db.select(
        db.recurringRules,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (local != null && local.revision == pushedRevision) {
        await (db.update(
          db.recurringRules,
        )..where((t) => t.id.equals(recordId))).write(
          RecurringRulesCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
      }
    } else if (table == 'companies') {
      final local = await (db.select(
        db.companies,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (local != null && local.revision == pushedRevision) {
        await (db.update(
          db.companies,
        )..where((t) => t.id.equals(recordId))).write(
          CompaniesCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
      }
    } else if (table == 'user_profiles') {
      final local = await (db.select(
        db.userProfiles,
      )..where((t) => t.id.equals(recordId))).getSingleOrNull();
      if (local != null && local.revision == pushedRevision) {
        await (db.update(
          db.userProfiles,
        )..where((t) => t.id.equals(recordId))).write(
          UserProfilesCompanion(
            syncStatus: const Value(SyncRecordStatus.synced),
            remoteUpdatedAt: Value(now),
          ),
        );
      }
    }
  }

  Future<void> _markRecordError({
    required String table,
    required String recordId,
  }) async {
    if (table == 'vouchers') {
      await (db.update(db.vouchers)..where((t) => t.id.equals(recordId))).write(
        const VouchersCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'accounts') {
      await (db.update(db.accounts)..where((t) => t.id.equals(recordId))).write(
        const AccountsCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'parties') {
      await (db.update(db.parties)..where((t) => t.id.equals(recordId))).write(
        const PartiesCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'ledger_entries') {
      await (db.update(
        db.ledgerEntries,
      )..where((t) => t.id.equals(recordId))).write(
        const LedgerEntriesCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'journals') {
      await (db.update(db.journals)..where((t) => t.id.equals(recordId))).write(
        const JournalsCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'journal_lines') {
      await (db.update(
        db.journalLines,
      )..where((t) => t.id.equals(recordId))).write(
        const JournalLinesCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'budgets') {
      await (db.update(db.budgets)..where((t) => t.id.equals(recordId))).write(
        const BudgetsCompanion(syncStatus: Value(SyncRecordStatus.error)),
      );
    } else if (table == 'recurring_rules') {
      await (db.update(
        db.recurringRules,
      )..where((t) => t.id.equals(recordId))).write(
        const RecurringRulesCompanion(
          syncStatus: Value(SyncRecordStatus.error),
        ),
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
          mode: Value(CompanyMode.fromName(c['mode']?.toString()).canonicalValue),
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
  ];

  /// Pulls changes from remote backend for [companyId] in FK-safe topological order.
  Future<SyncResult> pullChanges({String? companyId}) async {
    final cid = companyId ?? 'cmp_default';
    return _synchronizedSync(() async {
      return _pullChangesInternal(companyId: cid);
    });
  }

  Future<SyncResult> _pullChangesInternal({required String companyId}) async {
    setStatus(SyncEngineStatus.syncing);
    final tableErrors = <String, String>{};
    int totalPulled = 0;

    for (final table in syncTables) {
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

        int offset = 0;
        const pageSize = 500;

        while (true) {
          final remoteRows = await gateway.pullRows(
            table: table.name,
            companyId: companyId,
            cursor: cursor,
            pageSize: pageSize,
            offset: offset,
          );

          if (remoteRows.isEmpty) break;

          await db.transaction(() async {
            for (final remoteMap in remoteRows) {
              final remoteUpdatedStr =
                  remoteMap['updated_at'] ??
                  remoteMap['updatedAt'] ??
                  remoteMap['created_at'];
              if (remoteUpdatedStr != null) {
                final dt = decodeTime(remoteUpdatedStr);
                if (maxRemoteUpdatedAt == null ||
                    dt.isAfter(maxRemoteUpdatedAt!)) {
                  maxRemoteUpdatedAt = dt;
                }
              }

              final recordId = (remoteMap['id'] ?? remoteMap['record_id'])
                  ?.toString();
              if (recordId == null) continue;

              final isPendingLocal = await _isRecordPendingLocal(
                table.name,
                recordId,
              );
              if (isPendingLocal) {
                // Protect un-pushed local edits
                continue;
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

              totalPulled++;
            }
          });

          if (remoteRows.length < pageSize) break;
          offset += pageSize;
        }

        if (maxRemoteUpdatedAt != null) {
          await db
              .into(db.syncState)
              .insertOnConflictUpdate(
                SyncStateCompanion(
                  targetTable: Value(table.name),
                  companyId: Value(companyId),
                  lastPulledAt: Value(maxRemoteUpdatedAt),
                ),
              );
        }

        if (table.name == 'journals' || table.name == 'journal_lines') {
          await _recalculateAccountBalances(companyId);
        }
      } catch (e) {
        debugPrint('Error pulling table ${table.name}: $e');
        tableErrors[table.name] = e.toString();
        // Do NOT advance cursor for failed table
      }
    }

    final finalStatus = tableErrors.isNotEmpty
        ? SyncEngineStatus.partial
        : SyncEngineStatus.success;
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
    }
  }

  Future<void> _recalculateAccountBalances(String companyId) async {
    final companyAccounts = await (db.select(
      db.accounts,
    )..where((t) => t.companyId.equals(companyId))).get();
    for (final acc in companyAccounts) {
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
      await (db.update(db.accounts)..where((t) => t.id.equals(acc.id))).write(
        AccountsCompanion(
          currentBalanceInCents: Value(net),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
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
    DateTime? cursor,
    int pageSize = 500,
    int offset = 0,
  }) async {
    return [];
  }
}
