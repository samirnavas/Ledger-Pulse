import '../../data/models/expense/expense_category_model.dart';
import '../../data/models/expense/expense_transaction_model.dart';
import '../../data/models/expense/expense_wallet_model.dart';
import 'sync_contract.dart';

class ExpenseSyncSerializer {
  static Map<String, dynamic> serializeWallet(ExpenseWalletModel wallet) {
    return {
      'id': wallet.id,
      'profile_id': wallet.profileId,
      'name': wallet.name,
      'wallet_type': wallet.walletType.toDbValue(),
      'currency_code': wallet.currencyCode,
      'starting_balance_in_cents': wallet.startingBalanceInCents,
      'current_balance_in_cents': wallet.currentBalanceInCents,
      'color_hex': wallet.colorHex,
      'icon_name': wallet.iconName,
      'is_archived': wallet.isArchived,
      'created_at': wallet.createdAt.toIso8601String(),
      'updated_at': wallet.updatedAt.toIso8601String(),
      'is_deleted': wallet.isDeleted,
    };
  }

  static Map<String, dynamic> serializeCategory(ExpenseCategoryModel category) {
    return {
      'id': category.id,
      'profile_id': category.profileId,
      'name': category.name,
      'category_type': category.categoryType.toDbValue(),
      'parent_category_id': category.parentCategoryId,
      'icon_name': category.iconName,
      'color_hex': category.colorHex,
      'is_system': category.isSystem,
      'created_at': category.createdAt.toIso8601String(),
      'updated_at': category.updatedAt.toIso8601String(),
      'is_deleted': category.isDeleted,
    };
  }

  static Map<String, dynamic> serializeTransaction(
      ExpenseTransactionModel transaction) {
    return {
      'id': transaction.id,
      'profile_id': transaction.profileId,
      'transaction_type': transaction.transactionType.toDbValue(),
      'amount_in_cents': transaction.amountInCents,
      'wallet_id': transaction.walletId,
      'to_wallet_id': transaction.toWalletId,
      'category_id': transaction.categoryId,
      'transaction_date': transaction.transactionDate.toIso8601String(),
      'note': transaction.note,
      'payee_or_payer': transaction.payeeOrPayer,
      'reference_number': transaction.referenceNumber,
      'receipt_photo_url': transaction.receiptPhotoUrl,
      'is_cleared': transaction.isCleared,
      'created_at': transaction.createdAt.toIso8601String(),
      'updated_at': transaction.updatedAt.toIso8601String(),
      'is_deleted': transaction.isDeleted,
    };
  }

  static SyncMutationEnvelope wrapWallet({
    required ExpenseWalletModel wallet,
    required SyncOperation operation,
    int revision = 0,
  }) {
    return SyncMutationEnvelope(
      id: 'mut_${wallet.id}_$revision',
      profileId: wallet.profileId,
      domain: SyncDomain.expense,
      entityType: SyncEntityType.expWallet,
      entityId: wallet.id,
      operation: operation,
      payload: serializeWallet(wallet),
      revision: revision,
      idempotencyKey: 'idem_${wallet.id}_$revision',
      createdAt: DateTime.now(),
    );
  }

  static SyncMutationEnvelope wrapTransaction({
    required ExpenseTransactionModel transaction,
    required SyncOperation operation,
    int revision = 0,
  }) {
    return SyncMutationEnvelope(
      id: 'mut_${transaction.id}_$revision',
      profileId: transaction.profileId,
      domain: SyncDomain.expense,
      entityType: SyncEntityType.expTransaction,
      entityId: transaction.id,
      operation: operation,
      payload: serializeTransaction(transaction),
      revision: revision,
      idempotencyKey: 'idem_${transaction.id}_$revision',
      createdAt: DateTime.now(),
    );
  }
}

