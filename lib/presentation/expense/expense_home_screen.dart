import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_bottom_nav.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../core/widgets/skeleton_list_tile.dart';
import '../../core/widgets/spring_morphing_fab.dart';
import '../../data/models/account_model.dart';
import '../../data/models/company_model.dart';
import '../../data/models/voucher_model.dart';
import '../home/company_switcher_sheet.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import 'accounts_screen.dart';
import 'budgets_screen.dart';
import 'expense_reports_screen.dart';
import 'quick_add_transaction_sheet.dart';
import 'recurring_screen.dart';
import 'transactions_screen.dart';
import 'widgets/category_breakdown_card.dart';

/// Adaptive Home Screen for Expense Tracker mode.
/// Replaces the temporary placeholder with an adaptive bottom-nav shell:
/// Home, Transactions, Budgets (if enabled), Reports (placeholder), Accounts.
class ExpenseHomeScreen extends ConsumerStatefulWidget {
  const ExpenseHomeScreen({super.key});

  @override
  ConsumerState<ExpenseHomeScreen> createState() => _ExpenseHomeScreenState();
}

class _ExpenseHomeScreenState extends ConsumerState<ExpenseHomeScreen> {
  int _currentTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(activeCompanyProvider);
    final hasBudgets = company.isModuleEnabled(AppModule.budgets);

    // Build adaptive destinations
    final List<NavigationDestination> androidDestinations = [
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Home',
      ),
      const NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long),
        label: 'Transactions',
      ),
      if (hasBudgets)
        const NavigationDestination(
          icon: Icon(Icons.pie_chart_outline),
          selectedIcon: Icon(Icons.pie_chart),
          label: 'Budgets',
        ),
      const NavigationDestination(
        icon: Icon(Icons.bar_chart_outlined),
        selectedIcon: Icon(Icons.bar_chart),
        label: 'Reports',
      ),
      const NavigationDestination(
        icon: Icon(Icons.account_balance_wallet_outlined),
        selectedIcon: Icon(Icons.account_balance_wallet),
        label: 'Accounts',
      ),
    ];

    final List<BottomNavigationBarItem> iosItems = [
      const BottomNavigationBarItem(
        icon: Icon(CupertinoIcons.home),
        label: 'Home',
      ),
      const BottomNavigationBarItem(
        icon: Icon(CupertinoIcons.list_bullet),
        label: 'Transactions',
      ),
      if (hasBudgets)
        const BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.chart_pie),
          label: 'Budgets',
        ),
      const BottomNavigationBarItem(
        icon: Icon(CupertinoIcons.chart_bar),
        label: 'Reports',
      ),
      const BottomNavigationBarItem(
        icon: Icon(CupertinoIcons.creditcard),
        label: 'Accounts',
      ),
    ];

    // Map current index to screen
    final List<Widget> screens = [
      _ExpenseHomeView(
        onViewAllTransactions: () {
          setState(() => _currentTabIndex = 1);
        },
      ),
      const ExpenseTransactionsScreen(),
      if (hasBudgets) const BudgetsScreen(),
      const ExpenseReportsScreen(),
      const ExpenseAccountsScreen(),
    ];

    final clampedIndex = _currentTabIndex.clamp(0, screens.length - 1);

    return Scaffold(
      body: IndexedStack(
        index: clampedIndex,
        children: screens,
      ),
      bottomNavigationBar: AdaptiveBottomNav(
        currentIndex: clampedIndex,
        onTap: (index) {
          setState(() => _currentTabIndex = index);
        },
        destinations: androidDestinations,
        iosItems: iosItems,
      ),
      floatingActionButton: clampedIndex == 0 || clampedIndex == 1
          ? SpringMorphingFab(
              key: const Key('expense_quick_add_fab'),
              icon: Icons.add,
              label: 'Transaction',
              onPressed: () {
                QuickAddTransactionSheet.show(context);
              },
            )
          : null,
    );
  }
}

/// Main Home Tab View: Total wallet balance, Month switcher, Income/Expense/Net cards,
/// Category breakdown chart, and Last 10 transactions.
class _ExpenseHomeView extends ConsumerWidget {
  final VoidCallback onViewAllTransactions;

  const _ExpenseHomeView({required this.onViewAllTransactions});

  void _previousMonth(WidgetRef ref, DateTime current) {
    final prev = DateTime(current.year, current.month - 1);
    ref.read(selectedMonthProvider.notifier).setMonth(prev);
  }

