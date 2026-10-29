import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/mode_strings.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_bottom_nav.dart';
import '../../core/widgets/adaptive_chip.dart';
import '../../core/widgets/adaptive_list_row.dart';
import '../../core/widgets/adaptive_metric_card.dart';
import '../../core/widgets/adaptive_page_entrance.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_section_header.dart';
import '../../core/widgets/adaptive_surface_card.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/skeleton_list_tile.dart';
import '../../core/widgets/smart_fab_switcher.dart';
import '../../core/widgets/spring_morphing_fab.dart';
import '../../data/models/account_model.dart';
import '../../data/models/company_model.dart';
import '../../data/models/sync_model.dart';
import '../../data/models/voucher_model.dart';
import '../home/company_switcher_sheet.dart';
import '../home/sync_settings_sheet.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import '../providers/sync_providers.dart';
import 'accounts_screen.dart';
import 'budgets_screen.dart';
import 'expense_reports_screen.dart';
import 'providers/expense_tab_controller.dart';
import 'quick_add_transaction_sheet.dart';
import 'recurring_screen.dart';
import 'transactions_screen.dart';
import 'widgets/category_breakdown_card.dart';
import 'widgets/expense_sidebar_drawer.dart';

/// Adaptive Home Shell for Expense Tracker mode mirroring DashboardScreen.
/// Uses AdaptiveScaffold with company-switcher title, cloud sync action,
/// drawer navigation, adaptive bottom nav, and back behaviour.
class ExpenseHomeScreen extends ConsumerStatefulWidget {
  const ExpenseHomeScreen({super.key});

  @override
  ConsumerState<ExpenseHomeScreen> createState() => _ExpenseHomeScreenState();
}

