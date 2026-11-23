import 'dart:convert';

import 'package:drift/drift.dart';

import '../../data/local/database.dart';
import 'sync_engine.dart';
import 'workspace_sync_engine.dart';

/// Projects normalized workspace details and Expense records into Drift.
final class DriftWorkspaceReplica implements WorkspaceReplica {
  final AppDatabase db;

  DriftWorkspaceReplica(this.db);

  static final _decoders = {
    for (final table in SyncEngine.syncTables) table.name: table.fromRemote,
  };

  @override
  Future<void> applyBatch(
    String workspaceId,
    List<WorkspaceChange> changes,
  ) async {
    for (final change in changes) {
      await _apply(workspaceId, change);
    }
    if (changes.any(
      (change) =>
          change.table == 'expense_wallets' ||
          change.table == 'expense_transactions',
    )) {
      await _reconcileBalances(workspaceId);
    }
  }

  @override
  Future<void> replaceSnapshot(
    String workspaceId,
    List<WorkspaceChange> rows,
  ) async {
    // Expense snapshots include all retained tombstones. Applying those rows
    // directly also keeps device-local attachment metadata intact.
    await applyBatch(workspaceId, rows);
  }

  @override
  Future<void> clear(String workspaceId) async {
    final profile = await (db.select(
      db.profiles,
    )..where((row) => row.id.equals(workspaceId))).getSingleOrNull();
    if (profile == null) return;
    if (profile.ownerId != db.userId) {
      throw StateError('Cannot clear an unrelated workspace');
    }
    if (profile.profileType == 'ledger') {
      await (db.update(db.companies)..where((row) =>
          row.profileId.equals(workspaceId) | row.id.equals(workspaceId))).write(
        const CompaniesCompanion(isActive: Value(false), isDeleted: Value(true)),
      );
    }
    await (db.delete(
      db.expenseAttachments,
    )..where((row) => row.profileId.equals(workspaceId))).go();
    await (db.delete(
      db.expenseTransactions,
    )..where((row) => row.profileId.equals(workspaceId))).go();
    await (db.delete(
      db.expenseRecurringRules,
    )..where((row) => row.profileId.equals(workspaceId))).go();
    await (db.delete(
      db.expenseBudgets,
    )..where((row) => row.profileId.equals(workspaceId))).go();
    await (db.delete(
      db.expenseCategories,
    )..where((row) => row.profileId.equals(workspaceId))).go();
    await (db.delete(
      db.expenseWallets,
    )..where((row) => row.profileId.equals(workspaceId))).go();
    await (db.update(db.profiles)..where(
          (row) => row.id.equals(workspaceId) & row.ownerId.equals(db.userId),
        ))
        .write(
          const ProfilesCompanion(
            isActive: Value(false),
            isDeleted: Value(true),
          ),
        );
  }

  @override
  Future<void> confirmOperations(
    String workspaceId,
    List<String> operationIds,
  ) async {
    // The engine owns the durable receipts and checkpoint. Synced financial
    // rows are marked as part of the same projection transaction.
  }

