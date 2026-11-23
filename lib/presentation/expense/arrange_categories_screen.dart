import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_list_row.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_section_header.dart';
import '../../core/widgets/app_feedback.dart';
import '../../data/models/account_model.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';

class ArrangeCategoriesScreen extends ConsumerStatefulWidget {
  const ArrangeCategoriesScreen({
    super.key,
    required this.workspaceId,
    required this.type,
    required this.categories,
  });

  final String workspaceId;
  final AccountType type;
  final List<AccountModel> categories;

  @override
  ConsumerState<ArrangeCategoriesScreen> createState() =>
      _ArrangeCategoriesScreenState();
}

class _ArrangeCategoriesScreenState
    extends ConsumerState<ArrangeCategoriesScreen> {
  final _groups = <String?, List<AccountModel>>{};
  bool _changed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final category in widget.categories) {
      _groups.putIfAbsent(category.parentAccountId, () => []).add(category);
    }
  }

  Future<void> _save() async {
    if (ref.read(activeCompanyProvider).id != widget.workspaceId) {
      showAppFeedback(context, 'The active workspace changed.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(expenseRepositoryProvider).saveCategoryPriority(
        widget.type,
        [for (final group in _groups.values) ...group.map((item) => item.id)],
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppFeedback(context, 'Could not save category order.');
    }
  }

  Widget _buildGroup(String? parentId, String heading) {
    final items = _groups[parentId]!;
    return SliverMainAxisGroup(
      key: ValueKey(parentId),
      slivers: [
        SliverToBoxAdapter(child: AdaptiveSectionHeader(title: heading)),
        SliverReorderableList(
          itemCount: items.length,
          onReorder: (from, to) {
            if (to > from) to--;
            if (from == to) return;
            setState(() {
              items.insert(to, items.removeAt(from));
              _changed = true;
            });
          },
          itemBuilder: (_, index) {
            final item = items[index];
            return Material(
              key: ValueKey(item.id),
              color: Colors.transparent,
              child: AdaptiveListRow(
                title: item.name,
                showDivider: index < items.length - 1,
                trailing: items.length > 1
                    ? ReorderableDragStartListener(
                        index: index,
                        enabled: !_saving,
                        child: Tooltip(
                          message: 'Reorder ${item.name}',
                          child: const ColoredBox(
                            color: Colors.transparent,
                            child: SizedBox.square(
                              dimension: 44,
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final names = {for (final item in widget.categories) item.id: item.name};
    return AdaptiveScaffold(
      title: 'Arrange categories',
      actions: [
        AdaptiveButton(
          type: AdaptiveButtonType.text,
          onPressed: _changed && !_saving ? _save : null,
          isLoading: _saving,
          child: const Text('Save'),
        ),
      ],
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                'Drag the handles to set the order in Add Transaction.',
              ),
            ),
          ),
          if (_groups.containsKey(null))
            _buildGroup(
              null,
              widget.type == AccountType.income
                  ? 'Income categories'
                  : 'Expense categories',
            ),
          for (final parentId in _groups.keys.whereType<String>())
            _buildGroup(parentId, names[parentId] ?? 'Subcategories'),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
