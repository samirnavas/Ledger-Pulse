import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../foundations/foundations.dart';
import '../../cards/enums/m3e_card_variant.dart';
import 'm3e_list_reorder_state.dart';
import 'm3e_list_selection_state.dart';

/// Theme values for `M3EListItem`.
@immutable
class M3EListItemTheme {
  /// M3EListItemTheme.
  const M3EListItemTheme({
    this.horizontalPadding = 16,
    this.verticalPadding = 8,
    this.threeLineVerticalPadding = 12,
    this.minHeight = 40,
    this.iconSize = 24,
    this.gap = 16,
    this.variant = M3ECardVariant.filled,
    this.border,
  });

  /// defaults.

  static const M3EListItemTheme defaults = M3EListItemTheme();

  /// horizontalPadding.

  final double horizontalPadding;

  /// verticalPadding.
  final double verticalPadding;

  /// threeLineVerticalPadding.
  final double threeLineVerticalPadding;

  /// minHeight.
  final double minHeight;

  /// iconSize.
  final double iconSize;

  /// gap.
  final double gap;

  /// Card variant for standalone list items.
  final M3ECardVariant variant;

  /// Optional card outline; null keeps the variant default.
  final BorderSide? border;

  /// selectedColor.

  Color selectedColor(M3EColorScheme scheme) => scheme.secondaryContainer;

  /// iconColor.

  Color iconColor(M3EColorScheme scheme) => scheme.onSurfaceVariant;

  /// overlineStyle.

  TextStyle overlineStyle(M3ETypeScale type, M3EColorScheme scheme) =>
      type.labelSmall.copyWith(color: scheme.onSurfaceVariant);

  /// headlineStyle.

  TextStyle headlineStyle(M3ETypeScale type, M3EColorScheme scheme) =>
      type.bodyLarge.copyWith(color: scheme.onSurface);

  /// supportingStyle.

  TextStyle supportingStyle(M3ETypeScale type, M3EColorScheme scheme) =>
      type.bodyMedium.copyWith(color: scheme.onSurfaceVariant);

  /// copyWith.

  M3EListItemTheme copyWith({
    double? horizontalPadding,
    double? verticalPadding,
    double? threeLineVerticalPadding,
    double? minHeight,
    double? iconSize,
    double? gap,
    M3ECardVariant? variant,
    BorderSide? border,
  }) {
    return M3EListItemTheme(
      horizontalPadding: horizontalPadding ?? this.horizontalPadding,
      verticalPadding: verticalPadding ?? this.verticalPadding,
      threeLineVerticalPadding:
          threeLineVerticalPadding ?? this.threeLineVerticalPadding,
      minHeight: minHeight ?? this.minHeight,
      iconSize: iconSize ?? this.iconSize,
      gap: gap ?? this.gap,
      variant: variant ?? this.variant,
      border: border ?? this.border,
    );
  }
}

/// Theme values for `M3ECardList`.
@immutable
class M3EListCardListTheme {
  /// defaultOuterRadius.
  static const double defaultOuterRadius = 24;

  /// defaultInnerRadius.
  static const double defaultInnerRadius = 4;

  /// defaultGap.
  static const double defaultGap = 4;

  /// defaultItemPadding.
  static const EdgeInsets defaultItemPadding = EdgeInsets.all(12);

  /// M3EListCardListTheme.

  const M3EListCardListTheme({
    this.outerRadius = defaultOuterRadius,
    this.innerRadius = defaultInnerRadius,
    this.gap = defaultGap,
    this.itemPadding = defaultItemPadding,
    this.variant = M3ECardVariant.filled,
    this.border,
    this.radiusSpring = M3EMotion.expressiveSpatialDefault,
  });

  /// defaults.

  static const M3EListCardListTheme defaults = M3EListCardListTheme();

  /// outerRadius.

  final double outerRadius;

  /// innerRadius.
  final double innerRadius;

  /// gap.
  final double gap;

  /// itemPadding.
  final EdgeInsetsGeometry itemPadding;

  /// Card variant for each card-list item.
  final M3ECardVariant variant;

  /// Optional card outline; null keeps the variant default.
  final BorderSide? border;

  /// Corner-radius morph spring for card list items.
  final M3ESpring radiusSpring;

  /// backgroundColor.

  Color backgroundColor(M3EColorScheme scheme) =>
      scheme.surfaceContainerHighest;

  /// copyWith.

