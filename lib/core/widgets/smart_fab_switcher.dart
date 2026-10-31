import 'package:flutter/material.dart';

/// Animated FAB switcher for bottom navigation and screen state changes.
class SmartFabSwitcher extends StatelessWidget {
  final Widget? fab;

  const SmartFabSwitcher({
    super.key,
    this.fab,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: fab ?? const SizedBox.shrink(),
    );
  }
}
