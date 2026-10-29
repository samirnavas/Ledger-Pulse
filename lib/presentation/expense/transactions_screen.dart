import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/mode_strings.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/adaptive_chip.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_date_field.dart';
import '../../core/widgets/adaptive_form_sheet.dart';
import '../../core/widgets/adaptive_icon_surface_button.dart';
import '../../core/widgets/adaptive_list_row.dart';
import '../../core/widgets/adaptive_search_field.dart';
import '../../core/widgets/adaptive_section_header.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/skeleton_list_tile.dart';
import '../../data/models/account_model.dart';
import '../../data/models/voucher_model.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import '../providers/sync_providers.dart';
import 'quick_add_transaction_sheet.dart';

/// Transactions list tab matching the ledger's party list layout and primitives:
/// - Sticky top row with [AdaptiveSearchField] and [AdaptiveIconSurfaceButton] (active filter indicator).
/// - [AdaptiveChipRow] for transaction type filtering (All, Expense, Income, Transfer).
/// - Day-grouped list with [AdaptiveSectionHeader] (Today, Yesterday, date) and daily total.
/// - Rows rendered with [AdaptiveListRow] (category avatar, title=category, subtitle=wallet & note, trailing signed AmountText).
/// - Swipe actions with [AdaptiveSwipeBackgrounds] (edit & void confirmation).
/// - Predictive Android back & focus dismissal via [PopScope].
/// - [RefreshIndicator.adaptive] with [AnimatedSwitcher] keyed on active filters.
class ExpenseTransactionsScreen extends ConsumerStatefulWidget {
  const ExpenseTransactionsScreen({super.key});

  /// Opens the platform-adaptive transaction filters bottom sheet.
  static void showFilterModal(BuildContext context, WidgetRef ref) {
    showAdaptiveFormSheet<void>(
      context: context,
      title: 'Filter Transactions',
      doneLabel: 'Done',
      builder: (sheetContext) => const _TransactionFilterModalContent(),
    );
  }

  @override
  ConsumerState<ExpenseTransactionsScreen> createState() =>
      _ExpenseTransactionsScreenState();
}

