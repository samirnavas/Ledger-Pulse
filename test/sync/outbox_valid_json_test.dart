import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_budget_repository.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/budget_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/recurring_rule_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/data/services/recurring_service.dart';

import 'support/strict_fake_remote.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const realTableNames = <String>{
    'companies',
    'user_profiles',
    'parties',
    'ledger_entries',
    'audit_logs',
    'sync_outbox',
    'inventory_items',
    'stock_ledger',
    'vouchers',
    'accounts',
    'journals',
    'journal_lines',
    'budgets',
    'recurring_rules',
  };

  group('Outbox Valid JSON & Table Name Schema Tests', () {
    test('1. collect ALL sync_outbox violations and report tuples at end', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final syncEngine = SyncEngine(db: db, simulateSyncForTesting: true);
      final auditService = AuditService(db);
      final postingEngine = VoucherPostingEngine(db, auditService);
      const companyId = 'cmp_outbox_json_test';
      const userId = 'usr_outbox_json_test';

      final company = Company(
        id: companyId,
        name: 'Outbox Test Co',
        legalName: 'Outbox Test Co',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.vouchers, AppModule.budgets, AppModule.recurring},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final ledgerRepo = DriftLedgerRepository(
        db: db,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );
      await ledgerRepo.createCompany(company);
      await postingEngine.ensureCompanyAccounts(companyId);

      final expenseRepo = DriftExpenseRepository(
        db: db,
        auditService: auditService,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );

      final budgetRepo = DriftBudgetRepository(
        db: db,
        auditService: auditService,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );

      final recurringService = RecurringService(
        db: db,
        auditService: auditService,
        expenseRepo: expenseRepo,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );

      final walletId = '${companyId}_${ExpenseTrackerDefaults.walletCashId}';
      final categoryId = '${companyId}_${ExpenseTrackerDefaults.groceriesId}';

      // 1. addExpense
      await expenseRepo.addExpense(
        categoryAccountId: categoryId,
        walletAccountId: walletId,
        amountInCents: 10000,
        narration: 'Test expense for outbox',
      );

      // 2. createWallet
      final wallet = await expenseRepo.createWallet(name: 'Outbox Wallet', type: AccountType.asset);

      // 3. createCategory
      final category = await expenseRepo.createCategory(name: 'Outbox Category', type: AccountType.expense);

      // 4. createBudget
      await budgetRepo.createBudget(
        categoryAccountId: category.id,
        amountInCents: 500000,
        periodType: BudgetPeriodType.monthly,
      );

      // 5. createRule
      final template = RecurringTemplate(
        type: VoucherType.expense,
        amountInCents: 99900,
        walletAccountId: wallet.id,
        categoryAccountId: category.id,
        narration: 'Monthly Subscription',
      );
      await recurringService.createRule(
        template: template,
        interval: RecurringIntervalType.monthly,
        intervalCount: 1,
        nextRunDate: DateTime.now(),
      );

      final outboxRows = await (db.select(db.syncOutbox)).get();
      final violations = <String>[];

      for (final row in outboxRows) {
        final isValidTable = realTableNames.contains(row.targetTable);
        bool isValidJson = false;
        try {
          jsonDecode(row.payload);
          isValidJson = true;
        } catch (_) {
          isValidJson = false;
        }

        if (!isValidTable || !isValidJson) {
          violations.add(
            '(targetTable: "${row.targetTable}", recordId: "${row.recordId}", mutationType: "${row.mutationType}", payloadIsJson: $isValidJson)',
          );
        }
      }

      if (violations.isNotEmpty) {
        fail(
          'Outbox schema violations found (${violations.length} total violations):\n'
          '${violations.join('\n')}',
        );
      }

      await db.close();
    });

    test('2. createWallet sets accounts row syncStatus == pending and queues accounts mutation in sync_outbox', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final fakeRemote = StrictFakeRemoteSyncBackend();
      final syncEngine = SyncEngine(
        db: db,
        simulateSyncForTesting: true,
        fakeRemoteStore: fakeRemote,
      );
      final auditService = AuditService(db);
      final postingEngine = VoucherPostingEngine(db, auditService);
      const companyId = 'cmp_wallet_autoqueue_test';
      const userId = 'usr_wallet_autoqueue_test';

      final company = Company(
        id: companyId,
        name: 'AutoQueue Test Co',
        legalName: 'AutoQueue Test Co',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.vouchers},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final ledgerRepo = DriftLedgerRepository(
        db: db,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );
      await ledgerRepo.createCompany(company);
      await postingEngine.ensureCompanyAccounts(companyId);

      final expenseRepo = DriftExpenseRepository(
        db: db,
        auditService: auditService,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );

      final wallet = await expenseRepo.createWallet(name: 'AutoQueue Wallet', type: AccountType.asset);

      final accountRow = await (db.select(db.accounts)..where((t) => t.id.equals(wallet.id))).getSingle();
      expect(
        accountRow.syncStatus,
        equals(SyncRecordStatus.pending),
        reason: 'Local accounts row should have syncStatus == pending after creation',
      );

      final outboxRowsBeforePush = await (db.select(db.syncOutbox)).get();
      final accountOutboxRows = outboxRowsBeforePush.where((r) => r.targetTable == 'accounts' && r.recordId == wallet.id);

      final outboxSummary = outboxRowsBeforePush.map((r) {
        bool parses = false;
        try {
          jsonDecode(r.payload);
          parses = true;
        } catch (_) {}
        return '(targetTable: ${r.targetTable}, recordId: ${r.recordId}, parsesJson: $parses)';
      }).join(', ');

      expect(
        accountOutboxRows,
        isNotEmpty,
        reason: 'Expected wallet account to be queued with targetTable "accounts" in sync_outbox. Actual outbox rows: [$outboxSummary]',
      );

      await syncEngine.pushQueue(companyId: companyId);
      final pendingCountAfterPush = await syncEngine.getPendingCount();
      expect(pendingCountAfterPush, equals(0));

      await db.close();
    });
  });
}
