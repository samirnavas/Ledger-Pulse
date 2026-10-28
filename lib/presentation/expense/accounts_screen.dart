import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../core/widgets/adaptive_text_field_dialog.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../core/widgets/skeleton_list_tile.dart';
import '../../data/models/account_model.dart';
import '../../data/models/company_model.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';

/// Screen managing Wallets (with running balances and opening balance editor)
/// and Categories (hierarchical list with add, edit, and archive operations).
class ExpenseAccountsScreen extends ConsumerStatefulWidget {
  const ExpenseAccountsScreen({super.key});

  /// Opens dialog to add a wallet or category.
  static Future<void> showAddAccountOrCategoryDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final company = ref.read(activeCompanyProvider);
    final categoriesAsync = ref.read(categoriesProvider);
    final allCats = categoriesAsync.asData?.value ?? [];

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_rounded),
                title: const Text('Add Wallet'),
                subtitle: const Text('Bank account, cash or credit card'),
                onTap: () {
                  Navigator.pop(ctx);
                  _ExpenseAccountsScreenState.showAddWalletDialogStatic(
                    context,
                    ref,
                    company,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.category_rounded),
                title: const Text('Add Category'),
                subtitle: const Text('Expense or income category'),
                onTap: () {
                  Navigator.pop(ctx);
                  _ExpenseAccountsScreenState.showAddCategoryDialogStatic(
                    context,
                    ref,
                    allCats,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  ConsumerState<ExpenseAccountsScreen> createState() =>
      _ExpenseAccountsScreenState();
}

class _ExpenseAccountsScreenState extends ConsumerState<ExpenseAccountsScreen> {
  int _selectedTab = 0; // 0 = Wallets, 1 = Categories
  AccountType _selectedCatType = AccountType.expense;

  // -------------------------------------------------------------
  // WALLET DIALOGS & ACTIONS
  // -------------------------------------------------------------


  static Future<void> showAddWalletDialogStatic(
    BuildContext context,
    WidgetRef ref,
    Company company,
  ) async {
    final nameController = TextEditingController();
    final balanceController = TextEditingController();
    AccountType walletType = AccountType.asset;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Wallet'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const Key('wallet_name_input'),
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Wallet Name',
                    hintText: 'e.g. ICICI Bank, Petty Cash',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Wallet Type',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Asset (Cash/Bank)'),
                      selected: walletType == AccountType.asset,
                      onSelected: (val) {
                        if (val) setDialogState(() => walletType = AccountType.asset);
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Liability (Card)'),
                      selected: walletType == AccountType.liability,
                      onSelected: (val) {
                        if (val) setDialogState(() => walletType = AccountType.liability);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('wallet_opening_balance_input'),
                  controller: balanceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Opening Balance (Optional)',
                    prefixText:
                        '${CurrencyFormatter.getSymbol(company.currencyCode)} ',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              key: const Key('save_wallet_button'),
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                final cents =
                    CurrencyFormatter.parseToCents(balanceController.text);
                try {
                  final repo = ref.read(expenseRepositoryProvider);
                  await repo.createWallet(
                    name: name,
                    type: walletType,
                    openingBalanceInCents: cents,
                  );
                  if (context.mounted) Navigator.of(ctx).pop();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error creating wallet: $e')),
                    );
                  }
                }
              },
              child: const Text('Save Wallet'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOpeningBalanceDialog(
    BuildContext context,
    AccountModel wallet,
    Company company,
  ) async {
    final result = await showAdaptiveTextFieldDialog(
      context: context,
      title: 'Opening Balance: ${wallet.name}',
      message: wallet.type == AccountType.liability
          ? 'Set historical liability / debt owed on this credit card.'
          : 'Set historical starting balance for this wallet.',
      initialValue: wallet.currentBalanceInCents > 0
          ? (wallet.currentBalanceInCents / 100.0).toStringAsFixed(2)
          : '',
      labelText: 'Opening Balance',
      prefixText: '${CurrencyFormatter.getSymbol(company.currencyCode)} ',
      textFieldKey: const Key('edit_opening_balance_field'),
      confirmButtonKey: const Key('save_opening_balance_button'),
      confirmLabel: 'Save Balance',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );

    if (result != null) {
      final cents = CurrencyFormatter.parseToCents(result);
      try {
        final repo = ref.read(expenseRepositoryProvider);
        await repo.setOpeningBalance(wallet.id, cents);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating opening balance: $e')),
          );
        }
      }
    }
  }

  // -------------------------------------------------------------
  // CATEGORY DIALOGS & ACTIONS
  // -------------------------------------------------------------


  static Future<void> showAddCategoryDialogStatic(
    BuildContext context,
    WidgetRef ref,
    List<AccountModel> allCategories, {
    AccountType categoryType = AccountType.expense,
  }) async {
    final nameController = TextEditingController();
    String? selectedParentId;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final potentialParents = allCategories
              .where((c) => c.type == categoryType && c.parentAccountId == null)
              .toList();

          return AlertDialog(
            title: Text(
              'Add ${categoryType == AccountType.expense ? 'Expense' : 'Income'} Category',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('category_name_input'),
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Category Name',
                      hintText: 'e.g. Subscriptions, Groceries',
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (potentialParents.isNotEmpty) ...[
                    const Text('Parent Category (Optional)',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedParentId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      hint: const Text('None (Top Level)'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('None (Top Level)'),
                        ),
                        ...potentialParents.map(
                          (p) => DropdownMenuItem<String?>(
                            value: p.id,
                            child: Text(p.name),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setDialogState(() => selectedParentId = val);
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                key: const Key('save_category_button'),
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;

                  try {
                    final repo = ref.read(expenseRepositoryProvider);
                    await repo.createCategory(
                      name: name,
                      type: categoryType,
                      parentAccountId: selectedParentId,
                    );
                    if (context.mounted) Navigator.of(ctx).pop();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error creating category: $e')),
                      );
                    }
                  }
                },
                child: const Text('Save Category'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteOrArchiveCategory(AccountModel cat) async {
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Delete or Archive Category?',
      message:
          'If this category has existing transactions, it will be safely archived instead of deleted.',
      confirmLabel: 'Confirm',
      isDestructive: true,
    );

    if (confirmed) {
      try {
        final repo = ref.read(expenseRepositoryProvider);
        final wasDeleted = await repo.deleteCategory(cat.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                wasDeleted
                    ? '${cat.name} was deleted'
                    : '${cat.name} was archived (has transaction history)',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting category: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(activeCompanyProvider);
    final walletsAsync = ref.watch(walletsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: AdaptiveSegmentedControl<int>(
              groupValue: _selectedTab,
              children: const {
                0: Text('Wallets'),
                1: Text('Categories'),
              },
              onValueChanged: (tab) => setState(() => _selectedTab = tab),
            ),
          ),
          Expanded(
            child: _selectedTab == 0
                ? _buildWalletsTab(context, company, walletsAsync)
                : _buildCategoriesTab(context, company, categoriesAsync),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: WALLETS VIEW
  // -------------------------------------------------------------

  Widget _buildWalletsTab(
    BuildContext context,
    Company company,
    AsyncValue<List<AccountModel>> walletsAsync,
  ) {
    final theme = Theme.of(context);

    return walletsAsync.when(
      data: (wallets) {
        if (wallets.isEmpty) {
          return const EmptyStateView(
            title: 'No Wallets Configured',
            subtitle: 'Add a wallet to record cash, bank, or credit card transactions.',
            icon: Icons.account_balance_wallet_outlined,
          );
        }

        // Calculate total balance across asset wallets and liability cards
        int totalAssetBalance = 0;
        int totalLiabilityBalance = 0;
        for (final w in wallets) {
          if (w.type == AccountType.liability) {
            totalLiabilityBalance += w.currentBalanceInCents;
          } else {
            totalAssetBalance += w.currentBalanceInCents;
          }
        }
        final netWorth = totalAssetBalance - totalLiabilityBalance;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
          children: [
            // Net Balance Across Wallets Card
            LiquidGlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Liquid Assets',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AmountText(
                    amountInCents: netWorth,
                    currencyCode: company.currencyCode,
                    variant: AmountVariant.large,
                  ),
                  if (totalLiabilityBalance > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Includes ${CurrencyFormatter.format(totalLiabilityBalance, currencyCode: company.currencyCode)} credit debt',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'Your Wallets',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            ...wallets.map((wallet) {
              final isLiability = wallet.type == AccountType.liability;
              final icon = isLiability
                  ? Icons.credit_card
                  : (wallet.name.toLowerCase().contains('bank')
                      ? Icons.account_balance
                      : Icons.wallet);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LiquidGlassCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isLiability
                              ? Colors.purple.withValues(alpha: 0.12)
                              : Colors.teal.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          color: isLiability ? Colors.purple : Colors.teal,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              wallet.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              isLiability ? 'Credit Card / Liability' : 'Asset Wallet',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          AmountText(
                            amountInCents: wallet.currentBalanceInCents,
                            currencyCode: company.currencyCode,
                            overrideColor: isLiability ? Colors.redAccent : null,
                            variant: AmountVariant.medium,
                          ),
                          InkWell(
                            key: Key('edit_opening_btn_${wallet.id}'),
                            onTap: () => _showOpeningBalanceDialog(
                                context, wallet, company),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Set Opening',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
      loading: () => ListView.builder(
        itemCount: 4,
        itemBuilder: (_, index) => const SkeletonListTile(),
      ),
      error: (e, _) => Center(child: Text('Error loading wallets: $e')),
    );
  }

  // -------------------------------------------------------------
  // TAB 2: CATEGORIES VIEW
  // -------------------------------------------------------------

  Widget _buildCategoriesTab(
    BuildContext context,
    Company company,
    AsyncValue<List<AccountModel>> categoriesAsync,
  ) {
    final theme = Theme.of(context);

    return categoriesAsync.when(
      data: (allCategories) {
        final filtered =
            allCategories.where((c) => c.type == _selectedCatType).toList();

        // Top level categories
        final topLevel =
            filtered.where((c) => c.parentAccountId == null).toList();

        // Child categories grouped by parent
        final Map<String, List<AccountModel>> subCats = {};
        for (final c in filtered) {
          if (c.parentAccountId != null) {
            subCats.putIfAbsent(c.parentAccountId!, () => []).add(c);
          }
        }

        return Column(
          children: [
            // Expense / Income Segmented Toggle
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: AdaptiveSegmentedControl<AccountType>(
                groupValue: _selectedCatType,
                children: const {
                  AccountType.expense: Text('Expense Categories'),
                  AccountType.income: Text('Income Categories'),
                },
                onValueChanged: (t) => setState(() => _selectedCatType = t),
              ),
            ),

            Expanded(
              child: filtered.isEmpty
                  ? const EmptyStateView(
                      title: 'No Categories',
                      subtitle: 'Tap the + button below to create a category.',
                      icon: Icons.category_outlined,
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      children: topLevel.map((parent) {
                        final children = subCats[parent.id] ?? [];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: LiquidGlassCard(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            child: Column(
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: _selectedCatType == AccountType.expense
                                          ? Colors.red.withValues(alpha: 0.1)
                                          : Colors.green.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.category,
                                      size: 18,
                                      color: _selectedCatType == AccountType.expense
                                          ? Colors.redAccent
                                          : Colors.green,
                                    ),
                                  ),
                                  title: Text(
                                    parent.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    children.isNotEmpty
                                        ? '${children.length} subcategories'
                                        : (parent.description ?? ''),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.archive_outlined,
                                        size: 20),
                                    tooltip: 'Archive category',
                                    onPressed: () =>
                                        _deleteOrArchiveCategory(parent),
                                  ),
                                ),

                                // Subcategories if present
                                if (children.isNotEmpty) ...[
                                  const Divider(height: 1),
                                  ...children.map((sub) => Padding(
                                        padding: const EdgeInsets.only(
                                            left: 48, top: 6, bottom: 6),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '• ${sub.name}',
                                              style: theme.textTheme.bodyMedium,
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.archive_outlined,
                                                  size: 18),
                                              onPressed: () =>
                                                  _deleteOrArchiveCategory(sub),
                                            ),
                                          ],
                                        ),
                                      )),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        );
      },
      loading: () => ListView.builder(
        itemCount: 5,
        itemBuilder: (_, index) => const SkeletonListTile(),
      ),
      error: (e, _) => Center(child: Text('Error loading categories: $e')),
    );
  }
}