  M3EListCardListTheme copyWith({
    double? outerRadius,
    double? innerRadius,
    double? gap,
    EdgeInsetsGeometry? itemPadding,
    M3ECardVariant? variant,
    BorderSide? border,
    M3ESpring? radiusSpring,
  }) {
    return M3EListCardListTheme(
      outerRadius: outerRadius ?? this.outerRadius,
      innerRadius: innerRadius ?? this.innerRadius,
      gap: gap ?? this.gap,
      itemPadding: itemPadding ?? this.itemPadding,
      variant: variant ?? this.variant,
      border: border ?? this.border,
      radiusSpring: radiusSpring ?? this.radiusSpring,
    );
  }
}

/// Theme values for dismissible list widgets.
///
/// Stack geometry ([defaultOuterRadius], [defaultInnerRadius], [defaultGap],
/// [defaultItemPadding]) matches [M3EListCardListTheme] so card and dismissible
/// lists share the same item layout defaults.
@immutable
class M3EListDismissibleTheme {
  /// defaultOuterRadius.
  static const double defaultOuterRadius =
      M3EListCardListTheme.defaultOuterRadius;

  /// defaultInnerRadius.
  static const double defaultInnerRadius =
      M3EListCardListTheme.defaultInnerRadius;

  /// defaultGap.
  static const double defaultGap = M3EListCardListTheme.defaultGap;

  /// defaultActionGap.
  ///
  /// Matches [defaultActionSpacing] / [defaultActionEdgePadding] so the gap
  /// between actions equals the gap between actions and the list item.
  static const double defaultActionGap = 2;

  /// defaultActionSpacing.
  static const double defaultActionSpacing = 2;

  /// defaultActionEdgePadding.
  static const double defaultActionEdgePadding = 2;

  /// Fraction of actions width at which the preview snaps open on release.
  static const double defaultActionPreviewThreshold = 0.35;

  /// Extra drag past the actions width before rubber-band overdrag.
  static const double defaultActionOverdragExtent = 24;

  /// Vertical inset subtracted from the row height for action pills.
  static const double defaultActionVerticalInset = 8;

  /// Minimum action / dismiss pill height.
  static const double defaultActionMinHeight = 28;

  /// Minimum visual width for action pills (keeps icons inside while revealing).
  static const double defaultActionMinWidth = 40;

  /// defaultDismissThreshold.
  static const double defaultDismissThreshold = 0.2;

  /// defaultNeighbourPull.
  static const double defaultNeighbourPull = 8;

  /// defaultNeighbourReach.
  static const int defaultNeighbourReach = 3;

  /// defaultBackgroundBorderRadius.
  static const double defaultBackgroundBorderRadius = 100;

  /// defaultCollapseSpeed.
  static const double defaultCollapseSpeed = 50;

  /// defaultItemPadding.
  static const EdgeInsets defaultItemPadding =
      M3EListCardListTheme.defaultItemPadding;

  /// M3EListDismissibleTheme.

  const M3EListDismissibleTheme({
    this.outerRadius = defaultOuterRadius,
    this.innerRadius = defaultInnerRadius,
    this.gap = defaultGap,
    this.actionGap = defaultActionGap,
    this.actionSpacing = defaultActionSpacing,
    this.actionEdgePadding = defaultActionEdgePadding,
    this.actionPreviewThreshold = defaultActionPreviewThreshold,
    this.actionOverdragExtent = defaultActionOverdragExtent,
    this.actionVerticalInset = defaultActionVerticalInset,
    this.actionMinHeight = defaultActionMinHeight,
    this.actionMinWidth = defaultActionMinWidth,
    this.dismissThreshold = defaultDismissThreshold,
    this.neighbourPull = defaultNeighbourPull,
    this.neighbourReach = defaultNeighbourReach,
    this.backgroundBorderRadius = defaultBackgroundBorderRadius,
    this.collapseSpeed = defaultCollapseSpeed,
    this.itemPadding = defaultItemPadding,
    this.neighbourSpring = const M3ESpring(stiffness: 800, damping: 0.7),
    this.reEngageSpring = const M3ESpring(stiffness: 800, damping: 0.9),
    this.detachPushSpring = const M3ESpring(stiffness: 800, damping: 0.95),
    this.roundnessSnapSpring = const M3ESpring(stiffness: 1000, damping: 0.4),
    this.springBackSpring = const M3ESpring(stiffness: 380, damping: 0.6),
    this.flySpring = const M3ESpring(stiffness: 400, damping: 0.8),
    this.collapseDamping = 0.8,
  });

  /// defaults.

  static const M3EListDismissibleTheme defaults = M3EListDismissibleTheme();