  Future<void> _apply(String workspace, WorkspaceChange change) async {
    final row = change.row;
    if (row == null) {
      if (change.table == 'ledger_voucher_lines') return;
      throw const FormatException('Unexpected workspace hard delete');
    }
    if (change.table == 'workspaces') {
      if (row['id'] != workspace ||
          row['owner_user_id'] != db.userId ||
          !const {'expense', 'ledger'}.contains(row['workspace_type'])) {
        throw const FormatException('Invalid workspace scope');
      }
      final lifecycle = row['lifecycle_state'];
      if (lifecycle != 'active' &&
          lifecycle != 'archived' &&
          lifecycle != 'deleted') {
        throw const FormatException('Invalid workspace lifecycle');
      }
      final before = await (db.select(
        db.profiles,
      )..where((profile) => profile.id.equals(workspace))).getSingleOrNull();
      if (before != null && before.ownerId != db.userId) {
        throw StateError(
          'Workspace identity already belongs to another account',
        );
      }
      await db
          .into(db.profiles)
          .insertOnConflictUpdate(
            ProfilesCompanion.insert(
              id: workspace,
              ownerId: Value(db.userId),
              name: row['name'] as String,
              profileType: Value(row['workspace_type'] as String),
              currencyCode: Value(row['currency_code'] as String),
              isActive: Value(lifecycle == 'active'),
              isDeleted: Value(lifecycle == 'deleted'),
              createdAt: Value(DateTime.parse(row['created_at'] as String)),
              updatedAt: Value(DateTime.parse(row['updated_at'] as String)),
              revision: Value(_integer(row['revision'])),
              syncStatus: const Value(SyncRecordStatus.synced),
            ),
          );
      return;
    }

    if (row['workspace_id'] != workspace) {
      throw const FormatException('Foreign row in Expense projection');
    }
    if (change.table == 'workspace_memberships' ||
        change.table == 'expense_profiles') {
      return;
    }

    final profile =
        await (db.select(db.profiles)..where(
              (row) => row.id.equals(workspace) & row.ownerId.equals(db.userId),
            ))
            .getSingleOrNull();
    if (profile?.profileType == 'ledger') {
      if (change.table == 'ledger_profiles') await _applyLedgerDetails(profile!, row);
      return;
    }
    if (profile == null || profile.isDeleted) {
      throw StateError('Expense workspace is unavailable for projection');
    }

    final fields = <String, dynamic>{
      ...row,
      'profile_id': workspace,
      'revision': _integer(row['revision']),
      'is_deleted': row['deleted_at'] != null,
    };
    final legacyTable = switch (change.table) {
      'expense_wallets' => 'exp_wallets',
      'expense_categories' => 'exp_categories',
      'expense_transactions' => 'exp_transactions',
      'expense_budgets' => 'exp_budgets',
      'expense_recurring_rules' => 'exp_recurring_rules',
      _ => throw FormatException(
        'Unexpected Expense projection table: ${change.table}',
      ),
    };
    final id = row['id'] as String;
    final pendingEdit =
        await (db.select(db.syncOutbox)..where(
              (entry) =>
                  entry.targetTable.equals(legacyTable) &
                  entry.recordId.equals(id),
            ))
            .getSingleOrNull();
    if (pendingEdit != null && legacyTable != 'exp_categories') {
      throw StateError(
        'A local Expense edit must be queued before projection.',
      );
    }
    switch (legacyTable) {
      case 'exp_wallets':
        await _requireScope(
          db.expenseWallets,
          db.expenseWallets.id,
          db.expenseWallets.profileId,
          id,
          workspace,
        );
        fields.addAll({
          'currency_code': profile.currencyCode,
          'starting_balance_in_cents': _integer(row['opening_balance_minor']),
          'current_balance_in_cents': _integer(row['opening_balance_minor']),
          'is_archived': row['archived_at'] != null,
        });
        await db
            .into(db.expenseWallets)
            .insertOnConflictUpdate(
              _decoders[legacyTable]!(fields) as ExpenseWalletsCompanion,
            );
      case 'exp_categories':
        await _requireScope(
          db.expenseCategories,
          db.expenseCategories.id,
          db.expenseCategories.profileId,
          id,
          workspace,
        );
        final local = await (db.select(db.expenseCategories)..where((entry) =>
            entry.id.equals(id) & entry.profileId.equals(workspace)))
            .getSingleOrNull();
        final pendingCategoryChange = local != null &&
            local.syncStatus == SyncRecordStatus.pending &&
            await hasUnacceptedCategoryWrite(db, workspace, id);
        if (pendingEdit != null || pendingCategoryChange) {
          // Learn the cloud revision without overwriting a pending local edit.
          await (db.update(db.expenseCategories)..where((entry) =>
                entry.id.equals(id) & entry.profileId.equals(workspace)))
              .write(ExpenseCategoriesCompanion(
                revision: Value(_integer(row['revision'])),
              ));
          return;
        }
        fields['is_system'] = row['system_key'] != null;
        final category =
            _decoders[legacyTable]!(fields) as ExpenseCategoriesCompanion;
        await db
            .into(db.expenseCategories)
            .insertOnConflictUpdate(
              category.copyWith(archivedAt: Value(_date(row['archived_at']))),
            );
      case 'exp_transactions':
        await _requireScope(
          db.expenseTransactions,
          db.expenseTransactions.id,
          db.expenseTransactions.profileId,
          id,
          workspace,
        );
        await _requireScope(
          db.expenseWallets,
          db.expenseWallets.id,
          db.expenseWallets.profileId,
          row['wallet_id'] as String,
          workspace,
        );
        if (row['to_wallet_id'] case final String toWallet) {
          await _requireScope(
            db.expenseWallets,
            db.expenseWallets.id,
            db.expenseWallets.profileId,
            toWallet,
            workspace,
          );
        }
        if (row['category_id'] case final String category) {
          await _requireScope(
            db.expenseCategories,
            db.expenseCategories.id,
            db.expenseCategories.profileId,
            category,
            workspace,
          );
        }
        fields.addAll({
          'amount_in_cents': _integer(row['amount_minor']),
          'transaction_date': row['occurred_at'],
        });
        await db
            .into(db.expenseTransactions)
            .insertOnConflictUpdate(
              _decoders[legacyTable]!(fields) as ExpenseTransactionsCompanion,
            );
      case 'exp_budgets':
        await _requireScope(
          db.expenseBudgets,
          db.expenseBudgets.id,
          db.expenseBudgets.profileId,
          id,
          workspace,
        );
        if (row['category_id'] case final String category) {
          await _requireScope(
            db.expenseCategories,
            db.expenseCategories.id,
            db.expenseCategories.profileId,
            category,
            workspace,
          );
        }
        fields.addAll({
          'amount_in_cents': _integer(row['amount_minor']),
          'start_date': row['start_on'],
        });
        await db
            .into(db.expenseBudgets)
            .insertOnConflictUpdate(
              _decoders[legacyTable]!(fields) as ExpenseBudgetsCompanion,
            );
      case 'exp_recurring_rules':
        await _requireScope(
          db.expenseRecurringRules,
          db.expenseRecurringRules.id,
          db.expenseRecurringRules.profileId,
          id,
          workspace,
        );
        fields.addAll({
          'template_json': jsonEncode({
            'type': row['transaction_type'],
            'amountInCents': _integer(row['amount_minor']),
            'walletAccountId': row['wallet_id'],
            'toWalletAccountId': row['to_wallet_id'],
            'categoryAccountId': row['category_id'],
            'narration': row['note'],
          }),
          'interval_type': switch (row['interval_unit']) {
            'day' => 'daily',
            'week' => 'weekly',
            'month' => 'monthly',
            'year' => 'yearly',
            _ => throw const FormatException('Invalid recurrence interval'),
          },
          'next_run_date': row['next_occurrence_on'],
          'end_date': row['ends_on'],
        });
        await db
            .into(db.expenseRecurringRules)
            .insertOnConflictUpdate(
              _decoders[legacyTable]!(fields) as ExpenseRecurringRulesCompanion,
            );
    }
  }

