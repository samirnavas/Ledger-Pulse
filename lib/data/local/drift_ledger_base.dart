import 'dart:async';
import 'package:uuid/uuid.dart';
import '../../core/network/sync_engine.dart';
import '../accounting/voucher_posting_engine.dart';
import '../models/audit_log_model.dart';
import '../models/company_model.dart';
import '../models/party_model.dart';
import '../models/rbac_model.dart';
import 'audit_service.dart';
import 'database.dart';

/// Base class exposing shared state, transaction helpers, outbox, and audit
/// mechanisms to domain-specific repository mixins.
abstract class DriftLedgerRepositoryBase {
  AppDatabase get db;
  SyncEngine get syncEngine;
  AuditService get auditService;
  VoucherPostingEngine get postingEngine;
  Uuid get uuid;
  StreamController<void> get updateStreamController;

  String get currentCompanyId;
  String get currentUserId;
  Role get currentRole;

  Future<void> ensureInitialized();
  void triggerBackgroundSync();

  /// Shared helper to record an entry in the sync outbox
  Future<void> recordOutboxEntry({
    required String targetTable,
    required String recordId,
    required String mutationType,
    required Map<String, dynamic> payload,
    String? companyId,
  });

  /// Shared helper to record an audit log
  Future<void> recordAuditLog({
    required String entityType,
    required String entityId,
    required AuditAction action,
    Map<String, dynamic>? oldState,
    Map<String, dynamic>? newState,
    String? companyId,
    String? userId,
  });

  // Cross-domain declarations
  Future<Party> getPartyById(String partyId);
  Future<List<Company>> getCompanies();
}