  /// outerRadius.

  final double outerRadius;

  /// innerRadius.
  final double innerRadius;

  /// gap.
  final double gap;

  /// Horizontal gap between a swiped card and its revealed action background.
  final double actionGap;

  /// Spacing between revealed swipe action buttons.
  final double actionSpacing;

  /// Horizontal padding at the leading / trailing edges of the action row.
  final double actionEdgePadding;

  /// Fraction of actions width required to snap the preview open on release.
  final double actionPreviewThreshold;

  /// Extra pixels past the actions width before rubber-band overdrag.
  final double actionOverdragExtent;

  /// Vertical inset subtracted from the list row height for action pills.
  final double actionVerticalInset;

  /// Minimum height for action / dismiss pills.
  final double actionMinHeight;

  /// Minimum visual width for action pills while revealing / hiding.
  final double actionMinWidth;

  /// dismissThreshold.
  final double dismissThreshold;

  /// neighbourPull.
  final double neighbourPull;

  /// neighbourReach.
  final int neighbourReach;

  /// backgroundBorderRadius.
  final double backgroundBorderRadius;

  /// collapseSpeed.
  final double collapseSpeed;

  /// itemPadding.
  final EdgeInsetsGeometry itemPadding;

  /// Neighbour fraction spring (base; stiffness scaled by multiplier).
  final M3ESpring neighbourSpring;

  /// Roundness re-engage spring (base; stiffness scaled by multiplier).
  final M3ESpring reEngageSpring;

  /// Detach push spring (base; stiffness scaled by multiplier).
  final M3ESpring detachPushSpring;

  /// Roundness snap spring (base; stiffness scaled by multiplier).
  final M3ESpring roundnessSnapSpring;

  /// Drag spring-back spring (base; stiffness scaled by speedMul).
  final M3ESpring springBackSpring;

  /// Fly-away spring (base; stiffness scaled by speedMul).
  final M3ESpring flySpring;

  /// Damping for collapse; stiffness still uses [collapseSpeed] × speedMul.
  final double collapseDamping;

  /// backgroundColor.

  Color backgroundColor(M3EColorScheme scheme) =>
      scheme.surfaceContainerHighest;

  /// copyWith.

  M3EListDismissibleTheme copyWith({
    double? outerRadius,
    double? innerRadius,
    double? gap,
    double? actionGap,
    double? actionSpacing,
    double? actionEdgePadding,
    double? actionPreviewThreshold,
    double? actionOverdragExtent,
    double? actionVerticalInset,
    double? actionMinHeight,
    double? actionMinWidth,
    double? dismissThreshold,
    double? neighbourPull,
    int? neighbourReach,
    double? backgroundBorderRadius,
    double? collapseSpeed,
    EdgeInsetsGeometry? itemPadding,
    M3ESpring? neighbourSpring,
    M3ESpring? reEngageSpring,
    M3ESpring? detachPushSpring,
    M3ESpring? roundnessSnapSpring,
    M3ESpring? springBackSpring,
    M3ESpring? flySpring,
    double? collapseDamping,
  }) {
    return M3EListDismissibleTheme(
      outerRadius: outerRadius ?? this.outerRadius,
      innerRadius: innerRadius ?? this.innerRadius,
      gap: gap ?? this.gap,
      actionGap: actionGap ?? this.actionGap,
      actionSpacing: actionSpacing ?? this.actionSpacing,
      actionEdgePadding: actionEdgePadding ?? this.actionEdgePadding,
      actionPreviewThreshold:
          actionPreviewThreshold ?? this.actionPreviewThreshold,
      actionOverdragExtent: actionOverdragExtent ?? this.actionOverdragExtent,
      actionVerticalInset: actionVerticalInset ?? this.actionVerticalInset,
      actionMinHeight: actionMinHeight ?? this.actionMinHeight,
      actionMinWidth: actionMinWidth ?? this.actionMinWidth,
      dismissThreshold: dismissThreshold ?? this.dismissThreshold,
      neighbourPull: neighbourPull ?? this.neighbourPull,
      neighbourReach: neighbourReach ?? this.neighbourReach,
      backgroundBorderRadius:
          backgroundBorderRadius ?? this.backgroundBorderRadius,
      collapseSpeed: collapseSpeed ?? this.collapseSpeed,
      itemPadding: itemPadding ?? this.itemPadding,
      neighbourSpring: neighbourSpring ?? this.neighbourSpring,
      reEngageSpring: reEngageSpring ?? this.reEngageSpring,
      detachPushSpring: detachPushSpring ?? this.detachPushSpring,
      roundnessSnapSpring: roundnessSnapSpring ?? this.roundnessSnapSpring,
      springBackSpring: springBackSpring ?? this.springBackSpring,
      flySpring: flySpring ?? this.flySpring,
      collapseDamping: collapseDamping ?? this.collapseDamping,
    );
  }
}

