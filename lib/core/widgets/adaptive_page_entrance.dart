import 'package:flutter/material.dart';

/// Platform-adaptive page entrance transition wrapper.
class AdaptivePageEntrance extends StatelessWidget {
  final Widget child;

  const AdaptivePageEntrance({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