  Future<void> _applyLedgerDetails(
    ProfileTableData profile,
    SyncJson row,
  ) async {
    final workspace = profile.id;
    final existing = await (db.select(db.companies)..where((entry) =>
        entry.profileId.equals(workspace) | entry.id.equals(workspace)))
        .getSingleOrNull();
    if (existing?.ownerId != null && existing!.ownerId != db.userId) {
      throw StateError('Ledger company belongs to a different account');
    }

    final id = existing?.id ?? workspace;
    final revision = _integer(row['revision']);
    final pending = await (db.select(db.syncOutbox)..where((entry) =>
        entry.targetTable.equals('companies') & entry.recordId.equals(id)))
        .getSingleOrNull();
    if (existing != null && pending != null) {
      // Preserve newer local edits while learning the confirmed revision.
      await (db.update(db.companies)..where((entry) => entry.id.equals(id)))
          .write(CompaniesCompanion(revision: Value(revision)));
      return;
    }

    await db.into(db.companies).insertOnConflictUpdate(CompaniesCompanion.insert(
      id: id,
      profileId: Value(workspace),
      ownerId: Value(db.userId),
      mode: const Value('ledger'),
      name: profile.name,
      legalName: row['legal_name'] as String,
      currencyCode: Value(profile.currencyCode),
      gstin: Value(row['tax_registration_no'] as String?),
      stateCode: Value(row['tax_region_code'] as String?),
      dealerType: Value(row['dealer_type'] as String? ?? 'regular'),
      address: Value(row['business_address'] as String?),
      email: Value(row['business_email'] as String?),
      phoneNumber: Value(row['business_phone'] as String?),
      signatoryName: Value(row['signatory_name'] as String?),
      bankName: Value(row['bank_name'] as String?),
      bankAccountNumber: Value(row['bank_account_no'] as String?),
      bankIfsc: Value(row['bank_routing_code'] as String?),
      upiId: Value(row['payment_address'] as String?),
      isActive: Value(profile.isActive),
      isDeleted: Value(profile.isDeleted),
      revision: Value(revision),
      syncStatus: const Value(SyncRecordStatus.synced),
      createdAt: Value(DateTime.parse(row['created_at'] as String)),
      updatedAt: Value(DateTime.parse(row['updated_at'] as String)),
    ));
  }

  Future<void> _requireScope<T extends Table, D>(
    TableInfo<T, D> table,
    GeneratedColumn<String> idColumn,
    GeneratedColumn<String> scopeColumn,
    String id,
    String workspace,
  ) async {
    final query = db.selectOnly(table)
      ..addColumns([scopeColumn])
      ..where(idColumn.equals(id));
    final existing = await query.getSingleOrNull();
    if (existing != null && existing.read(scopeColumn) != workspace) {
      throw StateError('Expense record belongs to another workspace');
    }
  }

  Future<void> _reconcileBalances(String workspace) async {
    await db.customUpdate(
      '''
      UPDATE expense_wallets
      SET current_balance_in_cents = starting_balance_in_cents
        + COALESCE((
          SELECT SUM(
            CASE WHEN t.to_wallet_id = expense_wallets.id THEN t.amount_in_cents ELSE 0 END
            + CASE WHEN t.wallet_id = expense_wallets.id
              THEN CASE WHEN t.transaction_type = 'income' THEN t.amount_in_cents ELSE -t.amount_in_cents END
              ELSE 0 END
          )
          FROM expense_transactions t
          WHERE t.profile_id = expense_wallets.profile_id AND NOT t.is_deleted
            AND (t.wallet_id = expense_wallets.id OR t.to_wallet_id = expense_wallets.id)
        ), 0)
      WHERE profile_id = ?
      ''',
      variables: [Variable(workspace)],
      updates: {db.expenseWallets},
    );
  }

  static int _integer(Object? value) => switch (value) {
    int value => value,
    String value => int.parse(value),
    _ => throw const FormatException('Expected an integer'),
  };

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
