import '../../core/widgets/app_pull_to_refresh.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/mode_strings.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_bottom_nav.dart';
import '../../core/widgets/adaptive_list_row.dart';
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
import '../../data/models/voucher_model.dart';
import '../widgets/active_profile_indicator_pill.dart';
import '../widgets/account_header_button.dart';
import '../providers/budget_providers.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import '../providers/sync_providers.dart';
import 'accounts_screen.dart';
import 'budgets_screen.dart';
import 'expense_reports_screen.dart';
import 'providers/expense_tab_controller.dart';
import 'quick_add_transaction_sheet.dart';
import 'transaction_details_screen.dart';
import 'transactions_screen.dart';
import 'widgets/category_breakdown_card.dart';
import 'widgets/expense_sidebar_drawer.dart';
import 'widgets/category_icons.dart';

/// Adaptive Home Shell for Expense Tracker mode mirroring DashboardScreen.
/// Uses AdaptiveScaffold with company-switcher title, profile action,
/// drawer navigation, adaptive bottom nav, and back behaviour.
class ExpenseHomeScreen extends ConsumerStatefulWidget {
  const ExpenseHomeScreen({super.key});

  @override
  ConsumerState<ExpenseHomeScreen> createState() => _ExpenseHomeScreenState();
}

class _ExpenseHomeScreenState extends ConsumerState<ExpenseHomeScreen> {
  bool _fabExtended = true;
  late final PageController _pageController;
  ({int index, Object token})? _navTransition;

