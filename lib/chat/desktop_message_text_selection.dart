import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Message text is selected by dragging, not by opening its action menu or
/// clicking it. Keyboard selection and non-mouse gestures remain unchanged.
class DesktopMessageTextSelectionArea extends StatefulWidget {
  const DesktopMessageTextSelectionArea({
    super.key,
    this.selectionAreaKey,
    required this.child,
  });

  final GlobalKey<SelectionAreaState>? selectionAreaKey;
  final Widget child;

  @override
  State<DesktopMessageTextSelectionArea> createState() =>
      _DesktopMessageTextSelectionAreaState();
}

class _DesktopMessageTextSelectionAreaState
    extends State<DesktopMessageTextSelectionArea> {
  final _localKey = GlobalKey<SelectionAreaState>();
  final _delegate = _DragOnlySelectionDelegate();
  int? _mousePointer;
  double _mouseDistanceMoved = 0;

  GlobalKey<SelectionAreaState> get _selectionAreaKey =>
      widget.selectionAreaKey ?? _localKey;

  void _onPointerDown(PointerDownEvent event) {
    _mousePointer = null;
    _mouseDistanceMoved = 0;
    _delegate.pendingBoundary = null;
    _delegate.acceptsPointerSelection = event.kind != PointerDeviceKind.mouse;
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    _mousePointer = event.pointer;
    _selectionAreaKey.currentState?.selectableRegion.clearSelection();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_mousePointer != event.pointer) return;
    // Match Flutter's mouse pan recognizer, including a curved drag path.
    _mouseDistanceMoved += event.delta.distance;
    if (_mouseDistanceMoved >
        computePanSlop(event.kind, MediaQuery.gestureSettingsOf(context))) {
      _delegate.acceptsPointerSelection = true;
    }
  }

  void _endPointer(PointerEvent event) {
    if (_mousePointer != event.pointer) return;
    _mousePointer = null;
    _mouseDistanceMoved = 0;
    _delegate.pendingBoundary = null;
  }

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onPointerDown,
    onPointerMove: _onPointerMove,
    onPointerUp: _endPointer,
    onPointerCancel: _endPointer,
    child: SelectionArea(
      key: _selectionAreaKey,
      contextMenuBuilder: (_, _) => const SizedBox.shrink(),
      child: SelectionContainer(delegate: _delegate, child: widget.child),
    ),
  );
}

class _DragOnlySelectionDelegate extends StaticSelectionContainerDelegate {
  bool acceptsPointerSelection = true;
  SelectionEvent? pendingBoundary;

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final isPointerSelection = switch (event.type) {
      SelectionEventType.startEdgeUpdate ||
      SelectionEventType.endEdgeUpdate ||
      SelectionEventType.selectWord ||
      SelectionEventType.selectParagraph => true,
      _ => false,
    };
    if (isPointerSelection && !acceptsPointerSelection) {
      if (event is SelectWordSelectionEvent ||
          event is SelectParagraphSelectionEvent) {
        pendingBoundary = event;
      }
      return SelectionResult.none;
    }
    // Multi-click drags extend a word/paragraph boundary initialized on down.
    // Defer that boundary until the drag so repeated stationary clicks never
    // flash a selection, while intentional word/paragraph drags still work.
    final boundary = pendingBoundary;
    pendingBoundary = null;
    if (isPointerSelection && boundary != null) {
      super.dispatchSelectionEvent(boundary);
    }
    return super.dispatchSelectionEvent(event);
  }
}
