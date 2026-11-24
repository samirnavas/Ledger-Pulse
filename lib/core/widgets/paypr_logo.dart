import 'package:flutter/widgets.dart';

/// The official Paypr mark on a surface that preserves its contrast.
class PayprLogo extends StatelessWidget {
  static const backgroundColor = Color(0xFF030303);

  const PayprLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size / 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: Image.asset(
        'assets/icons/paypr_logo.png',
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    );
  }
}
