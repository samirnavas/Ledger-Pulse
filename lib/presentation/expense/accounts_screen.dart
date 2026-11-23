import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/mode_strings.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_chip.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_controls.dart';
import '../../core/widgets/adaptive_form_sheet.dart';
import '../../core/widgets/adaptive_list_row.dart';
import '../../core/widgets/adaptive_page_entrance.dart';
import '../../core/widgets/adaptive_picker.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_section_header.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../core/widgets/adaptive_surface_card.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/skeleton_list_tile.dart';
import '../../core/widgets/spring_morphing_fab.dart';
import '../../data/models/account_model.dart';
import '../../data/models/company_model.dart';
import '../../data/models/user_profile_model.dart';
import '../auth/phone_input_screen.dart';
import '../home/company_switcher_sheet.dart';
import '../home/sync_settings_sheet.dart';
import '../providers/auth_providers.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import '../providers/profile_provider.dart';
import 'archived_categories_screen.dart';
import 'arrange_categories_screen.dart';
import 'recurring_screen.dart';
import 'wallet_report_screen.dart';

/// Screen managing My Account (with Account, Wallet, and Category sections).
class ExpenseAccountsScreen extends ConsumerStatefulWidget {
  final int initialTab;
  final bool isStandalone;

  const ExpenseAccountsScreen({
    super.key,
    this.initialTab = 0,
    this.isStandalone = false,
  });

