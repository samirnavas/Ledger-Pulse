import 'package:flutter/widgets.dart';

import '../../../foundations/foundations.dart';
import '../buttons/utils/m3e_button_gradient_layer.dart';
import 'components/m3e_segment_divider.dart';
import 'models/m3e_segment.dart';
import 'styles/m3e_segmented_button_theme.dart';

export 'models/m3e_segment.dart';
export 'styles/m3e_segmented_button_theme.dart';

/// A Material 3 Expressive segmented button.
///
/// Presents 2-5 connected [M3ESegment]s for selecting options, switching views
/// or sorting. Supports single or multiple selection and shows a check icon on
/// selected segments.
class M3ESegmentedButton<T> extends StatefulWidget {
  /// M3ESegmentedButton.
  const M3ESegmentedButton({
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.multiSelect = false,
    this.showSelectedIcon = true,
    super.key,
  }) : assert(segments.length >= 2, 'A segmented button needs 2+ segments.');

  /// segments.

  final List<M3ESegment<T>> segments;

  /// selected.
  final Set<T> selected;

  /// onSelectionChanged.
  final ValueChanged<Set<T>> onSelectionChanged;

  /// multiSelect.
  final bool multiSelect;

  /// showSelectedIcon.
  final bool showSelectedIcon;

  @override
  State<M3ESegmentedButton<T>> createState() => _M3ESegmentedButtonState<T>();

  void _handleTap(T value) {
    final next = Set<T>.of(selected);
    if (multiSelect) {
      if (next.contains(value)) {
        next.remove(value);
      } else {
        next.add(value);
      }
    } else {
      next
        ..clear()
        ..add(value);
    }
    onSelectionChanged(next);
  }
}

class _M3ESegmentedButtonState<T> extends State<M3ESegmentedButton<T>> {
  /// Segment row. Dividers sample their gradient across this box.
  final GlobalKey _rowKey = GlobalKey();

  /// Segment currently showing a keyboard focus ring, if any.
  final ValueNotifier<int?> _focusedIndex = ValueNotifier<int?>(null);

  @override
  void dispose() {
    M3EFocusInteraction.instance.removeListener(_onFocusInteractionChanged);
    _focusedIndex.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    M3EFocusInteraction.instance.addListener(_onFocusInteractionChanged);
  }

  void _onFocusInteractionChanged() {
    if (!M3EFocusInteraction.instance.ringsAllowed &&
        _focusedIndex.value != null) {
      _focusedIndex.value = null;
    }
  }

  void _handleSegmentFocus(int index, {required bool focused}) {
    if (focused && M3EFocusInteraction.instance.ringsAllowed) {
      _focusedIndex.value = index;
    } else if (_focusedIndex.value == index) {
      _focusedIndex.value = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return M3EComponentTheme(builder: _buildButton);
  }

  Widget _buildButton(BuildContext context) {
    final theme = M3ETheme.of(context);
    final segmentedButtonTheme = theme.segmentedButtonTheme;
    final scheme = theme.colorScheme;
    final borderRadius = segmentedButtonTheme.borderRadius;

    final Color outlineColor = segmentedButtonTheme.outline(scheme);
    Widget ring = Container(
      height: segmentedButtonTheme.height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: segmentedButtonTheme.outlineGradient == null
            ? Border.all(
                color: outlineColor,
                width: segmentedButtonTheme.borderWidth,
              )
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          ClipRRect(
            borderRadius: borderRadius,
            child: Row(
              key: _rowKey,
              mainAxisSize: MainAxisSize.min,
              children: _buildSegments(context, segmentedButtonTheme),
            ),
          ),
          // Rings live above the group clip so they stay visible on the
          // outer edges and over neighbouring segment fills.
          Positioned.fill(child: _buildFocusRingOverlay(segmentedButtonTheme)),
        ],
      ),
    );
    final Gradient? outlineGradient = segmentedButtonTheme.outlineGradient;
    if (outlineGradient != null) {
      ring = m3eGradientOutlineLayer(
        clipRadius: borderRadius,
        gradient: outlineGradient,
        width: segmentedButtonTheme.borderWidth,
        child: ring,
      );
    }
    return ring;
  }

  List<Widget> _buildSegments(
    BuildContext context,
    M3ESegmentedButtonTheme segmentedButtonTheme,
  ) {
    final theme = M3ETheme.of(context);
    final children = <Widget>[];
    for (var i = 0; i < widget.segments.length; i++) {
      if (i > 0) {
        children.add(
          M3ESegmentDivider(
            hostKey: _rowKey,
            width: segmentedButtonTheme.borderWidth,
            color: segmentedButtonTheme.divider(theme.colorScheme),
            gradient: segmentedButtonTheme.dividerGradient,
          ),
        );
      }
      children.add(
        Flexible(
          child: _M3ESegmentTile<T>(
            segmentedButtonTheme: segmentedButtonTheme,
            index: i,
            parent: widget,
            onFocusChanged: (bool focused) =>
                _handleSegmentFocus(i, focused: focused),
          ),
        ),
      );
    }
    return children;
  }

  /// Mirrors the segment row's flex structure so the ring of the focused
  /// segment lines up with it without measuring anything.
  Widget _buildFocusRingOverlay(M3ESegmentedButtonTheme segmentedButtonTheme) {
    return IgnorePointer(
      child: ValueListenableBuilder<int?>(
        valueListenable: _focusedIndex,
        builder: (BuildContext context, int? focusedIndex, _) {
          if (focusedIndex == null) {
            return const SizedBox.shrink();
          }
          final TextDirection direction = Directionality.of(context);
          final slots = <Widget>[];
          for (var i = 0; i < widget.segments.length; i++) {
            if (i > 0) {
              slots.add(SizedBox(width: segmentedButtonTheme.borderWidth));
            }
            slots.add(
              Flexible(
                child: i == focusedIndex
                    ? M3EFocusRing(
                        focused: true,
                        radius: _segmentRadius(
                          segmentedButtonTheme,
                          i,
                          direction,
                        ),
                        child: const SizedBox.expand(),
                      )
                    : const SizedBox.expand(),
              ),
            );
          }
          return Row(children: slots);
        },
      ),
    );
  }

  /// Outer corners are rounded only where the segment meets the group edge.
  BorderRadius _segmentRadius(
    M3ESegmentedButtonTheme segmentedButtonTheme,
    int index,
    TextDirection direction,
  ) {
    final Radius outer = segmentedButtonTheme.borderRadius.topLeft;
    return BorderRadiusDirectional.horizontal(
      start: index == 0 ? outer : Radius.zero,
      end: index == widget.segments.length - 1 ? outer : Radius.zero,
    ).resolve(direction);
  }
}

