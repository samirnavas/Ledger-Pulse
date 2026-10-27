import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/config/supabase_config.dart';
import '../local/database.dart';
import '../models/company_model.dart';
import '../models/party_model.dart';
import '../models/sync_model.dart';
import '../models/transaction_model.dart';
import '../models/voucher_model.dart';
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
          if (body['companies'] is List) {
            for (final c in body['companies']) {
              final comp = Company.fromMap(c as Map<String, dynamic>);
              await _applyRemoteCompany(comp);
              pulledCount++;
            }
          }
          if (body['parties'] is List) {
            for (final p in body['parties']) {
              final party = Party.fromMap(p as Map<String, dynamic>);
              await _applyRemoteParty(companyId, party);
              pulledCount++;
            }
          }
          if (body['accounts'] is List) {
            for (final a in body['accounts']) {
              await _applyRemoteAccount(companyId, a as Map<String, dynamic>);
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
          if (body['vouchers'] is List) {
            for (final v in body['vouchers']) {
              final voucher = VoucherModel.fromMap(v as Map<String, dynamic>);
              await _applyRemoteVoucher(companyId, voucher);
              pulledCount++;
            }
          }
          if (body['journals'] is List) {
            for (final j in body['journals']) {
              await _applyRemoteJournal(companyId, j as Map<String, dynamic>);
              pulledCount++;
            }
          }
          if (body['journal_lines'] is List) {
            for (final jl in body['journal_lines']) {
              await _applyRemoteJournalLine(companyId, jl as Map<String, dynamic>);
              pulledCount++;
            }
          }
          if (body['budgets'] is List) {
            for (final b in body['budgets']) {
              await _applyRemoteBudget(companyId, b as Map<String, dynamic>);
              pulledCount++;
            }
          }
          if (body['recurring_rules'] is List) {
            for (final r in body['recurring_rules']) {
              await _applyRemoteRecurringRule(companyId, r as Map<String, dynamic>);
              pulledCount++;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Pull failed for company $companyId: $e');
      // In offline scenario or unconfigured remote, keep existing local state
    }

    return SyncResult(
      success: true,
      itemsPulled: pulledCount,
      timestamp: DateTime.now(),
    );
  }

  Future<void> _applyRemoteCompany(Company company) async {
    final existing = await (db.select(db.companies)..where((t) => t.id.equals(company.id))).getSingleOrNull();
    if (existing == null || company.updatedAt.isAfter(existing.updatedAt)) {
      await db.into(db.companies).insertOnConflictUpdate(
            CompaniesCompanion.insert(
              id: company.id,
              name: company.name,
              legalName: company.legalName,
              gstin: Value(company.gstin),
              stateCode: Value(company.stateCode),
              dealerType: Value(company.dealerType),
              currencyCode: Value(company.currencyCode),
              address: Value(company.address),
              email: Value(company.email),
              phoneNumber: Value(company.phoneNumber),
              logoUrl: Value(company.logoUrl),
              signatureUrl: Value(company.signatureUrl),
              signatoryName: Value(company.signatoryName),
              bankName: Value(company.bankName),
              bankAccountNumber: Value(company.bankAccountNumber),
              bankIfsc: Value(company.bankIfsc),
              upiId: Value(company.upiId),
              isCloudSyncEnabled: Value(company.isCloudSyncEnabled),
              isDropboxSyncEnabled: Value(company.isDropboxSyncEnabled),
              isActive: Value(company.isActive),
              mode: Value(company.mode.name),
              enabledModulesJson: Value(jsonEncode(company.enabledModules.map((m) => m.name).toList())),
              createdAt: Value(company.createdAt),
              updatedAt: Value(company.updatedAt),
              syncStatus: const Value(SyncRecordStatus.synced),
            ),
          );
    }
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

  Future<void> _applyRemoteVoucher(String companyId, VoucherModel voucher) async {
    final existing = await (db.select(db.vouchers)..where((t) => t.id.equals(voucher.id))).getSingleOrNull();
    if (existing == null || voucher.updatedAt.isAfter(existing.updatedAt)) {
      await db.into(db.vouchers).insertOnConflictUpdate(
            VouchersCompanion.insert(
              id: voucher.id,
              companyId: Value(companyId),
              voucherNumber: voucher.voucherNumber,
              type: voucher.type.name,
              date: voucher.date,
              dueDate: Value(voucher.dueDate),
              partyId: Value(voucher.partyId),
              partyName: Value(voucher.partyName),
              status: Value(voucher.status.name),
              paymentMode: Value(voucher.paymentMode.name),
              subtotalInCents: Value(voucher.subtotalInCents),
              taxInCents: Value(voucher.taxInCents),
              discountInCents: Value(voucher.discountInCents),
              totalAmountInCents: Value(voucher.totalAmountInCents),
              narration: Value(voucher.narration),
              referenceNumber: Value(voucher.referenceNumber),
              sourceVoucherId: Value(voucher.sourceVoucherId),
              receiptPhotoUrl: Value(voucher.receiptPhotoUrl),
              itemsJson: Value(jsonEncode(voucher.items.map((i) => i.toMap()).toList())),
              categoryAccountId: Value(voucher.categoryAccountId),
              walletAccountId: Value(voucher.walletAccountId),
              toWalletAccountId: Value(voucher.toWalletAccountId),
              createdAt: Value(voucher.createdAt),
              updatedAt: Value(voucher.updatedAt),
              syncStatus: const Value(SyncRecordStatus.synced),
            ),
          );
    }
  }

  Future<void> _applyRemoteBudget(String companyId, Map<String, dynamic> map) async {
    final id = map['id'] as String;
    final updatedAt = map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : DateTime.now();
    final existing = await (db.select(db.budgets)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null || updatedAt.isAfter(existing.updatedAt)) {
      await db.into(db.budgets).insertOnConflictUpdate(
            BudgetsCompanion.insert(
              id: id,
              companyId: Value(companyId),
              categoryAccountId: map['category_account_id'] as String? ?? '',
              periodType: map['period_type'] as String? ?? 'monthly',
              amountInCents: (map['amount_in_cents'] as num?)?.toInt() ?? 0,
              startDate: map['start_date'] != null ? DateTime.parse(map['start_date'] as String) : DateTime.now(),
              rolloverEnabled: Value(map['rollover_enabled'] as bool? ?? false),
              isActive: Value(map['is_active'] as bool? ?? true),
              createdAt: Value(map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now()),
              updatedAt: Value(updatedAt),
              isDeleted: Value(map['is_deleted'] as bool? ?? false),
              syncStatus: const Value(SyncRecordStatus.synced),
            ),
          );
    }
  }

  Future<void> _applyRemoteRecurringRule(String companyId, Map<String, dynamic> map) async {
    final id = map['id'] as String;
    final updatedAt = map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : DateTime.now();
    final existing = await (db.select(db.recurringRules)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null || updatedAt.isAfter(existing.updatedAt)) {
      final templateJson = map['template_json'] != null
          ? (map['template_json'] is String ? map['template_json'] as String : jsonEncode(map['template_json']))
          : '{}';
      await db.into(db.recurringRules).insertOnConflictUpdate(
            RecurringRulesCompanion.insert(
              id: id,
              companyId: Value(companyId),
              templateJson: templateJson,
              intervalType: map['interval_type'] as String? ?? 'monthly',
              intervalCount: Value((map['interval_count'] as num?)?.toInt() ?? 1),
              nextRunDate: map['next_run_date'] != null ? DateTime.parse(map['next_run_date'] as String) : DateTime.now(),
              endDate: Value(map['end_date'] != null ? DateTime.parse(map['end_date'] as String) : null),
              isActive: Value(map['is_active'] as bool? ?? true),
              createdAt: Value(map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now()),
              updatedAt: Value(updatedAt),
              isDeleted: Value(map['is_deleted'] as bool? ?? false),
              syncStatus: const Value(SyncRecordStatus.synced),
            ),
          );
    }
  }

  Future<void> _applyRemoteAccount(String companyId, Map<String, dynamic> map) async {
    final id = map['id'] as String;
    final updatedAt = map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : DateTime.now();
    final existing = await (db.select(db.accounts)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null || updatedAt.isAfter(existing.updatedAt)) {
      await db.into(db.accounts).insertOnConflictUpdate(
            AccountsCompanion.insert(
              id: id,
              companyId: Value(companyId),
              code: map['code'] as String? ?? '',
              name: map['name'] as String? ?? '',
              type: map['type'] as String? ?? 'asset',
              parentAccountId: Value(map['parent_account_id'] as String?),
              isSystem: Value(map['is_system'] as bool? ?? false),
              isActive: Value(map['is_active'] as bool? ?? true),
              description: Value(map['description'] as String?),
              currentBalanceInCents: Value((map['current_balance_in_cents'] as num?)?.toInt() ?? 0),
              createdAt: Value(map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now()),
              updatedAt: Value(updatedAt),
              isDeleted: Value(map['is_deleted'] as bool? ?? false),
              syncStatus: const Value(SyncRecordStatus.synced),
            ),
          );
    }
  }

  Future<void> _applyRemoteJournal(String companyId, Map<String, dynamic> map) async {
    final id = map['id'] as String;
    final updatedAt = map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : DateTime.now();
    final existing = await (db.select(db.journals)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null || updatedAt.isAfter(existing.updatedAt)) {
      await db.into(db.journals).insertOnConflictUpdate(
            JournalsCompanion.insert(
              id: id,
              companyId: Value(companyId),
              journalNumber: map['journal_number'] as String? ?? 'JRN-001',
              voucherId: Value(map['voucher_id'] as String?),
              date: map['date'] != null ? DateTime.parse(map['date'] as String) : DateTime.now(),
              narration: Value(map['narration'] as String?),
              totalAmountInCents: Value((map['total_amount_in_cents'] as num?)?.toInt() ?? 0),
              status: Value(map['status'] as String? ?? 'posted'),
              createdAt: Value(map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now()),
              updatedAt: Value(updatedAt),
              isDeleted: Value(map['is_deleted'] as bool? ?? false),
              syncStatus: const Value(SyncRecordStatus.synced),
            ),
          );
    }
  }

  Future<void> _applyRemoteJournalLine(String companyId, Map<String, dynamic> map) async {
    final id = map['id'] as String;
    final updatedAt = map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : DateTime.now();
    final existing = await (db.select(db.journalLines)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null || updatedAt.isAfter(existing.updatedAt)) {
      await db.into(db.journalLines).insertOnConflictUpdate(
            JournalLinesCompanion.insert(
              id: id,
              companyId: Value(companyId),
              journalId: map['journal_id'] as String,
              accountId: map['account_id'] as String,
              partyId: Value(map['party_id'] as String?),
              debitInCents: Value((map['debit_in_cents'] as num?)?.toInt() ?? 0),
              creditInCents: Value((map['credit_in_cents'] as num?)?.toInt() ?? 0),
              narration: Value(map['narration'] as String?),
              createdAt: Value(map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now()),
              updatedAt: Value(updatedAt),
              isDeleted: Value(map['is_deleted'] as bool? ?? false),
              syncStatus: const Value(SyncRecordStatus.synced),
            ),
          );
    }
  }
}
