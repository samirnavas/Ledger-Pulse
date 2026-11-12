import 'dart:async';
import 'package:drift/drift.dart';
import '../../core/network/sync_codec.dart';
import '../../core/network/sync_engine.dart';
import '../../domain/repositories/i_expense_repository.dart';
import '../models/expense/expense_category_model.dart';
import '../models/expense/expense_transaction_model.dart';
import '../models/expense/expense_wallet_model.dart';
import 'database.dart';
import 'outbox_helper.dart';

class DriftExpenseRepository implements IExpenseRepository {
  final AppDatabase db;
  final SyncEngine syncEngine;
  final String _profileId;
  final StreamController<void> _updateController =
      StreamController<void>.broadcast();

  DriftExpenseRepository({
    required this.db,
    required this.syncEngine,
    required String profileId,
  }) : _profileId = profileId;

  @override
  String get currentProfileId => _profileId;

  @override
  Stream<void> get repositoryUpdatesStream => _updateController.stream;

  @override
  void dispose() {
    _updateController.close();
  }

  // --- Transactions ---

  @override
  Future<List<ExpenseTransactionModel>> getTransactions({
    ExpenseTransactionFilter? filter,
    int? limit,
    int? offset,
  }) async {
    final query = db.select(db.expenseTransactions)
      ..where((t) => t.profileId.equals(_profileId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.transactionDate)]);

    if (filter != null) {
      if (filter.walletId != null) {
        query.where((t) =>
            t.walletId.equals(filter.walletId!) |
            t.toWalletId.equals(filter.walletId!));
      }
      if (filter.categoryId != null) {
        query.where((t) => t.categoryId.equals(filter.categoryId!));
      }
      if (filter.type != null) {
        query.where((t) => t.transactionType.equals(filter.type!.toDbValue()));
      }
      if (filter.startDate != null) {
        query.where((t) => t.transactionDate.isBiggerOrEqualValue(filter.startDate!));
      }
      if (filter.endDate != null) {
        query.where((t) => t.transactionDate.isSmallerOrEqualValue(filter.endDate!));
      }
      if (filter.searchQuery != null && filter.searchQuery!.trim().isNotEmpty) {
        final queryStr = '%${filter.searchQuery!.trim()}%';
        query.where((t) =>
            t.note.like(queryStr) |
            t.payeeOrPayer.like(queryStr) |
            t.referenceNumber.like(queryStr));
      }
    }

    if (limit != null) {
      query.limit(limit, offset: offset);
    }

