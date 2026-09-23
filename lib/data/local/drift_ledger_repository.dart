import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';

import '../../core/network/sync_engine.dart';
import '../../domain/exceptions/ledger_exceptions.dart';
import '../../domain/repositories/i_ledger_repository.dart';
import '../mock/mock_seed_data.dart';
import '../models/audit_log_model.dart';
import '../models/company_model.dart';
import '../models/party_model.dart';
import '../models/rbac_model.dart';
import '../models/sync_model.dart';
import '../models/transaction_model.dart';
import '../security/access_control_service.dart';
import 'audit_service.dart';
import 'database.dart';

class DriftLedgerRepository implements ILedgerRepository {
  final AppDatabase _db;
  final SyncEngine _syncEngine;
  final String _assetPath;
  final AuditService _auditService;
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
        _auditService = AuditService(db ?? AppDatabase());

  AppDatabase get db => _db;
  SyncEngine get syncEngine => _syncEngine;
  AuditService get auditService => _auditService;
  String get currentCompanyId => _currentCompanyId;
  String get currentUserId => _currentUserId;
  Role get currentRole => _currentRole;
  bool get autoSync => _autoSync;

  void _triggerBackgroundSync() {
    if (_isDisposed || !_autoSync) return;
    _syncEngine.pushQueue(companyId: _currentCompanyId).catchError((e) {
      debugPrint('DriftLedgerRepository background sync error: $e');
      return SyncResult(success: false, errorMessage: e.toString(), timestamp: DateTime.now());
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

  Future<void> _ensureInitialized() {
    _initFuture ??= _seedIfEmpty();
    return _initFuture!;
  }

  Future<void> _seedIfEmpty() async {
    try {
      // Ensure default company exists
      final existingCompany = await (_db.select(_db.companies)
            ..where((t) => t.id.equals(_currentCompanyId)))
          .getSingleOrNull();

      if (existingCompany == null) {
        await _db.into(_db.companies).insertOnConflictUpdate(
              CompaniesCompanion.insert(
                id: _currentCompanyId,
                name: 'Ledger Pulse Enterprise',
                legalName: 'Ledger Pulse Enterprise Pvt Ltd',
                gstin: const Value('29ABCDE1234F1ZH'),
                currencyCode: const Value('INR'),
                address: const Value('Suite 402, Trade Tower, Bangalore, India'),
                isCloudSyncEnabled: const Value(true),
                isDropboxSyncEnabled: const Value(false),
                isActive: const Value(true),
              ),
            );
      }

      final existingCount = await (_db.select(_db.parties)
            ..where((t) => t.companyId.equals(_currentCompanyId)))
          .get();
      if (existingCount.isNotEmpty || _currentCompanyId != 'cmp_default') {
        return;
      }

      // Database is empty for this company; seed from asset or mock data
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
      if (_autoSync) {
        _syncEngine.syncAll(companyId: _currentCompanyId).catchError((e) {
          debugPrint('DriftLedgerRepository initial sync notice: $e');
          return SyncResult(success: false, errorMessage: e.toString(), timestamp: DateTime.now());
        });
      }
    } catch (e) {
      debugPrint('DriftLedgerRepository: error during initial seeding ($e)');
    }
  }

  @override
  Stream<void> get repositoryUpdatesStream => _updateStreamController.stream;

  // --- Multi-Company Management ---

  Future<List<Company>> getCompanies() async {
    await _ensureInitialized();
    final rows = await (_db.select(_db.companies)..where((t) => t.isActive.equals(true))).get();
    return rows.map((r) => Company(
      id: r.id,
      name: r.name,
      legalName: r.legalName,
      gstin: r.gstin,
      currencyCode: r.currencyCode,
      address: r.address,
      email: r.email,
      phoneNumber: r.phoneNumber,
      isCloudSyncEnabled: r.isCloudSyncEnabled,
      isDropboxSyncEnabled: r.isDropboxSyncEnabled,
      isActive: r.isActive,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    )).toList();
  }

  Future<Company> createCompany(Company company) async {
    await _ensureInitialized();
    AccessControlService.verifyPermission(_currentRole, UserAction.createCompany);

    await _db.into(_db.companies).insertOnConflictUpdate(
          CompaniesCompanion.insert(
            id: company.id,
            name: company.name,
            legalName: company.legalName,
            gstin: Value(company.gstin),
            currencyCode: Value(company.currencyCode),
            address: Value(company.address),
            email: Value(company.email),
            phoneNumber: Value(company.phoneNumber),
            isCloudSyncEnabled: Value(company.isCloudSyncEnabled),
            isDropboxSyncEnabled: Value(company.isDropboxSyncEnabled),
            isActive: Value(company.isActive),
          ),
        );

    await _auditService.recordLog(
      companyId: company.id,
      userId: _currentUserId,
      entityType: 'company',
      entityId: company.id,
      action: AuditAction.insert,
      newState: company.toMap(),
    );

    _updateStreamController.add(null);
    return company;
  }

  // --- Parties ---

  @override
  Future<List<Party>> getParties({PartyType? filter}) async {
    await _ensureInitialized();

    final query = _db.select(_db.parties)
      ..where((t) => t.companyId.equals(_currentCompanyId) & t.isDeleted.equals(false))
      ..orderBy([
        (t) => OrderingTerm.desc(t.lastUpdated),
      ]);

    if (filter != null) {
      query.where((t) => t.companyId.equals(_currentCompanyId) & t.isDeleted.equals(false) & t.type.equals(filter.name));
    }

    final rows = await query.get();
    return rows
        .map(
          (row) => Party(
            id: row.id,
            name: row.name,
            phoneNumber: row.phoneNumber,
            type: row.type,
            netBalanceInCents: row.netBalanceInCents,
            lastUpdated: row.lastUpdated,
          ),
        )
        .toList();
  }

  @override
  Future<Party> getPartyById(String partyId) async {
    await _ensureInitialized();

    final query = _db.select(_db.parties)
      ..where((t) => t.id.equals(partyId) & t.companyId.equals(_currentCompanyId) & t.isDeleted.equals(false));
    final row = await query.getSingleOrNull();

    if (row == null) {
      throw Exception('Party not found with id: $partyId');
    }

    return Party(
      id: row.id,
      name: row.name,
      phoneNumber: row.phoneNumber,
      type: row.type,
      netBalanceInCents: row.netBalanceInCents,
      lastUpdated: row.lastUpdated,
    );
  }

  @override
  Future<void> addParty(Party party) async {
    await _ensureInitialized();

    // RBAC check based on party type
    final action = party.type == PartyType.customer
        ? UserAction.createCustomerParty
        : UserAction.createSupplierParty;
    AccessControlService.verifyPermission(_currentRole, action);

    final partyId = party.id.trim().isEmpty ? _uuid.v4() : party.id;
    final effectiveParty = party.id == partyId ? party : party.copyWith(id: partyId);

    await _db.transaction(() async {
      await _db.into(_db.parties).insertOnConflictUpdate(
            PartiesCompanion.insert(
              id: effectiveParty.id,
              companyId: Value(_currentCompanyId),
              name: effectiveParty.name,
              phoneNumber: effectiveParty.phoneNumber,
              type: effectiveParty.type,
              netBalanceInCents: Value(effectiveParty.netBalanceInCents),
              lastUpdated: effectiveParty.lastUpdated,
              isDeleted: const Value(false),
              updatedAt: Value(DateTime.now()),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );

      await _db.into(_db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              id: _uuid.v4(),
              targetTable: 'parties',
              recordId: effectiveParty.id,
              mutationType: 'INSERT',
              payload: jsonEncode({
                ...effectiveParty.toMap(),
                'companyId': _currentCompanyId,
              }),
            ),
          );

      await _auditService.recordLog(
        companyId: _currentCompanyId,
        userId: _currentUserId,
        entityType: 'party',
        entityId: effectiveParty.id,
        action: AuditAction.insert,
        newState: effectiveParty.toMap(),
      );
    });

    _updateStreamController.add(null);
    _triggerBackgroundSync();
  }

  @override
  Future<void> updateParty(Party party) async {
    await _ensureInitialized();

    final action = party.type == PartyType.customer
        ? UserAction.updateCustomerParty
        : UserAction.updateSupplierParty;
    AccessControlService.verifyPermission(_currentRole, action);

    final existing = await (_db.select(_db.parties)
          ..where((t) => t.id.equals(party.id) & t.companyId.equals(_currentCompanyId) & t.isDeleted.equals(false)))
        .getSingleOrNull();

    if (existing == null) {
      throw Exception('Party not found with id: ${party.id}');
    }

    final oldMap = {
      'id': existing.id,
      'name': existing.name,
      'phoneNumber': existing.phoneNumber,
      'type': existing.type.name,
      'netBalanceInCents': existing.netBalanceInCents,
      'lastUpdated': existing.lastUpdated.toIso8601String(),
    };

    await _db.transaction(() async {
      await (_db.update(_db.parties)..where((t) => t.id.equals(party.id) & t.companyId.equals(_currentCompanyId))).write(
        PartiesCompanion(
          name: Value(party.name),
          phoneNumber: Value(party.phoneNumber),
          type: Value(party.type),
          lastUpdated: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      await _db.into(_db.syncOutbox).insert(
        SyncOutboxCompanion.insert(
          id: _uuid.v4(),
          targetTable: 'parties',
          recordId: party.id,
          mutationType: 'UPDATE',
          payload: jsonEncode({
            ...party.toMap(),
            'companyId': _currentCompanyId,
          }),
        ),
      );

      await _auditService.recordLog(
        companyId: _currentCompanyId,
        userId: _currentUserId,
        entityType: 'party',
        entityId: party.id,
        action: AuditAction.update,
        oldState: oldMap,
        newState: party.toMap(),
      );
    });

    _updateStreamController.add(null);
    _triggerBackgroundSync();
  }

  @override
  Future<void> deleteParty(String partyId) async {
    await _ensureInitialized();
    AccessControlService.verifyPermission(_currentRole, UserAction.deleteParty);

    final party = await (_db.select(_db.parties)
          ..where((t) => t.id.equals(partyId) & t.companyId.equals(_currentCompanyId) & t.isDeleted.equals(false)))
        .getSingleOrNull();

    if (party == null) {
      return;
    }

    if (party.netBalanceInCents != 0) {
      throw const ActiveBalanceException(
        'Cannot delete a party with an active balance.',
      );
    }

    final oldMap = {
      'id': party.id,
      'name': party.name,
      'phoneNumber': party.phoneNumber,
      'type': party.type.name,
      'netBalanceInCents': party.netBalanceInCents,
      'isDeleted': false,
    };

    await _db.transaction(() async {
      // Soft-delete party to maintain referential integrity
      await (_db.update(_db.parties)..where((t) => t.id.equals(partyId) & t.companyId.equals(_currentCompanyId))).write(
        PartiesCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      // Void/archive associated entries
      await (_db.update(_db.ledgerEntries)..where((t) => t.partyId.equals(partyId) & t.companyId.equals(_currentCompanyId))).write(
        LedgerEntriesCompanion(
          isVoided: const Value(true),
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      await _db.into(_db.syncOutbox).insert(
        SyncOutboxCompanion.insert(
          id: _uuid.v4(),
          targetTable: 'parties',
          recordId: partyId,
          mutationType: 'DELETE',
          payload: jsonEncode({'id': partyId, 'isDeleted': true, 'companyId': _currentCompanyId}),
        ),
      );

      await _auditService.recordLog(
        companyId: _currentCompanyId,
        userId: _currentUserId,
        entityType: 'party',
        entityId: partyId,
        action: AuditAction.delete,
        oldState: oldMap,
        newState: {'id': partyId, 'isDeleted': true},
      );
    });

    _updateStreamController.add(null);
    _triggerBackgroundSync();
  }

  // --- Ledger Entries ---

  @override
  Future<List<LedgerEntry>> getEntriesForParty(String partyId) async {
    await _ensureInitialized();

    final query = _db.select(_db.ledgerEntries)
      ..where((t) => t.partyId.equals(partyId) & t.companyId.equals(_currentCompanyId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.date),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);

    final rows = await query.get();

    int currentBalance = 0;
    final List<LedgerEntry> entriesWithRunningBalance = [];

    for (final row in rows) {
      if (row.type == EntryType.gave) {
        currentBalance += row.amountInCents;
      } else {
        currentBalance -= row.amountInCents;
      }

      entriesWithRunningBalance.add(
        LedgerEntry(
          id: row.id,
          partyId: row.partyId,
          amountInCents: row.amountInCents,
          type: row.type,
          date: row.date,
          note: row.note,
          receiptPhotoUrl: row.receiptPhotoUrl,
          runningBalanceInCents: currentBalance,
          isVoided: row.isVoided,
        ),
      );
    }

    entriesWithRunningBalance.sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(entriesWithRunningBalance);
  }

  @override
  Future<void> addEntry(LedgerEntry entry) async {
    await _ensureInitialized();

    // Verify party existence and determine role permission
    final party = await getPartyById(entry.partyId);
    final action = party.type == PartyType.customer
        ? UserAction.createCustomerEntry
        : UserAction.createSupplierEntry;
    AccessControlService.verifyPermission(_currentRole, action);

    final entryId = entry.id.trim().isEmpty ? _uuid.v4() : entry.id;
    final effectiveEntry = entry.id == entryId ? entry : entry.copyWith(id: entryId);

    await _db.transaction(() async {
      await _db.into(_db.ledgerEntries).insertOnConflictUpdate(
            LedgerEntriesCompanion.insert(
              id: effectiveEntry.id,
              companyId: Value(_currentCompanyId),
              partyId: effectiveEntry.partyId,
              amountInCents: effectiveEntry.amountInCents,
              type: effectiveEntry.type,
              date: effectiveEntry.date,
              note: Value(effectiveEntry.note),
              receiptPhotoUrl: Value(effectiveEntry.receiptPhotoUrl),
              isVoided: const Value(false),
              createdAt: Value(effectiveEntry.date),
              updatedAt: Value(DateTime.now()),
              isDeleted: const Value(false),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );

      await _db.into(_db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              id: _uuid.v4(),
              targetTable: 'ledger_entries',
              recordId: effectiveEntry.id,
              mutationType: 'INSERT',
              payload: jsonEncode({
                ...effectiveEntry.toMap(),
                'companyId': _currentCompanyId,
              }),
            ),
          );

      await _auditService.recordLog(
        companyId: _currentCompanyId,
        userId: _currentUserId,
        entityType: 'ledger_entry',
        entityId: effectiveEntry.id,
        action: AuditAction.insert,
        newState: effectiveEntry.toMap(),
      );

      await _recalculatePartyBalanceInTx(effectiveEntry.partyId);
    });

    _updateStreamController.add(null);
    _triggerBackgroundSync();
  }

  @override
  Future<void> updateEntry(LedgerEntry entry) async {
    await _ensureInitialized();
    AccessControlService.verifyPermission(_currentRole, UserAction.updateEntry);

    final existing = await (_db.select(_db.ledgerEntries)
          ..where((t) => t.id.equals(entry.id) & t.companyId.equals(_currentCompanyId)))
        .getSingleOrNull();

    if (existing == null) {
      throw Exception('Ledger entry not found with id: ${entry.id}');
    }

    final oldMap = {
      'id': existing.id,
      'partyId': existing.partyId,
      'amountInCents': existing.amountInCents,
      'type': existing.type.name,
      'date': existing.date.toIso8601String(),
      'note': existing.note,
      'isVoided': existing.isVoided,
    };

    await _db.transaction(() async {
      final amountChanged = existing.amountInCents != entry.amountInCents;
      final typeChanged = existing.type != entry.type;

      if (amountChanged || typeChanged) {
        // Immutable adjustment:
        await (_db.update(_db.ledgerEntries)..where((t) => t.id.equals(existing.id) & t.companyId.equals(_currentCompanyId))).write(
          LedgerEntriesCompanion(
            isVoided: const Value(true),
            updatedAt: Value(DateTime.now()),
            syncStatus: const Value(SyncRecordStatus.pending),
          ),
        );

        final offsettingType = existing.type == EntryType.gave
            ? EntryType.got
            : EntryType.gave;
        final timestamp = DateTime.now();
        final offsetEntryId = _uuid.v4();
        final offsetNote = 'Reversal: Voided entry #${existing.id}';

        await _db.into(_db.ledgerEntries).insert(
          LedgerEntriesCompanion.insert(
            id: offsetEntryId,
            companyId: Value(_currentCompanyId),
            partyId: existing.partyId,
            amountInCents: existing.amountInCents,
            type: offsettingType,
            date: timestamp,
            note: Value(offsetNote),
            isVoided: const Value(false),
            createdAt: Value(timestamp),
            updatedAt: Value(timestamp),
            isDeleted: const Value(false),
            syncStatus: const Value(SyncRecordStatus.pending),
          ),
        );

        final newEntryId = _uuid.v4();
        final replacementEntry = entry.copyWith(id: newEntryId);

        await _db.into(_db.ledgerEntries).insert(
          LedgerEntriesCompanion.insert(
            id: replacementEntry.id,
            companyId: Value(_currentCompanyId),
            partyId: replacementEntry.partyId,
            amountInCents: replacementEntry.amountInCents,
            type: replacementEntry.type,
            date: replacementEntry.date,
            note: Value(replacementEntry.note),
            receiptPhotoUrl: Value(replacementEntry.receiptPhotoUrl),
            isVoided: const Value(false),
            createdAt: Value(timestamp),
            updatedAt: Value(timestamp),
            isDeleted: const Value(false),
            syncStatus: const Value(SyncRecordStatus.pending),
          ),
        );

        await _db.into(_db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            id: _uuid.v4(),
            targetTable: 'ledger_entries',
            recordId: existing.id,
            mutationType: 'UPDATE',
            payload: jsonEncode({'id': existing.id, 'isVoided': true, 'companyId': _currentCompanyId}),
          ),
        );

        await _db.into(_db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            id: _uuid.v4(),
            targetTable: 'ledger_entries',
            recordId: offsetEntryId,
            mutationType: 'INSERT',
            payload: jsonEncode({
              'id': offsetEntryId,
              'companyId': _currentCompanyId,
              'partyId': existing.partyId,
              'amountInCents': existing.amountInCents,
              'type': offsettingType.name,
              'date': timestamp.toIso8601String(),
              'note': offsetNote,
            }),
          ),
        );

        await _db.into(_db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            id: _uuid.v4(),
            targetTable: 'ledger_entries',
            recordId: replacementEntry.id,
            mutationType: 'INSERT',
            payload: jsonEncode({
              ...replacementEntry.toMap(),
              'companyId': _currentCompanyId,
            }),
          ),
        );

        await _auditService.recordLog(
          companyId: _currentCompanyId,
          userId: _currentUserId,
          entityType: 'ledger_entry',
          entityId: entry.id,
          action: AuditAction.update,
          oldState: oldMap,
          newState: replacementEntry.toMap(),
        );

        await _recalculatePartyBalanceInTx(entry.partyId);
      } else {
        await (_db.update(_db.ledgerEntries)..where((t) => t.id.equals(entry.id) & t.companyId.equals(_currentCompanyId))).write(
          LedgerEntriesCompanion(
            date: Value(entry.date),
            note: Value(entry.note),
            receiptPhotoUrl: Value(entry.receiptPhotoUrl),
            updatedAt: Value(DateTime.now()),
            syncStatus: const Value(SyncRecordStatus.pending),
          ),
        );

        await _db.into(_db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            id: _uuid.v4(),
            targetTable: 'ledger_entries',
            recordId: entry.id,
            mutationType: 'UPDATE',
            payload: jsonEncode({
              ...entry.toMap(),
              'companyId': _currentCompanyId,
            }),
          ),
        );

        await _auditService.recordLog(
          companyId: _currentCompanyId,
          userId: _currentUserId,
          entityType: 'ledger_entry',
          entityId: entry.id,
          action: AuditAction.update,
          oldState: oldMap,
          newState: entry.toMap(),
        );

        await _recalculatePartyBalanceInTx(entry.partyId);
      }
    });

    _updateStreamController.add(null);
    _triggerBackgroundSync();
  }

  @override
  Future<void> deleteEntry(String entryId) async {
    await _ensureInitialized();
    AccessControlService.verifyPermission(_currentRole, UserAction.voidEntry);

    final originalQuery = _db.select(_db.ledgerEntries)
      ..where((t) => t.id.equals(entryId) & t.companyId.equals(_currentCompanyId));
    final original = await originalQuery.getSingleOrNull();

    if (original == null || original.isVoided) {
      return;
    }

    final offsettingType = original.type == EntryType.gave
        ? EntryType.got
        : EntryType.gave;
    final timestamp = DateTime.now();
    final offsetEntryId = _uuid.v4();
    final offsetNote = 'Offset: Voided entry #${original.id}'
        '${original.note != null && original.note!.isNotEmpty ? ' (${original.note})' : ''}';

    final offsetEntry = LedgerEntry(
      id: offsetEntryId,
      partyId: original.partyId,
      amountInCents: original.amountInCents,
      type: offsettingType,
      date: timestamp,
      note: offsetNote,
    );

    final oldMap = {
      'id': original.id,
      'partyId': original.partyId,
      'amountInCents': original.amountInCents,
      'type': original.type.name,
      'isVoided': false,
    };

    await _db.transaction(() async {
      await (_db.update(_db.ledgerEntries)..where((t) => t.id.equals(entryId) & t.companyId.equals(_currentCompanyId)))
          .write(
        LedgerEntriesCompanion(
          isVoided: const Value(true),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      await _db.into(_db.ledgerEntries).insert(
            LedgerEntriesCompanion.insert(
              id: offsetEntry.id,
              companyId: Value(_currentCompanyId),
              partyId: offsetEntry.partyId,
              amountInCents: offsetEntry.amountInCents,
              type: offsetEntry.type,
              date: offsetEntry.date,
              note: Value(offsetEntry.note),
              receiptPhotoUrl: Value(offsetEntry.receiptPhotoUrl),
              isVoided: const Value(false),
              createdAt: Value(offsetEntry.date),
              updatedAt: Value(DateTime.now()),
              isDeleted: const Value(false),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );

      await _db.into(_db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              id: _uuid.v4(),
              targetTable: 'ledger_entries',
              recordId: original.id,
              mutationType: 'UPDATE',
              payload: jsonEncode({'id': original.id, 'isVoided': true, 'companyId': _currentCompanyId}),
            ),
          );

      await _db.into(_db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              id: _uuid.v4(),
              targetTable: 'ledger_entries',
              recordId: offsetEntry.id,
              mutationType: 'INSERT',
              payload: jsonEncode({
                ...offsetEntry.toMap(),
                'companyId': _currentCompanyId,
              }),
            ),
          );

      await _auditService.recordLog(
        companyId: _currentCompanyId,
        userId: _currentUserId,
        entityType: 'ledger_entry',
        entityId: original.id,
        action: AuditAction.voided,
        oldState: oldMap,
        newState: {'id': original.id, 'isVoided': true, 'offsetEntryId': offsetEntry.id},
      );

      await _recalculatePartyBalanceInTx(original.partyId);
    });

    _updateStreamController.add(null);
    _triggerBackgroundSync();
  }

  @override
  Future<(int totalReceivable, int totalPayable)> getBusinessSummary() async {
    await _ensureInitialized();

    final parties = await (_db.select(_db.parties)
          ..where((t) => t.companyId.equals(_currentCompanyId) & t.isDeleted.equals(false)))
        .get();
    int totalReceivable = 0;
    int totalPayable = 0;

    for (final p in parties) {
      if (p.netBalanceInCents > 0) {
        totalReceivable += p.netBalanceInCents;
      } else if (p.netBalanceInCents < 0) {
        totalPayable += p.netBalanceInCents.abs();
      }
    }

    return (totalReceivable, totalPayable);
  }

  Future<void> _recalculatePartyBalanceInTx(String partyId) async {
    final partyQuery = _db.select(_db.parties)
      ..where((t) => t.id.equals(partyId) & t.companyId.equals(_currentCompanyId));
    final party = await partyQuery.getSingleOrNull();
    if (party == null) return;

    final entriesQuery = _db.select(_db.ledgerEntries)
      ..where((t) => t.partyId.equals(partyId) & t.companyId.equals(_currentCompanyId));
    final entries = await entriesQuery.get();

    int newBalance = 0;
    DateTime latestDate = party.lastUpdated;

    for (final entry in entries) {
      if (entry.type == EntryType.gave) {
        newBalance += entry.amountInCents;
      } else {
        newBalance -= entry.amountInCents;
      }
      if (entry.date.isAfter(latestDate)) {
        latestDate = entry.date;
      }
    }

    await (_db.update(_db.parties)..where((t) => t.id.equals(partyId) & t.companyId.equals(_currentCompanyId))).write(
      PartiesCompanion(
        netBalanceInCents: Value(newBalance),
        lastUpdated: Value(latestDate),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );

    await _db.into(_db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            id: _uuid.v4(),
            targetTable: 'parties',
            recordId: partyId,
            mutationType: 'UPDATE',
            payload: jsonEncode({
              'partyId': partyId,
              'companyId': _currentCompanyId,
              'netBalanceInCents': newBalance,
              'lastUpdated': latestDate.toIso8601String(),
            }),
          ),
        );
  }

  void dispose() {
    _isDisposed = true;
    _updateStreamController.close();
  }
}
