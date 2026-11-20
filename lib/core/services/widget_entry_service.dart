import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import '../../data/local/database.dart';
import '../../data/local/drift_budget_repository.dart';
import '../../data/local/drift_expense_repository.dart';
import '../../data/models/account_model.dart';
import '../../data/models/company_model.dart';
import '../../data/models/rbac_model.dart';
import '../../data/security/access_control_service.dart';
import 'widget_sync_service.dart';

class WidgetEntryService {
  static const enabledKey = 'widget_keypad_enabled';
  static const contextKey = 'widget_entry_context';
  static const revisionKey = 'widget_entry_revision';
  static const channel = MethodChannel('ledger_pulse/widget_entry');

  static Future<void> refresh() async {
    await HomeWidget.updateWidget(
      qualifiedAndroidName:
          'com.ledgerpulse.ledger_pulse.LedgerPulseWidgetProvider',
    );
  }

  static Future<void> publish({
    required Company company,
    required String userId,
    required Role role,
    required List<AccountModel> wallets,
    required List<AccountModel> categories,
  }) async {
    if (!AccessControlService.hasPermission(role, UserAction.createExpense)) {
      await clear();
      return;
    }
    final value = jsonEncode({
      'company': company.id,
      'user': userId,
      'role': role.name,
      'wallets': _accounts(company.id, wallets),
      'expense': _accounts(
        company.id,
        categories.where((a) => a.type == AccountType.expense),
      ),
      'income': _accounts(
        company.id,
        categories.where((a) => a.type == AccountType.income),
      ),
    });
    if (await HomeWidget.getWidgetData<String>(contextKey) != value) {
      await HomeWidget.saveWidgetData(contextKey, value);
      await refresh();
    }
  }

  static List<Map<String, String>> _accounts(
    String companyId,
    Iterable<AccountModel> accounts,
  ) =>
      accounts
          .where((a) => a.companyId == companyId && a.isActive && !a.isDeleted)
          .map((a) => {'id': a.id, 'name': a.name})
          .toList();

  static Future<void> clear() async {
    if (await HomeWidget.getWidgetData<String>(contextKey) != null) {
      await HomeWidget.saveWidgetData<String>(contextKey, null);
      await refresh();
    }
  }

  static Future<void> start() async {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'save') throw MissingPluginException();
      return _save(Map<String, String>.from(call.arguments as Map));
    });
    await channel.invokeMethod<void>('ready');
  }

  static Future<String?> _save(Map<String, String> request) async {
    final rawContext = await HomeWidget.getWidgetData<String>(contextKey);
    if (rawContext == null ||
        await HomeWidget.getWidgetData<bool>(enabledKey) != true) {
      return 'Keypad is unavailable';
    }
    final context = jsonDecode(rawContext) as Map<String, dynamic>;
    final user = context['user'] as String;
    final companyId = context['company'] as String;
    if (request['user'] != user || request['company'] != companyId) {
      return 'Profile changed. Start again.';
    }
    final type = request['type'];
    if (!const ['expense', 'income', 'transfer'].contains(type)) {
      return 'Choose a type';
    }
    final id = request['id']!;
    final cents = int.tryParse(request['cents'] ?? '') ?? 0;
    if (cents <= 0 || cents > 99999999999) return 'Enter a valid amount';

    final db = AppDatabase(null, user);
    DriftExpenseRepository? repo;
    DriftBudgetRepository? budgetRepo;
    try {
      final companyRow =
          await (db.select(db.companies)..where(
                (t) => t.id.equals(companyId) & t.isDeleted.equals(false),
              ))
              .getSingleOrNull();
      if (companyRow == null ||
          CompanyMode.tryParse(companyRow.mode) != CompanyMode.expenseTracker) {
        return 'Expense profile unavailable';
      }
      final company = Company(
        id: companyId,
        name: companyRow.name,
        legalName: companyRow.legalName,
        currencyCode: companyRow.currencyCode,
        mode: CompanyMode.expenseTracker,
        createdAt: companyRow.createdAt,
        updatedAt: companyRow.updatedAt,
      );
      final profile =
          await (db.select(db.userProfiles)
                ..where((t) => t.id.equals(user) & t.isDeleted.equals(false)))
              .getSingleOrNull();
      final role = Role.values.byName(
        profile?.role ?? context['role'] as String,
      );
      final entries = repo = DriftExpenseRepository(
        db: db,
        currentCompanyId: companyId,
        currentUserId: user,
        currentRole: role,
        company: company,
      );
      final now = DateTime.now();
      final error = await db.transaction<String?>(() async {
        // Keep the retry check and repository write in the same transaction.
        final existing = await (db.select(
          db.expenseTransactions,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (existing != null) {
          return existing.profileId == companyId
              ? null
              : 'Entry ID already used';
        }
        final walletId = request['wallet']!;
        final destination = request['destination']!;
        final wallets = await entries.getWallets();
        if (!wallets.any((w) => w.id == walletId)) {
          return 'Choose an active wallet';
        }
        final isTransfer = type == 'transfer';
        if (isTransfer) {
          if (destination == walletId ||
              !wallets.any((w) => w.id == destination)) {
            return 'Choose a different wallet';
          }
        } else {
          final categories = await entries.getCategories();
          final categoryType = type == 'expense'
              ? AccountType.expense
              : AccountType.income;
          if (!categories.any(
            (c) => c.id == destination && c.type == categoryType,
          )) {
            return 'Choose an active category';
          }
        }
        if (await HomeWidget.getWidgetData<String>(contextKey) != rawContext ||
            await HomeWidget.getWidgetData<bool>(enabledKey) != true) {
          return 'Widget settings changed. Try again.';
        }
        if (isTransfer) {
          await entries.addTransfer(
            walletAccountId: walletId,
            toWalletAccountId: destination,
            amountInCents: cents,
            date: now,
            customId: id,
          );
        } else {
          final add = type == 'expense'
              ? entries.addExpense
              : entries.addIncome;
          await add(
            categoryAccountId: destination,
            walletAccountId: walletId,
            amountInCents: cents,
            date: now,
            customId: id,
          );
        }
        return null;
      });
      if (error != null) return error;

      try {
        await HomeWidget.saveWidgetData(revisionKey, id);
        final budgets = budgetRepo = DriftBudgetRepository(
          db: db,
          currentCompanyId: companyId,
          currentUserId: user,
          currentRole: role,
          company: company,
        );
        final summary = await entries.getMonthSummary(now);
        final categories = await entries.getCategories();
        final budget = company.isModuleEnabled(AppModule.budgets)
            ? await budgets.getAllCategoriesBudget(month: now)
            : null;
        final transactions = await entries.getTransactions(
          startDate: DateTime(now.year, now.month, 1),
          endDate: DateTime(
            now.year,
            now.month + 1,
          ).subtract(const Duration(milliseconds: 1)),
        );
        if (await HomeWidget.getWidgetData<String>(contextKey) == rawContext) {
          await syncExpenseWidgetData(
            company: company,
            summary: summary,
            categories: categories,
            overallBudget: budget,
            transactions: transactions,
          );
        }
      } catch (error) {
        debugPrint('Could not refresh saved widget entry: $error');
      }
      return null;
    } catch (error) {
      debugPrint('Widget transaction save failed: $error');
      return 'Could not save. Try again.';
    } finally {
      budgetRepo?.dispose();
      repo?.dispose();
      await db.close();
    }
  }
}
