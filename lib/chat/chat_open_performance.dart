/// Returns whether asynchronous work started for a chat can no longer affect
/// the currently active view.
///
/// TDLib queries cannot be cancelled once sent, so callers use this at await
/// boundaries to avoid starting the next query after a chat is closed or the
/// active account changes.
bool chatOpenWorkIsStale({
  required bool disposed,
  required int openingClientId,
  required int openingAccountSlot,
  required int activeClientId,
  required int activeAccountSlot,
}) =>
    disposed ||
    openingClientId != activeClientId ||
    openingAccountSlot != activeAccountSlot;

/// Keep placeholder content visually distinct from real chat messages until
/// the transcript has finished its initial positioning.
bool shouldShowTranscriptSkeleton({required bool initialTranscriptReady}) =>
    !initialTranscriptReady;

/// Once any cached message is available, opening should no longer wait for a
/// remote history round trip. A latest-window refresh can continue in the
/// background while the cached transcript is already interactive.
bool shouldHydrateInitialHistoryInBackground({
  required int loadedMessageCount,
}) => loadedMessageCount > 0;
