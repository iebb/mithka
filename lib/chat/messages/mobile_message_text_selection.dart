import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;

/// A message-scoped mobile selection region that reports when its transcript
/// row is unmounted.
///
/// Chat transcript rows are intentionally not kept alive. Without the dispose
/// callback, scrolling the selected row out of the sliver would leave the chat
/// believing that the next long press is still the second press.
class MobileMessageTextSelectionArea extends StatefulWidget {
  const MobileMessageTextSelectionArea({
    super.key,
    required this.selectionAreaKey,
    required this.onSelectionChanged,
    required this.onDisposed,
    required this.child,
  });

  final GlobalKey<SelectionAreaState> selectionAreaKey;
  final ValueChanged<SelectedContent?>? onSelectionChanged;
  final VoidCallback onDisposed;
  final Widget child;

  @override
  State<MobileMessageTextSelectionArea> createState() =>
      _MobileMessageTextSelectionAreaState();
}

class _MobileMessageTextSelectionAreaState
    extends State<MobileMessageTextSelectionArea> {
  @override
  void dispose() {
    final onDisposed = widget.onDisposed;
    WidgetsBinding.instance.addPostFrameCallback((_) => onDisposed());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectionArea(
    key: widget.selectionAreaKey,
    onSelectionChanged: widget.onSelectionChanged,
    child: widget.child,
  );
}
