import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../foundations/foundations.dart';
import '../../selection/components/m3e_selection_scope.dart';
import '../../selection/controllers/m3e_selection_controller.dart';
import '../styles/m3e_expandable_style.dart';
import '../styles/m3e_list_reorder_state.dart';
import '../styles/m3e_list_selection_state.dart';
import '../styles/m3e_list_theme.dart';
import 'm3e_expandable_expanded.dart';
import 'm3e_expandable_item.dart';
import 'm3e_list_feature_scope.dart';

/// M3EExpandableListBase.

abstract class M3EExpandableListBase extends StatefulWidget {
  /// itemCount.
  final int itemCount;

  /// headerBuilder.
  final M3EExpandableHeaderBuilder headerBuilder;

  /// bodyBuilder.
  final M3EExpandableBodyBuilder bodyBuilder;

  /// Optional per-index expanded content (`.list` or `.content`).
  final M3EExpandableExpanded? Function(int index)? expandedBuilder;

  /// allowMultipleExpanded.
  final bool? allowMultipleExpanded;

  /// initiallyExpanded.
  final Set<int> initiallyExpanded;

  /// style.
  final M3EExpandableStyle? style;

  /// expandMotion.
  final M3ESpring? expandMotion;

  /// collapseMotion.
  final M3ESpring? collapseMotion;

  /// Called when an item expands or collapses.
  final void Function(int index, {required bool isExpanded})?
  onExpansionChanged;

  /// Enables selection on main expandable rows (not nested sublists).
  final bool selection;

  /// Optional selection controller; ancestor [M3ESelectionScope] wins.
  final M3ESelectionController? selectionController;

  /// Called when selection indices change.
  final ValueChanged<Set<int>>? onSelectionChanged;

  /// Optional selection state override (else [M3EListTheme.selection]).
  final M3EListSelectionState? selectionState;

  /// Enables long-press reorder of header rows. Requires [onReorder].
  final bool reorder;

  /// Called after a successful header reorder drop.
  final ReorderCallback? onReorder;

  /// Optional reorder state override (else [M3EListTheme.reorder]).
  final M3EListReorderState? reorderState;

  /// M3EExpandableListBase.
  const M3EExpandableListBase({
    super.key,
    required this.itemCount,
    required this.headerBuilder,
    required this.bodyBuilder,
    this.expandedBuilder,
    this.allowMultipleExpanded,
    this.initiallyExpanded = const {},
    this.style,
    this.expandMotion,
    this.collapseMotion,
    this.onExpansionChanged,
    this.selection = false,
    this.selectionController,
    this.onSelectionChanged,
    this.selectionState,
    this.reorder = false,
    this.onReorder,
    this.reorderState,
  });
}

/// M3EExpandableStateMixin.

