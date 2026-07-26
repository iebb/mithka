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

/// The chat list already owns the latest message, so a newly opened chat can
/// show that lightweight preview while its full transcript is positioned.
bool shouldShowSeedMessageWhileOpening({
  required bool initialTranscriptReady,
  required bool hasSeedMessage,
}) => !initialTranscriptReady && hasSeedMessage;

/// Once any cached message is available, opening should no longer wait for a
/// remote history round trip. A latest-window refresh can continue in the
/// background while the cached transcript is already interactive.
bool shouldHydrateInitialHistoryInBackground({
  required int loadedMessageCount,
}) => loadedMessageCount > 0;
