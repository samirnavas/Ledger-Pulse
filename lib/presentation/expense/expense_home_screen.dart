import '../../core/widgets/app_pull_to_refresh.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/constants/mode_strings.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_bottom_nav.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_list_row.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_section_header.dart';
import '../../core/widgets/adaptive_surface_card.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/skeleton_list_tile.dart';
import '../../core/widgets/smart_fab_switcher.dart';
import '../../core/widgets/spring_morphing_fab.dart';
import '../../data/models/account_model.dart';
import '../../data/models/company_model.dart';
import '../../data/models/voucher_model.dart';
import '../widgets/active_profile_indicator_pill.dart';
import '../widgets/account_header_button.dart';
import '../providers/auth_providers.dart';
import '../providers/budget_providers.dart';
import '../providers/company_providers.dart';
import '../providers/database_providers.dart';
import '../providers/expense_providers.dart';
import '../providers/profile_session_controller.dart';
import '../providers/profile_session_state.dart';
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
  // Standard 56 dp FAB, Scaffold's 16 dp margin, and 8 dp breathing room.
  static const _homeFabClearance = 56.0 + 16 + 8;
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
        isExtended:
            _fabExtended && MediaQuery.textScalerOf(context).scale(14) <= 21,
        key: tabIndex == 0
            ? const Key('expense_quick_add_fab')
            : const Key('transactions_quick_add_fab'),
        icon: Symbols.add,
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
    final showHomeAdd =
        ref
            .watch(dashboardTransactionHistoryProvider)
            .asData
            ?.value
            .hasActivity ==
        true;

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
        bottomClearance: !isIos && showHomeAdd ? _homeFabClearance : 0,
        onOpenTransactions: ({transaction}) {
          ref.read(transactionFiltersProvider.notifier).reset();
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
          ((clampedIndex == 0 && showHomeAdd) ||
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
        floatingActionButton: isIos || (clampedIndex == 0 && !showHomeAdd)
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
  final double bottomClearance;

  const _ExpenseHomeView({
    super.key,
    required this.onOpenTransactions,
    required this.bottomClearance,
  });

  Widget _retry(BuildContext context, String message, VoidCallback onRetry) {
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(message, style: Theme.of(context).textTheme.bodyMedium),
        AdaptiveButton(
          type: AdaptiveButtonType.text,
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
      ],
    );
  }

  Widget _buildFirstExpense(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<AccountModel>> wallets,
  ) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('home_first_expense'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        wallets.when(
          loading: () => const SkeletonListTile(),
          error: (_, _) => _retry(
            context,
            'Could not load wallets.',
            () => ref.invalidate(walletsProvider),
          ),
          data: (items) {
            final needsWallet = items.isEmpty;
            return AdaptiveSurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    foregroundColor: theme.colorScheme.onSecondaryContainer,
                    child: const Icon(Icons.receipt_long_outlined, size: 20),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your first expense',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    needsWallet
                        ? 'Set up a wallet to record your first expense.'
                        : 'Record an expense to start understanding your spending.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AdaptiveButton(
                    key: const Key('home_first_expense_action'),
                    isFullWidth: true,
                    onPressed: () => needsWallet
                        ? ExpenseAccountsScreen.showAddWalletSheet(context, ref)
                        : QuickAddTransactionSheet.show(context),
                    child: Text(
                      needsWallet ? 'Set up a wallet' : 'Add transaction',
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBreakdown(
    BuildContext context,
    WidgetRef ref,
    Company company,
    AsyncValue<ExpenseMonthSummary> summary,
    AsyncValue<List<AccountModel>> categories,
  ) {
    final data = summary.asData?.value;
    if (data == null ||
        data.totalExpenseInCents <= 0 ||
        !data.categoryTotalsInCents.values.any((amount) => amount > 0)) {
      return const SizedBox.shrink();
    }
    final reportsTab = company.isModuleEnabled(AppModule.budgets) ? 2 : 1;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: categories.when(
        loading: () => const SkeletonListTile(),
        error: (_, _) => _retry(
          context,
          'Could not load spending categories.',
          () => ref.invalidate(categoriesProvider),
        ),
        data: (items) => CategoryBreakdownCard(
          categoryTotalsInCents: data.categoryTotalsInCents,
          totalExpenseInCents: data.totalExpenseInCents,
          categories: items,
          currencyCode: company.currencyCode,
          onCardTap: () => ref
              .read(expenseTabControllerProvider.notifier)
              .setTab(reportsTab),
          onCategoryTap: (id) {
            final current = ref.read(transactionFiltersProvider);
            ref
                .read(transactionFiltersProvider.notifier)
                .updateFilters(current.copyWith(categoryIds: [id]));
            ref.read(expenseTabControllerProvider.notifier).setTab(reportsTab);
          },
        ),
      ),
    );
  }

  Widget _buildSetup(
    BuildContext context,
    WidgetRef ref,
    Company company,
    ({bool hasActivity, bool hasExpense})? history,
    List<AccountModel>? wallets,
  ) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final dismissed = ref.watch(dashboardSetupPreferenceProvider(company.id));
    if (prefs == null ||
        history == null ||
        wallets == null ||
        dismissed == true ||
        (dismissed == null && history.hasExpense)) {
      return const SizedBox.shrink();
    }

    final needsWallet = wallets.isEmpty;
    final hasBudgets = company.isModuleEnabled(AppModule.budgets);
    final budgets = hasBudgets
        ? ref.watch(budgetsListProvider).asData?.value
        : null;
    final actions = <(String, VoidCallback)>[
      // First use already has one prominent inline action.
      if (history.hasActivity && needsWallet)
        (
          'Set up a wallet',
          () => ExpenseAccountsScreen.showAddWalletSheet(context, ref),
        ),
      if (history.hasActivity && !history.hasExpense && !needsWallet)
        (
          'Record your first expense',
          () => QuickAddTransactionSheet.show(context),
        ),
      if (budgets?.isEmpty == true)
        (
          'Create a budget',
          () => BudgetsScreen.showAddBudgetSheet(context, ref),
        ),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();

    final user = ref.watch(activeUserIdProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        key: const Key('home_get_started'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveSectionHeader(
            title: 'Get started',
            padding: EdgeInsets.zero,
            trailing: IconButton(
              tooltip: 'Dismiss Get started',
              icon: Icon(
                AdaptiveThemeHelper.isIos(context)
                    ? CupertinoIcons.xmark
                    : Symbols.close,
              ),
              onPressed: () async {
                final saved = await prefs.setBool(
                  dashboardSetupPreferenceKey(user, company.id),
                  true,
                );
                if (context.mounted && saved) {
                  ref.invalidate(dashboardSetupPreferenceProvider(company.id));
                }
              },
            ),
          ),
          for (final (label, action) in actions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                label.contains('wallet')
                    ? Icons.account_balance_wallet_outlined
                    : label.contains('budget')
                    ? Icons.pie_chart_outline
                    : Icons.receipt_long_outlined,
              ),
              title: Text(label),
              trailing: const Icon(Icons.chevron_right),
              onTap: action,
            ),
        ],
      ),
    );
  }

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
            Flexible(
              child: GestureDetector(
                onTap: () => _pickMonth(context, ref, selectedMonth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Text(
                    monthTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
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
        Flexible(
          child: InkWell(
            onTap: () => _pickMonth(context, ref, selectedMonth),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      monthTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
    final transactionsAsync = ref.watch(dashboardRecentTransactionsProvider);
    final history = ref.watch(dashboardTransactionHistoryProvider);
    final isFirstUse = history.asData?.value.hasActivity == false;
    final allCategoriesBudgetAsync = ref.watch(allCategoriesBudgetProvider);
    final walletsAsync = ref.watch(walletsProvider);
    final offline = ref.watch(
      profileSessionProvider.select(
        (session) =>
            session is ActiveProfileReadySessionState && session.isOffline,
      ),
    );
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);

    final monthTitle = DateFormat('MMMM yyyy').format(selectedMonth);

    return SafeArea(
      minimum: EdgeInsets.only(bottom: bottomClearance),
      child: AppPullToRefresh(
        onRefresh: () async {
          ref.invalidate(monthSummaryProvider);
          ref.invalidate(walletsProvider);
          ref.invalidate(categoriesProvider);
          ref.invalidate(transactionsProvider);
          ref.invalidate(dashboardRecentTransactionsProvider);
          ref.invalidate(dashboardTransactionHistoryProvider);
          ref.invalidate(allCategoriesBudgetProvider);
          await ref.read(syncControllerProvider.notifier).triggerSync();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          children: [
            if (offline)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Offline · Changes sync when you reconnect.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (isFirstUse)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome!', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      "Let's start tracking your money.",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            if (!isFirstUse) ...[
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    'Overview',
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
            ],
            if (isFirstUse)
              AdaptiveSurfaceCard(
                color: theme.colorScheme.secondaryContainer,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modeStrings.spentThisMonth,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AmountText(
                      amountInCents: 0,
                      currencyCode: company.currencyCode,
                      variant: AmountVariant.large,
                      overrideColor: theme.colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('MMMM yyyy').format(DateTime.now()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              )
            else
              summaryAsync.when(
                loading: () => const SkeletonListTile(),
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
                          'Could not load the monthly summary.',
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(monthSummaryProvider),
                        child: const Text('Retry'),
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
                    padding: EdgeInsets.all(expense > 0 || hasBudget ? 20 : 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
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
                                Flexible(
                                  child: Text(
                                    modeStrings.spentThisMonth,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
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
                        if (expense > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Daily average: ${CurrencyFormatter.format(dailyAvgInCents, currencyCode: company.currencyCode)} / day (${daysCount}d)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
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
                              Expanded(
                                child: Text(
                                  'Budget: ${CurrencyFormatter.format(spentCents, currencyCode: company.currencyCode)} of ${CurrencyFormatter.format(budgetCents, currencyCode: company.currencyCode)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
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
            if (!isFirstUse)
              AnimatedSize(
                duration: motion,
                alignment: Alignment.topCenter,
                child: _buildBreakdown(
                  context,
                  ref,
                  company,
                  summaryAsync,
                  categoriesAsync,
                ),
              ),
            const SizedBox(height: 20),
            AnimatedSize(
              duration: motion,
              alignment: Alignment.topCenter,
              child: isFirstUse
                  ? _buildFirstExpense(context, ref, walletsAsync)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AdaptiveSectionHeader(
                          title: 'Recent Transactions',
                          padding: const EdgeInsets.only(bottom: 8),
                          trailing:
                              transactionsAsync.asData?.value.isNotEmpty == true
                              ? TextButton(
                                  onPressed: onOpenTransactions,
                                  child: const Text('See all'),
                                )
                              : null,
                        ),
                        if (history.hasError)
                          _retry(
                            context,
                            'Could not load workspace activity.',
                            () => ref.invalidate(
                              dashboardTransactionHistoryProvider,
                            ),
                          )
                        else if (history.isLoading)
                          const SkeletonListTile()
                        else
                          transactionsAsync.when(
                            data: (txns) {
                              if (txns.isEmpty) {
                                return Text(
                                  'No transactions in this month.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                );
                              }
                              final catMap =
                                  categoriesAsync.asData?.value != null
                                  ? <String, AccountModel>{
                                      for (final c
                                          in categoriesAsync.asData!.value)
                                        c.id: c,
                                    }
                                  : <String, AccountModel>{};

                              return Column(
                                children: txns.map((t) {
                                  final cat = t.categoryAccountId != null
                                      ? catMap[t.categoryAccountId!]
                                      : null;
                                  final isIncome = t.type == VoucherType.income;
                                  final isTransfer =
                                      t.type == VoucherType.transfer;
                                  final color = theme.colorScheme.primary;
                                  final icon = isTransfer
                                      ? (isIos
                                            ? CupertinoIcons
                                                  .arrow_right_arrow_left
                                            : Icons.swap_horiz_rounded)
                                      : savedCategoryIcon(cat) ??
                                            (isIncome
                                                ? (isIos
                                                      ? CupertinoIcons
                                                            .arrow_down
                                                      : Icons
                                                            .arrow_downward_rounded)
                                                : (isIos
                                                      ? CupertinoIcons.arrow_up
                                                      : Icons
                                                            .arrow_upward_rounded));
                                  final title =
                                      t.narration?.trim().isNotEmpty == true
                                      ? t.narration!
                                      : (isTransfer
                                            ? 'Transfer'
                                            : cat?.name ??
                                                  (isIncome
                                                      ? 'Income'
                                                      : 'Expense'));

                                  return AdaptiveListRow(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    title: title,
                                    subtitle: DateFormat(
                                      'dd MMM yyyy, hh:mm a',
                                    ).format(t.date),
                                    leading: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(
                                          isIos ? 10 : 12,
                                        ),
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
                                    onTap: () =>
                                        onOpenTransactions(transaction: t),
                                  );
                                }).toList(),
                              );
                            },
                            loading: () => const SkeletonListTile(),
                            error: (_, _) => _retry(
                              context,
                              'Could not load transactions.',
                              () => ref.invalidate(
                                dashboardRecentTransactionsProvider,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            _buildSetup(
              context,
              ref,
              company,
              history.asData?.value,
              walletsAsync.asData?.value,
            ),
          ],
        ),
      ),
    );
  }
}
