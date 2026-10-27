import 'package:drift/drift.dart';
import '../../data/models/party_model.dart';
import '../../data/models/rbac_model.dart';
import '../../data/models/sync_model.dart';
import '../../domain/exceptions/ledger_exceptions.dart';
import '../models/audit_log_model.dart';
import '../security/access_control_service.dart';
import 'database.dart';
import 'drift_ledger_base.dart';

/// Mixin handling Party operations for DriftLedgerRepository.
mixin DriftPartiesMixin on DriftLedgerRepositoryBase {
  Future<List<Party>> getParties({PartyType? filter}) async {
    await ensureInitialized();

    final query = db.select(db.parties)
      ..where((t) => t.companyId.equals(currentCompanyId) & t.isDeleted.equals(false))
      ..orderBy([
        (t) => OrderingTerm.desc(t.lastUpdated),
      ]);

    if (filter != null) {
      query.where((t) => t.companyId.equals(currentCompanyId) & t.isDeleted.equals(false) & t.type.equals(filter.name));
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
    await ensureInitialized();

    final query = db.select(db.parties)
      ..where((t) => t.id.equals(partyId) & t.companyId.equals(currentCompanyId) & t.isDeleted.equals(false));
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

  Future<void> addParty(Party party) async {
    await ensureInitialized();

    // RBAC check based on party type
    final action = party.type == PartyType.customer
        ? UserAction.createCustomerParty
        : UserAction.createSupplierParty;
    AccessControlService.verifyPermission(currentRole, action);

    final partyId = party.id.trim().isEmpty ? uuid.v4() : party.id;
    final effectiveParty = party.id == partyId ? party : party.copyWith(id: partyId);

    await db.transaction(() async {
      await db.into(db.parties).insertOnConflictUpdate(
            PartiesCompanion.insert(
              id: effectiveParty.id,
              companyId: Value(currentCompanyId),
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

      await recordOutboxEntry(
        targetTable: 'parties',
        recordId: effectiveParty.id,
        mutationType: 'INSERT',
        payload: {
          ...effectiveParty.toMap(),
          'companyId': currentCompanyId,
        },
      );

      await recordAuditLog(
        entityType: 'party',
        entityId: effectiveParty.id,
        action: AuditAction.insert,
        newState: effectiveParty.toMap(),
      );
    });

    updateStreamController.add(null);
    triggerBackgroundSync();
  }

  Future<void> updateParty(Party party) async {
    await ensureInitialized();

    final action = party.type == PartyType.customer
        ? UserAction.updateCustomerParty
        : UserAction.updateSupplierParty;
    AccessControlService.verifyPermission(currentRole, action);

    final existing = await (db.select(db.parties)
          ..where((t) => t.id.equals(party.id) & t.companyId.equals(currentCompanyId) & t.isDeleted.equals(false)))
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

    await db.transaction(() async {
      await (db.update(db.parties)..where((t) => t.id.equals(party.id) & t.companyId.equals(currentCompanyId))).write(
        PartiesCompanion(
          name: Value(party.name),
          phoneNumber: Value(party.phoneNumber),
          type: Value(party.type),
          lastUpdated: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      await recordOutboxEntry(
        targetTable: 'parties',
        recordId: party.id,
        mutationType: 'UPDATE',
        payload: {
          ...party.toMap(),
          'companyId': currentCompanyId,
        },
      );

      await recordAuditLog(
        entityType: 'party',
        entityId: party.id,
        action: AuditAction.update,
        oldState: oldMap,
        newState: party.toMap(),
      );
    });

    updateStreamController.add(null);
    triggerBackgroundSync();
  }

  Future<void> deleteParty(String partyId) async {
    await ensureInitialized();
    AccessControlService.verifyPermission(currentRole, UserAction.deleteParty);

    final party = await (db.select(db.parties)
          ..where((t) => t.id.equals(partyId) & t.companyId.equals(currentCompanyId) & t.isDeleted.equals(false)))
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

    await db.transaction(() async {
      // Soft-delete party to maintain referential integrity
      await (db.update(db.parties)..where((t) => t.id.equals(partyId) & t.companyId.equals(currentCompanyId))).write(
        PartiesCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      // Void/archive associated entries
      await (db.update(db.ledgerEntries)..where((t) => t.partyId.equals(partyId) & t.companyId.equals(currentCompanyId))).write(
        LedgerEntriesCompanion(
          isVoided: const Value(true),
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      await recordOutboxEntry(
        targetTable: 'parties',
        recordId: partyId,
        mutationType: 'DELETE',
        payload: {'id': partyId, 'isDeleted': true, 'companyId': currentCompanyId},
      );

      await recordAuditLog(
        entityType: 'party',
        entityId: partyId,
        action: AuditAction.delete,
        oldState: oldMap,
        newState: {'id': partyId, 'isDeleted': true},
      );
    });

    updateStreamController.add(null);
    triggerBackgroundSync();
  }
}
