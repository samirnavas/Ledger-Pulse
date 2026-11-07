import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/local/database.dart';

import 'generated_migrations/schema.dart';

void main() {
  late SchemaVerifier verifier;
  const validationOpts = ValidationOptions(validateColumnConstraints: false);

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('Drift Step-by-Step Migrations (Every Old Schema Version to Latest v11)', () {
    for (int fromVersion = 1; fromVersion < 11; fromVersion++) {
      test('migrates from v$fromVersion directly to latest v11', () async {
        final schema = await verifier.schemaAt(fromVersion);

        // Connect AppDatabase to the schema connection and run migrations
        final db = AppDatabase(schema.newConnection());
        await verifier.migrateAndValidate(db, 11, options: validationOpts);
        await db.close();
      });
    }
  });

  group('Drift Step-by-Step Migrations (Step-by-step single version increments)', () {
    for (int fromVersion = 1; fromVersion < 11; fromVersion++) {
      final nextVersion = fromVersion + 1;
      test('migrates step-by-step from v$fromVersion to v$nextVersion', () async {
        final schema = await verifier.schemaAt(fromVersion);

        final db = AppDatabase(schema.newConnection());
        await verifier.migrateAndValidate(db, nextVersion, options: validationOpts);
        await db.close();
      });
    }
  });

  group('Data Integrity & Dual Domain Preservation (v10 to v11 Migration)', () {
    test('non-destructively migrates Expense data and preserves Ledger data with zero loss', () async {
      final schema = await verifier.schemaAt(10);
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // 1. Seed Expense Profile & legacy accounts/vouchers in schema v10
      schema.rawDatabase.execute('''
        INSERT INTO companies (
          id, name, legal_name, mode, owner_id, currency_code, is_cloud_sync_enabled, is_active, is_deleted, created_at, updated_at
        ) VALUES (
          'cmp_expense_01', 'Personal Expense Tracker', 'Personal Expense Tracker', 'expenseTracker', 'usr_owner_123', 'INR', 1, 1, 0, $nowSeconds, $nowSeconds
        );
      ''');

      schema.rawDatabase.execute('''
        INSERT INTO accounts (
          id, company_id, code, name, type, kind, is_system, is_active, current_balance_in_cents, is_deleted, created_at, updated_at
        ) VALUES 
          ('acc_wal_cash_01', 'cmp_expense_01', 'WAL_01', 'Cash in Pocket', 'asset', 'wallet', 1, 1, 150000, 0, $nowSeconds, $nowSeconds),
          ('acc_cat_food_01', 'cmp_expense_01', 'CAT_01', 'Dining & Groceries', 'expense', 'category', 1, 1, 0, 0, $nowSeconds, $nowSeconds);
      ''');

      schema.rawDatabase.execute('''
        INSERT INTO vouchers (
          id, company_id, voucher_number, type, status, total_amount_in_cents,
          wallet_account_id, category_account_id, narration, date, is_deleted, created_at, updated_at
        ) VALUES (
          'vch_exp_001', 'cmp_expense_01', 'EXP-001', 'expense', 'posted', 4500,
          'acc_wal_cash_01', 'acc_cat_food_01', 'Dinner at Cafe', $nowSeconds, 0, $nowSeconds, $nowSeconds
        );
      ''');

      // 2. Seed Business Ledger Profile in schema v10
      schema.rawDatabase.execute('''
        INSERT INTO companies (
          id, name, legal_name, mode, owner_id, currency_code, is_cloud_sync_enabled, is_active, is_deleted, created_at, updated_at
        ) VALUES (
          'cmp_ledger_01', 'Apex Hardware Pvt Ltd', 'Apex Hardware Private Limited', 'ledger', 'usr_owner_123', 'INR', 1, 1, 0, $nowSeconds, $nowSeconds
        );
      ''');

      schema.rawDatabase.execute('''
        INSERT INTO parties (
          id, company_id, name, phone_number, type, net_balance_in_cents, last_updated, is_deleted, updated_at
        ) VALUES (
          'pty_001', 'cmp_ledger_01', 'Metro Distributors', '9876543210', 'supplier', -100000, $nowSeconds, 0, $nowSeconds
        );
      ''');

      schema.rawDatabase.execute('''
        INSERT INTO vouchers (
          id, company_id, voucher_number, type, status, total_amount_in_cents,
          party_id, narration, date, is_deleted, created_at, updated_at
        ) VALUES (
          'vch_led_001', 'cmp_ledger_01', 'PUR-001', 'purchase', 'posted', 100000,
          'pty_001', 'Wholesale copper tubes', $nowSeconds, 0, $nowSeconds, $nowSeconds
        );
      ''');

      // 3. Migrate from v10 to v11
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 11, options: validationOpts);

      // 4. Assert: Shared Memberships backfilled
      final memberships = await (db.select(db.sharedMemberships)..where((t) => t.accountId.equals('usr_owner_123'))).get();
      expect(memberships.length, 2, reason: 'Both companies should backfill an owner membership');
      expect(memberships.any((m) => m.profileId == 'cmp_expense_01' && m.role == 'owner'), isTrue);
      expect(memberships.any((m) => m.profileId == 'cmp_ledger_01' && m.role == 'owner'), isTrue);

      // 5. Assert: Expense Domain entities populated in dedicated single-entry tables
      final wallets = await (db.select(db.expenseWallets)..where((t) => t.profileId.equals('cmp_expense_01'))).get();
      expect(wallets.length, 1);
      expect(wallets.first.id, 'acc_wal_cash_01');
      expect(wallets.first.name, 'Cash in Pocket');
      expect(wallets.first.currentBalanceInCents, 150000);

      final categories = await (db.select(db.expenseCategories)..where((t) => t.profileId.equals('cmp_expense_01'))).get();
      expect(categories.length, 1);
      expect(categories.first.id, 'acc_cat_food_01');
      expect(categories.first.name, 'Dining & Groceries');
      expect(categories.first.categoryType, 'expense');

      final transactions = await (db.select(db.expenseTransactions)..where((t) => t.profileId.equals('cmp_expense_01'))).get();
      expect(transactions.length, 1);
      final txn = transactions.first;
      expect(txn.id, 'vch_exp_001');
      expect(txn.amountInCents, 4500);
      expect(txn.walletId, 'acc_wal_cash_01');
      expect(txn.categoryId, 'acc_cat_food_01');
      expect(txn.note, 'Dinner at Cafe');

      // 6. Assert: Ledger data preserved with full fidelity in original tables
      final ledgerParties = await (db.select(db.parties)..where((t) => t.companyId.equals('cmp_ledger_01'))).get();
      expect(ledgerParties.length, 1);
      expect(ledgerParties.first.id, 'pty_001');
      expect(ledgerParties.first.name, 'Metro Distributors');
      expect(ledgerParties.first.netBalanceInCents, -100000);

      final ledgerVouchers = await (db.select(db.vouchers)..where((t) => t.companyId.equals('cmp_ledger_01'))).get();
      expect(ledgerVouchers.length, 1);
      expect(ledgerVouchers.first.id, 'vch_led_001');
      expect(ledgerVouchers.first.type, 'purchase');
      expect(ledgerVouchers.first.totalAmountInCents, 100000);
      expect(ledgerVouchers.first.partyId, 'pty_001');

      await db.close();
    });
  });
}
