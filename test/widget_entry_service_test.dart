import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/services/widget_entry_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/rbac_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('widget save retries keep a single transaction and wallet debit', () async {
    final directory = await Directory.systemTemp.createTemp('ledger_widget_test');
    addTearDown(() => directory.delete(recursive: true));
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const widgetChannel = MethodChannel('home_widget');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    const channel = WidgetEntryService.channel;
    const codec = StandardMethodCodec();
    const user = 'usr_widget_test';
    const company = 'widget_expense_test';
    const transactionId = 'tx_widget_retry_test';
    final prefs = <String, Object?>{
      WidgetEntryService.enabledKey: true,
      WidgetEntryService.contextKey: jsonEncode({
        'user': user,
        'company': company,
        'role': 'admin',
      }),
    };
    messenger.setMockMethodCallHandler(pathChannel, (_) async => directory.path);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    messenger.setMockMethodCallHandler(widgetChannel, (call) async {
      if (call.method == 'updateWidget') return true;
      final args = call.arguments as Map;
      final id = args['id'] as String;
      if (call.method == 'getWidgetData') return prefs[id];
      if (call.method == 'saveWidgetData') {
        prefs[id] = args['data'];
        return true;
      }
      return null;
    });
    addTearDown(() {
      channel.setMethodCallHandler(null);
      for (final handler in [pathChannel, widgetChannel, channel]) {
        messenger.setMockMethodCallHandler(handler, null);
      }
    });

    final db = AppDatabase(null, user);
    final repo = DriftExpenseRepository(db: db, currentCompanyId: company, currentUserId: user);
    addTearDown(db.close);
    addTearDown(repo.dispose);
    await db.into(db.profiles).insert(
      ProfilesCompanion.insert(id: company, name: 'Expenses', profileType: const Value('expense')),
    );
    await db.into(db.companies).insert(
      CompaniesCompanion.insert(
        id: company,
        profileId: const Value(company),
        name: 'Expenses',
        legalName: 'Expenses',
        mode: const Value('expense'),
      ),
    );
    final wallet = await repo.createWallet(
      name: 'Cash',
      type: AccountType.asset,
      openingBalanceInCents: 10000,
    );
    final category = await repo.createCategory(name: 'Food', type: AccountType.expense);
    final workspace = Company(
      id: company,
      name: 'Expenses',
      legalName: 'Expenses',
      mode: CompanyMode.expenseTracker,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await WidgetEntryService.publish(
      company: workspace,
      userId: user,
      role: Role.admin,
      wallets: [wallet],
      categories: [category],
      defaultWalletId: wallet.id,
    );
    expect(
      jsonDecode(prefs[WidgetEntryService.contextKey] as String)['default_wallet'],
      wallet.id,
    );
    await WidgetEntryService.publish(
      company: workspace,
      userId: user,
      role: Role.admin,
      wallets: [wallet.copyWith(isActive: false)],
      categories: [category],
      defaultWalletId: wallet.id,
    );
    expect(
      jsonDecode(prefs[WidgetEntryService.contextKey] as String)['default_wallet'],
      isNull,
    );
    await WidgetEntryService.start();

    Future<Object?> sendSave(String companyId) async {
      final response = Completer<Object?>();
      await messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall('save', {
          'id': transactionId,
          'user': user,
          'company': companyId,
          'type': 'expense',
          'wallet': wallet.id,
          'destination': category.id,
          'cents': '1250',
        })),
        (reply) => response.complete(codec.decodeEnvelope(reply!)),
      );
      return response.future;
    }

    expect(await sendSave('different_profile'), 'Profile changed. Start again.');
    expect(await sendSave(company), isNull);
    expect(await sendSave(company), isNull);
    expect((await repo.getWallets()).single.currentBalanceInCents, 8750);
    final transactions = await (db.select(db.expenseTransactions)
          ..where((row) => row.profileId.equals(company)))
        .get();
    expect(transactions.single.amountInCents, 1250);
    final queued = await (db.select(db.syncOutbox)
          ..where((row) => row.recordId.equals(transactionId)))
        .get();
    expect(queued.single.targetTable, 'exp_transactions');
  });
}