mixin M3EExpandableStateMixin<T extends M3EExpandableListBase> on State<T> {
  late Set<int> _expandedIndices;

  /// Index that was snap-collapsed for an in-progress reorder, if any.
  int? _collapsedForReorder;

  /// When true, expand/collapse updates snap instead of springing.
  bool _snapCollapse = false;

  /// The expandedIndices.
  Set<int> get expandedIndices => _expandedIndices;

  /// Whether expand updates should snap (for reorder prepare).
  bool get snapCollapseForReorder => _snapCollapse;

  @override
  void initState() {
    super.initState();
    _expandedIndices = Set<int>.from(widget.initiallyExpanded);
  }

  /// Snap-collapses [index] if expanded so reorder can measure header height.
  Future<void> prepareReorderDrag(int index) async {
    _collapsedForReorder = null;
    if (!isExpanded(index)) {
      return;
    }
    _collapsedForReorder = index;
    _snapCollapse = true;
    setState(() => _expandedIndices.remove(index));
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
  }

  /// Remaps expansion (and selection) indices after settle; restores expand.
  void settleReorderDrag(int from, int to) {
    final int? pending = _collapsedForReorder;
    _collapsedForReorder = null;
    _snapCollapse = false;
    setState(() {
      _expandedIndices = _expandedIndices
          .map((int i) => _m3eRemapIndexAfterMove(i, from, to))
          .toSet();
      if (pending != null && pending == from) {
        _expandedIndices.add(to);
      }
    });
    if (from != to) {
      _remapSelectionAfterMove(from, to);
    }
  }

  void _remapSelectionAfterMove(int from, int to) {
    final M3EListFeatureScope? scope = M3EListFeatureScope.maybeOf(context);
    final controller = scope?.controller;
    if (controller == null || !scope!.selectionEnabled) {
      return;
    }
    final Set<int> remapped = controller.selectedIndices
        .map((int i) => _m3eRemapIndexAfterMove(i, from, to))
        .toSet();
    if (setEquals(remapped, controller.selectedIndices)) {
      return;
    }
    controller.clear();
    remapped.forEach(controller.select);
    widget.onSelectionChanged?.call(controller.selectedIndices);
  }

  /// handleToggle.

  void handleToggle(
    int index, {
    required bool allowMultipleExpanded,
    required M3EHapticFeedback haptic,
    void Function(int index, {required bool isExpanded})? onExpansionChanged,
  }) {
    M3EHaptics.trigger(haptic);
    final isExpanding = !_expandedIndices.contains(index);
    setState(() {
      if (isExpanding) {
        if (!allowMultipleExpanded) {
          _expandedIndices.clear();
        }
        _expandedIndices.add(index);
      } else {
        _expandedIndices.remove(index);
      }
    });
    onExpansionChanged?.call(index, isExpanded: isExpanding);
  }

  /// isExpanded.

  bool isExpanded(int index) => _expandedIndices.contains(index);

  /// buildItem.

  Widget buildItem(BuildContext context, int index) {
    final expandable = M3ETheme.of(context).listTheme.expandable;
    final effectiveStyle =
        widget.style ?? M3EExpandableStyle.fromTheme(expandable);
    final M3EExpandableExpanded? expanded = widget.expandedBuilder?.call(index);
    final bool hasList = expanded != null && expanded.isList;

    // Noticeable overshoot for list-type open/close.
    final M3ESpring defaultExpand = hasList
        ? M3EMotion.expressiveSpatialPress
        : expandable.expandMotion;
    final M3ESpring defaultCollapse = hasList
        ? M3EMotion.expressiveSpatialPress
        : expandable.collapseMotion;

    final effectiveExpandMotion = widget.expandMotion ?? defaultExpand;
    final effectiveCollapseMotion = widget.collapseMotion ?? defaultCollapse;
    final effectiveAllowMultiple =
        widget.allowMultipleExpanded ?? expandable.allowMultipleExpanded;

    Widget item = M3EExpandableItem(
      index: index,
      totalCount: widget.itemCount,
      isExpanded: isExpanded(index),
      headerBuilder: (BuildContext context, int i, double progress) {
        return Builder(
          builder: (BuildContext context) {
            return M3EListItemIndex(
              index: i,
              child: widget.headerBuilder(context, i, progress),
            );
          },
        );
      },
      bodyBuilder: widget.bodyBuilder,
      expanded: expanded,
      decoration: effectiveStyle,
      expandMotion: effectiveExpandMotion,
      collapseMotion: effectiveCollapseMotion,
      onToggle: () => handleToggle(
        index,
        allowMultipleExpanded: effectiveAllowMultiple,
        haptic: effectiveStyle.haptic,
        onExpansionChanged: widget.onExpansionChanged,
      ),
    );

    return item = M3EListItemIndex(index: index, child: item);
  }
}

/// Remaps [index] after an item moves from [from] to [to].
int _m3eRemapIndexAfterMove(int index, int from, int to) {
  if (index == from) {
    return to;
  }
  if (from < to && index > from && index <= to) {
    return index - 1;
  }
  if (from > to && index >= to && index < from) {
    return index + 1;
  }
  return index;
}
