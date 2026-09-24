import 'package:flutter/widgets.dart';

import '../../selection/components/m3e_selection_scope.dart';
import '../../selection/controllers/m3e_selection_controller.dart';
import '../enums/m3e_list_selection_enums.dart';
import '../styles/m3e_list_selection_state.dart';

/// Resolves which [M3ESelectionController] a list should use.
///
/// Preference: ancestor [M3ESelectionScope] → [widgetController] → create.
M3ESelectionController resolveListSelectionController({
  required BuildContext context,
  M3ESelectionController? widgetController,
  required M3ESelectionController Function() createOwned,
}) {
  final M3ESelectionScope? scope = M3ESelectionScope.maybeOf(context);
  if (scope != null) {
    return scope.controller;
  }
  if (widgetController != null) {
    return widgetController;
  }
  return createOwned();
}

/// Whether the controller came from an ancestor selection scope.
bool listSelectionUsesAncestorScope(BuildContext context) =>
    M3ESelectionScope.maybeOf(context) != null;

/// Applies single/multiple selection semantics and notifies [onChanged].
void applyListSelectionToggle({
  required M3ESelectionController controller,
  required int index,
  required M3EListSelectionMode mode,
  ValueChanged<Set<int>>? onChanged,
}) {
  if (mode == M3EListSelectionMode.single) {
    final bool wasSelected = controller.isSelected(index);
    controller.clear();
    if (!wasSelected) {
      controller.select(index);
    }
  } else {
    controller.toggle(index);
  }
  onChanged?.call(controller.selectedIndices);
}

/// Effective selection state (widget override over theme).
M3EListSelectionState mergeListSelectionState({
  required M3EListSelectionState theme,
  M3EListSelectionState? override,
}) => override ?? theme;
