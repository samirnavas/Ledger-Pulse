import 'package:flutter/widgets.dart';

/// Nesting hints for a card list under an expanded expandable row.
///
/// When [closeBottom] is true (parent is last / single), the nested list's
/// last row should use outer bottom radii so the group visually closes.
class M3EExpandableNestScope extends InheritedWidget {
  /// Creates a nest scope for an expandable sublist.
  const M3EExpandableNestScope({
    required this.closeBottom,
    required this.outerRadius,
    required super.child,
    super.key,
  });

  /// Whether the nested list should close the group with outer bottom radii.
  final bool closeBottom;

  /// Outer corner radius to match the expandable parent.
  final double outerRadius;

  /// Nearest nest scope, if any.
  static M3EExpandableNestScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<M3EExpandableNestScope>();
  }

  @override
  bool updateShouldNotify(M3EExpandableNestScope oldWidget) {
    return closeBottom != oldWidget.closeBottom ||
        outerRadius != oldWidget.outerRadius;
  }
}
