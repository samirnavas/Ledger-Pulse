import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../core/widgets/skeleton_list_tile.dart';
import '../../data/models/account_model.dart';
import '../../data/models/company_model.dart';
import '../../data/models/voucher_model.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import 'quick_add_transaction_sheet.dart';

/// Transactions list screen grouped by day with search, type/category/wallet filters,
/// swipe or popup action menus to edit and void transactions with confirmation dialogs.
class ExpenseTransactionsScreen extends ConsumerStatefulWidget {
  const ExpenseTransactionsScreen({super.key});

  @override
  ConsumerState<ExpenseTransactionsScreen> createState() =>
      _ExpenseTransactionsScreenState();
}

class _ExpenseTransactionsScreenState
    extends ConsumerState<ExpenseTransactionsScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

  void _setTypeFilter(VoucherType? type) {
    final currentFilters = ref.read(transactionFiltersProvider);
    ref.read(transactionFiltersProvider.notifier).updateFilters(
          currentFilters.copyWith(
            type: type,
            clearType: type == null,
          ),
        );
  }

  void _showFilterModal(BuildContext context) {
    final walletsAsync = ref.read(walletsProvider);
    final categoriesAsync = ref.read(categoriesProvider);

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final filters = ref.watch(transactionFiltersProvider);

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: ListView(
              shrinkWrap: true,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Filter Transactions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        ref
                            .read(transactionFiltersProvider.notifier)
                            .updateFilters(const TransactionFilters());
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Reset All'),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),

                // Category Filter
                const Text('Category',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                categoriesAsync.when(
                  data: (cats) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('All Categories'),
                        selected: filters.categoryIds == null ||
                            filters.categoryIds!.isEmpty,
                        onSelected: (_) {
                          ref
                              .read(transactionFiltersProvider.notifier)
                              .updateFilters(
                                filters.copyWith(categoryIds: null),
                              );
                        },
                      ),
                      ...cats.map((c) {
                        final isSel = filters.categoryIds?.contains(c.id) ?? false;
                        return FilterChip(
                          label: Text(c.name),
                          selected: isSel,
                          onSelected: (selected) {
                            final next = selected ? [c.id] : null;
                            ref
                                .read(transactionFiltersProvider.notifier)
                                .updateFilters(
                                  filters.copyWith(categoryIds: next),
                                );
                          },
                        );
                      }),
                    ],
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (err, stack) => const SizedBox(),
                ),
                const SizedBox(height: 16),

                // Wallet Filter
                const Text('Wallet',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                walletsAsync.when(
                  data: (wallets) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('All Wallets'),
                        selected: filters.walletIds == null ||
                            filters.walletIds!.isEmpty,
                        onSelected: (_) {
                          ref
                              .read(transactionFiltersProvider.notifier)
                              .updateFilters(
                                filters.copyWith(walletIds: null),
                              );
                        },
                      ),
                      ...wallets.map((w) {
                        final isSel = filters.walletIds?.contains(w.id) ?? false;
                        return FilterChip(
                          label: Text(w.name),
                          selected: isSel,
                          onSelected: (selected) {
                            final next = selected ? [w.id] : null;
                            ref
                                .read(transactionFiltersProvider.notifier)
                                .updateFilters(
                                  filters.copyWith(walletIds: next),
                                );
                          },
                        );
                      }),
                    ],
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (err, stack) => const SizedBox(),
                ),
                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Apply Filters'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _voidTransaction(VoucherModel txn) async {
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Void Transaction?',
      message:
          'Are you sure you want to void ${txn.voucherNumber}? This will reverse all wallet balances.',
      confirmLabel: 'Void Transaction',
      isDestructive: true,
    );

    if (confirmed) {
      try {
        final repo = ref.read(expenseRepositoryProvider);
        await repo.voidTransaction(txn.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${txn.voucherNumber} voided successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error voiding transaction: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final company = ref.watch(activeCompanyProvider);
    final transactionsAsync = ref.watch(transactionsProvider);
    final filters = ref.watch(transactionFiltersProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final walletsAsync = ref.watch(walletsProvider);

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter',
            onPressed: () => _showFilterModal(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Quick Filter Chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const Key('transaction_search_field'),
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search note, voucher # or ref...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),

          // Horizontal Type Filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _buildTypeChip('All', null, filters.type == null),
                const SizedBox(width: 8),
                _buildTypeChip(
                  'Expenses',
                  VoucherType.expense,
                  filters.type == VoucherType.expense,
                  color: const Color(0xFFEF4444),
                ),
                const SizedBox(width: 8),
                _buildTypeChip(
                  'Income',
                  VoucherType.income,
                  filters.type == VoucherType.income,
                  color: const Color(0xFF10B981),
                ),
                const SizedBox(width: 8),
                _buildTypeChip(
                  'Transfers',
                  VoucherType.transfer,
                  filters.type == VoucherType.transfer,
                  color: const Color(0xFF3B82F6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Transactions List Grouped By Day
          Expanded(
            child: transactionsAsync.when(
              data: (transactions) {
                if (transactions.isEmpty) {
                  return const EmptyStateView(
                    key: Key('empty_transactions_view'),
                    title: 'No Transactions',
                    subtitle:
                        'No transactions match your active filters or date range.',
                    icon: Icons.receipt_long_outlined,
                  );
                }

                // Group transactions by date (Day)
                final Map<DateTime, List<VoucherModel>> grouped = {};
                for (final txn in transactions) {
                  final dayKey =
                      DateTime(txn.date.year, txn.date.month, txn.date.day);
                  grouped.putIfAbsent(dayKey, () => []).add(txn);
                }

                final sortedDays = grouped.keys.toList()
                  ..sort((a, b) => b.compareTo(a));

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: sortedDays.length,
                  itemBuilder: (ctx, dayIndex) {
                    final day = sortedDays[dayIndex];
                    final dayTxns = grouped[day]!;
                    final dayHeader = _formatDayHeader(day);

                    // Compute day net
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
                        // Day Header
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                dayHeader,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              AmountText(
                                amountInCents: dayTotal,
                                currencyCode: company.currencyCode,
                                showSign: true,
                                variant: AmountVariant.small,
                              ),
                            ],
                          ),
                        ),

                        // Transaction Cards
                        ...dayTxns.map((txn) {
                          return _buildTransactionTile(
                            context: context,
                            txn: txn,
                            company: company,
                            catMap: catMap,
                            walletMap: walletMap,
                          );
                        }),
                      ],
                    );
                  },
                );
              },
              loading: () => ListView.builder(
                itemCount: 6,
                itemBuilder: (_, index) => const SkeletonListTile(),
              ),
              error: (err, _) => Center(
                child: Text('Error loading transactions: $err'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(
    String label,
    VoucherType? type,
    bool isSelected, {
    Color? color,
  }) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: color?.withValues(alpha: 0.15) ??
          Theme.of(context).colorScheme.primaryContainer,
      labelStyle: TextStyle(
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected && color != null ? color : null,
      ),
      onSelected: (_) => _setTypeFilter(type),
    );
  }

  Widget _buildTransactionTile({
    required BuildContext context,
    required VoucherModel txn,
    required Company company,
    required Map<String, AccountModel> catMap,
    required Map<String, AccountModel> walletMap,
  }) {
    final theme = Theme.of(context);
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

    String title;
    IconData icon;
    Color iconColor;

    if (isTransfer) {
      title =
          '${sourceWallet?.name ?? 'Wallet'} ➔ ${destWallet?.name ?? 'Wallet'}';
      icon = Icons.swap_horiz;
      iconColor = const Color(0xFF3B82F6);
    } else {
      final hasNarration =
          txn.narration != null && txn.narration!.trim().isNotEmpty;
      if (hasNarration) {
        title = txn.narration!.trim();
      } else {
        title = cat?.name ?? (isIncome ? 'Income' : 'Expense');
      }
      icon = isIncome ? Icons.arrow_downward : Icons.arrow_upward;
      iconColor =
          isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    }

    final subtitleParts = <String>[];
    if (!isTransfer) {
      if (txn.narration != null &&
          txn.narration!.trim().isNotEmpty &&
          cat?.name != null) {
        subtitleParts.add(cat!.name);
      }
      if (sourceWallet != null) {
        subtitleParts.add(sourceWallet.name);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LiquidGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () {
          QuickAddTransactionSheet.show(context, initialVoucher: txn);
        },
        child: Row(
          children: [
            // Colored Avatar Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),

            // Title & Subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitleParts.isNotEmpty)
                    Text(
                      subtitleParts.join(' • '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AmountText(
                  amountInCents: txn.totalAmountInCents,
                  currencyCode: company.currencyCode,
                  overrideColor: iconColor,
                  showSign: !isTransfer,
                  variant: AmountVariant.medium,
                ),
                Text(
                  txn.voucherNumber,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ],
            ),

            // Action Menu
            PopupMenuButton<String>(
              key: Key('txn_menu_${txn.id}'),
              icon: const Icon(Icons.more_vert, size: 18),
              padding: EdgeInsets.zero,
              onSelected: (action) {
                if (action == 'edit') {
                  QuickAddTransactionSheet.show(context, initialVoucher: txn);
                } else if (action == 'void') {
                  _voidTransaction(txn);
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'void',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline,
                          size: 18, color: Colors.redAccent),
                      SizedBox(width: 8),
                      Text('Void', style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
}
