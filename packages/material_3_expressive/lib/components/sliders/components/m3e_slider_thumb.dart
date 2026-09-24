import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/components/sliders/m3e_sliders.dart'
    show M3ERangeSlider, M3ESlider;
import 'package:material_3_expressive/material_3_expressive.dart'
    show M3ERangeSlider, M3ESlider;

import '../../../foundations/foundations.dart';
import '../res/m3e_slider_tokens.dart';

/// Expressive bar handle for [M3ESlider] / [M3ERangeSlider].
///
/// Shrinks along its thickness axis while [pressed]. When [focused], draws a
/// concentric outline for keyboard / traditional focus highlighting.
class M3ESliderThumb extends StatelessWidget {
  /// M3ESliderThumb.
  const M3ESliderThumb({
    required this.color,
    required this.pressed,
    this.focused = false,
    this.axis = Axis.horizontal,
    this.width,
    this.height,
    this.pressedThickness,
    super.key,
  });

  /// color.

  final Color color;

  /// pressed.
  final bool pressed;

  /// Whether to show the keyboard focus outline.
  final bool focused;

  /// axis.
  final Axis axis;

  /// Resting thumb width (cross-axis for vertical). Defaults to token sizes.
  final double? width;

  /// Resting thumb height (main-axis for vertical). Defaults to token sizes.
  final double? height;

  /// Pressed thickness along the short axis. Defaults to token pressed width.
  final double? pressedThickness;

  @override
  Widget build(BuildContext context) {
    final vertical = axis == Axis.vertical;
    final double restingW =
        width ??
        (vertical
            ? M3ESliderTokens.verticalHandleWidth
            : M3ESliderTokens.handleWidth);
    final double restingH =
        height ??
        (vertical
            ? M3ESliderTokens.verticalHandleHeight
            : M3ESliderTokens.handleHeight);
    final double pressedT =
        pressedThickness ?? M3ESliderTokens.pressedHandleWidth;

    final w = vertical ? restingW : (pressed ? pressedT : restingW);
    final h = vertical ? (pressed ? pressedT : restingH) : restingH;
    final radius = math.max(w, h) / 2;

    Widget thumb = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    if (!focused) {
      return thumb;
    }

    final M3EFocusRingTheme ring = M3EFocusRing.themeOf(context);
    final Color ringColor = ring.resolveColor(M3ETheme.of(context).colorScheme);
    // Stroke is centered on the inflated edge, so half of it eats into the gap.
    final double inflate = 2 * ring.gap + ring.width;
    final double ringW = w + inflate;
    final double ringH = h + inflate;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          width: ringW,
          height: ringH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(math.max(ringW, ringH) / 2),
            border: Border.all(color: ringColor, width: ring.width),
          ),
        ),
        thumb,
      ],
    );
  }
}
