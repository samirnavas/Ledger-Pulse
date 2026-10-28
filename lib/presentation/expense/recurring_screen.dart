import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../core/widgets/skeleton_list_tile.dart';
import '../../data/models/account_model.dart';
import '../../data/models/company_model.dart';
import '../../data/models/recurring_rule_model.dart';
import '../../data/models/voucher_model.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import '../providers/recurring_providers.dart';

/// Screen listing recurring transaction rules, allowing users to
/// create, edit, pause/resume, delete, and manually trigger due rules.
class RecurringScreen extends ConsumerStatefulWidget {
  const RecurringScreen({super.key});

  @override
  ConsumerState<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends ConsumerState<RecurringScreen> {
  // Show Add/Edit Recurring Rule Bottom Sheet
  Future<void> _showAddEditRuleSheet(
    BuildContext context, {
    RecurringRuleModel? existingRule,
  }) async {
    final company = ref.read(activeCompanyProvider);
    final walletsAsync = ref.read(walletsProvider);
    final categoriesAsync = ref.read(categoriesProvider);

    final wallets = walletsAsync.asData?.value ?? [];
    final allCategories = categoriesAsync.asData?.value ?? [];

    VoucherType selectedType = existingRule?.template.type ?? VoucherType.expense;
    final amountController = TextEditingController(
      text: existingRule != null
          ? (existingRule.template.amountInCents / 100).toStringAsFixed(2)
          : '',
    );
    final notesController =
        TextEditingController(text: existingRule?.template.notes ?? '');

    String? selectedWalletId = existingRule?.template.walletAccountId ??
        (wallets.isNotEmpty ? wallets.first.id : null);
    String? selectedToWalletId = existingRule?.template.toWalletAccountId;

    RecurringIntervalType selectedInterval =
        existingRule?.interval ?? RecurringIntervalType.monthly;
    DateTime nextRunDate = existingRule?.nextRunDate ?? DateTime.now();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            final filteredCategories = allCategories
                .where((c) =>
                    selectedType == VoucherType.expense
                        ? c.type == AccountType.expense
                        : c.type == AccountType.income)
                .toList();

            String? selectedCategoryId = existingRule?.template.categoryAccountId ??
                (filteredCategories.isNotEmpty
                    ? filteredCategories.first.id
                    : null);

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          existingRule == null
                              ? 'Add Recurring Rule'
                              : 'Edit Recurring Rule',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Type Selector
                    SegmentedButton<VoucherType>(
                      segments: const [
                        ButtonSegment(
                          value: VoucherType.expense,
                          label: Text('Expense'),
                          icon: Icon(Icons.arrow_upward, size: 16),
                        ),
                        ButtonSegment(
                          value: VoucherType.income,
                          label: Text('Income'),
                          icon: Icon(Icons.arrow_downward, size: 16),
                        ),
                        ButtonSegment(
                          value: VoucherType.transfer,
                          label: Text('Transfer'),
                          icon: Icon(Icons.swap_horiz, size: 16),
                        ),
                      ],
                      selected: {selectedType},
                      onSelectionChanged: (val) {
                        setSheetState(() => selectedType = val.first);
                      },
                    ),
                    const SizedBox(height: 14),

                    // Amount
                    const Text(
                      'Amount',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const Key('recurring_amount_field'),
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        prefixText: '${company.currencyCode} ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        hintText: '0.00',
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Source Wallet
                    Text(
                      selectedType == VoucherType.transfer
                          ? 'From Wallet'
                          : 'Wallet',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      key: const Key('recurring_wallet_field'),
                      initialValue: selectedWalletId,
                      items: wallets.map((w) {
                        return DropdownMenuItem<String>(
                          value: w.id,
                          child: Text(w.name),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => selectedWalletId = val);
                        }
                      },
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Destination wallet (if Transfer) or Category (if Expense/Income)
                    if (selectedType == VoucherType.transfer) ...[
                      const Text(
                        'To Wallet',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        key: const Key('recurring_to_wallet_field'),
                        initialValue: selectedToWalletId,
                        items: wallets.map((w) {
                          return DropdownMenuItem<String>(
                            value: w.id,
                            child: Text(w.name),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setSheetState(() => selectedToWalletId = val);
                          }
                        },
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                    ] else ...[
                      const Text(
                        'Category',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        key: const Key('recurring_category_field'),
                        initialValue: selectedCategoryId,
                        items: filteredCategories.map((c) {
                          return DropdownMenuItem<String>(
                            value: c.id,
                            child: Text(c.name),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setSheetState(() => selectedCategoryId = val);
                          }
                        },
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Interval Selector
                    const Text(
                      'Repeat Frequency',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<RecurringIntervalType>(
                      key: const Key('recurring_interval_field'),
                      initialValue: selectedInterval,
                      items: RecurringIntervalType.values.map((interval) {
                        return DropdownMenuItem<RecurringIntervalType>(
                          value: interval,
                          child: Text(interval.displayName),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => selectedInterval = val);
                        }
                      },
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Next Run Date Picker
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Next Run Date',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text(DateFormat.yMMMd().format(nextRunDate)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: nextRunDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setSheetState(() => nextRunDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 10),

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
                    const SizedBox(height: 20),

                    // Save Button
                    FilledButton(
                      key: const Key('save_recurring_rule_button'),
                      onPressed: () async {
                        final amount =
                            double.tryParse(amountController.text.trim()) ?? 0;
                        if (amount <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a valid amount'),
                            ),
                          );
                          return;
                        }
                        if (selectedWalletId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please select a wallet'),
                            ),
                          );
                          return;
                        }

                        final amountInCents = (amount * 100).round();
                        final recurringService =
                            ref.read(recurringServiceProvider);

                        final template = RecurringTemplate(
                          type: selectedType,
                          amountInCents: amountInCents,
                          walletAccountId: selectedWalletId!,
                          categoryAccountId: selectedType == VoucherType.transfer
                              ? null
                              : selectedCategoryId,
                          toWalletAccountId: selectedType == VoucherType.transfer
                              ? selectedToWalletId
                              : null,
                          notes: notesController.text.trim().isEmpty
                              ? null
                              : notesController.text.trim(),
                        );

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

                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        existingRule == null
                            ? 'Create Recurring Rule'
                            : 'Update Rule',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Delete Rule Confirmation
  Future<void> _deleteRule(RecurringRuleModel rule) async {
    final confirmed = await AdaptiveConfirmDialog.show(
      context: context,
      title: 'Delete Recurring Rule',
      message: 'Are you sure you want to delete this recurring rule?',
      confirmText: 'Delete',
      isDestructive: true,
    );

    if (confirmed == true) {
      await ref.read(recurringServiceProvider).deleteRule(rule.id);
    }
  }

  // Trigger Run Due manually
  Future<void> _runDueRules() async {
    final count =
        await ref.read(recurringServiceProvider).generateDue(DateTime.now());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count == 0
              ? 'No recurring transactions were due'
              : 'Generated $count recurring transaction(s) successfully!'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final company = ref.watch(activeCompanyProvider);

    // Guard with module check
    if (!company.isModuleEnabled(AppModule.recurring)) {
      return const AdaptiveScaffold(
        key: Key('recurring_module_disabled'),
        title: 'Recurring Transactions',
        body: EmptyStateView(
          icon: Icons.update,
          title: 'Recurring Module Disabled',
          message:
              'The recurring transactions module is currently disabled for this company. Enable it in company settings to automate repeating transactions.',
        ),
      );
    }

    final rulesListAsync = ref.watch(recurringRulesListProvider);

    return AdaptiveScaffold(
      title: 'Recurring Rules',
      actions: [
        IconButton(
          key: const Key('run_due_recurring_button'),
          icon: const Icon(Icons.play_circle_outline),
          tooltip: 'Run Due Transactions',
          onPressed: _runDueRules,
        ),
        IconButton(
          key: const Key('add_recurring_rule_button'),
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'Add Rule',
          onPressed: () => _showAddEditRuleSheet(context),
        ),
      ],
      body: rulesListAsync.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            SkeletonListTile(),
            SkeletonListTile(),
            SkeletonListTile(),
          ],
        ),
        error: (err, _) => Center(child: Text('Error loading rules: $err')),
        data: (rules) {
          if (rules.isEmpty) {
            return EmptyStateView(
              icon: Icons.update,
              title: 'No Recurring Rules',
              message:
                  'Automate your repeating bills, subscriptions, or salaries with recurring transactions.',
              actionLabel: 'Create First Rule',
              onAction: () => _showAddEditRuleSheet(context),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
            itemCount: rules.length,
            itemBuilder: (context, index) {
              final rule = rules[index];
              return _buildRuleCard(theme, company, rule);
            },
          );
        },
      ),
    );
  }

  Widget _buildRuleCard(
    ThemeData theme,
    Company company,
    RecurringRuleModel rule,
  ) {
    final template = rule.template;
    final isExpense = template.type == VoucherType.expense;
    final isIncome = template.type == VoucherType.income;
    final typeColor = isExpense
        ? Colors.red
        : isIncome
            ? Colors.green
            : Colors.blue;

    final typeIcon = isExpense
        ? Icons.arrow_upward
        : isIncome
            ? Icons.arrow_downward
            : Icons.swap_horiz;

    return LiquidGlassCard(
      key: Key('recurring_rule_card_${rule.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: typeColor.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: Icon(typeIcon, color: typeColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.type.displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (template.notes != null && template.notes!.isNotEmpty)
                      Text(
                        template.notes!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              AmountText(
                amount: template.amountInCents / 100,
                currencyCode: company.currencyCode,
                color: typeColor,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      rule.interval.displayName,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Next: ${DateFormat.yMMMd().format(rule.nextRunDate)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Switch(
                    key: Key('toggle_rule_${rule.id}'),
                    value: rule.isActive,
                    onChanged: (val) async {
                      await ref
                          .read(recurringServiceProvider)
                          .toggleRuleActive(rule.id, val);
                    },
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
                            Icon(Icons.delete_outline,
                                size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