class _ExpenseHomeScreenState extends ConsumerState<ExpenseHomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _handlePrimaryAction(
    BuildContext context,
    WidgetRef ref,
    int tabIndex,
    bool hasBudgets,
  ) {
    HapticFeedback.lightImpact();
    final tabState = ref.read(expenseTabControllerProvider);
    if (tabState.customPrimaryAction != null) {
      tabState.customPrimaryAction!();
      return;
    }

    if (tabIndex == 0) {
      QuickAddTransactionSheet.show(context);
    } else if (hasBudgets && tabIndex == 1) {
      BudgetsScreen.showAddBudgetSheet(context, ref);
    } else if ((hasBudgets && tabIndex == 3) || (!hasBudgets && tabIndex == 2)) {
      ExpenseAccountsScreen.showAddAccountOrCategoryDialog(context, ref);
    }
  }

  Widget? _buildAnimatedFab(
    BuildContext context,
    WidgetRef ref,
    int tabIndex,
    bool hasBudgets,
    ColorScheme colorScheme,
  ) {
    final tabState = ref.watch(expenseTabControllerProvider);
    Widget? fabChild;

    if (tabState.customPrimaryAction != null) {
      fabChild = SpringMorphingFab(
        key: const ValueKey('expense_custom_action_fab'),
        icon: Icons.add,
        label: tabState.customPrimaryLabel ?? 'Add',
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        onPressed: tabState.customPrimaryAction!,
      );
    } else if (tabIndex == 0) {
      fabChild = SpringMorphingFab(
        key: const Key('expense_quick_add_fab'),
        icon: Icons.add,
        label: 'Add transaction',
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        onPressed: () {
          HapticFeedback.lightImpact();
          QuickAddTransactionSheet.show(context);
        },
      );
    } else if (hasBudgets && tabIndex == 1) {
      fabChild = SpringMorphingFab(
        key: const Key('budget_add_fab'),
        icon: Icons.add,
        label: 'Add budget',
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        onPressed: () {
          HapticFeedback.lightImpact();
          BudgetsScreen.showAddBudgetSheet(context, ref);
        },
      );
    } else if ((hasBudgets && tabIndex == 3) || (!hasBudgets && tabIndex == 2)) {
      fabChild = SpringMorphingFab(
        key: const Key('accounts_add_fab'),
        icon: Icons.add,
        label: 'Add wallet/category',
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        onPressed: () {
          HapticFeedback.lightImpact();
          ExpenseAccountsScreen.showAddAccountOrCategoryDialog(context, ref);
        },
      );
    }

    return SmartFabSwitcher(fab: fabChild);
  }

  Widget _buildCompanySwitcherTitle(
    BuildContext context,
    Company company,
    bool isIos,
  ) {
    return InkWell(
      key: const Key('expense_company_switcher_button'),
      onTap: () {
        HapticFeedback.lightImpact();
        CompanySwitcherSheet.show(context);
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                isIos
                    ? CupertinoIcons.money_dollar_circle_fill
                    : Icons.account_balance_wallet_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                company.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              isIos
                  ? CupertinoIcons.chevron_down
                  : Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: isIos
                  ? CupertinoColors.secondaryLabel
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(autoSyncProvider);
    final isIos = AdaptiveThemeHelper.isIos(context);
    final colorScheme = Theme.of(context).colorScheme;
    final company = ref.watch(activeCompanyProvider);
    final modeStrings = ModeStrings.of(company.mode);
    final hasBudgets = company.isModuleEnabled(AppModule.budgets);
    final syncStatus = ref.watch(syncControllerProvider);
    final tabState = ref.watch(expenseTabControllerProvider);
    final currentTabIndex = tabState.currentIndex;

    // Navigation destinations
    final List<NavigationDestination> androidDestinations = [
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
        label: modeStrings.homeTab,
      ),
      if (hasBudgets)
        NavigationDestination(
          icon: const Icon(Icons.pie_chart_outline),
          selectedIcon: const Icon(Icons.pie_chart),
          label: modeStrings.budgetsTab,
        ),
      NavigationDestination(
        icon: const Icon(Icons.bar_chart_outlined),
        selectedIcon: const Icon(Icons.bar_chart),
        label: modeStrings.reportsTab,
      ),
      NavigationDestination(
        icon: const Icon(Icons.account_balance_wallet_outlined),
        selectedIcon: const Icon(Icons.account_balance_wallet),
        label: modeStrings.accountsTab,
      ),
    ];

    final List<BottomNavigationBarItem> iosItems = [
      BottomNavigationBarItem(
        icon: const Icon(CupertinoIcons.home),
        label: modeStrings.homeTab,
      ),
      if (hasBudgets)
        BottomNavigationBarItem(
          icon: const Icon(CupertinoIcons.chart_pie),
          label: modeStrings.budgetsTab,
        ),
      BottomNavigationBarItem(
        icon: const Icon(CupertinoIcons.chart_bar),
        label: modeStrings.reportsTab,
      ),
      BottomNavigationBarItem(
        icon: const Icon(CupertinoIcons.creditcard),
        label: modeStrings.accountsTab,
      ),
    ];

    // Screens per tab
    final List<Widget> screens = [
      _ExpenseHomeView(
        key: const PageStorageKey('expense_tab_home'),
        onViewAllTransactions: () {
          Navigator.of(context).push(
            createAdaptivePageRoute(
              builder: (_) => const ExpenseTransactionsScreen(),
            ),
          );
        },
      ),
      if (hasBudgets)
        const BudgetsScreen(
          key: PageStorageKey('expense_tab_budgets'),
        ),
      const ExpenseReportsScreen(
        key: PageStorageKey('expense_tab_reports'),
      ),
      const ExpenseAccountsScreen(
        key: PageStorageKey('expense_tab_accounts'),
      ),
    ];

    final clampedIndex = currentTabIndex.clamp(0, screens.length - 1);

    // Header Title Widget or String
    Widget? titleWidget;
    String? titleText;
    if (clampedIndex == 0) {
      titleWidget = _buildCompanySwitcherTitle(context, company, isIos);
    } else if (hasBudgets && clampedIndex == 1) {
      titleText = modeStrings.budgetsTab;
    } else if ((hasBudgets && clampedIndex == 2) || (!hasBudgets && clampedIndex == 1)) {
      titleText = modeStrings.reportsTab;
    } else {
      titleText = modeStrings.accountsTab;
    }

    // Scaffold actions
    final List<Widget> actions = [
      // 1. Sync & Backup button
      if (isIos)
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          onPressed: () {
            HapticFeedback.lightImpact();
            SyncSettingsSheet.show(context);
          },
          child: syncStatus == SyncStatus.syncing
              ? const CupertinoActivityIndicator(radius: 9)
              : const Icon(CupertinoIcons.cloud_upload_fill, size: 22),
        )
      else
        IconButton(
          icon: syncStatus == SyncStatus.syncing
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                )
              : const Icon(Icons.cloud_sync_rounded),
          tooltip: syncStatus == SyncStatus.syncing ? 'Syncing...' : 'Sync & Backup',
          onPressed: () {
            HapticFeedback.lightImpact();
            SyncSettingsSheet.show(context);
          },
        ),

      if ((hasBudgets && clampedIndex == 2) || (!hasBudgets && clampedIndex == 1))
        if (isIos)
          CupertinoButton(
            key: const Key('reports_export_button'),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: () {
              HapticFeedback.lightImpact();
              final txns = ref.read(transactionsProvider).value ?? [];
              final now = DateTime.now();
              final start = DateTime(now.year, now.month, 1);
              final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
              ExpenseReportsScreen.showExportSheet(
                context: context,
                ref: ref,
                transactions: txns,
                dateRange: (start, end),
              );
            },
            child: const Icon(CupertinoIcons.square_arrow_up, size: 22),
          )
        else
          IconButton(
            key: const Key('reports_export_button'),
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Export Report',
            onPressed: () {
              HapticFeedback.lightImpact();
              final txns = ref.read(transactionsProvider).value ?? [];
              final now = DateTime.now();
              final start = DateTime(now.year, now.month, 1);
              final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
              ExpenseReportsScreen.showExportSheet(
                context: context,
                ref: ref,
                transactions: txns,
                dateRange: (start, end),
              );
            },
          ),

      if ((hasBudgets && clampedIndex == 3) || (!hasBudgets && clampedIndex == 2))
        if (company.isModuleEnabled(AppModule.recurring))
          if (isIos)
            CupertinoButton(
              key: const Key('accounts_recurring_rules_button'),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () => Navigator.of(context).push(
                createAdaptivePageRoute(builder: (_) => const RecurringScreen()),
              ),
              child: const Icon(CupertinoIcons.repeat, size: 22),
            )
          else
            IconButton(
              key: const Key('accounts_recurring_rules_button'),
              icon: const Icon(Icons.update_rounded),
              tooltip: 'Recurring Rules',
              onPressed: () => Navigator.of(context).push(
                createAdaptivePageRoute(builder: (_) => const RecurringScreen()),
              ),
            ),

      // 3. iOS '+' action button (no FAB on iOS)
      if (isIos && (clampedIndex == 0 || (hasBudgets && clampedIndex == 1) || (hasBudgets ? clampedIndex == 3 : clampedIndex == 2)))
        CupertinoButton(
          key: const Key('expense_ios_add_button'),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          onPressed: () => _handlePrimaryAction(context, ref, clampedIndex, hasBudgets),
          child: const Icon(CupertinoIcons.add, size: 22),
        ),
    ];

    return PopScope(
      canPop: clampedIndex == 0 && !(_scaffoldKey.currentState?.isDrawerOpen ?? false),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
          _scaffoldKey.currentState?.closeDrawer();
          return;
        }
        if (clampedIndex != 0) {
          HapticFeedback.lightImpact();
          ref.read(expenseTabControllerProvider.notifier).setTab(0);
          return;
        }
      },
      child: AdaptiveScaffold(
        scaffoldKey: _scaffoldKey,
        drawer: const ExpenseSidebarDrawer(),
        titleWidget: titleWidget,
        title: titleText,
        actions: actions,
        floatingActionButton: isIos
            ? null
            : _buildAnimatedFab(context, ref, clampedIndex, hasBudgets, colorScheme),
        bottomNavigationBar: AdaptiveBottomNav(
          currentIndex: clampedIndex,
          onTap: (index) {
            HapticFeedback.lightImpact();
            ref.read(expenseTabControllerProvider.notifier).setTab(index);
          },
          destinations: androidDestinations,
          iosItems: iosItems,
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          child: KeyedSubtree(
            key: ValueKey<int>(clampedIndex),
            child: AdaptivePageEntrance(
              key: ValueKey<int>(clampedIndex),
              child: screens[clampedIndex],
            ),
          ),
        ),
      ),
    );
  }
}

