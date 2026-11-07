import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/expense_sync_serializer.dart';
import 'package:ledger_pulse/core/network/ledger_sync_serializer.dart';
import 'package:ledger_pulse/core/network/sync_contract.dart';
import 'package:ledger_pulse/data/models/expense/expense_transaction_model.dart';
import 'package:ledger_pulse/data/models/expense/expense_wallet_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';

void main() {
  group('Shared Sync Contract & Isolated Serialization Tests', () {
    const expenseProfileId = 'prf_exp_test';
    const ledgerProfileId = 'prf_led_test';

    test('SyncEntityType prevents arbitrary table serialization', () {
      final validEntity = SyncEntityType.fromTableName('exp_transactions');
      expect(validEntity, equals(SyncEntityType.expTransaction));

      final invalidEntity = SyncEntityType.fromTableName('arbitrary_sql_injection_table');
      expect(invalidEntity, isNull);
    });

    test('ExpenseSyncSerializer formats Expense domain records with profile_id and idempotency', () {
      final wallet = ExpenseWalletModel(
        id: 'wal_test_1',
        profileId: expenseProfileId,
        name: 'My Wallet',
        walletType: ExpenseWalletType.cash,
        startingBalanceInCents: 10000,
        currentBalanceInCents: 10000,
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
      );

      final envelope = ExpenseSyncSerializer.wrapWallet(
        wallet: wallet,
        operation: SyncOperation.insert,
        revision: 1,
      );

      expect(envelope.domain, equals(SyncDomain.expense));
      expect(envelope.entityType, equals(SyncEntityType.expWallet));
      expect(envelope.profileId, equals(expenseProfileId));
      expect(envelope.idempotencyKey, equals('idem_wal_test_1_1'));

      final rpcParams = envelope.toRpcParams();
      expect(rpcParams['p_target_table'], equals('exp_wallets'));
      expect(rpcParams['p_record_id'], equals('wal_test_1'));
      expect(rpcParams['p_mutation_type'], equals('INSERT'));
      expect((rpcParams['p_payload'] as Map)['profile_id'], equals(expenseProfileId));
    });

    test('LedgerSyncSerializer formats double-entry vouchers preserving revision and invariants', () {
      final voucher = VoucherModel(
        id: 'vch_sales_101',
        companyId: ledgerProfileId,
        voucherNumber: 'INV-101',
        type: VoucherType.sales,
        partyId: 'pty_cust_1',
        partyName: 'Valued Customer',
        date: DateTime(2026, 11, 5),
        subtotalInCents: 100000,
        taxInCents: 18000,
        totalAmountInCents: 118000,
        createdAt: DateTime(2026, 11, 5),
        updatedAt: DateTime(2026, 11, 5),
      );

      final envelope = LedgerSyncSerializer.wrapVoucher(
        voucher: voucher,
        operation: SyncOperation.update,
        revision: 3,
      );

      expect(envelope.domain, equals(SyncDomain.ledger));
      expect(envelope.entityType, equals(SyncEntityType.voucher));
      expect(envelope.profileId, equals(ledgerProfileId));
      expect(envelope.revision, equals(3));
      expect(envelope.idempotencyKey, equals('idem_vch_vch_sales_101_3'));

      final rpcParams = envelope.toRpcParams();
      expect(rpcParams['p_target_table'], equals('vouchers'));
      expect(rpcParams['p_mutation_type'], equals('UPDATE'));
      expect((rpcParams['p_payload'] as Map)['company_id'], equals(ledgerProfileId));
      expect((rpcParams['p_payload'] as Map)['revision'], equals(3));
    });

    test('Domain boundary: Expense does not leak into Ledger and vice versa', () {
      final expTx = ExpenseTransactionModel(
        id: 'tx_1',
        profileId: expenseProfileId,
        transactionType: ExpenseTransactionType.expense,
        amountInCents: 5000,
        walletId: 'wal_1',
        transactionDate: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final envelope = ExpenseSyncSerializer.wrapTransaction(
        transaction: expTx,
        operation: SyncOperation.insert,
      );

      expect(envelope.domain, equals(SyncDomain.expense));
      expect(envelope.entityType.toTableName(), startsWith('exp_'));
      expect(envelope.entityType.toTableName(), isNot(equals('vouchers')));
    });
  });
}