  @override
  void initState() {
    super.initState();
    final company = ref.read(activeCompanyProvider);
    final lastIndex = company.isModuleEnabled(AppModule.budgets) ? 3 : 2;
    final initialIndex = ref.read(expenseTabControllerProvider).currentIndex;
    _pageController = PageController(
      initialPage: initialIndex.clamp(0, lastIndex),
      keepPage: false,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _handleScroll(UserScrollNotification notification) {
    if (notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical &&
        notification.direction != ScrollDirection.idle) {
      final extended = notification.direction == ScrollDirection.forward;
      if (_fabExtended != extended) setState(() => _fabExtended = extended);
    }
    return false;
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _handlePrimaryAction(
    BuildContext context,
    WidgetRef ref,
    int tabIndex,
    bool hasBudgets,
  ) {
    HapticFeedback.lightImpact();
    if (tabIndex == 0 || tabIndex == (hasBudgets ? 3 : 2)) {
      QuickAddTransactionSheet.show(context);
    } else if (hasBudgets && tabIndex == 1) {
      BudgetsScreen.showAddBudgetSheet(context, ref);
    }
  }

  Widget? _buildAnimatedFab(
    BuildContext context,
    WidgetRef ref,
    int tabIndex,
    bool hasBudgets,
    ColorScheme colorScheme,
  ) {
    Widget? fabChild;

    if (tabIndex == 0 || tabIndex == (hasBudgets ? 3 : 2)) {
      fabChild = SpringMorphingFab(
        isExtended: _fabExtended,
        key: tabIndex == 0
            ? const Key('expense_quick_add_fab')
            : const Key('transactions_quick_add_fab'),
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
        isExtended: _fabExtended,
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
    }

    return SmartFabSwitcher(fab: fabChild);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(autoSyncProvider);
    final isIos = AdaptiveThemeHelper.isIos(context);
    final colorScheme = Theme.of(context).colorScheme;
    final company = ref.watch(activeCompanyProvider);
    final modeStrings = ModeStrings.of(company.mode);
    final hasBudgets = company.isModuleEnabled(AppModule.budgets);
    final tabState = ref.watch(expenseTabControllerProvider);
    final currentTabIndex = tabState.currentIndex;
    final transactionsIndex = hasBudgets ? 3 : 2;
    final clampedIndex = currentTabIndex.clamp(0, transactionsIndex);

    ref.listen(
      expenseTabControllerProvider.select((state) => state.currentIndex),
      (previous, next) {
        final index = next.clamp(0, transactionsIndex);
        if (_navTransition?.index == index) return;
        if (_pageController.hasClients &&
            (_navTransition != null ||
                _pageController.page?.round() != index)) {
          _pageController.jumpToPage(index);
        }
      },
    );

    void selectTab(int index) {
      HapticFeedback.lightImpact();
      if (index != transactionsIndex && clampedIndex == transactionsIndex) {
        FocusManager.instance.primaryFocus?.unfocus();
        ref.read(transactionFiltersProvider.notifier).reset();
      }
      setState(() => _fabExtended = true);
      ref.read(expenseTabControllerProvider.notifier).setTab(index);
    }

    Future<void> slideToTab(int index) async {
      if (index == clampedIndex) return;
      if (!_pageController.hasClients ||
          MediaQuery.disableAnimationsOf(context)) {
        selectTab(index);
        return;
      }

      final transition = (index: index, token: Object());
      _navTransition = transition;
      selectTab(index);
      try {
        await _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        );
      } finally {
        if (mounted && _navTransition == transition) {
          setState(() => _navTransition = null);
        }
      }
    }

    void openProfile() {
      HapticFeedback.lightImpact();
      Navigator.of(context).push(
        createAdaptivePageRoute(
          builder: (_) => const ExpenseAccountsScreen(isStandalone: true),
        ),
      );
    }

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
        icon: const Icon(Icons.receipt_long_outlined),
        selectedIcon: const Icon(Icons.receipt_long_rounded),
        label: modeStrings.transactionsTab,
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
        icon: const Icon(CupertinoIcons.list_bullet),
        label: modeStrings.transactionsTab,
      ),
    ];

    // Screens per tab
    final List<Widget> screens = [
      _ExpenseHomeView(
        key: const PageStorageKey('expense_tab_home'),
        onOpenTransactions: ({transaction}) {
          selectTab(transactionsIndex);
          if (transaction != null) {
            TransactionDetailsScreen.show(context, transaction, ref);
          }
        },
      ),
      if (hasBudgets)
        const BudgetsScreen(key: PageStorageKey('expense_tab_budgets')),
      const ExpenseReportsScreen(key: PageStorageKey('expense_tab_reports')),
      ExpenseTransactionsScreen(
        key: const PageStorageKey('expense_tab_transactions'),
        isActive: clampedIndex == transactionsIndex,
        onBackToHome: () {
          if (ref
                  .read(expenseTabControllerProvider)
                  .currentIndex
                  .clamp(0, transactionsIndex) ==
              transactionsIndex) {
            selectTab(0);
          }
        },
      ),
    ];

    // Scaffold actions
    final List<Widget> actions = [
      if ((hasBudgets && clampedIndex == 2) ||
          (!hasBudgets && clampedIndex == 1))
        if (isIos)
          CupertinoButton(
            key: const Key('reports_export_button'),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: () {
              HapticFeedback.lightImpact();
              final txns = ref.read(transactionsProvider).asData?.value;
              if (txns == null) return;
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
              final txns = ref.read(transactionsProvider).asData?.value;
              if (txns == null) return;
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

      // iOS '+' action button (no FAB on iOS)
      if (isIos &&
          (clampedIndex == 0 ||
              (hasBudgets && clampedIndex == 1) ||
              clampedIndex == transactionsIndex))
        CupertinoButton(
          key: const Key('expense_ios_add_button'),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          onPressed: () =>
              _handlePrimaryAction(context, ref, clampedIndex, hasBudgets),
          child: const Icon(CupertinoIcons.add, size: 22),
        ),
      AccountHeaderButton(onPressed: openProfile),
    ];

    return PopScope(
      // Scaffold's drawer adds a LocalHistoryEntry, which handles back and
      // disables the page pop gesture while open. Only tab navigation needs
      // an explicit veto here; reading isDrawerOpen during build can go stale.
      canPop: clampedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || clampedIndex == transactionsIndex) return;
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
        titleWidget: const Material(
          type: MaterialType.transparency,
          child: ActiveProfileIndicatorPill(),
        ),
        actions: actions,
        floatingActionButton: isIos
            ? null
            : _buildAnimatedFab(
                context,
                ref,
                clampedIndex,
                hasBudgets,
                colorScheme,
              ),
        bottomNavigationBar: AdaptiveBottomNav(
          currentIndex: clampedIndex,
          onTap: slideToTab,
          destinations: androidDestinations,
          iosItems: iosItems,
        ),
        body: AbsorbPointer(
          absorbing: _navTransition != null,
          child: PageView(
            controller: _pageController,
            onPageChanged: (index) {
              if (_navTransition != null) return;
              final selectedIndex = ref
                  .read(expenseTabControllerProvider)
                  .currentIndex
                  .clamp(0, transactionsIndex);
              if (index != selectedIndex) selectTab(index);
            },
            children: [
              for (final screen in screens)
                NotificationListener<UserScrollNotification>(
                  key: screen.key,
                  onNotification: _handleScroll,
                  child: screen,
                ),
            ],
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
  final void Function({VoucherModel? transaction}) onOpenTransactions;

  const _ExpenseHomeView({super.key, required this.onOpenTransactions});

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
                        ref
                            .read(selectedMonthProvider.notifier)
                            .setMonth(
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
        ref
            .read(selectedMonthProvider.notifier)
            .setMonth(DateTime(picked.year, picked.month, 1));
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
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
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

  int _calculateDaysInPeriod(DateTime selectedMonth) {
    final now = DateTime.now();
    if (selectedMonth.year == now.year && selectedMonth.month == now.month) {
      return now.day > 0 ? now.day : 1;
    }
    if (selectedMonth.isAfter(DateTime(now.year, now.month))) {
      return 1;
    }
    return DateTime(selectedMonth.year, selectedMonth.month + 1, 0).day;
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
    final categoriesAsync = ref.watch(categoriesProvider);
    final transactionsAsync = ref.watch(transactionsProvider);
    final allCategoriesBudgetAsync = ref.watch(allCategoriesBudgetProvider);

    final monthTitle = DateFormat('MMMM yyyy').format(selectedMonth);

    return SafeArea(
      child: AppPullToRefresh(
        onRefresh: () async {
          ref.invalidate(monthSummaryProvider);
          ref.invalidate(walletsProvider);
          ref.invalidate(categoriesProvider);
          ref.invalidate(transactionsProvider);
          ref.invalidate(allCategoriesBudgetProvider);
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
                _buildMonthSwitcher(
                  context,
                  ref,
                  selectedMonth,
                  monthTitle,
                  isIos,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // (c) Focused Full-Width Expense Card with Daily Average & Budget Progress Bar
            summaryAsync.when(
              loading: () => Container(
                height: 110,
                decoration: BoxDecoration(
                  color: isIos
                      ? (isDark ? Colors.white10 : Colors.black12)
                      : theme.colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Center(child: CupertinoActivityIndicator()),
              ),
              error: (err, stack) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: theme.colorScheme.error,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Failed to load metrics: $err',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              data: (summary) {
                final expense = summary.totalExpenseInCents;
                final daysCount = _calculateDaysInPeriod(selectedMonth);
                final dailyAvgInCents = (expense / daysCount).round();

                final allCatBudget = allCategoriesBudgetAsync.asData?.value;
                final hasBudget =
                    allCatBudget != null &&
                    allCatBudget.effectiveAllocatedInCents > 0;
                final budgetCents =
                    allCatBudget?.effectiveAllocatedInCents ?? 0;
                final spentCents = allCatBudget?.spentInCents ?? expense;
                final rawRatio = hasBudget && budgetCents > 0
                    ? (spentCents / budgetCents)
                    : 0.0;
                final budgetPercent = rawRatio.clamp(0.0, 1.0);

                final primaryColor = theme.colorScheme.primary;

                Color progressColor;
                if (rawRatio >= 1.0) {
                  progressColor = theme.colorScheme.error;
                } else if (rawRatio >= 0.8) {
                  progressColor = theme.colorScheme.tertiary;
                } else {
                  progressColor = primaryColor;
                }

                return AdaptiveSurfaceCard(
                  accentColor: primaryColor,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isIos
                                      ? CupertinoIcons.arrow_up
                                      : Icons.arrow_upward_rounded,
                                  size: 16,
                                  color: primaryColor,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                modeStrings.spentThisMonth,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          if (hasBudget)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: progressColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                rawRatio >= 1.0
                                    ? 'Exceeded'
                                    : (rawRatio >= 0.8
                                          ? 'Warning'
                                          : 'On Track'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: progressColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AmountText(
                        amountInCents: expense,
                        currencyCode: company.currencyCode,
                        variant: AmountVariant.large,
                        overrideColor: theme.colorScheme.onSurface,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Daily average: ${CurrencyFormatter.format(dailyAvgInCents)} / day (${daysCount}d)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (hasBudget) ...[
                        const SizedBox(height: 16),
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: isDark ? 0.25 : 0.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Budget: ${CurrencyFormatter.format(spentCents)} of ${CurrencyFormatter.format(budgetCents)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '${(rawRatio * 100).round()}%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: progressColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: budgetPercent,
                            minHeight: 8,
                            backgroundColor: progressColor.withValues(
                              alpha: 0.15,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              progressColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // (f) Category Breakdown Card
            categoriesAsync.when(
              data: (categories) {
                return summaryAsync.when(
                  data: (summary) {
                    final hasBudgets = company.isModuleEnabled(
                      AppModule.budgets,
                    );
                    final reportsTabIndex = hasBudgets ? 2 : 1;
                    return CategoryBreakdownCard(
                      categoryTotalsInCents: summary.categoryTotalsInCents,
                      categories: categories,
                      currencyCode: company.currencyCode,
                      totalExpenseInCents: summary.totalExpenseInCents,
                      onCardTap: () {
                        ref
                            .read(expenseTabControllerProvider.notifier)
                            .setTab(reportsTabIndex);
                      },
                      onCategoryTap: (catId) {
                        final current = ref.read(transactionFiltersProvider);
                        ref
                            .read(transactionFiltersProvider.notifier)
                            .updateFilters(
                              current.copyWith(categoryIds: [catId]),
                            );
                        ref
                            .read(expenseTabControllerProvider.notifier)
                            .setTab(reportsTabIndex);
                      },
                    );
                  },
                  loading: () => const SkeletonListTile(),
                  error: (err, stack) => Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(
                        alpha: 0.3,
                      ),
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
                onPressed: onOpenTransactions,
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
                    onActionPressed: () =>
                        QuickAddTransactionSheet.show(context),
                  );
                }

                final recentTxns = txns.take(10).toList();
                final catMap = categoriesAsync.asData?.value != null
                    ? <String, AccountModel>{
                        for (final c in categoriesAsync.asData!.value) c.id: c,
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
                        ? (isIos
                              ? CupertinoIcons.arrow_right_arrow_left
                              : Icons.swap_horiz_rounded)
                        : savedCategoryIcon(cat) ??
                              (isIncome
                                  ? (isIos
                                        ? CupertinoIcons.arrow_down
                                        : Icons.arrow_downward_rounded)
                                  : (isIos
                                        ? CupertinoIcons.arrow_up
                                        : Icons.arrow_upward_rounded));
                    final title = t.narration?.trim().isNotEmpty == true
                        ? t.narration!
                        : (cat?.name ?? (isIncome ? 'Income' : 'Expense'));

                    return AdaptiveListRow(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      title: title,
                      subtitle: DateFormat(
                        'dd MMM yyyy, hh:mm a',
                      ).format(t.date),
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
                            : (isIncome
                                  ? t.totalAmountInCents
                                  : -t.totalAmountInCents),
                        currencyCode: company.currencyCode,
                        variant: AmountVariant.medium,
                        overrideColor: color,
                      ),
                      onTap: () => onOpenTransactions(transaction: t),
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
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.3,
                  ),
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
