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

/// Lets an older page fill a short visible transcript even when a touch froze
/// its previous pivot while the request was in flight. Full transcripts retain
/// their fixed pivot so ordinary pagination does not move the viewport.
bool shouldRebaseForHydratedOlderPage({
  required bool prependedOlder,
  required bool latestArmWasShort,
  required bool historyFillInFlight,
  required bool revealRequested,
}) =>
    prependedOlder &&
    latestArmWasShort &&
    (historyFillInFlight || revealRequested);

/// Whether the after-center arm is still too thin to treat as a filled
/// transcript.
///
/// [maxScrollExtent] alone is not enough: a single tall media bubble can push
/// extent past [extentThreshold] while older history remains off-screen in the
/// before-center sliver. A low [afterCenterEntryCount] keeps short-fill and
/// pivot rebase alive in that case.
bool isLatestTranscriptArmShort({
  required double maxScrollExtent,
  required int afterCenterEntryCount,
  double extentThreshold = 24,
  int entryThreshold = 3,
}) {
  if (afterCenterEntryCount < entryThreshold) return true;
  return maxScrollExtent <= extentThreshold;
}

/// Freeze only once the latest arm fills the viewport (or older history is
/// exhausted). Freezing a one-message after-center arm parks older pages above
/// the center forever.
bool shouldFreezeTranscriptPivot({
  required bool latestArmIsShort,
  required bool canLoadOlder,
}) => !latestArmIsShort || !canLoadOlder;

/// A restored pivot pinned to the newest known message leaves only that
/// bubble in the after-center arm. When reopening at the latest edge, discard
/// it so short-fill can rebuild a fuller cutoff.
bool shouldDiscardRestoredTranscriptPivot({
  required int? pivotMessageId,
  required int? newestMessageId,
  required bool openAtBottom,
}) =>
    openAtBottom &&
    pivotMessageId != null &&
    newestMessageId != null &&
    pivotMessageId == newestMessageId;

/// Whether a scroll-snapshot pivot may be applied when opening a chat.
///
/// Orphan snapshots (pivot without a matching session transcript) must not be
/// restored: the view-model then starts from a single seed message, freezes the
/// newest cutoff, and parks every later hydrate in the before-center sliver.
bool shouldRestoreTranscriptPivot({
  required int? pivotMessageId,
  required bool hasSessionTranscript,
  required int? newestMessageId,
  required bool openAtBottom,
}) {
  if (pivotMessageId == null || !hasSessionTranscript) return false;
  return !shouldDiscardRestoredTranscriptPivot(
    pivotMessageId: pivotMessageId,
    newestMessageId: newestMessageId,
    openAtBottom: openAtBottom,
  );
}

/// Force a pivot reset when the after-center arm is thin but older messages
/// are already present below the cutoff.
///
/// This is the open-chat failure mode where history is loaded yet invisible
/// until the user scrolls toward [ScrollPosition.minScrollExtent]. It must not
/// wait for another network page: `loadOlder` may already be exhausted.
bool shouldRebaseParkedShortTranscriptPivot({
  required int? pivotCutoffMessageId,
  required bool latestArmIsShort,
  required bool hasMessageOlderThanPivot,
  required bool followingLatest,
}) {
  if (!followingLatest || pivotCutoffMessageId == null) return false;
  return latestArmIsShort && hasMessageOlderThanPivot;
}

/// First window expansion after a seed/restored pivot: message identity changed
/// while the latest arm is still short and older IDs already exist.
bool shouldRebaseForExpandedInitialWindow({
  required bool transcriptChanged,
  required bool latestArmIsShort,
  required bool hasMessageOlderThanPivot,
  required bool followingLatest,
}) =>
    transcriptChanged &&
    latestArmIsShort &&
    hasMessageOlderThanPivot &&
    followingLatest;

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
