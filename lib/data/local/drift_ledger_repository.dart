import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';
import '../../core/network/sync_engine.dart';
import '../../domain/repositories/i_ledger_repository.dart';
import '../accounting/voucher_posting_engine.dart';
import '../mock/mock_seed_data.dart';
import '../models/audit_log_model.dart';
import '../models/party_model.dart';
import '../models/rbac_model.dart';
import '../models/sync_model.dart';
import '../models/transaction_model.dart';
import 'audit_service.dart';
import 'database.dart';
import 'drift_accounts_journals_mixin.dart';
import 'drift_companies_profile_mixin.dart';
import 'drift_entries_mixin.dart';
import 'drift_ledger_base.dart';
import 'drift_parties_mixin.dart';

/// Concrete Drift implementation of [ILedgerRepository].
///
/// Refactored into modular domain mixins:
/// - [DriftCompaniesProfileMixin]: Companies, Profiles, Upgrades, Seeding
/// - [DriftPartiesMixin]: Customer & Supplier parties, balances, search
/// - [DriftEntriesMixin]: Standalone entries, recalculation, audit & voiding
/// - [DriftAccountsJournalsMixin]: Chart of accounts, double-entry journals, opening balances
class DriftLedgerRepository extends DriftLedgerRepositoryBase
    with
        DriftCompaniesProfileMixin,
        DriftPartiesMixin,
        DriftEntriesMixin,
        DriftAccountsJournalsMixin
    implements ILedgerRepository {
  final AppDatabase _db;
  final SyncEngine _syncEngine;
  final String _assetPath;
  final AuditService _auditService;
  final VoucherPostingEngine _postingEngine;
  final _uuid = const Uuid();
  final StreamController<void> _updateStreamController =
      StreamController<void>.broadcast();

  String _currentCompanyId = 'cmp_default';
  String _currentUserId = 'usr_default';
  Role _currentRole = Role.admin;

  final bool _autoSync;
  bool _isDisposed = false;

  Future<void>? _initFuture;

  DriftLedgerRepository({
    AppDatabase? db,
    SyncEngine? syncEngine,
    VoucherPostingEngine? postingEngine,
    bool autoSync = true,
    String assetPath = 'assets/data/data.json',
    String currentCompanyId = 'cmp_default',
    String currentUserId = 'usr_default',
    Role currentRole = Role.admin,
  })  : _db = db ?? AppDatabase(),
        _syncEngine = syncEngine ?? SyncEngine(db: db ?? AppDatabase()),
        _autoSync = autoSync,
        _assetPath = assetPath,
        _currentCompanyId = currentCompanyId,
        _currentUserId = currentUserId,
        _currentRole = currentRole,
        _auditService = AuditService(db ?? AppDatabase()),
        _postingEngine = postingEngine ??
            VoucherPostingEngine(
              db ?? AppDatabase(),
              AuditService(db ?? AppDatabase()),
            );

  @override
  AppDatabase get db => _db;
  @override
  SyncEngine get syncEngine => _syncEngine;
  @override
  AuditService get auditService => _auditService;
  @override
  VoucherPostingEngine get postingEngine => _postingEngine;
  @override
  Uuid get uuid => _uuid;
  @override
  StreamController<void> get updateStreamController => _updateStreamController;

  @override
  String get currentCompanyId => _currentCompanyId;
  @override
  String get currentUserId => _currentUserId;
  @override
  Role get currentRole => _currentRole;
  bool get autoSync => _autoSync;

  @override
  void triggerBackgroundSync() {
    if (_isDisposed || !_autoSync) return;
    _syncEngine.pushQueue(companyId: _currentCompanyId).catchError((e) {
      debugPrint('DriftLedgerRepository background sync error: $e');
      return SyncResult(
        success: false,
        errorMessage: e.toString(),
        timestamp: DateTime.now(),
      );
    });
  }

  void setContext({
    String? companyId,
    String? userId,
    Role? role,
  }) {
    if (companyId != null) _currentCompanyId = companyId;
    if (userId != null) _currentUserId = userId;
    if (role != null) _currentRole = role;
  }

  @override
  Future<void> ensureInitialized() {
    _initFuture ??= _seedIfEmpty();
    return _initFuture!;
  }

  Future<void> _seedIfEmpty() async {
    // Fresh installs have no parties, entries, or pre-made company.
  }

  /// Shared helper to record outbox entries across all mixins.
  @override
  Future<void> recordOutboxEntry({
    required String targetTable,
    required String recordId,
    required String mutationType,
    required Map<String, dynamic> payload,
    String? companyId,
  }) async {
    await _db.into(_db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            id: _uuid.v4(),
            targetTable: targetTable,
            recordId: recordId,
            mutationType: mutationType,
            payload: jsonEncode({
              ...payload,
              'companyId': companyId ?? _currentCompanyId,
            }),
          ),
        );
  }

  /// Shared helper to record audit logs across all mixins.
  @override
  Future<void> recordAuditLog({
    required String entityType,
    required String entityId,
    required AuditAction action,
    Map<String, dynamic>? oldState,
    Map<String, dynamic>? newState,
    String? companyId,
    String? userId,
  }) async {
    await _auditService.recordLog(
      companyId: companyId ?? _currentCompanyId,
      userId: userId ?? _currentUserId,
      entityType: entityType,
      entityId: entityId,
      action: action,
      oldState: oldState,
      newState: newState,
    );
  }

  /// Populates the sample dataset on demand for testing / demonstration purposes.
  Future<void> loadSampleData() async {
    List<Party> initialParties = [];
    List<LedgerEntry> initialEntries = [];

    try {
      final jsonString = await rootBundle.loadString(_assetPath);
      final Map<String, dynamic> data = jsonDecode(jsonString);

      if (data['parties'] is List) {
        for (final p in data['parties']) {
          initialParties.add(Party.fromMap(p as Map<String, dynamic>));
        }
      }
      if (data['entries'] is List) {
        for (final e in data['entries']) {
          initialEntries.add(LedgerEntry.fromMap(e as Map<String, dynamic>));
        }
      }
    } catch (_) {
      initialParties = MockSeedData.initialParties;
      initialEntries = MockSeedData.initialEntries;
    }

    await _db.transaction(() async {
      for (final party in initialParties) {
        await _db.into(_db.parties).insertOnConflictUpdate(
              PartiesCompanion.insert(
                id: party.id,
                companyId: Value(_currentCompanyId),
                name: party.name,
                phoneNumber: party.phoneNumber,
                type: party.type,
                netBalanceInCents: Value(party.netBalanceInCents),
                lastUpdated: party.lastUpdated,
              ),
            );
      }

      for (final entry in initialEntries) {
        await _db.into(_db.ledgerEntries).insertOnConflictUpdate(
              LedgerEntriesCompanion.insert(
                id: entry.id,
                companyId: Value(_currentCompanyId),
                partyId: entry.partyId,
                amountInCents: entry.amountInCents,
                type: entry.type,
                date: entry.date,
                note: Value(entry.note),
                receiptPhotoUrl: Value(entry.receiptPhotoUrl),
                isVoided: const Value(false),
                createdAt: Value(entry.date),
              ),
            );
      }
    });

    _updateStreamController.add(null);
  }

  @override
  Stream<void> get repositoryUpdatesStream => _updateStreamController.stream;

  void dispose() {
    _isDisposed = true;
    _updateStreamController.close();
  }
}