/// Main Home Tab View: Total wallet balance, Month switcher, Income/Expense/Net cards,
/// Category breakdown chart, and Last 10 transactions.
/// Main Home Tab View matching the Dashboard layout:
/// - (a) Subscription alert banner if applicable
/// - (b) Adaptive month switcher (iOS glass pill / Android FilledTonalIconButtons)
/// - (c) Top metric row of two AdaptiveMetricCards: Spent this month & Income this month
/// - (d) Full-width balance card with total balance and up to 3 wallet chips (AdaptiveSurfaceCard with expense_balance_card key)
/// - (e) Net savings and savings-rate line using ModeStrings.netLabel and savingsRateLabel
/// - (f) Category breakdown card (AdaptiveSurfaceCard with adaptive palettes and legend density)
/// - (g) Recent transactions section with AdaptiveSectionHeader, See all, and AdaptiveListRow rows
/// - Wrapped in RefreshIndicator.adaptive
class _ExpenseHomeView extends ConsumerWidget {
  final VoidCallback onViewAllTransactions;

  const _ExpenseHomeView({
    super.key,
    required this.onViewAllTransactions,
  });

  void _previousMonth(WidgetRef ref, DateTime current) {
    final prev = DateTime(current.year, current.month - 1);
    ref.read(selectedMonthProvider.notifier).setMonth(prev);
  }

