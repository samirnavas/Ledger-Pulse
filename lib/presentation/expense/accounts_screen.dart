import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_chip.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_controls.dart';
import '../../core/widgets/adaptive_form_sheet.dart';
import '../../core/widgets/adaptive_list_row.dart';
import '../../core/widgets/adaptive_picker.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../core/widgets/adaptive_surface_card.dart';
import '../../core/widgets/adaptive_text_field_dialog.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/empty_state_view.dart';
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
                onTap: () async {
                  Navigator.pop(ctx);
                  final cats = allCats.isNotEmpty
                      ? allCats
                      : (await ref.read(expenseRepositoryProvider).getCategories());
                  if (context.mounted) {
                    _ExpenseAccountsScreenState.showAddCategoryDialogStatic(
                      context,
                      ref,
                      cats,
                    );
                  }
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

    Future<void> doSave(BuildContext sheetCtx) async {
      final name = nameController.text.trim();
      if (name.isEmpty) return;

      HapticFeedback.mediumImpact();
      final cents = CurrencyFormatter.parseToCents(balanceController.text);
      try {
        final repo = ref.read(expenseRepositoryProvider);
        await repo.createWallet(
          name: name,
          type: walletType,
          openingBalanceInCents: cents,
        );
        if (context.mounted) {
          Navigator.of(sheetCtx).pop();
          showAppFeedback(context, 'Wallet saved successfully');
        }
      } catch (e) {
        if (context.mounted) {
          showAppFeedback(context, 'Error creating wallet: $e', isError: true);
        }
      }
    }

    await showAdaptiveFormSheet<void>(
      context: context,
      title: 'Add Wallet',
      doneLabel: 'Done',
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final theme = Theme.of(ctx);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('wallet_name_input'),
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Wallet Name',
                    hintText: 'e.g. ICICI Bank, Petty Cash',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Wallet Type',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    AdaptiveChip(
                      label: 'Asset (Cash/Bank)',
                      isSelected: walletType == AccountType.asset,
                      onSelected: (val) {
                        if (val) setDialogState(() => walletType = AccountType.asset);
                      },
                    ),
                    const SizedBox(width: 8),
                    AdaptiveChip(
                      label: 'Liability (Card)',
                      isSelected: walletType == AccountType.liability,
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
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                AdaptiveButton(
                  key: const Key('save_wallet_button'),
                  child: const Text('Save Wallet'),
                  onPressed: () => doSave(sheetContext),
                ),
              ],
            ),
          );
        },
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
        HapticFeedback.mediumImpact();
        final repo = ref.read(expenseRepositoryProvider);
        await repo.setOpeningBalance(wallet.id, cents);
        if (context.mounted) {
          showAppFeedback(context, 'Opening balance updated');
        }
      } catch (e) {
        if (context.mounted) {
          showAppFeedback(
            context,
            'Error updating opening balance: $e',
            isError: true,
          );
        }
      }
    }
  }

  static Future<void> _renameWalletStatic(
    BuildContext context,
    WidgetRef ref,
    AccountModel wallet,
  ) async {
    final result = await showAdaptiveTextFieldDialog(
      context: context,
      title: 'Rename Wallet',
      initialValue: wallet.name,
      labelText: 'Wallet Name',
      confirmLabel: 'Save',
    );
    if (result != null && result.trim().isNotEmpty && result.trim() != wallet.name) {
      try {
        final repo = ref.read(expenseRepositoryProvider);
        await repo.updateWallet(id: wallet.id, name: result.trim());
        HapticFeedback.lightImpact();
        if (context.mounted) {
          showAppFeedback(context, 'Wallet renamed');
        }
      } catch (e) {
        if (context.mounted) {
          showAppFeedback(context, 'Error renaming wallet: $e', isError: true);
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

    final effectiveCategories = allCategories.isNotEmpty
        ? allCategories
        : (await ref.read(expenseRepositoryProvider).getCategories());

    final potentialParents = effectiveCategories
        .where((c) => c.type == categoryType && c.parentAccountId == null)
        .toList();

    Future<void> doSave(BuildContext sheetCtx) async {
      final name = nameController.text.trim();
      if (name.isEmpty) return;

      HapticFeedback.mediumImpact();
      try {
        final repo = ref.read(expenseRepositoryProvider);
        await repo.createCategory(
          name: name,
          type: categoryType,
          parentAccountId: selectedParentId,
        );
        if (context.mounted) {
          Navigator.of(sheetCtx).pop();
          showAppFeedback(context, 'Category saved successfully');
        }
      } catch (e) {
        if (context.mounted) {
          showAppFeedback(context, 'Error creating category: $e', isError: true);
        }
      }
    }

    if (!context.mounted) return;
    await showAdaptiveFormSheet<void>(
      context: context,
      title:
          'Add ${categoryType == AccountType.expense ? 'Expense' : 'Income'} Category',
      doneLabel: 'Done',
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final pickerItems = [
            const AdaptivePickerItem<String?>(
              value: null,
              label: 'None (Top Level)',
            ),
            ...potentialParents.map(
              (p) => AdaptivePickerItem<String?>(
                value: p.id,
                label: p.name,
              ),
            ),
          ];

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('category_name_input'),
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Category Name',
                    hintText: 'e.g. Subscriptions, Groceries',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (potentialParents.isNotEmpty) ...[
                  AdaptiveDropdownField<String?>(
                    label: 'Parent Category',
                    value: selectedParentId,
                    hint: 'None (Top Level)',
                    items: pickerItems,
                    onChanged: (val) {
                      setDialogState(() => selectedParentId = val);
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 8),
                AdaptiveButton(
                  key: const Key('save_category_button'),
                  child: const Text('Save Category'),
                  onPressed: () => doSave(sheetContext),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _renameCategory(AccountModel cat) async {
    final result = await showAdaptiveTextFieldDialog(
      context: context,
      title: 'Rename Category',
      initialValue: cat.name,
      labelText: 'Category Name',
      confirmLabel: 'Save',
    );
    if (result != null && result.trim().isNotEmpty && result.trim() != cat.name) {
      try {
        final repo = ref.read(expenseRepositoryProvider);
        await repo.updateCategory(id: cat.id, name: result.trim());
        HapticFeedback.lightImpact();
        if (mounted) {
          showAppFeedback(context, 'Category renamed');
        }
      } catch (e) {
        if (mounted) {
          showAppFeedback(context, 'Error renaming category: $e', isError: true);
        }
      }
    }
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
        HapticFeedback.mediumImpact();
        final repo = ref.read(expenseRepositoryProvider);
        final wasDeleted = await repo.deleteCategory(cat.id);
        if (mounted) {
          showAppFeedback(
            context,
            wasDeleted
                ? '${cat.name} was deleted'
                : '${cat.name} was archived (has transaction history)',
          );
        }
      } catch (e) {
        if (mounted) {
          showAppFeedback(
            context,
            'Error deleting category: $e',
            isError: true,
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
            AdaptiveSurfaceCard(
              padding: const EdgeInsets.all(18),
              margin: const EdgeInsets.only(bottom: 16),
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
                        color: AppColors.payableRed,
                      ),
                    ),
                  ],
                ],
              ),
            ),

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
                child: AdaptiveSurfaceCard(
                  key: Key('wallet_card_${wallet.id}'),
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
                            overrideColor: isLiability ? AppColors.payableRed : null,
                            variant: AmountVariant.medium,
                          ),
                          if (isLiability && wallet.currentBalanceInCents > 0)
                            Text(
                              'Owed',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.payableRed,
                                fontWeight: FontWeight.w600,
                              ),
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
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (val) {
                          if (val == 'rename') {
                            _renameWalletStatic(context, ref, wallet);
                          } else if (val == 'opening') {
                            _showOpeningBalanceDialog(context, wallet, company);
                          }
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            key: Key('rename_wallet_${wallet.id}'),
                            value: 'rename',
                            child: const Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Rename'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            key: Key('set_opening_wallet_${wallet.id}'),
                            value: 'opening',
                            child: const Row(
                              children: [
                                Icon(Icons.account_balance_wallet_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Set Opening Balance'),
                              ],
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
                      subtitle: 'Create a category to organize your transactions.',
                      icon: Icons.category_outlined,
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      children: topLevel.map((parent) {
                        final children = subCats[parent.id] ?? [];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AdaptiveSurfaceCard(
                            margin: EdgeInsets.zero,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              children: [
                                Dismissible(
                                  key: Key('cat_dismiss_${parent.id}'),
                                  direction: DismissDirection.endToStart,
                                  confirmDismiss: (dir) async {
                                    await _deleteOrArchiveCategory(parent);
                                    return false;
                                  },
                                  background: const SizedBox.shrink(),
                                  secondaryBackground:
                                      AdaptiveSwipeBackgrounds.delete(
                                    context,
                                    label: 'Archive',
                                    icon: Icons.archive_outlined,
                                  ),
                                  child: AdaptiveListRow(
                                    title: parent.name,
                                    subtitle: children.isNotEmpty
                                        ? '${children.length} subcategories'
                                        : (parent.description ?? ''),
                                    avatarColor: _selectedCatType == AccountType.expense
                                        ? AppColors.expense(context)
                                        : AppColors.income(context),
                                    showDivider: children.isNotEmpty,
                                    onTap: () => _renameCategory(parent),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          key: Key('archive_cat_btn_${parent.id}'),
                                          icon: const Icon(
                                            Icons.archive_outlined,
                                            size: 20,
                                          ),
                                          tooltip: 'Archive category',
                                          onPressed: () =>
                                              _deleteOrArchiveCategory(parent),
                                        ),
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert, size: 18),
                                          onSelected: (val) {
                                            if (val == 'rename') {
                                              _renameCategory(parent);
                                            } else if (val == 'archive') {
                                              _deleteOrArchiveCategory(parent);
                                            }
                                          },
                                          itemBuilder: (ctx) => [
                                            PopupMenuItem(
                                              key: Key('rename_cat_${parent.id}'),
                                              value: 'rename',
                                              child: const Row(
                                                children: [
                                                  Icon(Icons.edit_outlined, size: 18),
                                                  SizedBox(width: 8),
                                                  Text('Rename'),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              key: Key('archive_cat_${parent.id}'),
                                              value: 'archive',
                                              child: const Row(
                                                children: [
                                                  Icon(Icons.archive_outlined, size: 18),
                                                  SizedBox(width: 8),
                                                  Text('Archive'),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Subcategories if present
                                if (children.isNotEmpty)
                                  ...children.map((sub) {
                                    return Dismissible(
                                      key: Key('cat_dismiss_${sub.id}'),
                                      direction: DismissDirection.endToStart,
                                      confirmDismiss: (dir) async {
                                        await _deleteOrArchiveCategory(sub);
                                        return false;
                                      },
                                      background: const SizedBox.shrink(),
                                      secondaryBackground:
                                          AdaptiveSwipeBackgrounds.delete(
                                        context,
                                        label: 'Archive',
                                        icon: Icons.archive_outlined,
                                      ),
                                      child: AdaptiveListRow(
                                        padding: const EdgeInsets.only(
                                            left: 48, right: 16, top: 4, bottom: 4),
                                        title: sub.name,
                                        initials: '•',
                                        avatarColor: _selectedCatType == AccountType.expense
                                            ? AppColors.expense(context)
                                            : AppColors.income(context),
                                        showDivider: false,
                                        onTap: () => _renameCategory(sub),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              key: Key('archive_cat_btn_${sub.id}'),
                                              icon: const Icon(
                                                Icons.archive_outlined,
                                                size: 18,
                                              ),
                                              tooltip: 'Archive category',
                                              onPressed: () =>
                                                  _deleteOrArchiveCategory(sub),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }),
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
