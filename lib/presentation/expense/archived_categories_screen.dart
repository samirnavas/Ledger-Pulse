import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_list_row.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/skeleton_list_tile.dart';
import '../../data/models/account_model.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import 'widgets/category_icons.dart';

class ArchivedCategoriesScreen extends ConsumerWidget {
  const ArchivedCategoriesScreen({super.key});

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    AccountModel category,
  ) async {
    final companyId = ref.read(activeCompanyProvider).id;
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Restore category?',
      message: 'Restore ${category.name} to your active categories?',
      confirmLabel: 'Restore',
    );
    if (!confirmed || !context.mounted) return;
    if (ref.read(activeCompanyProvider).id != companyId) {
      showAppFeedback(context, 'The active workspace changed.');
      return;
    }
    try {
      await ref
          .read(expenseRepositoryProvider)
          .updateCategory(id: category.id, isActive: true);
      if (context.mounted) {
        showAppFeedback(context, '${category.name} was restored.');
      }
    } catch (error) {
      if (context.mounted) {
        showAppFeedback(
          context,
          error is ArgumentError
              ? error.message.toString()
              : 'Could not restore ${category.name}.',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(archivedCategoriesProvider);

    return AdaptiveScaffold(
      title: 'Archived Categories',
      body: categories.when(
        data: (items) {
          if (items.isEmpty) {
            return const EmptyStateView(
              icon: Icons.archive_outlined,
              title: 'No archived categories',
              subtitle: 'Archived expense and income categories appear here.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            itemBuilder: (_, index) {
              final category = items[index];
              return AdaptiveListRow(
                title: category.name,
                leading: Icon(categoryIcon(category)),
                subtitle: category.type == AccountType.income
                    ? 'Income'
                    : 'Expense',
                showDivider: index < items.length - 1,
                trailing: const Icon(Icons.restore_rounded),
                onTap: () => _restore(context, ref, category),
              );
            },
          );
        },
        loading: () => ListView.builder(
          itemCount: 4,
          itemBuilder: (_, _) => const SkeletonListTile(),
        ),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load archived categories'),
              AdaptiveButton(
                type: AdaptiveButtonType.text,
                onPressed: () => ref.invalidate(archivedCategoriesProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