  void _nextMonth(WidgetRef ref, DateTime current) {
    final next = DateTime(current.year, current.month + 1);
    ref.read(selectedMonthProvider.notifier).setMonth(next);
  }

  Future<void> _pickMonth(
    BuildContext context,
    WidgetRef ref,
    DateTime current,
  ) async {
    final isIos = AdaptiveThemeHelper.isIos(context);
    if (isIos) {
      DateTime tempDate = current;
      await showCupertinoModalPopup<void>(
        context: context,
        builder: (ctx) => Container(
          height: 260,
          color: CupertinoColors.systemBackground.resolveFrom(context),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      child: const Text('Cancel'),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                    CupertinoButton(
                      child: const Text('Done'),
                      onPressed: () {
                        ref.read(selectedMonthProvider.notifier).setMonth(
                              DateTime(tempDate.year, tempDate.month, 1),
                            );
                        Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: current,
                    onDateTimeChanged: (val) {
                      tempDate = val;
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      final picked = await showDatePicker(
        context: context,
        initialDate: current,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDatePickerMode: DatePickerMode.year,
      );
      if (picked != null) {
        ref.read(selectedMonthProvider.notifier).setMonth(
              DateTime(picked.year, picked.month, 1),
            );
      }
    }
  }

  Widget _buildMonthSwitcher(
    BuildContext context,
    WidgetRef ref,
    DateTime selectedMonth,
    String monthTitle,
    bool isIos,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isIos) {
      return Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              key: const Key('expense_prev_month_btn'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size.square(32),
              onPressed: () => _previousMonth(ref, selectedMonth),
              child: const Icon(CupertinoIcons.chevron_left, size: 16),
            ),
            GestureDetector(
              onTap: () => _pickMonth(context, ref, selectedMonth),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  monthTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
            CupertinoButton(
              key: const Key('expense_next_month_btn'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size.square(32),
              onPressed: () => _nextMonth(ref, selectedMonth),
              child: const Icon(CupertinoIcons.chevron_right, size: 16),
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          key: const Key('expense_prev_month_btn'),
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: 'Previous Month',
          onPressed: () => _previousMonth(ref, selectedMonth),
        ),
        const SizedBox(width: 4),
        InkWell(
          onTap: () => _pickMonth(context, ref, selectedMonth),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  monthTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton.filledTonal(
          key: const Key('expense_next_month_btn'),
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: 'Next Month',
          onPressed: () => _nextMonth(ref, selectedMonth),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = theme.brightness == Brightness.dark;
    final company = ref.watch(activeCompanyProvider);
    final modeStrings = ModeStrings.of(company.mode);
    final selectedMonth = ref.watch(selectedMonthProvider);
    final summaryAsync = ref.watch(monthSummaryProvider);
    final walletsAsync = ref.watch(walletsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final transactionsAsync = ref.watch(transactionsProvider);

    final monthTitle = DateFormat('MMMM yyyy').format(selectedMonth);

    return SafeArea(
      child: RefreshIndicator.adaptive(
        onRefresh: () async {
          HapticFeedback.lightImpact();
          ref.invalidate(monthSummaryProvider);
          ref.invalidate(walletsProvider);
          ref.invalidate(categoriesProvider);
          ref.invalidate(transactionsProvider);
          await ref.read(syncControllerProvider.notifier).triggerSync();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          children: [
            // (b) Month Switcher Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Monthly Overview',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                _buildMonthSwitcher(context, ref, selectedMonth, monthTitle, isIos),
              ],
            ),
            const SizedBox(height: 16),

            // (c) Top Metric Row: Spent this month & Income this month
            summaryAsync.when(
              loading: () => Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 90,
                      decoration: BoxDecoration(
                        color: isIos
                            ? (isDark ? Colors.white10 : Colors.black12)
                            : theme.colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Center(child: CupertinoActivityIndicator()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 90,
                      decoration: BoxDecoration(
                        color: isIos
                            ? (isDark ? Colors.white10 : Colors.black12)
                            : theme.colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Center(child: CupertinoActivityIndicator()),
                    ),
                  ),
                ],
              ),
              error: (err, stack) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: theme.colorScheme.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Failed to load metrics: $err',
                        style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              data: (summary) {
                final income = summary.totalIncomeInCents;
                final expense = summary.totalExpenseInCents;
                final primaryColor = theme.colorScheme.primary;

                return Row(
                  children: [
                    Expanded(
                      child: AdaptiveMetricCard(
                        label: modeStrings.spentThisMonth,
                        amountInCents: expense,
                        accentColor: primaryColor,
                        icon: Icon(
                          isIos ? CupertinoIcons.arrow_up : Icons.arrow_upward_rounded,
                          size: 14,
                          color: primaryColor,
                        ),
                        amountVariant: AmountVariant.large,
                        currencyCode: company.currencyCode,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AdaptiveMetricCard(
                        label: modeStrings.incomeThisMonth,
                        amountInCents: income,
                        accentColor: primaryColor,
                        icon: Icon(
                          isIos ? CupertinoIcons.arrow_down : Icons.arrow_downward_rounded,
                          size: 14,
                          color: primaryColor,
                        ),
                        amountVariant: AmountVariant.large,
                        currencyCode: company.currencyCode,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // (f) Category Breakdown Donut Card
            categoriesAsync.when(
              data: (categories) {
                return summaryAsync.when(
                  data: (summary) {
                    return CategoryBreakdownCard(
                      categoryTotalsInCents: summary.categoryTotalsInCents,
                      categories: categories,
                      currencyCode: company.currencyCode,
                      totalExpenseInCents: summary.totalExpenseInCents,
                      onCategoryTap: (catId) {
                        final current = ref.read(transactionFiltersProvider);
                        ref.read(transactionFiltersProvider.notifier).updateFilters(
                              current.copyWith(categoryIds: [catId]),
                            );
                        ref.read(expenseTabControllerProvider.notifier).setTab(1);
                      },
                    );
                  },
                  loading: () => const SkeletonListTile(),
                  error: (err, stack) => Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('Error loading category breakdown: $err'),
                  ),
                );
              },
              loading: () => const SkeletonListTile(),
              error: (err, stack) => const SizedBox(),
            ),
            const SizedBox(height: 20),

            // (g) Recent Transactions Section
            AdaptiveSectionHeader(
              title: 'Recent Transactions',
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              trailing: TextButton(
                onPressed: onViewAllTransactions,
                child: const Text('See all'),
              ),
            ),
            const SizedBox(height: 4),

            transactionsAsync.when(
              data: (txns) {
                if (txns.isEmpty) {
                  return EmptyStateView(
                    lottieAsset: 'assets/animations/empty_ledger.json',
                    title: modeStrings.emptyRecordsTitle,
                    subtitle: modeStrings.emptyRecordsSubtitle,
                    actionLabel: 'Add Transaction',
                    onActionPressed: () => QuickAddTransactionSheet.show(context),
                  );
                }

                final recentTxns = txns.take(10).toList();
                final catMap = categoriesAsync.asData?.value != null
                    ? <String, AccountModel>{
                        for (final c in categoriesAsync.asData!.value) c.id: c
                      }
                    : <String, AccountModel>{};

                return Column(
                  children: recentTxns.map((t) {
                    final cat = t.categoryAccountId != null
                        ? catMap[t.categoryAccountId!]
                        : null;
                    final isIncome = t.type == VoucherType.income;
                    final isTransfer = t.type == VoucherType.transfer;
                    final color = theme.colorScheme.primary;
                    final icon = isTransfer
                        ? (isIos ? CupertinoIcons.arrow_right_arrow_left : Icons.swap_horiz_rounded)
                        : (isIncome
                            ? (isIos ? CupertinoIcons.arrow_down : Icons.arrow_downward_rounded)
                            : (isIos ? CupertinoIcons.arrow_up : Icons.arrow_upward_rounded));
                    final title = t.narration?.trim().isNotEmpty == true
                        ? t.narration!
                        : (cat?.name ?? (isIncome ? 'Income' : 'Expense'));

                    return AdaptiveListRow(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      title: title,
                      subtitle: DateFormat('dd MMM yyyy, hh:mm a').format(t.date),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(isIos ? 10 : 12),
                        ),
                        child: Icon(icon, color: color, size: 18),
                      ),
                      trailing: AmountText(
                        amountInCents: isTransfer
                            ? t.totalAmountInCents
                            : (isIncome ? t.totalAmountInCents : -t.totalAmountInCents),
                        currencyCode: company.currencyCode,
                        variant: AmountVariant.medium,
                        overrideColor: color,
                      ),
                      onTap: onViewAllTransactions,
                    );
                  }).toList(),
                );
              },
              loading: () => Column(
                children: List.generate(3, (_) => const SkeletonListTile()),
              ),
              error: (err, stack) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Error loading transactions: $err'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
