import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_controls.dart';
import '../../core/widgets/adaptive_form_sheet.dart';
import '../../core/widgets/adaptive_page_entrance.dart';
import '../../core/widgets/adaptive_picker.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../core/widgets/adaptive_surface_card.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/skeleton_list_tile.dart';
import '../../data/models/account_model.dart';
import '../../data/models/budget_model.dart';
import '../../data/models/company_model.dart';
import '../providers/budget_providers.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';

/// Screen displaying category budgets, progress bars, rollover indicators,
/// and an overall budget summary for each period.
class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  /// Opens the add/edit budget bottom sheet.
  static Future<void> showAddBudgetSheet(
    BuildContext context,
    WidgetRef ref, {
    BudgetModel? existingBudget,
  }) => _BudgetsScreenState.showAddEditBudgetSheetStatic(
    context,
    ref,
    existingBudget: existingBudget,
  );

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  // Show Add/Edit Budget Sheet
  Future<void> _showAddEditBudgetSheet(
    BuildContext context, {
    BudgetModel? existingBudget,
  }) => showAddEditBudgetSheetStatic(
    context,
    ref,
    existingBudget: existingBudget,
  );

  static Color _getThresholdColor(BuildContext context, double percentUsed) {
    if (percentUsed >= 100.0) {
      return Theme.of(context).colorScheme.error;
    } else if (percentUsed >= 80.0) {
      return Theme.of(context).colorScheme.tertiary;
    } else {
      return Theme.of(context).colorScheme.primary;
    }
  }

  static Future<void> showAddEditBudgetSheetStatic(
    BuildContext context,
    WidgetRef ref, {
    BudgetModel? existingBudget,
  }) async {
    final company = ref.read(activeCompanyProvider);
    final allCats = await ref.read(expenseRepositoryProvider).getCategories();
    final expenseCategories = allCats
        .where((c) => c.type == AccountType.expense)
        .toList();

    final amountController = TextEditingController(
      text: existingBudget != null
          ? (existingBudget.allocatedInCents / 100).toStringAsFixed(2)
          : '',
    );
    String? selectedCategoryId = existingBudget?.categoryId ?? 'all';
    BudgetPeriodType selectedPeriod =
        existingBudget?.period ?? BudgetPeriodType.monthly;
    bool rolloverEnabled = existingBudget?.rolloverEnabled ?? false;

    Future<void> doSave(BuildContext sheetCtx) async {
      final parsedAmount = double.tryParse(amountController.text.trim()) ?? 0;
      if (parsedAmount <= 0) {
        showAppFeedback(context, 'Please enter a valid amount', isError: true);
        return;
      }
      if (selectedCategoryId == null) {
        showAppFeedback(context, 'Please select a category', isError: true);
        return;
      }

      final amountInCents = (parsedAmount * 100).round();
      final budgetRepo = ref.read(budgetRepositoryProvider);

      HapticFeedback.mediumImpact();
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
        Navigator.of(sheetCtx).pop();
        showAppFeedback(
          context,
          existingBudget == null
              ? 'Budget created successfully'
              : 'Budget updated successfully',
        );
      }
    }

    if (!context.mounted) return;
    await showAdaptiveFormSheet<void>(
      context: context,
      title: existingBudget == null ? 'Set Budget' : 'Edit Budget',
      doneLabel: 'Done',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            final categoryPickerItems = [
              const AdaptivePickerItem<String>(
                value: 'all',
                label: 'All Categories (Overall)',
              ),
              ...expenseCategories.map(
                (cat) =>
                    AdaptivePickerItem<String>(value: cat.id, label: cat.name),
              ),
            ];

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Category dropdown
                  Text(
                    'Expense Category',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AdaptiveDropdownField<String>(
                    key: const Key('budget_category_field'),
                    label: 'Category',
                    value: selectedCategoryId,
                    items: categoryPickerItems,
                    hint: 'Select Category',
                    onChanged: (val) {
                      if (val != null) {
                        setSheetState(() => selectedCategoryId = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Amount Field
                  Text(
                    'Allocated Amount',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('budget_amount_field'),
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: Center(
                        widthFactor: 1,
                        heightFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            CurrencyFormatter.getSymbol(company.currencyCode),
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      hintText: '0.00',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Period Selector
                  Text(
                    'Budget Period',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AdaptiveSegmentedControl<BudgetPeriodType>(
                    key: const Key('budget_period_selector'),
                    groupValue: selectedPeriod,
                    children: const {
                      BudgetPeriodType.weekly: Text('Weekly'),
                      BudgetPeriodType.monthly: Text('Monthly'),
                      BudgetPeriodType.yearly: Text('Yearly'),
                    },
                    onValueChanged: (val) {
                      setSheetState(() => selectedPeriod = val);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Rollover Switch
                  AdaptiveSwitch(
                    key: const Key('budget_rollover_switch'),
                    value: rolloverEnabled,
                    label: 'Enable Rollover',
                    subtitle: 'Carry over unspent budget to the next period',
                    onChanged: (val) {
                      setSheetState(() => rolloverEnabled = val);
                    },
                  ),
                  const SizedBox(height: 24),

                  // Save Button
                  AdaptiveButton(
                    key: const Key('save_budget_button'),
                    child: Text(
                      existingBudget == null ? 'Set Budget' : 'Update Budget',
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

  // Delete budget confirmation
  Future<void> _deleteBudget(BudgetModel budget) async {
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Delete Budget',
      message: 'Are you sure you want to remove this budget?',
      confirmLabel: 'Delete',
      isDestructive: true,
    );

    if (confirmed) {
      HapticFeedback.mediumImpact();
      await ref.read(budgetRepositoryProvider).deleteBudget(budget.id);
      if (mounted) {
        showAppFeedback(context, 'Budget deleted');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final company = ref.watch(activeCompanyProvider);

    // Guard with module check
    if (!company.isModuleEnabled(AppModule.budgets)) {
      return const Material(
        key: Key('budgets_module_disabled'),
        color: Colors.transparent,
        child: EmptyStateView(
          icon: Icons.pie_chart_outline,
          title: 'Budgets Module Disabled',
          message:
              'The budgets module is currently disabled for this company. Enable it in company settings to track spending limits.',
        ),
      );
    }

    final progressListAsync = ref.watch(budgetsProgressListProvider);
    final summaries = ref.watch(budgetSummariesByPeriodProvider);

    return AdaptivePageEntrance(
      child: Material(
        color: Colors.transparent,
        child: progressListAsync.when(
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
            final categoryBudgets = progressList.where(
              (item) => !item.budget.isOverall,
            ).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              children: [
                for (final summary
                    in summaries.value ?? const <OverallBudgetSummary>[])
                  _buildOverallBudgetCard(theme, company, summary),

                if (categoryBudgets.isNotEmpty) ...[
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
                        '${categoryBudgets.length} Active',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final progress in categoryBudgets)
                    _buildBudgetCard(theme, company, progress),
                ],

                if (progressList.isEmpty)
                  EmptyStateView(
                    icon: Icons.pie_chart_outline,
                    title: 'No Budgets Set',
                    message:
                        'Set category budgets to control spending and keep your finances on track.',
                    actionLabel: 'Set First Budget',
                    onAction: () => _showAddEditBudgetSheet(context),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBudgetMenu(ThemeData theme, BudgetModel budget) {
    return PopupMenuButton<String>(
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
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 18,
                color: theme.colorScheme.error,
              ),
              SizedBox(width: 8),
              Text(
                'Delete',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverallBudgetCard(
    ThemeData theme,
    Company company,
    OverallBudgetSummary overall,
  ) {
    final budget = overall.items.first.budget;
    final period = budget.periodType;
    final includesAll = budget.isOverall;
    final categories = overall.items.map((item) => item.categoryName).toList()
      ..sort();
    final percent = overall.percentUsed / 100;
    final progressColor = _getThresholdColor(context, overall.percentUsed);

    return AdaptiveSurfaceCard(
      key: ValueKey('overall_budget_card_${period.name}'),
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Overall ${period.displayName} Budget',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: progressColor.withValues(alpha: 0.15),
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
              if (includesAll) _buildBudgetMenu(theme, budget),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            includesAll ? 'All Categories' : 'Includes ${categories.join(', ')}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          _AdaptiveProgressBar(
            value: percent.clamp(0.0, 1.0),
            color: progressColor,
            height: 10,
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
                    amountInCents: overall.totalSpentInCents,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overrideColor: theme.colorScheme.onSurface,
                    currencyCode: company.currencyCode,
                    variant: AmountVariant.medium,
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
                    amountInCents: overall.remainingInCents,
                    currencyCode: company.currencyCode,
                    overrideColor: overall.remainingInCents < 0
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                    variant: AmountVariant.medium,
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
                    amountInCents: overall.totalAllocatedInCents,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overrideColor: theme.colorScheme.onSurface,
                    currencyCode: company.currencyCode,
                    variant: AmountVariant.medium,
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
    final progressColor = _getThresholdColor(context, progress.percentUsed);
    final percentClamped = (progress.percentUsed / 100).clamp(0.0, 1.0);

    return AdaptiveSurfaceCard(
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
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: progressColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.category_rounded,
                        color: progressColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  progress.categoryName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
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
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Rollover',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${DateFormat.yMMMd().format(progress.periodStartDate)} – ${DateFormat.yMMMd().format(progress.periodEndDate)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _buildBudgetMenu(theme, budget),
            ],
          ),
          const SizedBox(height: 12),
          _AdaptiveProgressBar(
            value: percentClamped,
            color: progressColor,
            height: 8,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  AmountText(
                    amountInCents: progress.spentInCents,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overrideColor: theme.colorScheme.onSurface,
                    currencyCode: company.currencyCode,
                    variant: AmountVariant.small,
                  ),
                  Text(
                    ' spent of ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  AmountText(
                    amountInCents: progress.effectiveAllocatedInCents,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overrideColor: theme.colorScheme.onSurface,
                    currencyCode: company.currencyCode,
                    variant: AmountVariant.small,
                  ),
                ],
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
                color: theme.colorScheme.primary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdaptiveProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;

  const _AdaptiveProgressBar({
    required this.value,
    required this.color,
    this.height = 10,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final theme = Theme.of(context);

    final clampedValue = value.clamp(0.0, 1.0);

    if (isIos) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final fillWidth = (totalWidth * clampedValue).clamp(0.0, totalWidth);

          return Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height / 2),
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: fillWidth,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height / 2),
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(
        value: clampedValue,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(color),
        minHeight: height,
      ),
    );
  }
}
