import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Paypr mark with contrast adapted to the surrounding theme.
class PayprLogo extends StatelessWidget {
  const PayprLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SvgPicture.asset(
      'assets/icons/paypr_black.svg',
      width: size * 253 / 336,
      height: size,
      colorMapper: isDark ? const _DarkLogoColorMapper() : null,
      excludeFromSemantics: true,
    );
  }
}

class _DarkLogoColorMapper extends ColorMapper {
  const _DarkLogoColorMapper();

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    return color == Colors.black ? Colors.white : color;
  }
}