/// Theme values for expandable list widgets.
///
/// Stack geometry ([defaultOuterRadius], [defaultInnerRadius], [defaultGap])
/// matches [M3EListCardListTheme].
@immutable
class M3EListExpandableTheme {
  /// defaultOuterRadius.
  static const double defaultOuterRadius =
      M3EListCardListTheme.defaultOuterRadius;

  /// defaultInnerRadius.
  static const double defaultInnerRadius =
      M3EListCardListTheme.defaultInnerRadius;

  /// defaultHoverRadius.
  static const double defaultHoverRadius = 10;

  /// defaultPressedRadius.
  static const double defaultPressedRadius = 4;

  /// defaultGap.
  static const double defaultGap = M3EListCardListTheme.defaultGap;

  /// defaultTitleSubtitleGap.
  static const double defaultTitleSubtitleGap = 4;

  /// defaultHeaderPadding.
  ///
  /// Matches [M3EListCardListTheme.defaultItemPadding] so expandable headers
  /// align with card / dismissible list rows.
  static const EdgeInsets defaultHeaderPadding =
      M3EListCardListTheme.defaultItemPadding;

  /// defaultBodyPadding.
  static const EdgeInsets defaultBodyPadding = EdgeInsets.fromLTRB(
    16,
    0,
    16,
    20,
  );

  /// defaultIconPadding.
  static const EdgeInsets defaultIconPadding = EdgeInsets.all(8);

  /// Width of the vertical pill behind the trailing expand icon.
  ///
  /// Height fills the header content area. The box size is the same when
  /// collapsed or expanded; only the fill is shown while expanded. Set to `0`
  /// to disable the chrome entirely.
  static const double defaultExpandedIconBackgroundSize = 32;

  /// defaultIconRotationAngle.
  static const double defaultIconRotationAngle = math.pi;

  /// defaultExpandTooltip.
  static const String defaultExpandTooltip = 'Expand';

  /// defaultCollapseTooltip.
  static const String defaultCollapseTooltip = 'Collapse';

  /// M3EListExpandableTheme.

  const M3EListExpandableTheme({
    this.outerRadius = defaultOuterRadius,
    this.innerRadius = defaultInnerRadius,
    this.hoverRadius = defaultHoverRadius,
    this.pressedRadius = defaultPressedRadius,
    this.gap = defaultGap,
    this.titleSubtitleGap = defaultTitleSubtitleGap,
    this.headerPadding = defaultHeaderPadding,
    this.bodyPadding = defaultBodyPadding,
    this.iconPadding = defaultIconPadding,
    this.expandedIconBackgroundSize = defaultExpandedIconBackgroundSize,
    this.expandedIconBackground,
    this.iconRotationAngle = defaultIconRotationAngle,
    this.expandTooltip = defaultExpandTooltip,
    this.collapseTooltip = defaultCollapseTooltip,
    this.expandMotion = M3EMotion.expressiveSpatialDefault,
    this.collapseMotion = M3EMotion.expressiveSpatialDefault,
    this.allowMultipleExpanded = false,
  });

  /// defaults.

  static const M3EListExpandableTheme defaults = M3EListExpandableTheme();

  /// outerRadius.

  final double outerRadius;

  /// innerRadius.
  final double innerRadius;

  /// hoverRadius.
  final double hoverRadius;

  /// pressedRadius.
  final double pressedRadius;

  /// gap.
  final double gap;

  /// titleSubtitleGap.
  final double titleSubtitleGap;

  /// headerPadding.
  final EdgeInsetsGeometry headerPadding;

  /// bodyPadding.
  final EdgeInsetsGeometry bodyPadding;

  /// iconPadding.
  final EdgeInsetsGeometry iconPadding;

  /// Width of the vertical pill behind the trailing expand icon.
  ///
  /// Height fills the header content area. Size is stable across expand /
  /// collapse; only the fill toggles. Set to `0` to disable.
  final double expandedIconBackgroundSize;

  /// Fill for the expanded trailing-icon chrome.
  ///
  /// When null, resolves to [M3EColorScheme.surfaceContainerLowest].
  final Color? expandedIconBackground;

  /// iconRotationAngle.
  final double iconRotationAngle;

