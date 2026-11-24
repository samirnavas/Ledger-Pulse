import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_controls.dart';
import '../../core/widgets/adaptive_date_field.dart';
import '../../core/widgets/adaptive_form_sheet.dart';
import '../../core/widgets/adaptive_page_entrance.dart';
import '../../core/widgets/adaptive_picker.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_surface_card.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/skeleton_list_tile.dart';
import '../../core/widgets/spring_morphing_fab.dart';
import '../../data/models/account_model.dart';
import '../../data/models/company_model.dart';
import '../../data/models/recurring_rule_model.dart';
import '../../data/models/voucher_model.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import '../providers/recurring_providers.dart';
import 'widgets/transaction_type_switcher.dart';
import 'widgets/category_icons.dart';

/// Screen listing recurring transaction rules, allowing users to
/// create, edit, pause/resume, delete, and manually trigger due rules.
class RecurringScreen extends ConsumerStatefulWidget {
  const RecurringScreen({super.key});

  /// Pushes the screen using [createAdaptivePageRoute].
  static Future<void> push(BuildContext context) {
    return Navigator.of(
      context,
    ).push(createAdaptivePageRoute(builder: (_) => const RecurringScreen()));
  }

  @override
  ConsumerState<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends ConsumerState<RecurringScreen> {
  // Show Add/Edit Automation Bottom Sheet
  Future<void> _showAddEditRuleSheet(
    BuildContext context, {
    RecurringRuleModel? existingRule,
  }) async {
    final company = ref.read(activeCompanyProvider);
    final wallets = await ref.read(expenseRepositoryProvider).getWallets();
    final allCategories = await ref
        .read(expenseRepositoryProvider)
        .getCategories();

    VoucherType selectedType =
        existingRule?.template.type ?? VoucherType.expense;
    final amountController = TextEditingController(
      text: existingRule != null
          ? (existingRule.template.amountInCents / 100).toStringAsFixed(2)
          : '',
    );
    final notesController = TextEditingController(
      text: existingRule?.template.notes ?? '',
    );

    String? selectedWalletId =
        existingRule?.template.walletAccountId ??
        (wallets.isNotEmpty ? wallets.first.id : null);
    String? selectedToWalletId = existingRule?.template.toWalletAccountId;
    String? selectedCategoryId = existingRule?.template.categoryAccountId;

    RecurringIntervalType selectedInterval =
        existingRule?.interval ?? RecurringIntervalType.monthly;
    final now = DateTime.now();
    DateTime nextRunDate =
        existingRule?.nextRunDate ??
        DateTime(now.year, now.month, now.day, now.hour, now.minute);

    List<AccountModel> categoriesForType() => allCategories
        .where(
          (category) =>
              category.type ==
              (selectedType == VoucherType.expense
                  ? AccountType.expense
                  : AccountType.income),
        )
        .toList();

    String? currentCategoryId(List<AccountModel> categories) =>
        categories.any((category) => category.id == selectedCategoryId)
        ? selectedCategoryId
        : categories.firstOrNull?.id;

    bool saving = false;
    Future<void> doSave(BuildContext sheetCtx) async {
      if (saving) return;
      final catId = currentCategoryId(categoriesForType());
      final amount = double.tryParse(amountController.text.trim()) ?? 0;
      if (!amount.isFinite || (amount * 100).round() <= 0) {
        showAppFeedback(context, 'Please enter a valid amount', isError: true);
        return;
      }
      if (selectedWalletId == null) {
        showAppFeedback(context, 'Please select a wallet', isError: true);
        return;
      }
      if (selectedType == VoucherType.transfer && selectedToWalletId == null) {
        showAppFeedback(
          context,
          'Please select destination wallet',
          isError: true,
        );
        return;
      }

      if (selectedType != VoucherType.transfer && catId == null) {
        showAppFeedback(context, 'Please select a category', isError: true);
        return;
      }
      if (selectedType == VoucherType.transfer &&
          selectedToWalletId == selectedWalletId) {
        showAppFeedback(
          context,
          'Please select a different destination wallet',
          isError: true,
        );
        return;
      }
      final amountInCents = (amount * 100).round();
      final recurringService = ref.read(recurringServiceProvider);

      final template = RecurringTemplate(
        type: selectedType,
        amountInCents: amountInCents,
        walletAccountId: selectedWalletId!,
        categoryAccountId: selectedType == VoucherType.transfer ? null : catId,
        toWalletAccountId: selectedType == VoucherType.transfer
            ? selectedToWalletId
            : null,
        notes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
        referenceNumber: existingRule?.template.referenceNumber,
        receiptPhotoUrl: existingRule?.template.receiptPhotoUrl,
      );

      saving = true;
      HapticFeedback.mediumImpact();
      try {
        if (existingRule == null) {
          await recurringService.createRule(
            template: template,
            interval: selectedInterval,
            nextRunDate: nextRunDate,
          );
        } else {
          await recurringService.updateRule(
            rule: existingRule.copyWith(
              template: template,
              interval: selectedInterval,
              nextRunDate: nextRunDate,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          showAppFeedback(
            context,
            'Could not save automation: $e',
            isError: true,
          );
        }
        return;
      } finally {
        saving = false;
      }
      if (context.mounted &&
          sheetCtx.mounted &&
          ModalRoute.of(sheetCtx)?.isCurrent == true) {
        Navigator.of(sheetCtx).pop();
        showAppFeedback(
          context,
          existingRule == null ? 'Automation created' : 'Automation updated',
        );
      }
    }

    if (!context.mounted) return;
    Future<void> Function()? saveFromHeader;
    await showAdaptiveFormSheet<void>(
      context: context,
      title: existingRule == null ? 'Add Automation' : 'Edit Automation',
      doneLabel: 'Save',
      onDone: () => saveFromHeader?.call(),
      builder: (sheetContext) {
        saveFromHeader = () => doSave(sheetContext);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filteredCategories = categoriesForType();
            final categoryId = currentCategoryId(filteredCategories);

            final walletPickerItems = wallets
                .map(
                  (w) => AdaptivePickerItem<String>(value: w.id, label: w.name),
                )
                .toList();

            final categoryPickerItems = filteredCategories
                .map(
                  (c) => AdaptivePickerItem<String>(
                    value: c.id,
                    label: c.name,
                    icon: Icon(categoryIcon(c)),
                  ),
                )
                .toList();

            final intervalPickerItems = RecurringIntervalType.values
                .map(
                  (interval) => AdaptivePickerItem<RecurringIntervalType>(
                    value: interval,
                    label: interval.displayName,
                  ),
                )
                .toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Type Switcher
                  TransactionTypeSwitcher(
                    selectedType: selectedType,
                    onTypeChanged: (type) {
                      setSheetState(() => selectedType = type);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Amount Field
                  Text(
                    'Amount',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('recurring_amount_field'),
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      prefixText: '${company.currencyCode} ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      hintText: '0.00',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Source Wallet Dropdown
                  AdaptiveDropdownField<String>(
                    key: const Key('recurring_wallet_field'),
                    label: selectedType == VoucherType.transfer
                        ? 'From Wallet'
                        : 'Wallet',
                    value: selectedWalletId,
                    items: walletPickerItems,
                    hint: 'Select Wallet',
                    onChanged: (val) {
                      if (val != null) {
                        setSheetState(() => selectedWalletId = val);
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  // Destination Wallet (Transfer) or Category (Expense/Income)
                  if (selectedType == VoucherType.transfer) ...[
                    AdaptiveDropdownField<String>(
                      key: const Key('recurring_to_wallet_field'),
                      label: 'To Wallet',
                      value: selectedToWalletId,
                      items: walletPickerItems,
                      hint: 'Select To Wallet',
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => selectedToWalletId = val);
                        }
                      },
                    ),
                  ] else ...[
                    AdaptiveDropdownField<String>(
                      key: const Key('recurring_category_field'),
                      label: 'Category',
                      value: categoryId,
                      items: categoryPickerItems,
                      hint: 'Select Category',
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => selectedCategoryId = val);
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 14),

                  // Interval Selector
                  AdaptiveDropdownField<RecurringIntervalType>(
                    key: const Key('recurring_interval_field'),
                    label: 'Repeat Frequency',
                    value: selectedInterval,
                    items: intervalPickerItems,
                    onChanged: (val) {
                      if (val != null) {
                        setSheetState(() => selectedInterval = val);
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  // Start / Next Run Date
                  AdaptiveDateField(
                    label: 'Next Run Date & Time',
                    enableTime: true,
                    selectedDate: nextRunDate,
                    onDateSelected: (date) {
                      setSheetState(() => nextRunDate = date);
                    },
                  ),
                  const SizedBox(height: 14),

                  // Notes
                  TextField(
                    controller: notesController,
                    decoration: InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Save Button
                  AdaptiveButton(
                    key: const Key('save_recurring_rule_button'),
                    child: Text(
                      existingRule == null
                          ? 'Create Automation'
                          : 'Save Changes',
                    ),
                    onPressed: () => doSave(sheetContext),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Delete Rule Confirmation
  Future<void> _deleteRule(RecurringRuleModel rule) async {
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Delete Automation',
      message: 'Delete this automation?',
      confirmLabel: 'Delete',
      isDestructive: true,
    );

    if (confirmed) {
      HapticFeedback.mediumImpact();
      await ref.read(recurringServiceProvider).deleteRule(rule.id);
      if (mounted) {
        showAppFeedback(context, 'Automation deleted');
      }
    }
  }

  // Trigger Run Due manually
  Future<void> _runDueRules() async {
    try {
      final count = await ref
          .read(recurringServiceProvider)
          .generateDue(DateTime.now());
      if (mounted) {
        HapticFeedback.lightImpact();
        showAppFeedback(
          context,
          count == 0
              ? 'No transactions were due'
              : 'Transactions added: $count',
        );
      }
    } catch (e) {
      if (mounted) {
        showAppFeedback(context, 'Could not run automation: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final company = ref.watch(activeCompanyProvider);

    // Guard with module check
    if (!company.isModuleEnabled(AppModule.recurring)) {
      return const AdaptiveScaffold(
        key: Key('recurring_module_disabled'),
        title: 'Automation',
        body: EmptyStateView(
          icon: Icons.update,
          title: 'Automation is off',
          message:
              'Enable Automation in workspace settings to record repeating transactions.',
        ),
      );
    }

    final rulesListAsync = ref.watch(recurringRulesListProvider);
    final walletsAsync = ref.watch(walletsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    final wallets = walletsAsync.asData?.value ?? [];
    final categories = categoriesAsync.asData?.value ?? [];

    return AdaptiveScaffold(
      title: 'Automation',
      actions: [
        IconButton(
          key: const Key('run_due_recurring_button'),
          icon: Icon(
            isIos ? CupertinoIcons.play_circle : Icons.play_circle_outline,
          ),
          tooltip: 'Run Due Transactions',
          onPressed: _runDueRules,
        ),
        if (isIos)
          IconButton(
            key: const Key('add_recurring_rule_button'),
            icon: const Icon(CupertinoIcons.add),
            tooltip: 'Add Automation',
            onPressed: () => _showAddEditRuleSheet(context),
          ),
      ],
      floatingActionButton: isIos
          ? null
          : SpringMorphingFab(
              key: const Key('add_recurring_rule_button'),
              label: 'Add Automation',
              icon: Icons.add_rounded,
              onPressed: () => _showAddEditRuleSheet(context),
            ),
      body: AdaptivePageEntrance(
        child: rulesListAsync.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              SkeletonListTile(),
              SkeletonListTile(),
              SkeletonListTile(),
            ],
          ),
          error: (err, _) =>
              Center(child: Text('Could not load automations: $err')),
          data: (rules) {
            if (rules.isEmpty) {
              return EmptyStateView(
                icon: Icons.update,
                title: 'No automations yet',
                message:
                    'Automatically record repeating bills, subscriptions, or income.',
                actionLabel: 'Create Automation',
                onAction: () => _showAddEditRuleSheet(context),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
              itemCount: rules.length,
              itemBuilder: (context, index) {
                final rule = rules[index];
                return _buildRuleCard(
                  context,
                  company,
                  rule,
                  wallets,
                  categories,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildRuleCard(
    BuildContext context,
    Company company,
    RecurringRuleModel rule,
    List<AccountModel> wallets,
    List<AccountModel> categories,
  ) {
    final template = rule.template;
    final isExpense = template.type == VoucherType.expense;
    final isIncome = template.type == VoucherType.income;

    final typeColor = isExpense
        ? AppColors.expense(context)
        : isIncome
        ? AppColors.income(context)
        : AppColors.transfer(context);

    final typeIcon = isExpense
        ? Icons.arrow_upward
        : isIncome
        ? Icons.arrow_downward
        : Icons.swap_horiz;

    final isTransfer = template.type == VoucherType.transfer;
    final wallet = wallets
        .where((account) => account.id == template.walletAccountId)
        .firstOrNull;
    final destination = wallets
        .where((account) => account.id == template.toWalletAccountId)
        .firstOrNull;
    final category = categories
        .where((account) => account.id == template.categoryAccountId)
        .firstOrNull;
    final notes = template.notes?.trim() ?? '';
    final nextRun = rule.nextRunDate.toLocal();
    final timeFormat = MediaQuery.alwaysUse24HourFormatOf(context)
        ? DateFormat.Hm()
        : DateFormat.jm();
    final frequency = rule.intervalCount == 1
        ? rule.interval.displayName
        : 'Every ${rule.intervalCount} ${switch (rule.interval) {
            RecurringIntervalType.daily => 'days',
            RecurringIntervalType.weekly => 'weeks',
            RecurringIntervalType.monthly => 'months',
            RecurringIntervalType.yearly => 'years',
          }}';
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AdaptiveSurfaceCard(
        key: Key('recurring_rule_card_${rule.id}'),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(typeIcon, color: typeColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.type.displayName,
                        style: textTheme.labelLarge,
                      ),
                      if (notes.isNotEmpty)
                        Text(notes, style: textTheme.titleMedium),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (val) {
                    if (val == 'edit') {
                      _showAddEditRuleSheet(context, existingRule: rule);
                    } else if (val == 'delete') {
                      _deleteRule(rule);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      key: Key('edit_rule_${rule.id}'),
                      value: 'edit',
                      child: const Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      key: Key('delete_rule_${rule.id}'),
                      value: 'delete',
                      child: const Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: Colors.red,
                          ),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            AmountText(
              amountInCents: template.amountInCents,
              currencyCode: company.currencyCode,
              overrideColor: typeColor,
              variant: AmountVariant.medium,
            ),
            const SizedBox(height: 12),
            Text(
              'Next: ${DateFormat.yMMMd().format(nextRun)} at '
              '${timeFormat.format(nextRun)}',
              style: textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text('Repeats: $frequency'),
            Text(
              'Ends: ${rule.endDate == null ? 'No end date' : DateFormat.yMMMd().add_jm().format(rule.endDate!.toLocal())}',
            ),
            const SizedBox(height: 8),
            Text(
              '${isTransfer ? 'From wallet' : 'Wallet'}: ${wallet?.name ?? 'Unavailable'}',
            ),
            if (isTransfer)
              Text('To wallet: ${destination?.name ?? 'Unavailable'}')
            else
              Text('Category: ${category?.name ?? 'Unavailable'}'),
            if (template.referenceNumber case final reference?
                when reference.isNotEmpty)
              Text('Reference: $reference'),
            if (template.receiptPhotoUrl?.isNotEmpty ?? false)
              const Text('Receipt attached'),
            const Divider(),
            Row(
              children: [
                Expanded(child: Text(rule.isActive ? 'Active' : 'Paused')),
                Semantics(
                  label: 'Automation active',
                  child: AdaptiveSwitch(
                    key: Key('toggle_rule_${rule.id}'),
                    value: rule.isActive,
                    onChanged: (value) async {
                      HapticFeedback.lightImpact();
                      await ref
                          .read(recurringServiceProvider)
                          .toggleRuleActive(rule.id, value);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
