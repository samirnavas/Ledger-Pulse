import 'package:flutter/widgets.dart';

import '../../foundations/foundations.dart';
import '../cards/m3e_cards.dart';
import '../selection/components/m3e_selection_scope.dart';
import '../selection/controllers/m3e_selection_controller.dart';
import 'components/m3e_card_list_item.dart';
import 'components/m3e_expandable_builders.dart';
import 'components/m3e_expandable_data.dart';
import 'components/m3e_expandable_expanded.dart';
import 'components/m3e_expandable_list_base.dart';
import 'components/m3e_expandable_snap_collapse.dart';
import 'components/m3e_list_feature_host.dart';
import 'components/m3e_list_feature_scope.dart';
import 'components/m3e_list_item_scope.dart';
import 'components/m3e_list_reorder_host.dart';
import 'controllers/m3e_dismissible_card_controller.dart';
import 'enums/m3e_list_enums.dart';
import 'enums/m3e_list_selection_enums.dart';
import 'models/m3e_list_swipe_action.dart';
import 'styles/m3e_dismissible_list_style.dart';
import 'styles/m3e_expandable_style.dart';
import 'styles/m3e_list_reorder_state.dart';
import 'styles/m3e_list_selection_state.dart';
import 'styles/m3e_list_theme.dart';
import 'utils/m3e_list_immediate_tap.dart';
import 'utils/m3e_list_row_features.dart';
import 'utils/m3e_list_selection_fill.dart';

export 'components/m3e_card_list_item.dart'
    show calculateCardPosition, calculateCardRadius;
export 'components/m3e_expandable_data.dart';
export 'components/m3e_expandable_expanded.dart';
export 'components/m3e_expandable_item.dart';
export 'components/m3e_list_feature_scope.dart';
export 'components/m3e_list_item_scope.dart';
export 'controllers/m3e_dismissible_card_controller.dart';
export 'enums/m3e_expandable_enums.dart';
export 'enums/m3e_list_enums.dart';
export 'enums/m3e_list_selection_enums.dart';
export 'models/m3e_dismissible_slot.dart';
export 'models/m3e_list_swipe_action.dart';
export 'styles/m3e_dismissible_list_style.dart';
export 'styles/m3e_expandable_style.dart';
export 'styles/m3e_list_reorder_state.dart';
export 'styles/m3e_list_selection_state.dart';
export 'styles/m3e_list_theme.dart';
export 'utils/m3e_measure_size.dart';

part 'components/m3e_card_list_widgets.dart';
part 'components/m3e_dismissible_list_widgets.dart';
part 'components/m3e_expandable_list_widgets.dart';

/// A Material 3 Expressive list item.
///
/// A single row of a list with optional leading and trailing widgets, a
/// headline and up to three lines of supporting text. Becomes interactive with
/// state layers when [onTap] is supplied.
///
/// Inside card-backed lists, the parent list owns the outer card surface
/// automatically.
class M3EListItem extends StatelessWidget {
  /// M3EListItem.
  const M3EListItem({
    required this.headline,
    this.supportingText,
    this.overline,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.variant,
    this.border,
    super.key,
  });

  /// headline.

  final String headline;

  /// supportingText.
  final String? supportingText;

  /// overline.
  final String? overline;

  /// leading.
  final Widget? leading;

  /// trailing.
  final Widget? trailing;

  /// onTap.
  final VoidCallback? onTap;

  /// selected.
  final bool selected;

  /// Card variant override; falls back to [M3EListItemTheme.variant].
  final M3ECardVariant? variant;

  /// Card outline override; falls back to [M3EListItemTheme.border].
  final BorderSide? border;

  @override
  Widget build(BuildContext context) {
    return M3EComponentTheme(builder: _buildItem);
  }

  Widget _buildItem(BuildContext context) {
    final body = _buildBody(context);
    if (M3EListItemScope.isEmbedded(context)) {
      return body;
    }

    final theme = M3ETheme.of(context);
    final scheme = theme.colorScheme;
    final listTheme = theme.listTheme.item;
    final bool threeLine = _isThreeLine;

    return M3ECard(
      variant: variant ?? listTheme.variant,
      border: border ?? listTheme.border,
      color: selected ? listTheme.selectedColor(scheme) : null,
      onPressed: onTap,
      semanticLabel: headline,
      padding: EdgeInsets.symmetric(
        horizontal: listTheme.horizontalPadding,
        vertical: threeLine
            ? listTheme.threeLineVerticalPadding
            : listTheme.verticalPadding,
      ),
      width: double.infinity,
      child: body,
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = M3ETheme.of(context);
    final listTheme = theme.listTheme.item;
    final bool threeLine = _isThreeLine;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: listTheme.minHeight),
      child: Row(
        crossAxisAlignment: threeLine
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: _buildChildrenFor(context, theme),
      ),
    );
  }

  List<Widget> _buildChildrenFor(BuildContext context, M3EThemeData theme) {
    final scheme = theme.colorScheme;
    final listTheme = theme.listTheme.item;
    final int? index = M3EListItemIndex.maybeOf(context);
    final Widget? resolvedLeading = m3eResolveListLeading(
      context: context,
      index: index,
      leading: leading,
    );
    final Widget? resolvedTrailing = m3eResolveListTrailing(
      context: context,
      trailing: trailing,
    );
    return <Widget>[
      if (resolvedLeading != null) ...<Widget>[
        IconTheme.merge(
          data: IconThemeData(
            color: listTheme.iconColor(scheme),
            size: listTheme.iconSize,
          ),
          child: resolvedLeading,
        ),
        SizedBox(width: listTheme.gap),
      ],
      Expanded(child: _buildText(theme)),
      if (resolvedTrailing != null) ...<Widget>[
        SizedBox(width: listTheme.gap),
        IconTheme.merge(
          data: IconThemeData(
            color: listTheme.iconColor(scheme),
            size: listTheme.iconSize,
          ),
          child: resolvedTrailing,
        ),
      ],
    ];
  }

  Widget _buildText(M3EThemeData theme) {
    final scheme = theme.colorScheme;
    final type = theme.typeScale;
    final listTheme = theme.listTheme.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (overline != null)
          Text(overline!, style: listTheme.overlineStyle(type, scheme)),
        Text(
          headline,
          style: listTheme.headlineStyle(type, scheme),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (supportingText != null)
          Text(
            supportingText!,
            style: listTheme.supportingStyle(type, scheme),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  bool get _isThreeLine => supportingText != null && overline != null;
}
