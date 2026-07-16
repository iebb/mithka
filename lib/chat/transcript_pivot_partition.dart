/// An immutable message-ID cutoff used to split transcript entries.
///
/// The cutoff is deliberately independent of the message that originally
/// supplied it. Removing that message later therefore does not move the
/// partition boundary.
class TranscriptPivot {
  const TranscriptPivot(this.cutoffMessageId);

  final int cutoffMessageId;
}

/// Keeps an existing pivot, but does not let a provisional seed message create
/// one before the first complete history window has loaded.
TranscriptPivot? resolveTranscriptPivot({
  required TranscriptPivot? currentPivot,
  required bool initialWindowLoaded,
  required int? firstMessageId,
}) {
  if (currentPivot != null) return currentPivot;
  if (!initialWindowLoaded || firstMessageId == null) return null;
  return TranscriptPivot(firstMessageId);
}

/// Whether a provisional pending-only cutoff must be replaced now that a
/// server-assigned message ID exists.
///
/// Pending messages use a synthetic ID at the latest edge. Keeping that
/// synthetic cutoff after TDLib replaces a pending message would otherwise
/// leave every real message in the before-center sliver.
bool shouldRebasePendingTranscriptPivot({
  required TranscriptPivot? pivot,
  required int pendingOrderId,
  required bool hasServerMessage,
}) {
  return pivot?.cutoffMessageId == pendingOrderId && hasServerMessage;
}

/// Keeps the first-contact card at the absolute start of non-empty history.
///
/// An empty centered transcript is the only exception: placing the card after
/// the center keeps that otherwise blank screen visible. As soon as a message
/// exists, the card returns to the far end of the before-center sliver and can
/// never split chronological history.
bool shouldPlaceFirstContactCardAtCenter({
  required bool hasTranscriptEntries,
}) => !hasTranscriptEntries;

/// Whether the card and the complete short transcript can share one viewport.
bool firstContactHistoryFitsViewport({
  required double cardTop,
  required double latestBottom,
  required double viewportExtent,
  double outerSpacing = 16,
}) {
  if (latestBottom < cardTop || viewportExtent < 0 || outerSpacing < 0) {
    return false;
  }
  return latestBottom - cardTop + outerSpacing <= viewportExtent + 0.5;
}

/// Whether [currentMessageId] starts the fixed pivot-and-after section.
bool startsTranscriptPivotSection({
  required TranscriptPivot? pivot,
  required int previousMessageId,
  required int currentMessageId,
}) {
  if (pivot == null) return false;
  return previousMessageId < pivot.cutoffMessageId &&
      currentMessageId >= pivot.cutoffMessageId;
}

/// Whole transcript entries on either side of a fixed [TranscriptPivot].
class TranscriptPivotPartition<Entry> {
  const TranscriptPivotPartition({
    required this.beforePivot,
    required this.pivotAndAfter,
  });

  /// Entries whose message IDs are all below the pivot cutoff.
  final List<Entry> beforePivot;

  /// Entries containing the cutoff, crossing it, or entirely above it.
  final List<Entry> pivotAndAfter;
}

/// Partitions ordered transcript [entries] without splitting an entry.
///
/// An entry belongs to [TranscriptPivotPartition.beforePivot] only when every
/// ID returned by [messageIdsOf] is lower than the immutable cutoff. An entry
/// that straddles the cutoff is kept whole in
/// [TranscriptPivotPartition.pivotAndAfter].
///
/// Every transcript entry must contain at least one message ID.
TranscriptPivotPartition<Entry> partitionTranscriptAtPivot<Entry>({
  required Iterable<Entry> entries,
  required TranscriptPivot pivot,
  required Iterable<int> Function(Entry entry) messageIdsOf,
}) {
  final beforePivot = <Entry>[];
  final pivotAndAfter = <Entry>[];

  for (final entry in entries) {
    final messageIds = messageIdsOf(entry).toList(growable: false);
    if (messageIds.isEmpty) {
      throw ArgumentError.value(
        entry,
        'entries',
        'Each transcript entry must contain at least one message ID.',
      );
    }

    final isEntirelyBeforePivot = messageIds.every(
      (messageId) => messageId < pivot.cutoffMessageId,
    );
    (isEntirelyBeforePivot ? beforePivot : pivotAndAfter).add(entry);
  }

  return TranscriptPivotPartition<Entry>(
    beforePivot: List<Entry>.unmodifiable(beforePivot),
    pivotAndAfter: List<Entry>.unmodifiable(pivotAndAfter),
  );
}
