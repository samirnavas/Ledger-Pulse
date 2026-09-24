import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

import '../../../foundations/foundations.dart';
import '../styles/m3e_list_reorder_state.dart';
import '../utils/m3e_expandable_spring_motion.dart';
import 'm3e_list_drag_proxy_scope.dart';
import 'm3e_list_reorder_exclude.dart';
import 'm3e_list_reorder_session_scope.dart';

/// Spring-driven reorderable list.
///
/// Layout slots stay fixed while dragging: the dragged row becomes an invisible
/// spacer, a floating proxy follows the pointer, and neighbors spring-shift to
/// open the destination gap (no layout-mutating placeholder widgets).
class M3EListReorderHost extends StatefulWidget {
  /// Creates a reorder host.
  const M3EListReorderHost({
    required this.itemCount,
    required this.itemBuilder,
    required this.onReorder,
    required this.reorderState,
    this.gap = 4,
    this.scrollable = false,
    this.controller,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    this.prepareDrag,
    this.onDragSettled,
    this.canStartDrag,
    super.key,
  });

  /// Number of items.
  final int itemCount;

  /// Builds each item at the given index.
  final IndexedWidgetBuilder itemBuilder;

  /// Called after a successful drop.
  final ReorderCallback onReorder;

  /// Reorder visuals / motion.
  final M3EListReorderState reorderState;

  /// Gap between items.
  final double gap;

  /// Whether to wrap in a [ListView].
  final bool scrollable;

  /// Scroll controller when [scrollable].
  final ScrollController? controller;

  /// Scroll physics when [scrollable].
  final ScrollPhysics? physics;

  /// Shrink-wrap when [scrollable].
  final bool shrinkWrap;

  /// List padding when [scrollable].
  final EdgeInsetsGeometry? padding;

  /// Called when a long-press drag is about to begin (before measuring).
  ///
  /// Awaited so callers can collapse expanded content before the drag extent
  /// is cached.
  final Future<void> Function(int index)? prepareDrag;

  /// Called after drag ends with the from/to indices (to == from if no move).
  ///
  /// Invoked after [onReorder] when the index changed.
  final void Function(int from, int to)? onDragSettled;

  /// When set, long-press only starts a drag if this returns true for the
  /// given index.
  final bool Function(int index)? canStartDrag;

  @override
  State<M3EListReorderHost> createState() => _M3EListReorderHostState();
}