class _ExpenseTransactionsScreenState
    extends ConsumerState<ExpenseTransactionsScreen> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    final initialQuery = ref.read(transactionFiltersProvider).textQuery ?? '';
    _searchController = TextEditingController(text: initialQuery);
    _searchFocusNode = FocusNode();
    _searchFocusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool get _isSearchActive =>
      _searchFocusNode.hasFocus || _searchController.text.trim().isNotEmpty;

  void _onSearchChanged(String query) {
    final currentFilters = ref.read(transactionFiltersProvider);
    final trimmed = query.trim();
    ref.read(transactionFiltersProvider.notifier).updateFilters(
          currentFilters.copyWith(
            textQuery: trimmed.isEmpty ? null : trimmed,
            clearTextQuery: trimmed.isEmpty,
          ),
        );
  }

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _searchController.clear();
    _searchFocusNode.unfocus();
    _onSearchChanged('');
    if (mounted) setState(() {});
  }

  void _setTypeFilter(VoucherType? type) {
    final currentFilters = ref.read(transactionFiltersProvider);
    ref.read(transactionFiltersProvider.notifier).updateFilters(
          currentFilters.copyWith(
            type: type,
            clearType: type == null,
          ),
        );
  }

  Future<bool> _voidTransaction(VoucherModel txn) async {
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Void Transaction?',
      message:
          'Are you sure you want to void ${txn.voucherNumber}? This will reverse all wallet balances.',
      confirmLabel: 'Void',
      cancelLabel: 'Cancel',
      isDestructive: true,
    );

    if (confirmed) {
      try {
        final repo = ref.read(expenseRepositoryProvider);
        await repo.voidTransaction(txn.id);
        if (mounted) {
          showAppFeedback(
            context,
            '${txn.voucherNumber} voided successfully',
          );
        }
        return true;
      } catch (e) {
        if (mounted) {
          showAppFeedback(
            context,
            'Error voiding transaction: $e',
            isError: true,
          );
        }
        return false;
      }
    }
    return false;
  }

  Widget _buildCategoryAvatar(
      BuildContext context, Color color, IconData icon, bool isIos) {
    if (isIos) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color, size: 20),
      );
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 22),
    );
  }

  String _formatDayHeader(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (day == today) {
      return 'Today';
    } else if (day == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('EEE, dd MMM yyyy').format(day);
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(activeCompanyProvider);
    final modeStrings = ModeStrings.of(company.mode);
    final transactionsAsync = ref.watch(transactionsProvider);
    final filters = ref.watch(transactionFiltersProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final walletsAsync = ref.watch(walletsProvider);
    final isIos = AdaptiveThemeHelper.isIos(context);

    final hasActiveFilters = (filters.categoryIds != null &&
            filters.categoryIds!.isNotEmpty) ||
        (filters.walletIds != null && filters.walletIds!.isNotEmpty) ||
        filters.startDate != null ||
        filters.endDate != null;

    final catMap = categoriesAsync.asData?.value != null
        ? <String, AccountModel>{
            for (final c in categoriesAsync.asData!.value) c.id: c
          }
        : <String, AccountModel>{};

    final walletMap = walletsAsync.asData?.value != null
        ? <String, AccountModel>{
            for (final w in walletsAsync.asData!.value) w.id: w
          }
        : <String, AccountModel>{};

    // Filter key for smooth AnimatedSwitcher transitions
    final filterKey =
        '${filters.type}_${filters.categoryIds?.join(",")}_${filters.walletIds?.join(",")}_${filters.startDate?.millisecondsSinceEpoch}_${filters.endDate?.millisecondsSinceEpoch}_${filters.textQuery}';

    return PopScope(
      canPop: !_isSearchActive,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _clearSearch();
      },
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            // 1. Top Search & Filter Button Row (matches party_list_tab.dart)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: AdaptiveSearchField(
                      key: const Key('transaction_search_field'),
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      hint: modeStrings.searchHint,
                      onChanged: _onSearchChanged,
                      onClear: _clearSearch,
                    ),
                  ),
                  const SizedBox(width: 10),
                  AdaptiveIconSurfaceButton(
                    key: const Key('transaction_filter_button'),
                    icon: isIos
                        ? CupertinoIcons.slider_horizontal_3
                        : Icons.filter_list_rounded,
                    isActive: hasActiveFilters,
                    tooltip: 'Filter Transactions',
                    onTap: () => ExpenseTransactionsScreen.showFilterModal(context, ref),
                  ),
                ],
              ),
            ),

            // 2. Horizontal Type Filter Row (All, Expense, Income, Transfer)
            AdaptiveChipRow<VoucherType?>(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              items: [
                const AdaptiveChipItem(
                  value: null,
                  label: 'All',
                ),
                AdaptiveChipItem(
                  value: VoucherType.expense,
                  label: 'Expenses',
                  icon: Icon(
                    isIos ? CupertinoIcons.arrow_up : Icons.arrow_upward_rounded,
                    size: 14,
                    color: AppColors.expense(context),
                  ),
                ),
                AdaptiveChipItem(
                  value: VoucherType.income,
                  label: 'Income',
                  icon: Icon(
                    isIos ? CupertinoIcons.arrow_down : Icons.arrow_downward_rounded,
                    size: 14,
                    color: AppColors.income(context),
                  ),
                ),
                AdaptiveChipItem(
                  value: VoucherType.transfer,
                  label: 'Transfers',
                  icon: Icon(
                    isIos
                        ? CupertinoIcons.arrow_right_arrow_left
                        : Icons.swap_horiz_rounded,
                    size: 14,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ],
              selectedValue: filters.type,
              onSelected: (val) => _setTypeFilter(val),
            ),
            const SizedBox(height: 4),

            // 3. Transactions List with Pull-to-Refresh & Day-grouping
            Expanded(
              child: RefreshIndicator.adaptive(
                onRefresh: () async {
                  HapticFeedback.lightImpact();
                  ref.invalidate(transactionsProvider);
                  ref.invalidate(monthSummaryProvider);
                  ref.invalidate(walletsProvider);
                  await ref.read(syncControllerProvider.notifier).triggerSync();
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: KeyedSubtree(
                    key: ValueKey<String>(filterKey),
                    child: transactionsAsync.when(
                      data: (transactions) {
                        if (transactions.isEmpty) {
                          final currentQuery = _searchController.text.trim();
                          return ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            children: [
                              EmptyStateView(
                                key: const Key('empty_transactions_view'),
                                lottieAsset: 'assets/animations/empty_ledger.json',
                                fallbackIcon: currentQuery.isNotEmpty
                                    ? (isIos
                                        ? CupertinoIcons.search
                                        : Icons.search_off_rounded)
                                    : Icons.receipt_long_outlined,
                                title: currentQuery.isNotEmpty
                                    ? 'No matches for "$currentQuery"'
                                    : modeStrings.emptyTransactionsTitle,
                                subtitle: currentQuery.isNotEmpty
                                    ? 'Try searching by a different note or voucher number.'
                                    : modeStrings.emptyTransactionsSubtitle,
                                actionLabel: modeStrings.addTransaction,
                                onActionPressed: () =>
                                    QuickAddTransactionSheet.show(context),
                              ),
                            ],
                          );
                        }

                        // Group transactions by day
                        final Map<DateTime, List<VoucherModel>> grouped = {};
                        for (final txn in transactions) {
                          final dayKey =
                              DateTime(txn.date.year, txn.date.month, txn.date.day);
                          grouped.putIfAbsent(dayKey, () => []).add(txn);
                        }

                        final sortedDays = grouped.keys.toList()
                          ..sort((a, b) => b.compareTo(a));

                        return ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(0, 0, 0, 90),
                          itemCount: sortedDays.length,
                          itemBuilder: (ctx, dayIndex) {
                            final day = sortedDays[dayIndex];
                            final dayTxns = grouped[day]!;
                            final dayHeader = _formatDayHeader(day);

                            // Compute day total net
                            int dayTotal = 0;
                            for (final t in dayTxns) {
                              if (t.type == VoucherType.income) {
                                dayTotal += t.totalAmountInCents;
                              } else if (t.type == VoucherType.expense) {
                                dayTotal -= t.totalAmountInCents;
                              }
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Day Section Header with Total Net
                                AdaptiveSectionHeader(
                                  title: dayHeader,
                                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                                  trailing: AmountText(
                                    amountInCents: dayTotal,
                                    currencyCode: company.currencyCode,
                                    showSign: true,
                                    isReceivablePositive: true,
                                    variant: AmountVariant.small,
                                  ),
                                ),

                                // Transaction List Rows with Swipe Backgrounds & Dividers
                                ...dayTxns.map((txn) {
                                  final isIncome = txn.type == VoucherType.income;
                                  final isTransfer = txn.type == VoucherType.transfer;
                                  final cat = txn.categoryAccountId != null
                                      ? catMap[txn.categoryAccountId!]
                                      : null;
                                  final sourceWallet = txn.walletAccountId != null
                                      ? walletMap[txn.walletAccountId!]
                                      : null;
                                  final destWallet = txn.toWalletAccountId != null
                                      ? walletMap[txn.toWalletAccountId!]
                                      : null;

                                  final color = isTransfer
                                      ? AppColors.primaryBlue
                                      : (isIncome
                                          ? AppColors.income(context)
                                          : AppColors.expense(context));

                                  final icon = isTransfer
                                      ? (isIos
                                          ? CupertinoIcons.arrow_right_arrow_left
                                          : Icons.swap_horiz_rounded)
                                      : (isIncome
                                          ? (isIos
                                              ? CupertinoIcons.arrow_down
                                              : Icons.arrow_downward_rounded)
                                          : (isIos
                                              ? CupertinoIcons.arrow_up
                                              : Icons.arrow_upward_rounded));

                                  final title = isTransfer
                                      ? 'Transfer'
                                      : (cat?.name ?? (isIncome ? 'Income' : 'Expense'));

                                  final subtitleParts = <String>[];
                                  if (isTransfer) {
                                    subtitleParts.add(
                                        '${sourceWallet?.name ?? 'Wallet'} ➔ ${destWallet?.name ?? 'Wallet'}');
                                  } else if (sourceWallet != null) {
                                    subtitleParts.add(sourceWallet.name);
                                  }

                                  if (txn.narration != null &&
                                      txn.narration!.trim().isNotEmpty) {
                                    subtitleParts.add(txn.narration!.trim());
                                  }

                                  final subtitle = subtitleParts.isNotEmpty
                                      ? subtitleParts.join(' • ')
                                      : null;

                                  final trailingAmount = isTransfer
                                      ? AmountText(
                                          amountInCents: txn.totalAmountInCents,
                                          currencyCode: company.currencyCode,
                                          overrideColor: AppColors.primaryBlue,
                                          variant: AmountVariant.medium,
                                        )
                                      : AmountText(
                                          amountInCents: isIncome
                                              ? txn.totalAmountInCents
                                              : -txn.totalAmountInCents,
                                          currencyCode: company.currencyCode,
                                          showSign: true,
                                          isReceivablePositive: true,
                                          variant: AmountVariant.medium,
                                        );

                                  return Dismissible(
                                    key: ValueKey('txn_${txn.id}'),
                                    direction: DismissDirection.horizontal,
                                    dismissThresholds: const {
                                      DismissDirection.startToEnd: 0.25,
                                      DismissDirection.endToStart: 0.25,
                                    },
                                    background: AdaptiveSwipeBackgrounds.edit(
                                      context,
                                      isIos: isIos,
                                    ),
                                    secondaryBackground:
                                        AdaptiveSwipeBackgrounds.delete(
                                      context,
                                      isIos: isIos,
                                      label: 'Void',
                                    ),
                                    confirmDismiss: (direction) async {
                                      if (direction == DismissDirection.startToEnd) {
                                        HapticFeedback.lightImpact();
                                        QuickAddTransactionSheet.show(
                                          context,
                                          initialVoucher: txn,
                                        );
                                        return false;
                                      } else if (direction ==
                                          DismissDirection.endToStart) {
                                        HapticFeedback.mediumImpact();
                                        return await _voidTransaction(txn);
                                      }
                                      return false;
                                    },
                                    child: AdaptiveListRow(
                                      leading: _buildCategoryAvatar(
                                        context,
                                        color,
                                        icon,
                                        isIos,
                                      ),
                                      title: title,
                                      subtitle: subtitle,
                                      trailing: trailingAmount,
                                      showDivider: true,
                                      onTap: () => QuickAddTransactionSheet.show(
                                        context,
                                        initialVoucher: txn,
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            );
                          },
                        );
                      },
                      loading: () => ListView.builder(
                        itemCount: 8,
                        itemBuilder: (_, _) => const SkeletonListTile(),
                      ),
                      error: (err, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Error loading transactions: $err',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Content for the platform-adaptive filter modal sheet.
class _TransactionFilterModalContent extends ConsumerWidget {
  const _TransactionFilterModalContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filters = ref.watch(transactionFiltersProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final walletsAsync = ref.watch(walletsProvider);
    final isIos = AdaptiveThemeHelper.isIos(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Filter Transactions',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ref.read(transactionFiltersProvider.notifier).reset();
                },
                child: const Text('Reset All'),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 12),

          // Date Range Section
          Text(
            'Date Range',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AdaptiveDateField(
                  label: 'From',
                  selectedDate: filters.startDate ?? DateTime.now(),
                  onDateSelected: (date) {
                    final cur = ref.read(transactionFiltersProvider);
                    ref.read(transactionFiltersProvider.notifier).updateFilters(
                          cur.copyWith(startDate: date),
                        );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdaptiveDateField(
                  label: 'To',
                  selectedDate: filters.endDate ?? DateTime.now(),
                  onDateSelected: (date) {
                    final cur = ref.read(transactionFiltersProvider);
                    ref.read(transactionFiltersProvider.notifier).updateFilters(
                          cur.copyWith(endDate: date),
                        );
                  },
                ),
              ),
            ],
          ),
          if (filters.startDate != null || filters.endDate != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  final cur = ref.read(transactionFiltersProvider);
                  ref.read(transactionFiltersProvider.notifier).updateFilters(
                        TransactionFilters(
                          categoryIds: cur.categoryIds,
                          walletIds: cur.walletIds,
                          textQuery: cur.textQuery,
                          type: cur.type,
                        ),
                      );
                },
                child: const Text('Clear Dates', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Category Filter Section
          Text(
            'Category',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          categoriesAsync.when(
            data: (cats) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AdaptiveChip(
                  label: 'All Categories',
                  isSelected:
                      filters.categoryIds == null || filters.categoryIds!.isEmpty,
                  onSelected: (_) {
                    final cur = ref.read(transactionFiltersProvider);
                    ref.read(transactionFiltersProvider.notifier).updateFilters(
                          cur.copyWith(categoryIds: null),
                        );
                  },
                ),
                ...cats.map((c) {
                  final isSel = filters.categoryIds?.contains(c.id) ?? false;
                  return AdaptiveChip(
                    label: c.name,
                    isSelected: isSel,
                    onSelected: (selected) {
                      final cur = ref.read(transactionFiltersProvider);
                      final next = selected ? [c.id] : null;
                      ref.read(transactionFiltersProvider.notifier).updateFilters(
                            cur.copyWith(categoryIds: next),
                          );
                    },
                  );
                }),
              ],
            ),
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Error: $err'),
          ),
          const SizedBox(height: 16),

          // Wallet Filter Section
          Text(
            'Wallet',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          walletsAsync.when(
            data: (wallets) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AdaptiveChip(
                  label: 'All Wallets',
                  isSelected:
                      filters.walletIds == null || filters.walletIds!.isEmpty,
                  onSelected: (_) {
                    final cur = ref.read(transactionFiltersProvider);
                    ref.read(transactionFiltersProvider.notifier).updateFilters(
                          cur.copyWith(walletIds: null),
                        );
                  },
                ),
                ...wallets.map((w) {
                  final isSel = filters.walletIds?.contains(w.id) ?? false;
                  return AdaptiveChip(
                    label: w.name,
                    isSelected: isSel,
                    onSelected: (selected) {
                      final cur = ref.read(transactionFiltersProvider);
                      final next = selected ? [w.id] : null;
                      ref.read(transactionFiltersProvider.notifier).updateFilters(
                            cur.copyWith(walletIds: next),
                          );
                    },
                  );
                }),
              ],
            ),
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Error: $err'),
          ),
          const SizedBox(height: 24),

          if (!isIos)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Apply Filters'),
              ),
            ),
        ],
      ),
    );
  }
}
