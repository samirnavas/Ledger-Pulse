import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository_v2.dart';
import 'package:ledger_pulse/data/models/expense/expense_category_model.dart';
import 'package:ledger_pulse/data/models/expense/expense_transaction_model.dart';
import 'package:ledger_pulse/data/models/expense/expense_wallet_model.dart';

void main() {
  group('Independent Expense Domain & Financial Invariants Tests', () {
    late AppDatabase db;
    late SyncEngine syncEngine;
    late DriftExpenseRepository repo;

    const profileId = 'prf_expense_test_01';

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      syncEngine = SyncEngine(db: db, simulateSyncForTesting: true);
      repo = DriftExpenseRepository(
        db: db,
        syncEngine: syncEngine,
        profileId: profileId,
      );

      // Seed test company profile
      await db.into(db.companies).insert(
            CompaniesCompanion.insert(
              id: profileId,
              name: 'Test Expense Profile',
              legalName: 'Test Expense Profile',
              mode: const Value('expense'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
    });

    tearDown(() async {
      repo.dispose();
      syncEngine.dispose();
      await db.close();
    });

    test('Wallet balances and single-entry transactions without Ledger coupling', () async {
      // 1. Add Cash Wallet with ₹1,000 starting balance (100,000 cents)
      final cashWallet = await repo.addWallet(
        ExpenseWalletModel(
          id: 'wal_cash',
          profileId: profileId,
          name: 'Cash',
          walletType: ExpenseWalletType.cash,
          startingBalanceInCents: 100000,
          currentBalanceInCents: 100000,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // 2. Add Bank Wallet with ₹5,000 starting balance (500,000 cents)
      final bankWallet = await repo.addWallet(
        ExpenseWalletModel(
          id: 'wal_bank',
          profileId: profileId,
          name: 'HDFC Bank',
          walletType: ExpenseWalletType.bank,
          startingBalanceInCents: 500000,
          currentBalanceInCents: 500000,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // 3. Add Category
      final foodCat = await repo.addCategory(
        ExpenseCategoryModel(
          id: 'cat_food',
          profileId: profileId,
          name: 'Food & Dining',
          categoryType: ExpenseCategoryType.expense,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // 4. Record ₹200 expense from Cash
      await repo.addTransaction(
        ExpenseTransactionModel(
          id: 'tx_exp_1',
          profileId: profileId,
          transactionType: ExpenseTransactionType.expense,
          amountInCents: 20000,
          walletId: cashWallet.id,
          categoryId: foodCat.id,
          transactionDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // Verify Cash decreased to ₹800 (80,000 cents)
      final walletsAfterExp = await repo.getWallets();
      final cashAfterExp = walletsAfterExp.firstWhere((w) => w.id == cashWallet.id);
      expect(cashAfterExp.currentBalanceInCents, equals(80000));

      // 5. Transfer ₹500 from Bank to Cash (50,000 cents)
      await repo.addTransaction(
        ExpenseTransactionModel(
          id: 'tx_transfer_1',
          profileId: profileId,
          transactionType: ExpenseTransactionType.transfer,
          amountInCents: 50000,
          walletId: bankWallet.id,
          toWalletId: cashWallet.id,
          transactionDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // Invariants check:
      // Cash: 80,000 + 50,000 = 130,000 cents (₹1,300)
      // Bank: 500,000 - 50,000 = 450,000 cents (₹4,500)
      final walletsAfterTransfer = await repo.getWallets();
      final cashAfterTr = walletsAfterTransfer.firstWhere((w) => w.id == cashWallet.id);
      final bankAfterTr = walletsAfterTransfer.firstWhere((w) => w.id == bankWallet.id);

      expect(cashAfterTr.currentBalanceInCents, equals(130000));
      expect(bankAfterTr.currentBalanceInCents, equals(450000));

      // Summary check: Transfer must NOT inflate income or expense!
      final summary = await repo.getSummary();
      expect(summary.totalExpenseInCents, equals(20000)); // Only the ₹200 expense
      expect(summary.totalIncomeInCents, equals(0)); // Zero income
      expect(summary.netSavingsInCents, equals(-20000));
      expect(summary.transactionCount, equals(2));
    });
  });
}