  /// expandTooltip.
  final String expandTooltip;

  /// collapseTooltip.
  final String collapseTooltip;

  /// expandMotion.
  final M3ESpring expandMotion;

  /// collapseMotion.
  final M3ESpring collapseMotion;

  /// allowMultipleExpanded.
  final bool allowMultipleExpanded;

  /// backgroundColor.

  Color backgroundColor(M3EColorScheme scheme) =>
      scheme.surfaceContainerHighest;

  /// Expanded trailing-icon chrome color.
  Color resolvedExpandedIconBackground(M3EColorScheme scheme) =>
      expandedIconBackground ?? scheme.surfaceContainerLowest;

  /// copyWith.

  M3EListExpandableTheme copyWith({
    double? outerRadius,
    double? innerRadius,
    double? hoverRadius,
    double? pressedRadius,
    double? gap,
    double? titleSubtitleGap,
    EdgeInsetsGeometry? headerPadding,
    EdgeInsetsGeometry? bodyPadding,
    EdgeInsetsGeometry? iconPadding,
    double? expandedIconBackgroundSize,
    Color? expandedIconBackground,
    double? iconRotationAngle,
    String? expandTooltip,
    String? collapseTooltip,
    M3ESpring? expandMotion,
    M3ESpring? collapseMotion,
    bool? allowMultipleExpanded,
  }) {
    return M3EListExpandableTheme(
      outerRadius: outerRadius ?? this.outerRadius,
      innerRadius: innerRadius ?? this.innerRadius,
      hoverRadius: hoverRadius ?? this.hoverRadius,
      pressedRadius: pressedRadius ?? this.pressedRadius,
      gap: gap ?? this.gap,
      titleSubtitleGap: titleSubtitleGap ?? this.titleSubtitleGap,
      headerPadding: headerPadding ?? this.headerPadding,
      bodyPadding: bodyPadding ?? this.bodyPadding,
      iconPadding: iconPadding ?? this.iconPadding,
      expandedIconBackgroundSize:
          expandedIconBackgroundSize ?? this.expandedIconBackgroundSize,
      expandedIconBackground:
          expandedIconBackground ?? this.expandedIconBackground,
      iconRotationAngle: iconRotationAngle ?? this.iconRotationAngle,
      expandTooltip: expandTooltip ?? this.expandTooltip,
      collapseTooltip: collapseTooltip ?? this.collapseTooltip,
      expandMotion: expandMotion ?? this.expandMotion,
      collapseMotion: collapseMotion ?? this.collapseMotion,
      allowMultipleExpanded:
          allowMultipleExpanded ?? this.allowMultipleExpanded,
    );
  }
}

/// Theme values for list-family widgets.
@immutable
class M3EListTheme extends M3EThemeExtension<M3EListTheme> {
  /// M3EListTheme.
  const M3EListTheme({
    this.item = M3EListItemTheme.defaults,
    this.cardList = M3EListCardListTheme.defaults,
    this.dismissible = M3EListDismissibleTheme.defaults,
    this.expandable = M3EListExpandableTheme.defaults,
    this.selection = M3EListSelectionState.defaults,
    this.reorder = M3EListReorderState.defaults,
  });

  /// defaults.

  static const M3EListTheme defaults = M3EListTheme();

  /// item.

  final M3EListItemTheme item;

  /// cardList.
  final M3EListCardListTheme cardList;

  /// dismissible.
  final M3EListDismissibleTheme dismissible;

  /// expandable.
  final M3EListExpandableTheme expandable;

  /// Selection visuals and triggers for list variants.
  final M3EListSelectionState selection;

  /// Reorder visuals and motion for list variants.
  final M3EListReorderState reorder;

  @override
  M3EListTheme copyWith({
    M3EListItemTheme? item,
    M3EListCardListTheme? cardList,
    M3EListDismissibleTheme? dismissible,
    M3EListExpandableTheme? expandable,
    M3EListSelectionState? selection,
    M3EListReorderState? reorder,
  }) {
    return M3EListTheme(
      item: item ?? this.item,
      cardList: cardList ?? this.cardList,
      dismissible: dismissible ?? this.dismissible,
      expandable: expandable ?? this.expandable,
      selection: selection ?? this.selection,
      reorder: reorder ?? this.reorder,
    );
  }

  @override
  M3EListTheme lerp(M3EListTheme? other, double t) {
    if (other is! M3EListTheme) {
      return this;
    }
    if (t < 0.5) {
      return this;
    }
    return other;
  }
}
