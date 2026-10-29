import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';
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
/// overall monthly budget summary, and warning/exceeded threshold banners.
class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  /// Opens the add/edit budget bottom sheet.
  static Future<void> showAddBudgetSheet(
    BuildContext context,
    WidgetRef ref, {
    BudgetModel? existingBudget,
  }) =>
      _BudgetsScreenState.showAddEditBudgetSheetStatic(context, ref,
          existingBudget: existingBudget);

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  // Show Add/Edit Budget Sheet
  Future<void> _showAddEditBudgetSheet(
    BuildContext context, {
    BudgetModel? existingBudget,
  }) =>
      showAddEditBudgetSheetStatic(context, ref,
          existingBudget: existingBudget);

  static Color _getThresholdColor(BuildContext context, double percentUsed) {
    if (percentUsed >= 100.0) {
      return AppColors.expense(context);
    } else if (percentUsed >= 80.0) {
      return Colors.amber.shade700;
    } else {
      return AppColors.income(context);
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
    String? selectedCategoryId = existingBudget?.categoryId ??
        (expenseCategories.isNotEmpty ? expenseCategories.first.id : null);
    BudgetPeriodType selectedPeriod =
        existingBudget?.period ?? BudgetPeriodType.monthly;
    bool rolloverEnabled = existingBudget?.rolloverEnabled ?? false;

    Future<void> doSave(BuildContext sheetCtx) async {
      final parsedAmount =
          double.tryParse(amountController.text.trim()) ?? 0;
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
            final categoryPickerItems = expenseCategories
                .map((cat) => AdaptivePickerItem<String>(
                      value: cat.id,
                      label: cat.name,
                    ))
                .toList();

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
                      existingBudget == null
                          ? 'Set Budget'
                          : 'Update Budget',
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
    final overallAsync = ref.watch(overallMonthlyBudgetProvider);

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

              // Overall Monthly Budget Hero Card
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
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withValues(alpha: 0.45)),
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
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.45)),
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
    final progressColor = _getThresholdColor(context, overall.percentUsed);

    return AdaptiveSurfaceCard(
      key: const Key('overall_budget_card'),
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 16),
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
            ],
          ),
          const SizedBox(height: 14),
          _AdaptiveProgressBar(
            value: percentClamped.clamp(0.0, 1.0),
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
                        ? AppColors.expense(context)
                        : AppColors.income(context),
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
                                    color: Colors.blue.withValues(alpha: 0.15),
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
                        ],
                      ),
                    ),
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
    final isDark = theme.brightness == Brightness.dark;
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
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.08),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.06),
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
