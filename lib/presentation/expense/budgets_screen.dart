import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../core/widgets/skeleton_list_tile.dart';
import '../../data/models/account_model.dart';
import '../../data/models/budget_model.dart';
import '../../data/models/company_model.dart';
import '../providers/budget_providers.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';

/// Screen displaying category budgets, progress bars, rollover indicators,
/// overall monthly budget summary, and warning/exceeded threshold banners.
class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  // Show Add/Edit Budget Sheet
  Future<void> _showAddEditBudgetSheet(
    BuildContext context, {
    BudgetModel? existingBudget,
  }) async {
    final company = ref.read(activeCompanyProvider);
    final categoriesAsync = ref.read(categoriesProvider);
    final expenseCategories = categoriesAsync.asData?.value
            .where((c) => c.type == AccountType.expense)
            .toList() ??
        [];

    final amountController = TextEditingController(
      text: existingBudget != null
          ? (existingBudget.allocatedInCents / 100).toStringAsFixed(2)
          : '',
    );
    String? selectedCategoryId = existingBudget?.categoryId ??
        (expenseCategories.isNotEmpty ? expenseCategories.first.id : null);
    BudgetPeriodType selectedPeriod =
        existingBudget?.period ?? BudgetPeriodType.monthly;
    bool rolloverEnabled = existingBudget?.rolloverEnabled ?? false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
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
                          existingBudget == null ? 'Set Budget' : 'Edit Budget',
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
                    const SizedBox(height: 16),

                    // Category dropdown
                    const Text(
                      'Expense Category',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      key: const Key('budget_category_field'),
                      initialValue: selectedCategoryId,
                      items: expenseCategories.map((cat) {
                        return DropdownMenuItem<String>(
                          value: cat.id,
                          child: Text(cat.name),
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
                    const SizedBox(height: 16),

                    // Amount Field
                    const Text(
                      'Allocated Amount',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const Key('budget_amount_field'),
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
                    const SizedBox(height: 16),

                    // Period Selector
                    const Text(
                      'Budget Period',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<BudgetPeriodType>(
                      key: const Key('budget_period_selector'),
                      segments: const [
                        ButtonSegment(
                          value: BudgetPeriodType.weekly,
                          label: Text('Weekly'),
                        ),
                        ButtonSegment(
                          value: BudgetPeriodType.monthly,
                          label: Text('Monthly'),
                        ),
                        ButtonSegment(
                          value: BudgetPeriodType.yearly,
                          label: Text('Yearly'),
                        ),
                      ],
                      selected: {selectedPeriod},
                      onSelectionChanged: (val) {
                        setSheetState(() => selectedPeriod = val.first);
                      },
                    ),
                    const SizedBox(height: 16),

                    // Rollover Switch
                    SwitchListTile(
                      key: const Key('budget_rollover_switch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable Rollover'),
                      subtitle: const Text(
                        'Carry over unspent budget to the next period',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: rolloverEnabled,
                      onChanged: (val) {
                        setSheetState(() => rolloverEnabled = val);
                      },
                    ),
                    const SizedBox(height: 20),

                    // Save Button
                    FilledButton(
                      key: const Key('save_budget_button'),
                      onPressed: () async {
                        final parsedAmount =
                            double.tryParse(amountController.text.trim()) ?? 0;
                        if (parsedAmount <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a valid amount'),
                            ),
                          );
                          return;
                        }
                        if (selectedCategoryId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please select a category'),
                            ),
                          );
                          return;
                        }

                        final amountInCents = (parsedAmount * 100).round();
                        final budgetRepo =
                            ref.read(budgetRepositoryProvider);

                        if (existingBudget == null) {
                          await budgetRepo.createBudget(
                            categoryId: selectedCategoryId!,
                            allocatedInCents: amountInCents,
                            period: selectedPeriod,
                            rolloverEnabled: rolloverEnabled,
                          );
                        } else {
                          await budgetRepo.updateBudget(
                            budget: existingBudget.copyWith(
                              categoryId: selectedCategoryId!,
                              allocatedInCents: amountInCents,
                              period: selectedPeriod,
                              rolloverEnabled: rolloverEnabled,
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
                        existingBudget == null
                            ? 'Set Budget'
                            : 'Update Budget',
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

  // Delete budget confirmation
  Future<void> _deleteBudget(BudgetModel budget) async {
    final confirmed = await AdaptiveConfirmDialog.show(
      context: context,
      title: 'Delete Budget',
      message: 'Are you sure you want to remove this budget?',
      confirmText: 'Delete',
      isDestructive: true,
    );

    if (confirmed == true) {
      await ref.read(budgetRepositoryProvider).deleteBudget(budget.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final company = ref.watch(activeCompanyProvider);

    // Guard with module check
    if (!company.isModuleEnabled(AppModule.budgets)) {
      return Scaffold(
        key: const Key('budgets_module_disabled'),
        appBar: AppBar(title: const Text('Budgets')),
        body: const EmptyStateView(
          icon: Icons.pie_chart_outline,
          title: 'Budgets Module Disabled',
          message:
              'The budgets module is currently disabled for this company. Enable it in company settings to track spending limits.',
        ),
      );
    }

    final progressListAsync = ref.watch(budgetsProgressListProvider);
    final overallAsync = ref.watch(overallMonthlyBudgetProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets & Limits'),
        actions: [
          IconButton(
            key: const Key('add_budget_button'),
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Add Budget',
            onPressed: () => _showAddEditBudgetSheet(context),
          ),
        ],
      ),
      body: progressListAsync.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            SkeletonListTile(),
            SkeletonListTile(),
            SkeletonListTile(),
          ],
        ),
        error: (err, _) => Center(child: Text('Error loading budgets: $err')),
        data: (progressList) {
          final exceededBudgets =
              progressList.where((p) => p.isExceeded).toList();
          final warningBudgets =
              progressList.where((p) => p.isWarning && !p.isExceeded).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            children: [
              // Threshold Banners
              if (exceededBudgets.isNotEmpty)
                _buildExceededBanner(theme, exceededBudgets),
              if (warningBudgets.isNotEmpty)
                _buildWarningBanner(theme, warningBudgets),

              // Overall Monthly Budget
              overallAsync.when(
                data: (overall) =>
                    _buildOverallBudgetCard(theme, company, overall),
                loading: () => const SizedBox.shrink(),
                error: (err, stack) => const SizedBox.shrink(),
              ),

              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Category Budgets',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${progressList.length} Active',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (progressList.isEmpty)
                EmptyStateView(
                  icon: Icons.pie_chart_outline,
                  title: 'No Budgets Set',
                  message:
                      'Set category budgets to control spending and keep your finances on track.',
                  actionLabel: 'Set First Budget',
                  onAction: () => _showAddEditBudgetSheet(context),
                )
              else
                ...progressList.map(
                  (progress) => _buildBudgetCard(
                    theme,
                    company,
                    progress,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // 100% Exceeded Banner
  Widget _buildExceededBanner(
    ThemeData theme,
    List<BudgetProgress> exceededBudgets,
  ) {
    final catNames = exceededBudgets.map((b) => b.categoryName).join(', ');
    return Container(
      key: const Key('budget_exceeded_banner'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withAlpha(120)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Budget Exceeded (100%+)',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'You have exceeded your allocated budget for $catNames.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.red.shade900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 80% Warning Banner
  Widget _buildWarningBanner(
    ThemeData theme,
    List<BudgetProgress> warningBudgets,
  ) {
    final catNames = warningBudgets.map((b) => b.categoryName).join(', ');
    return Container(
      key: const Key('budget_warning_banner'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.withAlpha(35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.shade700.withAlpha(120)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.amber.shade800, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Approaching Limit (80%+)',
                  style: TextStyle(
                    color: Colors.amber.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'You have reached 80% or more of your budget for $catNames.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.amber.shade900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Overall Monthly Budget Card
  Widget _buildOverallBudgetCard(
    ThemeData theme,
    Company company,
    OverallBudgetSummary overall,
  ) {
    final percentClamped =
        overall.totalAllocatedInCents > 0 ? (overall.percentUsed / 100) : 0.0;
    final progressColor = overall.isExceeded
        ? Colors.red
        : overall.isWarning
            ? Colors.orange
            : Colors.green;

    return LiquidGlassCard(
      key: const Key('overall_budget_card'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Overall Monthly Budget',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: progressColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${overall.percentUsed.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: progressColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percentClamped.clamp(0.0, 1.0),
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Spent',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  AmountText(
                    amount: overall.totalSpentInCents / 100,
                    currencyCode: company.currencyCode,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Remaining',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  AmountText(
                    amount: overall.remainingInCents / 100,
                    currencyCode: company.currencyCode,
                    color: overall.remainingInCents < 0
                        ? Colors.red
                        : Colors.green,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Allocated',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  AmountText(
                    amount: overall.totalAllocatedInCents / 100,
                    currencyCode: company.currencyCode,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Category Budget Card
  Widget _buildBudgetCard(
    ThemeData theme,
    Company company,
    BudgetProgress progress,
  ) {
    final budget = progress.budget;
    final progressColor = progress.isExceeded
        ? Colors.red
        : progress.isWarning
            ? Colors.orange
            : Colors.green;
    final percentClamped = (progress.percentUsed / 100).clamp(0.0, 1.0);

    return LiquidGlassCard(
      key: Key('budget_card_${budget.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      progress.categoryName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        budget.period.displayName,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (budget.rolloverEnabled) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Rollover',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (val) {
                  if (val == 'edit') {
                    _showAddEditBudgetSheet(context, existingBudget: budget);
                  } else if (val == 'delete') {
                    _deleteBudget(budget);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    key: Key('edit_budget_${budget.id}'),
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
                    key: Key('delete_budget_${budget.id}'),
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
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percentClamped,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${CurrencyFormatter.format(progress.spentInCents, currencyCode: company.currencyCode)} spent of ${CurrencyFormatter.format(progress.effectiveAllocatedInCents, currencyCode: company.currencyCode)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '${progress.percentUsed.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: progressColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (progress.rolloverInCents > 0) ...[
            const SizedBox(height: 4),
            Text(
              '+${CurrencyFormatter.format(progress.rolloverInCents, currencyCode: company.currencyCode)} rolled over from last period',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.blue.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