  /// Opens dialog to add a wallet or category.
  /// Creates a category without leaving the current transaction form.
  static Future<AccountModel?> showAddCategorySheet(
    BuildContext context,
    WidgetRef ref, {
    required AccountType categoryType,
  }) async {
    final categories = await ref
        .read(expenseRepositoryProvider)
        .getCategories();
    if (!context.mounted) return null;
    return _ExpenseAccountsScreenState.showAddOrEditCategoryDialogStatic(
      context,
      ref,
      categories,
      categoryType: categoryType,
    );
  }

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
                      : (await ref
                            .read(expenseRepositoryProvider)
                            .getCategories());
                  if (context.mounted) {
                    _ExpenseAccountsScreenState.showAddOrEditCategoryDialogStatic(
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
  late int _selectedTab; // 0 = Profile, 1 = Wallet, 2 = Category
  late final PageController _pageController;
  Object? _sectionTransition;
  AccountType _selectedCatType = AccountType.expense;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _pageController = PageController(
      initialPage: _selectedTab,
      keepPage: false,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _selectSection(int index) async {
    if (index == _selectedTab) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _selectedTab = index);
      _pageController.jumpToPage(index);
      return;
    }

    final transition = Object();
    setState(() {
      _selectedTab = index;
      _sectionTransition = transition;
    });
    try {
      await _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    } finally {
      if (mounted && identical(_sectionTransition, transition)) {
        setState(() => _sectionTransition = null);
      }
    }
  }

  Future<void> _addItem() async {
    HapticFeedback.lightImpact();
    switch (_selectedTab) {
      case 0:
        CompanySwitcherSheet.showAddCompanyDialog(context, ref);
      case 1:
        await showAddWalletDialogStatic(
          context, ref, ref.read(activeCompanyProvider),
        );
      case 2:
        await ExpenseAccountsScreen.showAddCategorySheet(
          context, ref, categoryType: _selectedCatType,
        );
    }
  }

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
                        if (val) {
                          setDialogState(() => walletType = AccountType.asset);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    AdaptiveChip(
                      label: 'Liability (Card)',
                      isSelected: walletType == AccountType.liability,
                      onSelected: (val) {
                        if (val) {
                          setDialogState(
                            () => walletType = AccountType.liability,
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('wallet_opening_balance_input'),
                  controller: balanceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
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

  Future<void> _editWallet(AccountModel wallet, Company company) async {
    try {
      final repo = ref.read(expenseRepositoryProvider);
      final opening = await repo.getWalletOpeningBalance(wallet.id);
      if (!mounted) return;
      var name = wallet.name;
      var balance = (opening / 100).toStringAsFixed(2);
      final changes = await showAdaptiveFormSheet<(String, int)>(
        context: context,
        title: 'Edit Wallet',
        builder: (sheetContext) => Material(
          type: MaterialType.transparency,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('edit_wallet_name'),
                  initialValue: name,
                  onChanged: (value) => name = value,
                  decoration: const InputDecoration(labelText: 'Wallet Name'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('edit_opening_balance_field'),
                  initialValue: balance,
                  onChanged: (value) => balance = value,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Opening Balance',
                    prefixText: '${CurrencyFormatter.getSymbol(company.currencyCode)} ',
                  ),
                ),
                const SizedBox(height: 24),
                AdaptiveButton(
                  onPressed: () {
                    final updatedName = name.trim();
                    if (updatedName.isEmpty) return;
                    Navigator.of(sheetContext).pop((
                      updatedName,
                      CurrencyFormatter.parseToCents(balance),
                    ));
                  },
                  child: const Text('Save Changes'),
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || changes == null) return;
      final (updatedName, updatedOpening) = changes;
      if (updatedName == wallet.name && updatedOpening == opening) return;
      await repo.updateWallet(
        id: wallet.id,
        name: updatedName == wallet.name ? null : updatedName,
        openingBalanceInCents: updatedOpening == opening ? null : updatedOpening,
      );
      if (mounted) showAppFeedback(context, 'Wallet updated');
    } catch (e) {
      if (mounted) {
        showAppFeedback(context, 'Error editing wallet: $e', isError: true);
      }
    }
  }

  Future<void> _deleteWallet(AccountModel wallet) async {
    try {
      final repo = ref.read(expenseRepositoryProvider);
      if (!await repo.walletHasTransactions(wallet.id)) {
        if (!mounted) return;
        final confirmed = await showAdaptiveConfirmDialog(
          context: context,
          title: 'Delete Wallet?',
          message: 'Delete ${wallet.name}?',
          confirmLabel: 'Delete',
          isDestructive: true,
        );
        if (!confirmed || !mounted) return;
        final deleted = await repo.deleteWallet(wallet.id);
        if (!mounted) return;
        if (deleted) {
          showAppFeedback(context, 'Wallet deleted');
          return;
        }
      }
      if (!mounted) return;
      await showAdaptiveInfoDialog(
        context: context,
        title: 'Wallet in use',
        message: '${wallet.name} cannot be deleted because it is used by '
            'one or more transactions.',
      );
    } catch (e) {
      if (mounted) {
        showAppFeedback(context, 'Error deleting wallet: $e', isError: true);
      }
    }
  }

  // -------------------------------------------------------------
  // CATEGORY DIALOGS & ACTIONS
  // -------------------------------------------------------------

  static Future<AccountModel?> showAddOrEditCategoryDialogStatic(
    BuildContext context,
    WidgetRef ref,
    List<AccountModel> allCategories, {
    AccountType categoryType = AccountType.expense,
    AccountModel? initialCategory,
  }) async {
    final nameController = TextEditingController(text: initialCategory?.name);
    String? selectedParentId = initialCategory?.parentAccountId;

    final effectiveCategories = allCategories.isNotEmpty
        ? allCategories
        : (await ref.read(expenseRepositoryProvider).getCategories());

    final potentialParents = effectiveCategories
        .where(
          (c) =>
              c.type == categoryType &&
              c.parentAccountId == null &&
              c.id != initialCategory?.id,
        )
        .toList();

    Future<void> doSave(BuildContext sheetCtx) async {
      final name = nameController.text.trim();
      if (name.isEmpty) return;

      HapticFeedback.mediumImpact();
      try {
        final repo = ref.read(expenseRepositoryProvider);
        AccountModel? createdCategory;
        if (initialCategory != null) {
          await repo.updateCategory(
            id: initialCategory.id,
            name: name,
            parentAccountId: selectedParentId,
          );
        } else {
          createdCategory = await repo.createCategory(
            name: name,
            type: categoryType,
            parentAccountId: selectedParentId,
          );
        }
        if (context.mounted) {
          Navigator.of(sheetCtx).pop(createdCategory);
          showAppFeedback(
            context,
            initialCategory != null ? 'Category updated' : 'Category saved',
          );
        }
      } catch (e) {
        if (context.mounted) {
          showAppFeedback(context, 'Error saving category: $e', isError: true);
        }
      }
    }

    if (!context.mounted) return null;
    return await showAdaptiveFormSheet<AccountModel>(
      context: context,
      title: initialCategory != null
          ? 'Edit Category'
          : 'Add ${categoryType == AccountType.expense ? 'Expense' : 'Income'} Category',
      doneLabel: 'Save',
      onDone: () => doSave(context),
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final pickerItems = [
            const AdaptivePickerItem<String?>(
              value: null,
              label: 'None (Top Level)',
            ),
            ...potentialParents.map(
              (p) => AdaptivePickerItem<String?>(value: p.id, label: p.name),
            ),
          ];

          return Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(
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
                    onPressed: () => doSave(sheetContext),
                    child: Text(
                      initialCategory != null
                          ? 'Update Category'
                          : 'Save Category',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _editCategory(AccountModel cat) async {
    final categoriesAsync = ref.read(categoriesProvider);
    final allCats = categoriesAsync.asData?.value ?? [];
    await showAddOrEditCategoryDialogStatic(
      context,
      ref,
      allCats,
      categoryType: cat.type,
      initialCategory: cat,
    );
  }

  Future<void> _deleteCategory(AccountModel cat) async {
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Delete Category?',
      message:
          'Are you sure you want to delete ${cat.name}? (If it has transactions, it will be safely archived).',
      confirmLabel: 'Delete',
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
                ? '${cat.name} was deleted. Tip: Swipe left to delete faster next time.'
                : '${cat.name} was moved to Archived Categories.',
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
    final profile = ref.watch(userProfileProvider);
    final walletsAsync = ref.watch(walletsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    final body = AdaptivePageEntrance(
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: AdaptiveSegmentedControl<int>(
                groupValue: _selectedTab,
                children: const {
                  0: Text('Account'),
                  1: Text('Wallet'),
                  2: Text('Category'),
                },
                onValueChanged: _selectSection,
              ),
            ),
            Expanded(
              child: AbsorbPointer(
                absorbing: _sectionTransition != null,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: 3,
                  onPageChanged: (index) {
                    if (_sectionTransition == null && index != _selectedTab) {
                      setState(() => _selectedTab = index);
                    }
                  },
                  itemBuilder: (context, index) => KeyedSubtree(
                    key: PageStorageKey<int>(index),
                    child: switch (index) {
                      0 => _buildProfileTab(context, company, profile),
                      1 => _buildWalletsTab(context, company, walletsAsync),
                      _ => _buildCategoriesTab(context, company, categoriesAsync),
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!widget.isStandalone) return body;

    final isIos = AdaptiveThemeHelper.isIos(context);
    final colors = Theme.of(context).colorScheme;
    final addLabel = ['Add workspace', 'Add wallet', 'Add category'][_selectedTab];

    void openAutomation() {
      Navigator.of(context).push(
        createAdaptivePageRoute(builder: (_) => const RecurringScreen()),
      );
    }

    return AdaptiveScaffold(
      title: ModeStrings.of(company.mode).accountsTab,
      actions: [
        if (company.isModuleEnabled(AppModule.recurring))
          if (isIos)
            Tooltip(
              message: 'Automation',
              child: CupertinoButton(
                key: const Key('accounts_recurring_rules_button'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: openAutomation,
                child: const Icon(CupertinoIcons.repeat, size: 22),
              ),
            )
          else
            IconButton(
              key: const Key('accounts_recurring_rules_button'),
              icon: const Icon(Icons.update_rounded),
              tooltip: 'Automation',
              onPressed: openAutomation,
            ),
        if (isIos)
          Tooltip(
            message: addLabel,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: _addItem,
              child: const Icon(CupertinoIcons.add, size: 22),
            ),
          ),
      ],
      floatingActionButton: isIos
          ? null
          : SpringMorphingFab(
              key: ValueKey(addLabel),
              isExtended: true,
              icon: Icons.add,
              label: addLabel,
              backgroundColor: colors.primaryContainer,
              foregroundColor: colors.onPrimaryContainer,
              onPressed: _addItem,
            ),
      body: body,
    );
  }

  // -------------------------------------------------------------
  // TAB 0: PROFILE VIEW
  // -------------------------------------------------------------

  Widget _buildProfileTab(
    BuildContext context,
    Company company,
    UserProfile profile,
  ) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        // 1. Profile Hero Avatar Card
        AdaptiveSurfaceCard(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 16),
          accentColor: primaryColor,
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: primaryColor.withValues(alpha: 0.15),
                    child: Text(
                      profile.name.isNotEmpty
                          ? profile.name.trim()[0].toUpperCase()
                          : 'U',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name.isNotEmpty
                              ? profile.name
                              : 'My Account',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (profile.phoneNumber.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            profile.phoneNumber,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (profile.email.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            profile.email,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Active: ${company.name} (${company.currencyCode})',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit_outlined, color: primaryColor),
                    onPressed: () => _openEditProfileSheet(context, profile),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 2. Personal Information Card
        AdaptiveSurfaceCard(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdaptiveSectionHeader(
                title: 'Personal Information',
                padding: const EdgeInsets.only(bottom: 12),
              ),
              AdaptiveListRow(
                leading: Icon(
                  Icons.person_outline_rounded,
                  color: primaryColor,
                ),
                title: 'Full Name',
                subtitle: profile.name.isNotEmpty
                    ? profile.name
                    : 'Tap to set name',
                onTap: () => _openEditProfileSheet(context, profile),
              ),
              const Divider(height: 1),
              AdaptiveListRow(
                leading: Icon(Icons.phone_outlined, color: primaryColor),
                title: 'Phone Number',
                subtitle: profile.phoneNumber.isNotEmpty
                    ? profile.phoneNumber
                    : 'Not provided',
                onTap: () => _openEditProfileSheet(context, profile),
              ),
              const Divider(height: 1),
              AdaptiveListRow(
                leading: Icon(Icons.email_outlined, color: primaryColor),
                title: 'Email Address',
                subtitle: profile.email.isNotEmpty
                    ? profile.email
                    : 'Not provided',
                onTap: () => _openEditProfileSheet(context, profile),
              ),
              if (profile.address.isNotEmpty) ...[
                const Divider(height: 1),
                AdaptiveListRow(
                  leading: Icon(
                    Icons.location_on_outlined,
                    color: primaryColor,
                  ),
                  title: 'Address',
                  subtitle: profile.address,
                  onTap: () => _openEditProfileSheet(context, profile),
                ),
              ],
            ],
          ),
        ),

        // 3. Company & Currency Card
        AdaptiveSurfaceCard(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdaptiveSectionHeader(
                title: 'Company & Currency',
                padding: const EdgeInsets.only(bottom: 12),
              ),
              AdaptiveListRow(
                leading: Icon(Icons.business_rounded, color: primaryColor),
                title: 'Active Company',
                subtitle: company.name,
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => CompanySwitcherSheet.show(context),
              ),
              const Divider(height: 1),
              AdaptiveListRow(
                leading: Icon(
                  Icons.currency_exchange_rounded,
                  color: primaryColor,
                ),
                title: 'Base Currency',
                subtitle:
                    '${company.currencyCode} (${CurrencyFormatter.getSymbol(company.currencyCode)})',
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => _openCurrencyPicker(context, company),
              ),
            ],
          ),
        ),

        // 4. Cloud Sync & Account Actions Card
        AdaptiveSurfaceCard(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdaptiveSectionHeader(
                title: 'App & Data',
                padding: const EdgeInsets.only(bottom: 12),
              ),
              AdaptiveListRow(
                leading: Icon(Icons.cloud_sync_outlined, color: primaryColor),
                title: 'Cloud Sync & Backup',
                subtitle: 'Manage local database sync and cloud backup',
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => SyncSettingsSheet.show(context),
              ),
              const Divider(height: 1),
              AdaptiveListRow(
                leading: const Icon(
                  Icons.logout_rounded,
                  color: AppColors.payableRed,
                ),
                title: 'Sign Out / Switch Phone',
                subtitle: 'Log out of current account',
                onTap: () => _confirmSignOut(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openEditProfileSheet(
    BuildContext context,
    UserProfile profile,
  ) async {
    final nameCtrl = TextEditingController(text: profile.name);
    final phoneCtrl = TextEditingController(text: profile.phoneNumber);
    final emailCtrl = TextEditingController(text: profile.email);

    BuildContext? accountSheetContext;
    var saving = false;
    Future<void> saveAccount(BuildContext sheetCtx) async {
      if (saving) return;
      final name = nameCtrl.text.trim();
      if (name.isEmpty) {
        showAppFeedback(context, 'Enter your full name');
        return;
      }
      saving = true;
      final updated = ref.read(userProfileProvider).copyWith(
        name: name,
        phoneNumber: phoneCtrl.text.trim(),
        email: emailCtrl.text.trim(),
      );
      final saved = await ref.read(userProfileProvider.notifier)
          .saveProfile(updated);
      saving = false;
      if (!context.mounted || !sheetCtx.mounted) return;
      if (!saved) {
        showAppFeedback(context, 'Could not save your account details');
        return;
      }
      Navigator.of(sheetCtx).pop();
      showAppFeedback(context, 'Account updated successfully');
    }

    await showAdaptiveFormSheet<void>(
      context: context,
      title: 'Edit Account',
      doneLabel: 'Save',
      onDone: () {
        final sheetCtx = accountSheetContext;
        if (sheetCtx != null) saveAccount(sheetCtx);
      },
      builder: (sheetCtx) {
        accountSheetContext = sheetCtx;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 20),
              AdaptiveButton(
                isFullWidth: true,
                height: 48,
                onPressed: () => saveAccount(sheetCtx),
                child: const Text('Save Account'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirm = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Sign Out?',
      message: 'Are you sure you want to sign out and change account?',
      confirmLabel: 'Sign Out',
      cancelLabel: 'Cancel',
      isDestructive: true,
    );
    if (confirm && context.mounted) {
      ref.read(authControllerProvider.notifier).logout();
      Navigator.of(context).pushAndRemoveUntil(
        createAdaptivePageRoute(builder: (_) => const PhoneInputScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _openCurrencyPicker(
    BuildContext context,
    Company company,
  ) async {
    final picked = await showAdaptivePicker<String>(
      context: context,
      title: 'Select Base Currency',
      selectedValue: company.currencyCode,
      items: const [
        AdaptivePickerItem(value: 'INR', label: 'INR - Indian Rupee (₹)'),
        AdaptivePickerItem(value: 'USD', label: 'USD - US Dollar (\$)'),
        AdaptivePickerItem(value: 'EUR', label: 'EUR - Euro (€)'),
        AdaptivePickerItem(value: 'GBP', label: 'GBP - British Pound (£)'),
        AdaptivePickerItem(value: 'AED', label: 'AED - UAE Dirham (AED)'),
        AdaptivePickerItem(value: 'SGD', label: 'SGD - Singapore Dollar (S\$)'),
        AdaptivePickerItem(value: 'CAD', label: 'CAD - Canadian Dollar (\$)'),
        AdaptivePickerItem(value: 'AUD', label: 'AUD - Australian Dollar (\$)'),
        AdaptivePickerItem(value: 'JPY', label: 'JPY - Japanese Yen (¥)'),
      ],
    );
    if (picked != null && picked != company.currencyCode && context.mounted) {
      final updated = company.copyWith(
        currencyCode: picked,
        updatedAt: DateTime.now(),
      );
      await ref.read(companyControllerProvider.notifier).updateCompany(updated);
      if (!context.mounted) return;
      showAppFeedback(context, 'Base currency updated to $picked');
    }
  }

  IconData _getCategoryIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('food') ||
        lower.contains('dining') ||
        lower.contains('restaurant')) {
      return Icons.restaurant_rounded;
    } else if (lower.contains('salary') ||
        lower.contains('income') ||
        lower.contains('wage')) {
      return Icons.payments_rounded;
    } else if (lower.contains('transport') ||
        lower.contains('travel') ||
        lower.contains('fuel')) {
      return Icons.directions_car_rounded;
    } else if (lower.contains('bill') ||
        lower.contains('utility') ||
        lower.contains('electric')) {
      return Icons.receipt_long_rounded;
    } else if (lower.contains('shopping') || lower.contains('grocer')) {
      return Icons.shopping_bag_rounded;
    } else if (lower.contains('invest') || lower.contains('dividend')) {
      return Icons.trending_up_rounded;
    } else if (lower.contains('rent') || lower.contains('home')) {
      return Icons.home_rounded;
    } else if (lower.contains('health') || lower.contains('medical')) {
      return Icons.medical_services_rounded;
    }
    return Icons.category_rounded;
  }

  IconData _getWalletIcon(AccountModel wallet) {
    if (wallet.type == AccountType.liability) {
      return Icons.credit_card_rounded;
    }
    final lower = wallet.name.toLowerCase();
    if (lower.contains('bank')) {
      return Icons.account_balance_rounded;
    } else if (lower.contains('cash')) {
      return Icons.payments_rounded;
    }
    return Icons.account_balance_wallet_rounded;
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
    final primaryColor = theme.colorScheme.primary;
    final defaultWalletId = ref.watch(defaultWalletIdProvider).value;

    return walletsAsync.when(
      data: (wallets) {
        if (wallets.isEmpty) {
          return const EmptyStateView(
            title: 'No Wallets Configured',
            subtitle:
                'Add a wallet to record cash, bank, or credit card transactions.',
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

            AdaptiveSectionHeader(
              title: 'Your Wallets',
              padding: const EdgeInsets.only(bottom: 12),
            ),

            ...wallets.map((wallet) {
              final isLiability = wallet.type == AccountType.liability;
              final isDefault = wallet.id == defaultWalletId;
              final walletType = isLiability
                  ? 'Credit Card / Liability'
                  : 'Asset Wallet';
              final icon = _getWalletIcon(wallet);
              final iconColor = isLiability
                  ? AppColors.payableRed
                  : primaryColor;
              final iconBg = iconColor.withValues(alpha: 0.12);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AdaptiveSurfaceCard(
                  key: Key('wallet_card_${wallet.id}'),
                  onTap: () => Navigator.of(context).push(
                    createAdaptivePageRoute<void>(
                      builder: (_) => WalletReportScreen(wallet: wallet),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: iconBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: iconColor, size: 22),
                      ),
                      const SizedBox(width: 14),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              wallet.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isDefault ? '$walletType · Default' : walletType,
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
                            overrideColor: isLiability
                                ? AppColors.payableRed
                                : null,
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

                        ],
                      ),
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        key: Key('wallet_menu_${wallet.id}'),
                        icon: Icon(
                          Icons.more_vert_rounded,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onSelected: (val) async {
                          if (val == 'edit') {
                            _editWallet(wallet, company);
                          } else if (val == 'delete') {
                            _deleteWallet(wallet);
                          } else if (val == 'default') {
                            if (ref.read(activeCompanyProvider).id != company.id) {
                              return;
                            }
                            try {
                              await ref.read(expenseRepositoryProvider)
                                  .setDefaultWalletId(isDefault ? null : wallet.id);
                            } catch (_) {
                              if (context.mounted) {
                                showAppFeedback(
                                  context,
                                  'Could not change the default wallet.',
                                  isError: true,
                                );
                              }
                            }
                          }
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'default',
                            child: Text(isDefault
                                ? 'Clear default wallet'
                                : 'Set as default wallet'),
                          ),
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete')),
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
    final primaryColor = theme.colorScheme.primary;

    return categoriesAsync.when(
      data: (allCategories) {
        final filtered = allCategories
            .where((c) => c.type == _selectedCatType)
            .toList();

        // Top level categories
        final topLevel = filtered
            .where((c) => c.parentAccountId == null)
            .toList();

        // Child categories grouped by parent
        final Map<String, List<AccountModel>> subCats = {};
        for (final c in filtered) {
          if (c.parentAccountId != null) {
            subCats.putIfAbsent(c.parentAccountId!, () => []).add(c);
          }
        }
        final canArrange = topLevel.length > 1 ||
            subCats.values.any((children) => children.length > 1);

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

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AdaptiveButton(
                    type: AdaptiveButtonType.text,
                    height: 44,
                    onPressed: !canArrange ? null : () {
                      Navigator.of(context).push(
                        createAdaptivePageRoute<void>(
                          builder: (_) => ArrangeCategoriesScreen(
                            workspaceId: company.id,
                            type: _selectedCatType,
                            categories: filtered,
                          ),
                        ),
                      );
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        Icon(Icons.swap_vert_rounded, size: 18),
                        Text('Arrange'),
                      ],
                    ),
                  ),
                  AdaptiveButton(
                    type: AdaptiveButtonType.text,
                    height: 44,
                    onPressed: () => Navigator.of(context).push(
                      createAdaptivePageRoute(
                        builder: (_) => const ArchivedCategoriesScreen(),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        Icon(Icons.archive_outlined, size: 18),
                        Text('View archive'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: filtered.isEmpty
                  ? const EmptyStateView(
                      title: 'No Categories',
                      subtitle:
                          'Create a category to organize your transactions.',
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
                                    await _deleteCategory(parent);
                                    return false;
                                  },
                                  background: const SizedBox.shrink(),
                                  secondaryBackground:
                                      AdaptiveSwipeBackgrounds.delete(
                                        context,
                                        label: 'Delete',
                                        icon: Icons.delete_outline,
                                      ),
                                  child: AdaptiveListRow(
                                    leading: Icon(
                                      _getCategoryIcon(parent.name),
                                      color: primaryColor,
                                    ),
                                    title: parent.name,
                                    subtitle: children.isNotEmpty
                                        ? '${children.length} subcategories'
                                        : (parent.description ?? ''),
                                    showDivider: children.isNotEmpty,
                                    onTap: () => _editCategory(parent),
                                    trailing: PopupMenuButton<String>(
                                      icon: const Icon(
                                        Icons.more_vert,
                                        size: 18,
                                      ),
                                      onSelected: (val) {
                                        if (val == 'edit') {
                                          _editCategory(parent);
                                        } else if (val == 'delete') {
                                          _deleteCategory(parent);
                                        }
                                      },
                                      itemBuilder: (ctx) => [
                                        PopupMenuItem(
                                          key: Key('edit_cat_${parent.id}'),
                                          value: 'edit',
                                          child: const Row(
                                            children: [
                                              Icon(
                                                Icons.edit_outlined,
                                                size: 18,
                                              ),
                                              SizedBox(width: 8),
                                              Text('Edit'),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          key: Key('delete_cat_${parent.id}'),
                                          value: 'delete',
                                          child: const Row(
                                            children: [
                                              Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                              ),
                                              SizedBox(width: 8),
                                              Text('Delete'),
                                            ],
                                          ),
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
                                        await _deleteCategory(sub);
                                        return false;
                                      },
                                      background: const SizedBox.shrink(),
                                      secondaryBackground:
                                          AdaptiveSwipeBackgrounds.delete(
                                            context,
                                            label: 'Delete',
                                            icon: Icons.delete_outline,
                                          ),
                                      child: AdaptiveListRow(
                                        padding: const EdgeInsets.only(
                                          left: 48,
                                          right: 16,
                                          top: 4,
                                          bottom: 4,
                                        ),
                                        leading: Icon(
                                          _getCategoryIcon(sub.name),
                                          size: 18,
                                          color: primaryColor.withValues(
                                            alpha: 0.8,
                                          ),
                                        ),
                                        title: sub.name,
                                        showDivider: false,
                                        onTap: () => _editCategory(sub),
                                        trailing: PopupMenuButton<String>(
                                          icon: const Icon(
                                            Icons.more_vert,
                                            size: 18,
                                          ),
                                          onSelected: (val) {
                                            if (val == 'edit') {
                                              _editCategory(sub);
                                            } else if (val == 'delete') {
                                              _deleteCategory(sub);
                                            }
                                          },
                                          itemBuilder: (ctx) => [
                                            PopupMenuItem(
                                              key: Key('edit_cat_${sub.id}'),
                                              value: 'edit',
                                              child: const Row(
                                                children: [
                                                  Icon(
                                                    Icons.edit_outlined,
                                                    size: 18,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text('Edit'),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              key: Key('delete_cat_${sub.id}'),
                                              value: 'delete',
                                              child: const Row(
                                                children: [
                                                  Icon(
                                                    Icons.delete_outline,
                                                    size: 18,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text('Delete'),
                                                ],
                                              ),
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