    final rows = await query.get();
    return rows.map((r) => _mapTransactionFromRow(r)).toList();
  }

  @override
  Future<ExpenseTransactionModel> addTransaction(
      ExpenseTransactionModel transaction) async {
    return await db.transaction(() async {
      await db.into(db.expenseTransactions).insertOnConflictUpdate(
            ExpenseTransactionsCompanion.insert(
              id: transaction.id,
              profileId: _profileId,
              transactionType: transaction.transactionType.toDbValue(),
              amountInCents: transaction.amountInCents,
              walletId: transaction.walletId,
              toWalletId: Value(transaction.toWalletId),
              categoryId: Value(transaction.categoryId),
              transactionDate: transaction.transactionDate,
              note: Value(transaction.note),
              payeeOrPayer: Value(transaction.payeeOrPayer),
              referenceNumber: Value(transaction.referenceNumber),
              receiptPhotoUrl: Value(transaction.receiptPhotoUrl),
              isCleared: Value(transaction.isCleared),
              createdAt: Value(transaction.createdAt),
              updatedAt: Value(transaction.updatedAt),
              isDeleted: const Value(false),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );

      // Adjust wallet balances
      await _applyTransactionBalanceEffects(
        type: transaction.transactionType,
        amountInCents: transaction.amountInCents,
        walletId: transaction.walletId,
        toWalletId: transaction.toWalletId,
        isReversal: false,
      );

      // Record outbox mutation
      await enqueueMutation(
        db: db,
        table: 'exp_transactions',
        recordId: transaction.id,
        type: 'INSERT',
        fullRowMap: {
          'id': transaction.id,
          'profile_id': _profileId,
          'transaction_type': transaction.transactionType.toDbValue(),
          'amount_in_cents': transaction.amountInCents,
          'wallet_id': transaction.walletId,
          'to_wallet_id': transaction.toWalletId,
          'category_id': transaction.categoryId,
          'transaction_date': encodeTime(transaction.transactionDate),
          'note': transaction.note,
          'payee_or_payer': transaction.payeeOrPayer,
          'reference_number': transaction.referenceNumber,
          'receipt_photo_url': transaction.receiptPhotoUrl,
          'is_cleared': transaction.isCleared,
          'created_at': encodeTime(transaction.createdAt),
          'updated_at': encodeTime(transaction.updatedAt),
          'is_deleted': false,
        },
      );

      _updateController.add(null);
      return transaction;
    });
  }

  @override
  Future<ExpenseTransactionModel> updateTransaction(
      ExpenseTransactionModel transaction) async {
    return await db.transaction(() async {
      final existing = await (db.select(db.expenseTransactions)
            ..where((t) => t.id.equals(transaction.id) & t.profileId.equals(_profileId)))
          .getSingleOrNull();

      if (existing != null) {
        // Revert old effect
        await _applyTransactionBalanceEffects(
          type: ExpenseTransactionType.fromString(existing.transactionType),
          amountInCents: existing.amountInCents,
          walletId: existing.walletId,
          toWalletId: existing.toWalletId,
          isReversal: true,
        );
      }

      await (db.update(db.expenseTransactions)
            ..where((t) => t.id.equals(transaction.id)))
          .write(
        ExpenseTransactionsCompanion(
          transactionType: Value(transaction.transactionType.toDbValue()),
          amountInCents: Value(transaction.amountInCents),
          walletId: Value(transaction.walletId),
          toWalletId: Value(transaction.toWalletId),
          categoryId: Value(transaction.categoryId),
          transactionDate: Value(transaction.transactionDate),
          note: Value(transaction.note),
          payeeOrPayer: Value(transaction.payeeOrPayer),
          referenceNumber: Value(transaction.referenceNumber),
          receiptPhotoUrl: Value(transaction.receiptPhotoUrl),
          isCleared: Value(transaction.isCleared),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      // Apply new effect
      await _applyTransactionBalanceEffects(
        type: transaction.transactionType,
        amountInCents: transaction.amountInCents,
        walletId: transaction.walletId,
        toWalletId: transaction.toWalletId,
        isReversal: false,
      );

      await enqueueMutation(
        db: db,
        table: 'exp_transactions',
        recordId: transaction.id,
        type: 'UPDATE',
        fullRowMap: {
          'id': transaction.id,
          'profile_id': _profileId,
          'transaction_type': transaction.transactionType.toDbValue(),
          'amount_in_cents': transaction.amountInCents,
          'wallet_id': transaction.walletId,
          'to_wallet_id': transaction.toWalletId,
          'category_id': transaction.categoryId,
          'transaction_date': encodeTime(transaction.transactionDate),
          'note': transaction.note,
          'payee_or_payer': transaction.payeeOrPayer,
          'reference_number': transaction.referenceNumber,
          'receipt_photo_url': transaction.receiptPhotoUrl,
          'is_cleared': transaction.isCleared,
          'updated_at': encodeTime(DateTime.now()),
          'is_deleted': false,
        },
      );

      _updateController.add(null);
      return transaction;
    });
  }

  @override
  Future<void> deleteTransaction(String id) async {
    await db.transaction(() async {
      final existing = await (db.select(db.expenseTransactions)
            ..where((t) => t.id.equals(id) & t.profileId.equals(_profileId)))
          .getSingleOrNull();

      if (existing == null) return;

      // Revert balance effect
      await _applyTransactionBalanceEffects(
        type: ExpenseTransactionType.fromString(existing.transactionType),
        amountInCents: existing.amountInCents,
        walletId: existing.walletId,
        toWalletId: existing.toWalletId,
        isReversal: true,
      );

      await (db.update(db.expenseTransactions)..where((t) => t.id.equals(id)))
          .write(
        ExpenseTransactionsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      await enqueueMutation(
        db: db,
        table: 'exp_transactions',
        recordId: id,
        type: 'DELETE',
        fullRowMap: {
          'id': id,
          'profile_id': _profileId,
          'is_deleted': true,
          'updated_at': encodeTime(DateTime.now()),
        },
      );

      _updateController.add(null);
    });
  }

  // --- Balance Calculation Helpers ---

  Future<void> _applyTransactionBalanceEffects({
    required ExpenseTransactionType type,
    required int amountInCents,
    required String walletId,
    String? toWalletId,
    required bool isReversal,
  }) async {
    final factor = isReversal ? -1 : 1;

    switch (type) {
      case ExpenseTransactionType.expense:
        // Decreases wallet balance
        await _adjustWalletBalance(walletId, -1 * amountInCents * factor);
        break;
      case ExpenseTransactionType.income:
        // Increases wallet balance
        await _adjustWalletBalance(walletId, amountInCents * factor);
        break;
      case ExpenseTransactionType.transfer:
        // Transfers: fromWallet decreases, toWallet increases
        await _adjustWalletBalance(walletId, -1 * amountInCents * factor);
        if (toWalletId != null && toWalletId.isNotEmpty) {
          await _adjustWalletBalance(toWalletId, amountInCents * factor);
        }
        break;
    }
  }

  Future<void> _adjustWalletBalance(String walletId, int deltaInCents) async {
    final wallet = await (db.select(db.expenseWallets)
          ..where((t) => t.id.equals(walletId) & t.profileId.equals(_profileId)))
        .getSingleOrNull();

    if (wallet == null) return;

    final newBalance = wallet.currentBalanceInCents + deltaInCents;
    await (db.update(db.expenseWallets)..where((t) => t.id.equals(walletId)))
        .write(
      ExpenseWalletsCompanion(
        currentBalanceInCents: Value(newBalance),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );
  }

  // --- Wallets ---

  @override
  Future<List<ExpenseWalletModel>> getWallets({bool includeArchived = false}) async {
    final query = db.select(db.expenseWallets)
      ..where((t) => t.profileId.equals(_profileId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);

    if (!includeArchived) {
      query.where((t) => t.isArchived.equals(false));
    }

    final rows = await query.get();
    return rows.map((r) => _mapWalletFromRow(r)).toList();
  }

  @override
  Future<ExpenseWalletModel> addWallet(ExpenseWalletModel wallet) async {
    await db.into(db.expenseWallets).insertOnConflictUpdate(
          ExpenseWalletsCompanion.insert(
            id: wallet.id,
            profileId: _profileId,
            name: wallet.name,
            walletType: Value(wallet.walletType.toDbValue()),
            currencyCode: Value(wallet.currencyCode),
            startingBalanceInCents: Value(wallet.startingBalanceInCents),
            currentBalanceInCents: Value(wallet.currentBalanceInCents),
            colorHex: Value(wallet.colorHex),
            iconName: Value(wallet.iconName),
            isArchived: Value(wallet.isArchived),
            createdAt: Value(wallet.createdAt),
            updatedAt: Value(wallet.updatedAt),
            isDeleted: const Value(false),
            syncStatus: const Value(SyncRecordStatus.pending),
          ),
        );

    await enqueueMutation(
      db: db,
      table: 'exp_wallets',
      recordId: wallet.id,
      type: 'INSERT',
      fullRowMap: {
        'id': wallet.id,
        'profile_id': _profileId,
        'name': wallet.name,
        'wallet_type': wallet.walletType.toDbValue(),
        'currency_code': wallet.currencyCode,
        'starting_balance_in_cents': wallet.startingBalanceInCents,
        'current_balance_in_cents': wallet.currentBalanceInCents,
        'color_hex': wallet.colorHex,
        'icon_name': wallet.iconName,
        'is_archived': wallet.isArchived,
        'created_at': encodeTime(wallet.createdAt),
        'updated_at': encodeTime(wallet.updatedAt),
        'is_deleted': false,
      },
    );

    _updateController.add(null);
    return wallet;
  }

  @override
  Future<ExpenseWalletModel> updateWallet(ExpenseWalletModel wallet) async {
    await (db.update(db.expenseWallets)..where((t) => t.id.equals(wallet.id)))
        .write(
      ExpenseWalletsCompanion(
        name: Value(wallet.name),
        walletType: Value(wallet.walletType.toDbValue()),
        currencyCode: Value(wallet.currencyCode),
        colorHex: Value(wallet.colorHex),
        iconName: Value(wallet.iconName),
        isArchived: Value(wallet.isArchived),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );

    await enqueueMutation(
      db: db,
      table: 'exp_wallets',
      recordId: wallet.id,
      type: 'UPDATE',
      fullRowMap: {
        'id': wallet.id,
        'profile_id': _profileId,
        'name': wallet.name,
        'wallet_type': wallet.walletType.toDbValue(),
        'currency_code': wallet.currencyCode,
        'color_hex': wallet.colorHex,
        'icon_name': wallet.iconName,
        'is_archived': wallet.isArchived,
        'updated_at': encodeTime(DateTime.now()),
        'is_deleted': false,
      },
    );

    _updateController.add(null);
    return wallet;
  }

  @override
  Future<void> deleteWallet(String id) async {
    await (db.update(db.expenseWallets)..where((t) => t.id.equals(id))).write(
      ExpenseWalletsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );

    await enqueueMutation(
      db: db,
      table: 'exp_wallets',
      recordId: id,
      type: 'DELETE',
      fullRowMap: {
        'id': id,
        'profile_id': _profileId,
        'is_deleted': true,
        'updated_at': encodeTime(DateTime.now()),
      },
    );

    _updateController.add(null);
  }

  // --- Categories ---

  @override
  Future<List<ExpenseCategoryModel>> getCategories({
    ExpenseCategoryType? type,
  }) async {
    final query = db.select(db.expenseCategories)
      ..where((t) => t.profileId.equals(_profileId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);

    if (type != null) {
      query.where((t) => t.categoryType.equals(type.toDbValue()));
    }

    final rows = await query.get();
    return rows.map((r) => _mapCategoryFromRow(r)).toList();
  }

  @override
  Future<ExpenseCategoryModel> addCategory(ExpenseCategoryModel category) async {
    await db.into(db.expenseCategories).insertOnConflictUpdate(
          ExpenseCategoriesCompanion.insert(
            id: category.id,
            profileId: _profileId,
            name: category.name,
            categoryType: Value(category.categoryType.toDbValue()),
            parentCategoryId: Value(category.parentCategoryId),
            iconName: Value(category.iconName),
            colorHex: Value(category.colorHex),
            isSystem: Value(category.isSystem),
            createdAt: Value(category.createdAt),
            updatedAt: Value(category.updatedAt),
            isDeleted: const Value(false),
            syncStatus: const Value(SyncRecordStatus.pending),
          ),
        );

    await enqueueMutation(
      db: db,
      table: 'exp_categories',
      recordId: category.id,
      type: 'INSERT',
      fullRowMap: {
        'id': category.id,
        'profile_id': _profileId,
        'name': category.name,
        'category_type': category.categoryType.toDbValue(),
        'parent_category_id': category.parentCategoryId,
        'icon_name': category.iconName,
        'color_hex': category.colorHex,
        'is_system': category.isSystem,
        'created_at': encodeTime(category.createdAt),
        'updated_at': encodeTime(category.updatedAt),
        'is_deleted': false,
      },
    );

    _updateController.add(null);
    return category;
  }

  @override
  Future<ExpenseCategoryModel> updateCategory(ExpenseCategoryModel category) async {
    await (db.update(db.expenseCategories)..where((t) => t.id.equals(category.id)))
        .write(
      ExpenseCategoriesCompanion(
        name: Value(category.name),
        categoryType: Value(category.categoryType.toDbValue()),
        parentCategoryId: Value(category.parentCategoryId),
        iconName: Value(category.iconName),
        colorHex: Value(category.colorHex),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );

    await enqueueMutation(
      db: db,
      table: 'exp_categories',
      recordId: category.id,
      type: 'UPDATE',
      fullRowMap: {
        'id': category.id,
        'profile_id': _profileId,
        'name': category.name,
        'category_type': category.categoryType.toDbValue(),
        'parent_category_id': category.parentCategoryId,
        'icon_name': category.iconName,
        'color_hex': category.colorHex,
        'updated_at': encodeTime(DateTime.now()),
        'is_deleted': false,
      },
    );

    _updateController.add(null);
    return category;
  }

  @override
  Future<void> deleteCategory(String id) async {
    await (db.update(db.expenseCategories)..where((t) => t.id.equals(id))).write(
      ExpenseCategoriesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );

    await enqueueMutation(
      db: db,
      table: 'exp_categories',
      recordId: id,
      type: 'DELETE',
      fullRowMap: {
        'id': id,
        'profile_id': _profileId,
        'is_deleted': true,
        'updated_at': encodeTime(DateTime.now()),
      },
    );

    _updateController.add(null);
  }

  // --- Metrics ---

  @override
  Future<ExpenseSummary> getSummary({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final query = db.select(db.expenseTransactions)
      ..where((t) => t.profileId.equals(_profileId) & t.isDeleted.equals(false));

    if (startDate != null) {
      query.where((t) => t.transactionDate.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((t) => t.transactionDate.isSmallerOrEqualValue(endDate));
    }

    final rows = await query.get();

    int totalIncome = 0;
    int totalExpense = 0;
    int count = 0;

    for (final row in rows) {
      count++;
      if (row.transactionType == 'income') {
        totalIncome += row.amountInCents;
      } else if (row.transactionType == 'expense') {
        totalExpense += row.amountInCents;
      }
      // Transfers are neither income nor expense!
    }

    return ExpenseSummary(
      totalIncomeInCents: totalIncome,
      totalExpenseInCents: totalExpense,
      netSavingsInCents: totalIncome - totalExpense,
      transactionCount: count,
    );
  }

  // --- Mapping Mappers ---

  ExpenseTransactionModel _mapTransactionFromRow(ExpenseTransactionTableData r) {
    return ExpenseTransactionModel(
      id: r.id,
      profileId: r.profileId,
      transactionType: ExpenseTransactionType.fromString(r.transactionType),
      amountInCents: r.amountInCents,
      walletId: r.walletId,
      toWalletId: r.toWalletId,
      categoryId: r.categoryId,
      transactionDate: r.transactionDate,
      note: r.note,
      payeeOrPayer: r.payeeOrPayer,
      referenceNumber: r.referenceNumber,
      receiptPhotoUrl: r.receiptPhotoUrl,
      isCleared: r.isCleared,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      isDeleted: r.isDeleted,
    );
  }

  ExpenseWalletModel _mapWalletFromRow(ExpenseWalletTableData r) {
    return ExpenseWalletModel(
      id: r.id,
      profileId: r.profileId,
      name: r.name,
      walletType: ExpenseWalletType.fromString(r.walletType),
      currencyCode: r.currencyCode,
      startingBalanceInCents: r.startingBalanceInCents,
      currentBalanceInCents: r.currentBalanceInCents,
      colorHex: r.colorHex,
      iconName: r.iconName,
      isArchived: r.isArchived,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      isDeleted: r.isDeleted,
    );
  }

  ExpenseCategoryModel _mapCategoryFromRow(ExpenseCategoryTableData r) {
    return ExpenseCategoryModel(
      id: r.id,
      profileId: r.profileId,
      name: r.name,
      categoryType: ExpenseCategoryType.fromString(r.categoryType),
      parentCategoryId: r.parentCategoryId,
      iconName: r.iconName,
      colorHex: r.colorHex,
      isSystem: r.isSystem,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      isDeleted: r.isDeleted,
    );
  }
}

