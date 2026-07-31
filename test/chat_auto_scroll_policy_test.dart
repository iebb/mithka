import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_auto_scroll_policy.dart';

void main() {
  test('scrolling toward older messages locks the current viewport', () {
    final policy = ChatAutoScrollPolicy();

    policy.noteUserScroll(towardOlderMessages: true, isAtBottom: false);

    expect(policy.preservesViewport, isTrue);
    expect(policy.shouldFollowAppendedMessage(wasNearBottom: true), isFalse);
  });

  test('incoming messages follow only while the user remains at bottom', () {
    final policy = ChatAutoScrollPolicy();

    expect(policy.shouldFollowAppendedMessage(wasNearBottom: true), isTrue);
    expect(policy.shouldFollowAppendedMessage(wasNearBottom: false), isFalse);

    policy.noteUserScroll(towardOlderMessages: true, isAtBottom: false);
    expect(policy.shouldFollowAppendedMessage(wasNearBottom: true), isFalse);

    policy.noteUserScroll(towardOlderMessages: false, isAtBottom: true);
    expect(policy.shouldFollowAppendedMessage(wasNearBottom: true), isTrue);
  });

  test('restored scrolled-up chats stay locked until returning to bottom', () {
    final policy = ChatAutoScrollPolicy(preserveViewport: true);

    expect(policy.shouldFollowAppendedMessage(wasNearBottom: true), isFalse);
    policy.returnToBottom();
    expect(policy.shouldFollowAppendedMessage(wasNearBottom: true), isTrue);
  });

  test('requestReturnToBottom ignores inertia toward older messages', () {
    final policy = ChatAutoScrollPolicy();

    policy.noteUserScroll(towardOlderMessages: true, isAtBottom: false);
    expect(policy.preservesViewport, isTrue);

    policy.requestReturnToBottom();
    expect(policy.preservesViewport, isFalse);

    // Ballistic scroll updates must not re-lock after an explicit jump request.
    policy.noteUserScroll(towardOlderMessages: true, isAtBottom: false);
    expect(policy.preservesViewport, isFalse);

    policy.noteUserScroll(towardOlderMessages: false, isAtBottom: true);
    expect(policy.preservesViewport, isFalse);

    // After settling at bottom, normal scroll-up locking works again.
    policy.noteUserScroll(towardOlderMessages: true, isAtBottom: false);
    expect(policy.preservesViewport, isTrue);
  });

  test('allowViewportPreservation restores locking after a bottom request', () {
    final policy = ChatAutoScrollPolicy();

    policy.requestReturnToBottom();
    policy.noteUserScroll(towardOlderMessages: true, isAtBottom: false);
    expect(policy.preservesViewport, isFalse);

    policy.allowViewportPreservation();
    policy.noteUserScroll(towardOlderMessages: true, isAtBottom: false);
    expect(policy.preservesViewport, isTrue);
  });

  test('returnToBottom clears lock without suppressing later scroll-up', () {
    final policy = ChatAutoScrollPolicy(preserveViewport: true);

    policy.returnToBottom();
    expect(policy.preservesViewport, isFalse);

    policy.noteUserScroll(towardOlderMessages: true, isAtBottom: false);
    expect(policy.preservesViewport, isTrue);
  });

  test('sending a message releases a preserved viewport', () {
    final policy = ChatAutoScrollPolicy(preserveViewport: true);

    policy.noteMessageSent();

    expect(policy.preservesViewport, isFalse);
    expect(policy.shouldFollowAppendedMessage(wasNearBottom: true), isTrue);
  });

  test('composer panels follow only when the transcript was at bottom', () {
    final policy = ChatAutoScrollPolicy();

    expect(policy.shouldFollowComposerPanelChange(wasNearBottom: true), isTrue);
    expect(
      policy.shouldFollowComposerPanelChange(wasNearBottom: false),
      isFalse,
    );

    policy.noteUserScroll(towardOlderMessages: true, isAtBottom: false);
    expect(
      policy.shouldFollowComposerPanelChange(wasNearBottom: true),
      isFalse,
    );
  });

  test('first restored-position gesture cannot return to latest', () {
    final guard = ChatRestoredPositionGuard(true);

    expect(guard.blocksAutomaticReturn, isTrue);
    guard.noteUserScroll();
    expect(guard.finishUserScroll(), isTrue);
    expect(guard.blocksAutomaticReturn, isFalse);
    expect(guard.finishUserScroll(), isFalse);
  });

  test('pointer activity alone does not consume restored-position guard', () {
    final guard = ChatRestoredPositionGuard(true);

    expect(guard.finishUserScroll(), isFalse);
    expect(guard.blocksAutomaticReturn, isTrue);
    guard.cancel();
    expect(guard.blocksAutomaticReturn, isFalse);
  });

  test('automatic latest return respects restored-position protection', () {
    bool decide({required bool protected}) =>
        shouldRequestAutomaticReturnToLatest(
          anchoredHistory: true,
          restoredPositionProtected: protected,
          pointerDown: false,
          hasScrollTarget: false,
          hasScrollClients: true,
          isNearLatestEdge: true,
        );

    expect(decide(protected: true), isFalse);
    expect(decide(protected: false), isTrue);
    expect(
      shouldRequestAutomaticReturnToLatest(
        anchoredHistory: true,
        restoredPositionProtected: false,
        pointerDown: true,
        hasScrollTarget: false,
        hasScrollClients: true,
        isNearLatestEdge: true,
      ),
      isFalse,
    );
  });

  test('user takeover invalidates pending reopen navigation', () {
    final guard = ChatSessionReopenNavigationGuard();
    final pendingGeneration = guard.begin();

    expect(guard.isCurrent(pendingGeneration), isTrue);
    guard.cancel();
    expect(guard.isCurrent(pendingGeneration), isFalse);
  });

  test('a newer reopen resolution invalidates the older generation', () {
    final guard = ChatSessionReopenNavigationGuard();
    final firstGeneration = guard.begin();
    final secondGeneration = guard.begin();

    expect(guard.isCurrent(firstGeneration), isFalse);
    expect(guard.isCurrent(secondGeneration), isTrue);
  });

  test('latest loading includes anchored and stale transcript windows', () {
    expect(
      shouldLoadLatestChatHistory(
        anchoredHistory: true,
        historyReachesLatest: true,
      ),
      isTrue,
      reason: 'an anchored window must be replaced even if it includes latest',
    );
    expect(
      shouldLoadLatestChatHistory(
        anchoredHistory: false,
        historyReachesLatest: false,
      ),
      isTrue,
      reason: 'a non-anchored restored cache may still be stale',
    );
    expect(
      shouldLoadLatestChatHistory(
        anchoredHistory: true,
        historyReachesLatest: false,
      ),
      isTrue,
    );
    expect(
      shouldLoadLatestChatHistory(
        anchoredHistory: false,
        historyReachesLatest: true,
      ),
      isFalse,
    );
  });

  test('pending reopen navigation blocks automatic and exit read marking', () {
    expect(
      shouldAllowAutomaticChatRead(
        sessionReopenPending: true,
        restoredPositionProtected: false,
        preservesViewport: false,
        historyReachesLatest: true,
      ),
      isFalse,
    );
    expect(
      shouldMarkChatReadOnExit(
        isAtLoadedBottom: true,
        sessionReopenPending: true,
        restoredPositionProtected: false,
        preservesViewport: false,
        historyReachesLatest: true,
      ),
      isFalse,
    );
    expect(
      shouldMarkChatReadOnExit(
        isAtLoadedBottom: true,
        sessionReopenPending: false,
        restoredPositionProtected: false,
        preservesViewport: false,
        historyReachesLatest: true,
      ),
      isTrue,
    );
    expect(
      shouldMarkChatReadOnExit(
        isAtLoadedBottom: false,
        sessionReopenPending: false,
        restoredPositionProtected: false,
        preservesViewport: false,
        historyReachesLatest: true,
      ),
      isFalse,
    );
  });

  test('a protected or stale restored viewport cannot mark messages read', () {
    bool allows({
      bool protected = false,
      bool preservesViewport = false,
      bool historyReachesLatest = true,
    }) => shouldAllowAutomaticChatRead(
      sessionReopenPending: false,
      restoredPositionProtected: protected,
      preservesViewport: preservesViewport,
      historyReachesLatest: historyReachesLatest,
    );

    expect(allows(protected: true), isFalse);
    expect(allows(preservesViewport: true), isFalse);
    expect(allows(historyReachesLatest: false), isFalse);
    expect(allows(), isTrue);
  });

  test('failed or pending reopen jumps preserve the previous snapshot', () {
    expect(
      shouldSaveChatSessionScrollSnapshot(
        sessionReopenPending: true,
        preservingSnapshotAfterFailedJump: false,
      ),
      isFalse,
    );
    expect(
      shouldSaveChatSessionScrollSnapshot(
        sessionReopenPending: false,
        preservingSnapshotAfterFailedJump: true,
      ),
      isFalse,
    );
    expect(
      shouldSaveChatSessionScrollSnapshot(
        sessionReopenPending: false,
        preservingSnapshotAfterFailedJump: false,
      ),
      isTrue,
    );
  });

  test('a live inbox update wins over a stale initial header response', () {
    expect(
      shouldApplyInitialChatReadState(
        readInboxRevisionAtRequestStart: 3,
        currentReadInboxRevision: 3,
      ),
      isTrue,
    );
    expect(
      shouldApplyInitialChatReadState(
        readInboxRevisionAtRequestStart: 3,
        currentReadInboxRevision: 4,
      ),
      isFalse,
    );
  });

  test('bottom follow corrects only while laid-out geometry has a gap', () {
    final coordinator = ChatBottomFollowCoordinator();
    final callbacks = <void Function()>[];
    var distance = 3.0;
    var corrections = 0;
    var settled = 0;
    final generation = coordinator.begin();

    coordinator.follow(
      generation: generation,
      schedulePostFrame: callbacks.add,
      canFollow: () => true,
      distanceToLatest: () => distance,
      latestExtent: () => 100,
      correct: () {
        corrections++;
        distance--;
      },
      settled: () => settled++,
      abandoned: () {},
    );
    while (callbacks.isNotEmpty) {
      callbacks.removeAt(0)();
    }

    expect(corrections, 3);
    expect(settled, 1);
  });

  test('cancelling bottom follow invalidates queued frame corrections', () {
    final coordinator = ChatBottomFollowCoordinator();
    final callbacks = <void Function()>[];
    var corrections = 0;
    final generation = coordinator.begin();

    coordinator.follow(
      generation: generation,
      schedulePostFrame: callbacks.add,
      canFollow: () => true,
      distanceToLatest: () => 100,
      latestExtent: () => 100,
      correct: () => corrections++,
      settled: () {},
      abandoned: () {},
    );
    coordinator.cancel();
    callbacks.single();

    expect(corrections, 0);
  });

  test('bottom follow waits for a stable lazy-list max extent', () {
    final coordinator = ChatBottomFollowCoordinator();
    final callbacks = <void Function()>[];
    var latestExtent = 100.0;
    var distance = 0.0;
    var corrections = 0;
    var settled = 0;
    final generation = coordinator.begin();

    coordinator.follow(
      generation: generation,
      schedulePostFrame: callbacks.add,
      canFollow: () => true,
      distanceToLatest: () => distance,
      latestExtent: () => latestExtent,
      correct: () {
        corrections++;
        distance = 0;
      },
      settled: () => settled++,
      abandoned: () {},
    );
    callbacks.removeAt(0)();
    latestExtent = 150;
    distance = 50;
    while (callbacks.isNotEmpty) {
      callbacks.removeAt(0)();
    }

    expect(corrections, 1);
    expect(settled, 1);
  });

  test('bottom follow reports when its correction budget is exhausted', () {
    final coordinator = ChatBottomFollowCoordinator();
    final callbacks = <void Function()>[];
    var abandoned = 0;
    final generation = coordinator.begin();

    coordinator.follow(
      generation: generation,
      remainingFrames: 1,
      schedulePostFrame: callbacks.add,
      canFollow: () => true,
      distanceToLatest: () => 100,
      latestExtent: () => 100,
      correct: () {},
      settled: () {},
      abandoned: () => abandoned++,
    );
    while (callbacks.isNotEmpty) {
      callbacks.removeAt(0)();
    }

    expect(abandoned, 1);
  });

  test(
    'bottom follow reports when current navigation can no longer follow',
    () {
      final coordinator = ChatBottomFollowCoordinator();
      final callbacks = <void Function()>[];
      var abandoned = 0;
      final generation = coordinator.begin();

      coordinator.follow(
        generation: generation,
        schedulePostFrame: callbacks.add,
        canFollow: () => false,
        distanceToLatest: () => 100,
        latestExtent: () => 100,
        correct: () {},
        settled: () {},
        abandoned: () => abandoned++,
      );
      callbacks.single();

      expect(abandoned, 1);
    },
  );
}
