import 'package:flutter/widgets.dart';

import '../../../foundations/foundations.dart';
import '../../selection/components/m3e_selection_flip.dart';
import '../components/m3e_list_feature_scope.dart';
import '../enums/m3e_list_selection_enums.dart';
import '../styles/m3e_list_selection_state.dart';

/// Resolves leading widget for list selection flip (leading only).
///
/// Flips between [leading] and [M3EListSelectionState.selectedIcon] when both
/// are present and selection is enabled. Otherwise returns [leading] unchanged.
Widget? m3eResolveListLeading({
  required BuildContext context,
  required int? index,
  required Widget? leading,
}) {
  if (leading == null || index == null) {
    return leading;
  }
  final M3EListFeatureScope? scope = M3EListFeatureScope.maybeOf(context);
  if (scope == null ||
      !scope.selectionEnabled ||
      !scope.selectionState.hasSelectedIcon) {
    return leading;
  }

  final Widget selectedIcon = scope.selectionState.selectedIcon!;
  final bool selected = scope.isSelected(index);
  final VoidCallback? onIconTap =
      scope.selectionState.trigger == M3EListSelectionTrigger.icon
      ? () => scope.onToggleSelection(index)
      : null;

  final theme = M3ETheme.of(context);
  final listTheme = theme.listTheme.item;
  return IconTheme.merge(
    data: IconThemeData(
      color: listTheme.iconColor(theme.colorScheme),
      size: listTheme.iconSize,
    ),
    child: M3ESelectionFlip(
      selected: selected,
      selectedChild: selectedIcon,
      duration: scope.selectionState.iconFlipDuration,
      onTap: onIconTap,
      child: leading,
    ),
  );
}

/// Resolves trailing widget; reorder drag handle replaces any trailing when on.
Widget? m3eResolveListTrailing({
  required BuildContext context,
  required Widget? trailing,
}) {
  final M3EListFeatureScope? scope = M3EListFeatureScope.maybeOf(context);
  if (scope == null ||
      !scope.reorderEnabled ||
      !scope.reorderState.showDragHandle) {
    return trailing;
  }

  final theme = M3ETheme.of(context);
  final listTheme = theme.listTheme.item;
  return Icon(
    M3EIcons.drag_handle,
    color: listTheme.iconColor(theme.colorScheme),
    size: listTheme.iconSize,
  );
}
