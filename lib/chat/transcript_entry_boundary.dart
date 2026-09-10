import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Tracks only laid-out transcript rows for viewport reads and scroll anchors.
/// Pagination can retain thousands of messages; a scroll frame needs the
/// handful of render boxes attached by the two lazy slivers.
class TranscriptEntryBoundary extends SingleChildRenderObjectWidget {
  const TranscriptEntryBoundary({
    super.key,
    required this.messageId,
    required this.mountedEntries,
    required super.child,
  });

  final int messageId;
  final Map<int, RenderBox> mountedEntries;

  @override
  RenderRepaintBoundary createRenderObject(BuildContext context) =>
      _RenderTranscriptEntryBoundary(messageId, mountedEntries);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderRepaintBoundary renderObject,
  ) => (renderObject as _RenderTranscriptEntryBoundary).updateRegistration(
    messageId,
    mountedEntries,
  );
}

class _RenderTranscriptEntryBoundary extends RenderRepaintBoundary {
  _RenderTranscriptEntryBoundary(this._messageId, this._mountedEntries);

  int _messageId;
  Map<int, RenderBox> _mountedEntries;

  void _unregister() {
    if (identical(_mountedEntries[_messageId], this)) {
      _mountedEntries.remove(_messageId);
    }
  }

  void updateRegistration(int messageId, Map<int, RenderBox> mountedEntries) {
    if (_messageId == messageId && identical(_mountedEntries, mountedEntries)) {
      return;
    }
    if (attached) _unregister();
    _messageId = messageId;
    _mountedEntries = mountedEntries;
    if (attached) _mountedEntries[_messageId] = this;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _mountedEntries[_messageId] = this;
  }

  @override
  void detach() {
    _unregister();
    super.detach();
  }
}
