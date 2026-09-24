import 'package:flutter/widgets.dart';

import '../../foundations/foundations.dart';
import 'enums/m3e_card_variant.dart';
import 'styles/m3e_card_theme.dart';

export 'enums/m3e_card_variant.dart';
export 'styles/m3e_card_theme.dart';

/// A Material 3 Expressive card.
///
/// A surface for a single subject's content and actions. When [onPressed] is
/// provided the card becomes interactive with hover/press state layers and, for
/// the elevated variant, a hover elevation lift.
class M3ECard extends StatelessWidget {
  /// M3ECard.
  const M3ECard({
    required this.child,
    this.variant = M3ECardVariant.elevated,
    this.onPressed,
    this.onLongPress,
    this.enabled = true,
    this.padding = const EdgeInsets.all(16),
    this.clipBehavior = Clip.antiAlias,
    this.borderRadius,
    this.color,
    this.elevation,
    this.border,
    this.animationDuration,
    this.animationCurve,
    this.width,
    this.surfaceKey,
    this.mouseCursor,
    this.semanticLabel,
    this.haptic = M3EHapticFeedback.none,
    this.onStateChanged,
    super.key,
  });

  /// child.

  final Widget child;

  /// variant.
  final M3ECardVariant variant;

  /// onPressed.
  final VoidCallback? onPressed;

  /// onLongPress.
  final VoidCallback? onLongPress;

  /// When false, hover/press state layers are suppressed even if callbacks are set.
  final bool enabled;

  /// padding.
  final EdgeInsetsGeometry padding;

  /// clipBehavior.
  final Clip clipBehavior;

  /// borderRadius.
  final BorderRadius? borderRadius;

  /// color.
  final Color? color;

  /// elevation.
  final double? elevation;

  /// border.
  final BorderSide? border;

  /// animationDuration.
  final Duration? animationDuration;

  /// animationCurve.
  final Curve? animationCurve;

  /// width.
  final double? width;

  /// surfaceKey.
  final Key? surfaceKey;

  /// mouseCursor.
  final MouseCursor? mouseCursor;

  /// semanticLabel.
  final String? semanticLabel;

  /// haptic.
  final M3EHapticFeedback haptic;

  /// onStateChanged.
  final ValueChanged<M3EInteractionState>? onStateChanged;

  bool get _hasCallbacks => onPressed != null || onLongPress != null;

  bool get _isInteractive => enabled && _hasCallbacks;

  @override
  Widget build(BuildContext context) {
    return M3EComponentTheme(builder: _buildCard);
  }

  Widget _buildCard(BuildContext context) {
    final cardTheme = M3ETheme.of(context).cardTheme;
    final resolvedBorderRadius = borderRadius ?? cardTheme.borderRadius;
    final shape = RoundedRectangleBorder(borderRadius: resolvedBorderRadius);

    if (!_hasCallbacks) {
      return _buildSurface(
        context,
        cardTheme,
        resolvedBorderRadius,
        shape,
        const M3EInteractionState(),
      );
    }

    return M3ETappable(
      enabled: enabled,
      onTap: onPressed,
      onLongPress: onLongPress,
      mouseCursor: mouseCursor,
      semanticLabel: semanticLabel,
      onStateChanged: onStateChanged,
      materialInk: true,
      haptic: haptic,
      builder: (BuildContext context, M3EInteractionState state) {
        return _buildSurface(
          context,
          cardTheme,
          resolvedBorderRadius,
          shape,
          enabled ? state : const M3EInteractionState(),
        );
      },
    );
  }

  Widget _buildSurface(
    BuildContext context,
    M3ECardTheme cardTheme,
    BorderRadius resolvedBorderRadius,
    RoundedRectangleBorder shape,
    M3EInteractionState state,
  ) {
    final scheme = M3ETheme.of(context).colorScheme;
    final double resolvedElevation =
        elevation ?? cardTheme.elevation(variant, hovered: state.hovered);
    final BoxBorder? resolvedBorder = border != null
        ? Border.all(color: border!.color, width: border!.width)
        : (variant == M3ECardVariant.outlined
              ? Border.all(color: cardTheme.outlineColor(scheme))
              : null);

    Widget decoratedChild = Padding(padding: padding, child: child);

    Widget surface = AnimatedContainer(
      key: surfaceKey,
      width: width,
      duration: animationDuration ?? M3EMotion.short4,
      curve: animationCurve ?? M3EMotion.standard,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: color ?? cardTheme.backgroundColor(scheme, variant),
        borderRadius: resolvedBorderRadius,
        border: resolvedBorder,
        boxShadow: M3EElevation.shadows(
          resolvedElevation,
          shadowColor: scheme.shadow,
        ),
      ),
      child: _isInteractive
          ? M3EStateLayerOverlay(
              state: state,
              color: scheme.onSurface,
              shape: shape,
              child: SizedBox(
                width: width ?? double.infinity,
                child: decoratedChild,
              ),
            )
          : decoratedChild,
    );

    if (!_isInteractive) {
      return surface;
    }

    // Keyboard focus ring follows the card's current outer radius.
    return M3EFocusRing(
      focused: state.focused,
      radius: resolvedBorderRadius,
      child: surface,
    );
  }
}