class _M3ESegmentTile<T> extends StatelessWidget {
  const _M3ESegmentTile({
    required this.segmentedButtonTheme,
    required this.index,
    required this.parent,
    required this.onFocusChanged,
  });

  final M3ESegmentedButtonTheme segmentedButtonTheme;
  final int index;
  final M3ESegmentedButton<T> parent;

  /// Reports keyboard focus so the group can paint the ring above its clip.
  final ValueChanged<bool> onFocusChanged;

  @override
  Widget build(BuildContext context) {
    final M3ESegment<T> segment = parent.segments[index];
    final bool isSelected = parent.selected.contains(segment.value);

    return M3ETappable(
      onTap: () => parent._handleTap(segment.value),
      semanticLabel: segment.label,
      materialInk: true,
      onStateChanged: (M3EInteractionState state) =>
          onFocusChanged(state.focused),
      builder: (BuildContext context, M3EInteractionState state) {
        final resolvedScheme = M3ETheme.of(context).colorScheme;
        final Gradient? fgGradient = isSelected
            ? segmentedButtonTheme.selectedForegroundGradient
            : segmentedButtonTheme.unselectedForegroundGradient;
        final resolvedForeground = fgGradient != null
            ? m3eGradientForegroundSourceColor
            : segmentedButtonTheme.foregroundColor(
                resolvedScheme,
                selected: isSelected,
              );
        final Gradient? gradient = isSelected
            ? segmentedButtonTheme.selectedBackgroundGradient
            : segmentedButtonTheme.unselectedBackgroundGradient;
        final Color? solidBg = segmentedButtonTheme.backgroundColor(
          resolvedScheme,
          selected: isSelected,
        );
        return Container(
          width: double.infinity,
          height: segmentedButtonTheme.height,
          decoration: BoxDecoration(
            color: gradient == null ? solidBg : null,
            gradient: gradient,
          ),
          child: M3EStateLayerOverlay(
            state: state,
            color: resolvedForeground,
            shape: const RoundedRectangleBorder(),
            alignment: Alignment.center,
            child: SizedBox(
              width: double.infinity,
              height: segmentedButtonTheme.height,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: segmentedButtonTheme.segmentHorizontalPadding,
                  ),
                  child: _wrapForeground(
                    segmentedButtonTheme,
                    isSelected,
                    _buildLabel(
                      context,
                      segment,
                      resolvedForeground,
                      isSelected,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLabel(
    BuildContext context,
    M3ESegment<T> segment,
    Color foreground,
    bool selected,
  ) {
    final theme = M3ETheme.of(context);
    final Widget? leading = _resolveLeading(segment, foreground, selected);
    final children = <Widget>[
      if (leading != null) ...<Widget>[
        leading,
        SizedBox(width: segmentedButtonTheme.iconLabelGap),
      ],
      if (segment.label != null)
        Flexible(
          child: Text(
            segment.label!,
            style: theme.typeScale.labelLarge.copyWith(color: foreground),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: children,
    );
  }

  Widget _wrapForeground(
    M3ESegmentedButtonTheme theme,
    bool selected,
    Widget child,
  ) {
    final Gradient? gradient = selected
        ? theme.selectedForegroundGradient
        : theme.unselectedForegroundGradient;
    if (gradient == null) {
      return child;
    }
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect bounds) => gradient.createShader(bounds),
      child: child,
    );
  }

  Widget? _resolveLeading(M3ESegment<T> segment, Color foreground, bool sel) {
    if (sel && parent.showSelectedIcon) {
      return Icon(
        M3EIcons.check,
        size: segmentedButtonTheme.iconSize,
        color: foreground,
      );
    }
    if (segment.icon != null) {
      return IconTheme.merge(
        data: IconThemeData(
          color: foreground,
          size: segmentedButtonTheme.iconSize,
        ),
        child: segment.icon!,
      );
    }
    return null;
  }
}
