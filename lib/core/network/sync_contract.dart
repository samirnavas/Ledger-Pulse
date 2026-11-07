import 'package:flutter/foundation.dart';

enum SyncDomain {
  shared,
  expense,
  ledger;

  static SyncDomain fromString(String val) {
    switch (val.toLowerCase().trim()) {
      case 'expense':
        return SyncDomain.expense;
      case 'ledger':
        return SyncDomain.ledger;
      case 'shared':
      default:
        return SyncDomain.shared;
    }
  }
}

enum SyncEntityType {
  // Shared
  company,
  userProfile,
  sharedMembership,
  sharedDevice,

  // Expense
  expWallet,
  expCategory,
  expTransaction,
  expBudget,
  expRecurringRule,

  // Ledger
  party,
  account,
  voucher,
  journal,
  journalLine,
  ledgerEntry,
  inventoryItem,
  stockLedger,
  auditLog;

  String toTableName() {
    switch (this) {
      case SyncEntityType.company:
        return 'companies';
      case SyncEntityType.userProfile:
        return 'user_profiles';
      case SyncEntityType.sharedMembership:
        return 'shared_memberships';
      case SyncEntityType.sharedDevice:
        return 'shared_devices';

      case SyncEntityType.expWallet:
        return 'exp_wallets';
      case SyncEntityType.expCategory:
        return 'exp_categories';
      case SyncEntityType.expTransaction:
        return 'exp_transactions';
      case SyncEntityType.expBudget:
        return 'exp_budgets';
      case SyncEntityType.expRecurringRule:
        return 'exp_recurring_rules';

      case SyncEntityType.party:
        return 'parties';
      case SyncEntityType.account:
        return 'accounts';
      case SyncEntityType.voucher:
        return 'vouchers';
      case SyncEntityType.journal:
        return 'journals';
      case SyncEntityType.journalLine:
        return 'journal_lines';
      case SyncEntityType.ledgerEntry:
        return 'ledger_entries';
      case SyncEntityType.inventoryItem:
        return 'inventory_items';
      case SyncEntityType.stockLedger:
        return 'stock_ledger';
      case SyncEntityType.auditLog:
        return 'audit_logs';
    }
  }

  static SyncEntityType? fromTableName(String table) {
    for (final val in SyncEntityType.values) {
      if (val.toTableName() == table) return val;
    }
    return null;
  }
}

enum SyncOperation {
  insert,
  update,
  delete,
  restore;

  static SyncOperation fromString(String val) {
    switch (val.toUpperCase().trim()) {
      case 'INSERT':
        return SyncOperation.insert;
      case 'UPDATE':
        return SyncOperation.update;
      case 'DELETE':
        return SyncOperation.delete;
      case 'RESTORE':
        return SyncOperation.restore;
      default:
        return SyncOperation.update;
    }
  }

  String toMutationType() => name.toUpperCase();
}

@immutable
class SyncMutationEnvelope {
  final String id;
  final String profileId;
  final SyncDomain domain;
  final SyncEntityType entityType;
  final String entityId;
  final SyncOperation operation;
  final Map<String, dynamic> payload;
  final int revision;
  final String idempotencyKey;
  final DateTime createdAt;
  final int retryCount;

  const SyncMutationEnvelope({
    required this.id,
    required this.profileId,
    required this.domain,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    this.revision = 0,
    required this.idempotencyKey,
    required this.createdAt,
    this.retryCount = 0,
  });

  Map<String, dynamic> toRpcParams() {
    return {
      'p_target_table': entityType.toTableName(),
      'p_record_id': entityId,
      'p_mutation_type': operation.toMutationType(),
      'p_payload': {
        ...payload,
        'profile_id': profileId,
        'revision': revision,
        'idempotency_key': idempotencyKey,
      },
    };
  }
}