class _M3EListReorderHostState extends State<M3EListReorderHost>
    with TickerProviderStateMixin {
  int? _dragIndex;
  int? _insertIndex;
  int? _activePointer;
  Offset? _pointerDownGlobal;
  Timer? _longPressTimer;
  final ValueNotifier<bool> _sessionActive = ValueNotifier<bool>(false);

  /// Finger delta from long-press start; updated without setState.
  final ValueNotifier<double> _dragDy = ValueNotifier<double>(0);

  final GlobalKey _stackKey = GlobalKey();
  final Map<int, GlobalKey> _keys = <int, GlobalKey>{};
  final Map<int, SingleMotionController> _offsets =
      <int, SingleMotionController>{};

  /// Cached item extent (height + gap) at drag start.
  double _dragExtent = 56;

  GlobalKey _keyFor(int index) => _keys.putIfAbsent(index, GlobalKey.new);

  SingleMotionController _offsetCtrl(int index) {
    return _offsets.putIfAbsent(
      index,
      () => SingleMotionController(
        motion: widget.reorderState.displaceMotion.toMotion(),
        vsync: this,
      ),
    );
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _sessionActive.dispose();
    _dragDy.dispose();
    for (final SingleMotionController c in _offsets.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _itemHeight(int index) {
    final box = _keyFor(index).currentContext?.findRenderObject() as RenderBox?;
    return box?.size.height ?? 56;
  }

  double _extent(int index) => _itemHeight(index) + widget.gap;

  /// Y of item [index] relative to the stack, ignoring transforms.
  double _slotTop(int index) {
    var top = 0.0;
    for (var i = 0; i < index; i++) {
      top += _extent(i);
    }
    return top;
  }

  void _cancelPendingLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _onPointerDown(int index, PointerDownEvent event) {
    if (!_canArmLongPress(index, event.position)) {
      return;
    }
    _activePointer = event.pointer;
    _pointerDownGlobal = event.position;
    _cancelPendingLongPress();
    _longPressTimer = Timer(
      kLongPressTimeout,
      () => _onLongPressArmed(index, event),
    );
  }

  bool _canArmLongPress(int index, Offset globalPosition) {
    if (_dragIndex != null) {
      return false;
    }
    if (widget.canStartDrag != null && !widget.canStartDrag!(index)) {
      return false;
    }
    return !_isOverReorderExclude(index, globalPosition);
  }

  void _onLongPressArmed(int index, PointerDownEvent event) {
    if (!mounted || _activePointer != event.pointer) {
      return;
    }
    if (widget.canStartDrag != null && !widget.canStartDrag!(index)) {
      return;
    }
    unawaited(_beginDrag(index, event.position, event.pointer));
  }

  /// True when [globalPosition] lies in a descendant [M3EListReorderExclude].
  bool _isOverReorderExclude(int index, Offset globalPosition) {
    final BuildContext? slotContext = _keyFor(index).currentContext;
    if (slotContext is! Element) {
      return false;
    }
    var hit = false;
    void visit(Element element) {
      if (hit) {
        return;
      }
      if (element.widget is M3EListReorderExclude) {
        final RenderObject? renderObject = element.renderObject;
        if (renderObject is RenderBox &&
            renderObject.hasSize &&
            renderObject.attached) {
          final Offset local = renderObject.globalToLocal(globalPosition);
          if ((Offset.zero & renderObject.size).contains(local)) {
            hit = true;
            return;
          }
        }
      }
      element.visitChildren(visit);
    }

    slotContext.visitChildren(visit);
    return hit;
  }

  Future<void> _beginDrag(int index, Offset globalPosition, int pointer) async {
    final Future<void> Function(int index)? prepare = widget.prepareDrag;
    if (prepare != null) {
      await prepare(index);
      if (!mounted || _activePointer != pointer || _dragIndex != null) {
        // Restore any snap-collapse if the drag never started.
        widget.onDragSettled?.call(index, index);
        return;
      }
    }
    _startDrag(index, globalPosition);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) {
      return;
    }
    if (_dragIndex != null) {
      _updateDrag(event.position);
      return;
    }
    final Offset? down = _pointerDownGlobal;
    if (down != null && (event.position - down).distance > kTouchSlop) {
      _cancelPendingLongPress();
    }
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    if (event.pointer != _activePointer) {
      return;
    }
    _cancelPendingLongPress();
    _activePointer = null;
    _pointerDownGlobal = null;
    if (_dragIndex != null) {
      _endDrag();
    }
  }

  void _startDrag(int index, Offset globalPosition) {
    if (widget.canStartDrag != null && !widget.canStartDrag!(index)) {
      return;
    }
    _dragExtent = _extent(index);
    _dragDy.value = 0;
    _pointerDownGlobal = globalPosition;
    setState(() {
      _dragIndex = index;
      _insertIndex = index;
    });
    _sessionActive.value = true;
    for (var i = 0; i < widget.itemCount; i++) {
      _offsetCtrl(i)
        ..motion = widget.reorderState.displaceMotion.toMotion()
        ..animateTo(0);
    }
  }

  void _updateDrag(Offset globalPosition) {
    final int? dragIndex = _dragIndex;
    final Offset? start = _pointerDownGlobal;
    if (dragIndex == null || start == null) {
      return;
    }

    _dragDy.value = globalPosition.dy - start.dy;

    // Insert index from finger Y relative to the list stack.
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    var fingerY = globalPosition.dy;
    if (stackBox != null) {
      fingerY = stackBox.globalToLocal(globalPosition).dy;
    }

    final ScrollableState? scrollable = Scrollable.maybeOf(context);
    if (scrollable != null) {
      fingerY += scrollable.position.pixels;
    }

    var insert = 0;
    var acc = 0.0;
    for (var i = 0; i < widget.itemCount; i++) {
      final double h = _extent(i);
      if (fingerY < acc + h / 2) {
        break;
      }
      acc += h;
      insert++;
    }
    insert = insert.clamp(0, widget.itemCount);

    if (insert != _insertIndex) {
      setState(() => _insertIndex = insert);
      _updateNeighborOffsets(dragIndex, insert);
    }
  }

  void _updateNeighborOffsets(int dragIndex, int insertIndex) {
    final double dragH = _dragExtent;
    for (var i = 0; i < widget.itemCount; i++) {
      _offsetCtrl(i).animateTo(
        _m3eReorderNeighborShift(
          index: i,
          dragIndex: dragIndex,
          insertIndex: insertIndex,
          dragExtent: dragH,
        ),
      );
    }
  }

  void _endDrag() {
    final int? from = _dragIndex;
    final int? to = _insertIndex;
    var settledTo = from;
    if (from != null && to != null) {
      var newIndex = to;
      if (newIndex > from) {
        newIndex -= 1;
      }
      settledTo = newIndex;
      if (newIndex != from) {
        widget.onReorder(from, newIndex);
      }
    }
    for (final SingleMotionController c in _offsets.values) {
      c
        ..motion = widget.reorderState.settleMotion.toMotion()
        ..animateTo(0);
    }
    _sessionActive.value = false;
    setState(() {
      _dragIndex = null;
      _insertIndex = null;
    });
    _dragDy.value = 0;
    if (from != null && settledTo != null) {
      widget.onDragSettled?.call(from, settledTo);
    }
  }

  Widget _buildSlot(BuildContext context, int index) {
    final Widget built = KeyedSubtree(
      key: _keyFor(index),
      child: widget.itemBuilder(context, index),
    );

    final Widget listening = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (PointerDownEvent e) => _onPointerDown(index, e),
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUpOrCancel,
      onPointerCancel: _onPointerUpOrCancel,
      child: built,
    );

    final isDragSource = _dragIndex == index;

    // Source slot: keep height, hide content (floating proxy paints instead).
    if (isDragSource) {
      return IgnorePointer(child: Opacity(opacity: 0, child: listening));
    }

    return AnimatedBuilder(
      animation: _offsetCtrl(index),
      builder: (BuildContext context, Widget? child) {
        return Transform.translate(
          offset: Offset(0, _offsetCtrl(index).value),
          child: child,
        );
      },
      child: listening,
    );
  }

  Widget _buildProxy(BuildContext context) {
    final int dragIndex = _dragIndex!;
    final theme = M3ETheme.of(context);
    final scheme = theme.colorScheme;
    final listTheme = theme.listTheme;
    final M3EListReorderState rs = widget.reorderState;
    final double slotTop = _slotTop(dragIndex);
    final Color dragColor = rs.resolvedDragColor(scheme);
    final double dragRadius = rs.resolvedDragRadius(listTheme);

    final double proxyHeight = (_dragExtent - widget.gap).clamp(
      0.0,
      double.infinity,
    );

    return ValueListenableBuilder<double>(
      valueListenable: _dragDy,
      builder: (BuildContext context, double dy, Widget? child) {
        return Positioned(
          left: 0,
          right: 0,
          top: slotTop + dy,
          height: proxyHeight > 0 ? proxyHeight : null,
          child: child!,
        );
      },
      child: Transform.scale(
        scale: rs.dragScale,
        child: PhysicalModel(
          color: dragColor,
          elevation: rs.dragElevation,
          borderRadius: BorderRadius.circular(dragRadius),
          child: M3EListDragProxyScope(
            color: dragColor,
            radius: dragRadius,
            child: widget.itemBuilder(context, dragIndex),
          ),
        ),
      ),
    );
  }

  Widget _buildDestinationHint(BuildContext context) {
    final int? dragIndex = _dragIndex;
    final int? insert = _insertIndex;
    if (dragIndex == null || insert == null || insert == dragIndex) {
      return const SizedBox.shrink();
    }

    final theme = M3ETheme.of(context);
    final scheme = theme.colorScheme;
    final listTheme = theme.listTheme;
    final M3EListReorderState rs = widget.reorderState;

    // Visual gap after neighbors spring-shift (original slot coordinates).
    final double top = insert < dragIndex
        ? _slotTop(insert)
        : _slotTop(insert - 1);

    final double height = (_dragExtent - widget.gap).clamp(
      0.0,
      double.infinity,
    );
    return Positioned(
      left: 0,
      right: 0,
      top: top,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: rs.resolvedPlaceholderColor(scheme),
            borderRadius: BorderRadius.circular(
              rs.resolvedPlaceholderRadius(listTheme),
            ),
            border: rs.placeholderBorder == null
                ? null
                : Border.fromBorderSide(rs.placeholderBorder!),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget list = widget.scrollable
        ? ListView.builder(
            controller: widget.controller,
            physics: widget.physics,
            shrinkWrap: widget.shrinkWrap,
            padding: widget.padding,
            itemCount: widget.itemCount,
            itemBuilder: (BuildContext context, int index) =>
                _buildSlot(context, index),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(
              widget.itemCount,
              (int index) => _buildSlot(context, index),
            ),
          );

    return M3EListReorderSessionScope(
      active: _sessionActive,
      child: Stack(
        key: _stackKey,
        clipBehavior: Clip.none,
        children: <Widget>[
          // Hint behind resting rows so it cannot cut them out.
          if (_dragIndex != null) _buildDestinationHint(context),
          list,
          if (_dragIndex != null) _buildProxy(context),
        ],
      ),
    );
  }
}

/// Neighbor Y shift while [dragIndex] opens a gap at [insertIndex].
double _m3eReorderNeighborShift({
  required int index,
  required int dragIndex,
  required int insertIndex,
  required double dragExtent,
}) {
  if (index == dragIndex) {
    return 0;
  }
  if (insertIndex <= dragIndex) {
    // Opening a gap above the dragged slot: items in [insert, drag) move down.
    if (index >= insertIndex && index < dragIndex) {
      return dragExtent;
    }
    return 0;
  }
  // Opening a gap below: items in (drag, insert) move up into the hole.
  if (index > dragIndex && index < insertIndex) {
    return -dragExtent;
  }
  return 0;
}