  void _nextMonth(WidgetRef ref, DateTime current) {
    final next = DateTime(current.year, current.month + 1);
    ref.read(selectedMonthProvider.notifier).setMonth(next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final company = ref.watch(activeCompanyProvider);
    final selectedMonth = ref.watch(selectedMonthProvider);
    final summaryAsync = ref.watch(monthSummaryProvider);
    final walletsAsync = ref.watch(walletsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final transactionsAsync = ref.watch(transactionsProvider);

    final monthTitle = DateFormat('MMMM yyyy').format(selectedMonth);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          // Top Header: Company Switcher & Month Navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Company Switcher Chip
              InkWell(
                key: const Key('expense_company_switcher_button'),
                onTap: () => CompanySwitcherSheet.show(context),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.business_outlined, size: 18),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          company.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
              ),

              // Month Switcher Controls & Actions
              Row(
                children: [
                  if (company.isModuleEnabled(AppModule.recurring))
                    IconButton(
                      key: const Key('expense_recurring_rules_button'),
                      icon: const Icon(Icons.update),
                      tooltip: 'Recurring Rules',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const RecurringScreen(),
                          ),
                        );
                      },
                    ),
                  IconButton(
                    key: const Key('expense_prev_month_btn'),
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Previous Month',
                    onPressed: () => _previousMonth(ref, selectedMonth),
                  ),
                  Text(
                    monthTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    key: const Key('expense_next_month_btn'),
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Next Month',
                    onPressed: () => _nextMonth(ref, selectedMonth),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Total Balance Across All Wallets Card
          walletsAsync.when(
            data: (wallets) {
              int totalBalance = 0;
              for (final w in wallets) {
                if (w.type == AccountType.liability) {
                  totalBalance -= w.currentBalanceInCents;
                } else {
                  totalBalance += w.currentBalanceInCents;
                }
              }

              return LiquidGlassCard(
                key: const Key('expense_balance_placeholder'),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Balance',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AmountText(
                      amountInCents: totalBalance,
                      currencyCode: company.currencyCode,
                      variant: AmountVariant.large,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: wallets.take(3).map((w) {
                        final isLiability =
                            w.type == AccountType.liability;
                        return Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isLiability
                                    ? Icons.credit_card
                                    : Icons.account_balance_wallet,
                                size: 14,
                                color: isLiability
                                    ? Colors.purple
                                    : theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${w.name}: ${CurrencyFormatter.formatCompact(w.currentBalanceInCents, currencyCode: company.currencyCode)}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SkeletonListTile(),
            error: (err, stack) => const SizedBox(),
          ),
          const SizedBox(height: 16),

          // Monthly Metrics: Income, Expense, Net
          summaryAsync.when(
            data: (summary) {
              return Row(
                children: [
                  // Income
                  Expanded(
                    child: LiquidGlassCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Income',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          AmountText(
                            amountInCents: summary.totalIncomeInCents,
                            currencyCode: company.currencyCode,
                            overrideColor: const Color(0xFF10B981),
                            variant: AmountVariant.medium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Expense
                  Expanded(
                    child: LiquidGlassCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Expense',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          AmountText(
                            amountInCents: summary.totalExpenseInCents,
                            currencyCode: company.currencyCode,
                            overrideColor: const Color(0xFFEF4444),
                            variant: AmountVariant.medium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Net
                  Expanded(
                    child: LiquidGlassCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF3B82F6),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Net',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          AmountText(
                            amountInCents: summary.netInCents,
                            currencyCode: company.currencyCode,
                            variant: AmountVariant.medium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error loading summary: $e'),
          ),
          const SizedBox(height: 16),

          // Category Breakdown Donut Card
          summaryAsync.when(
            data: (summary) {
              final cats = categoriesAsync.asData?.value ?? [];
              return CategoryBreakdownCard(
                categoryTotalsInCents: summary.categoryTotalsInCents,
                categories: cats,
                currencyCode: company.currencyCode,
                totalExpenseInCents: summary.totalExpenseInCents,
              );
            },
            loading: () => const SizedBox(),
            error: (err, stack) => const SizedBox(),
          ),
          const SizedBox(height: 20),

          // Last 10 Transactions Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Transactions',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                key: const Key('expense_view_all_transactions_btn'),
                onPressed: onViewAllTransactions,
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Last 10 Transactions List
          transactionsAsync.when(
            data: (transactions) {
              if (transactions.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No transactions for this month yet.'),
                  ),
                );
              }

              final top10 = transactions.take(10).toList();
              final catMap = categoriesAsync.asData?.value != null
                  ? {for (final c in categoriesAsync.asData!.value) c.id: c}
                  : <String, AccountModel>{};
              final walletMap = walletsAsync.asData?.value != null
                  ? {for (final w in walletsAsync.asData!.value) w.id: w}
                  : <String, AccountModel>{};

              return Column(
                children: top10.map((txn) {
                  final isIncome = txn.type == VoucherType.income;
                  final isTransfer = txn.type == VoucherType.transfer;
                  final color = isTransfer
                      ? const Color(0xFF3B82F6)
                      : (isIncome
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444));

                  final cat = txn.categoryAccountId != null
                      ? catMap[txn.categoryAccountId!]
                      : null;
                  final wallet = txn.walletAccountId != null
                      ? walletMap[txn.walletAccountId!]
                      : null;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: LiquidGlassCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      onTap: () {
                        QuickAddTransactionSheet.show(context,
                            initialVoucher: txn);
                      },
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isTransfer
                                  ? Icons.swap_horiz
                                  : (isIncome
                                      ? Icons.arrow_downward
                                      : Icons.arrow_upward),
                              color: color,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isTransfer
                                      ? 'Transfer'
                                      : (txn.narration != null &&
                                              txn.narration!.trim().isNotEmpty
                                          ? txn.narration!.trim()
                                          : (cat?.name ?? 'Expense')),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  [
                                    if (!isTransfer &&
                                        txn.narration != null &&
                                        txn.narration!.trim().isNotEmpty &&
                                        cat?.name != null)
                                      cat!.name,
                                    if (wallet?.name != null) wallet!.name,
                                  ].join(' • '),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AmountText(
                            amountInCents: txn.totalAmountInCents,
                            currencyCode: company.currencyCode,
                            overrideColor: color,
                            showSign: !isTransfer,
                            variant: AmountVariant.medium,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const SkeletonListTile(),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}
