import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_auto_scroll_policy.dart';

void main() {
  group('chat session scroll restore', () {
    test('cold entry starts from a finite zero offset', () {
      final plan = chatInitialScrollPlan(
        hasCachedTranscript: false,
        savedPixels: null,
        savedAtBottom: false,
      );

      expect(plan.initialOffset, 0);
      expect(plan.correctToBottomAfterLayout, isFalse);
    });

    test('cached bottom starts at saved pixels and corrects after layout', () {
      final plan = chatInitialScrollPlan(
        hasCachedTranscript: true,
        savedPixels: 1720,
        savedAtBottom: true,
      );

      expect(plan.initialOffset, 1720);
      expect(plan.correctToBottomAfterLayout, isTrue);
    });

    test('cached non-bottom restores without a bottom correction', () {
      final plan = chatInitialScrollPlan(
        hasCachedTranscript: true,
        savedPixels: 640,
        savedAtBottom: false,
      );

      expect(plan.initialOffset, 640);
      expect(plan.correctToBottomAfterLayout, isFalse);
    });

    test('a snapshot without cached messages uses cold-entry positioning', () {
      final plan = chatInitialScrollPlan(
        hasCachedTranscript: false,
        savedPixels: 1720,
        savedAtBottom: true,
      );

      expect(plan.initialOffset, 0);
      expect(plan.correctToBottomAfterLayout, isFalse);
    });

    test('finite negative offsets are preserved for centered history', () {
      final plan = chatInitialScrollPlan(
        hasCachedTranscript: true,
        savedPixels: -480,
        savedAtBottom: false,
      );

      expect(plan.initialOffset, -480);
    });

    test('non-finite cached offsets fall back to zero', () {
      for (final pixels in <double>[double.nan, double.infinity]) {
        final plan = chatInitialScrollPlan(
          hasCachedTranscript: true,
          savedPixels: pixels,
          savedAtBottom: false,
        );
        expect(plan.initialOffset, 0);
      }
    });

    test('a pending bottom correction can be cancelled safely', () {
      final coordinator = ChatBottomCorrectionCoordinator();
      final callbacks = <void Function()>[];
      var canCorrect = false;
      var corrections = 0;

      void schedule() {
        coordinator.schedule(
          enabled: true,
          schedulePostFrame: callbacks.add,
          canCorrect: () => canCorrect,
          correct: () => corrections++,
        );
      }

      schedule();
      schedule();
      expect(callbacks, hasLength(1));
      callbacks.removeAt(0)();
      expect(corrections, 0);

      canCorrect = true;
      schedule();
      callbacks.removeAt(0)();
      expect(corrections, 1);
    });

    testWidgets(
      'cached bottom is corrected immediately and survives a layout change',
      (tester) async {
        final key = GlobalKey<_BottomRestoreHarnessState>();
        final plan = chatInitialScrollPlan(
          hasCachedTranscript: true,
          savedPixels: 5000,
          savedAtBottom: true,
        );

        Widget buildHarness(double itemHeight) => Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 320,
            child: _BottomRestoreHarness(
              key: key,
              plan: plan,
              itemHeight: itemHeight,
            ),
          ),
        );

        await tester.pumpWidget(buildHarness(48));
        await tester.pump();
        _expectAtBottom(key.currentState!.controller);
        expect(_isVisible(tester, const ValueKey('message-39')), isTrue);

        await tester.pumpWidget(buildHarness(72));
        await tester.pump();
        _expectAtBottom(key.currentState!.controller);
        expect(_isVisible(tester, const ValueKey('message-39')), isTrue);
      },
    );

    test('a saved bottom position reopens at the current bottom', () {
      expect(
        shouldRestoreChatSessionOffset(
          hasExplicitTarget: false,
          hasSnapshot: true,
          snapshotWasAtBottom: true,
        ),
        isFalse,
      );
      expect(
        shouldOpenChatAtBottom(
          hasExplicitTarget: false,
          openAtLatest: false,
          hasSnapshot: true,
          snapshotWasAtBottom: true,
        ),
        isTrue,
      );
    });

    test('a saved non-bottom position restores its offset', () {
      expect(
        shouldRestoreChatSessionOffset(
          hasExplicitTarget: false,
          hasSnapshot: true,
          snapshotWasAtBottom: false,
        ),
        isTrue,
      );
      expect(
        shouldOpenChatAtBottom(
          hasExplicitTarget: false,
          openAtLatest: true,
          hasSnapshot: true,
          snapshotWasAtBottom: false,
        ),
        isFalse,
      );
    });

    test('reopen precedence is target, new unread, saved, then default', () {
      expect(
        resolveChatReopenDisposition(
          hasExplicitTarget: true,
          hasSavedPosition: true,
          prioritizeUnread: true,
        ),
        ChatReopenDisposition.explicitTarget,
      );
      expect(
        resolveChatReopenDisposition(
          hasExplicitTarget: false,
          hasSavedPosition: true,
          prioritizeUnread: true,
        ),
        ChatReopenDisposition.firstUnread,
      );
      expect(
        resolveChatReopenDisposition(
          hasExplicitTarget: false,
          hasSavedPosition: true,
          prioritizeUnread: false,
        ),
        ChatReopenDisposition.savedPosition,
      );
      expect(
        resolveChatReopenDisposition(
          hasExplicitTarget: false,
          hasSavedPosition: false,
          prioritizeUnread: false,
        ),
        ChatReopenDisposition.defaultPosition,
      );
    });

    test('existing unread replaces only a saved anchor in read history', () {
      expect(
        shouldPrioritizeUnreadOnChatReopen(
          currentUnreadCount: 3,
          currentLastReadInboxId: 120,
          savedAnchorMessageId: 80,
          hasConfirmedNewUnread: false,
        ),
        isTrue,
        reason: 'old browsed history must not hide the unread destination',
      );
      expect(
        shouldPrioritizeUnreadOnChatReopen(
          currentUnreadCount: 3,
          currentLastReadInboxId: 120,
          savedAnchorMessageId: 145,
          hasConfirmedNewUnread: false,
        ),
        isFalse,
        reason: 'an anchor within unread messages is reading progress',
      );
      expect(
        shouldPrioritizeUnreadOnChatReopen(
          currentUnreadCount: 3,
          currentLastReadInboxId: 120,
          savedAnchorMessageId: null,
          hasConfirmedNewUnread: false,
        ),
        isTrue,
        reason: 'raw pixels cannot prove the saved viewport is in unread',
      );
      expect(
        shouldPrioritizeUnreadOnChatReopen(
          currentUnreadCount: 0,
          currentLastReadInboxId: 120,
          savedAnchorMessageId: 80,
          hasConfirmedNewUnread: false,
        ),
        isFalse,
      );
      expect(
        shouldPrioritizeUnreadOnChatReopen(
          currentUnreadCount: 0,
          currentLastReadInboxId: 120,
          savedAnchorMessageId: 145,
          hasConfirmedNewUnread: true,
        ),
        isTrue,
        reason: 'a concrete newer unread remains authoritative',
      );
    });

    test('a concrete newer incoming unread confirms the reopen override', () {
      expect(
        isNewIncomingUnreadSinceChatSession(
          messageId: 130,
          isOutgoing: false,
          isService: false,
          savedKnownLatestMessageId: 100,
          currentLastReadInboxId: 90,
        ),
        isTrue,
        reason: 'the concrete message remains proof if counts are stale',
      );
      expect(
        isNewIncomingUnreadSinceChatSession(
          messageId: 130,
          isOutgoing: true,
          isService: false,
          savedKnownLatestMessageId: 100,
          currentLastReadInboxId: 90,
        ),
        isFalse,
        reason: 'a newer outgoing message is not an incoming unread',
      );
      expect(
        isNewIncomingUnreadSinceChatSession(
          messageId: 130,
          isOutgoing: false,
          isService: true,
          savedKnownLatestMessageId: 100,
          currentLastReadInboxId: 90,
        ),
        isFalse,
        reason: 'service messages must not displace the saved viewport',
      );
      expect(
        isNewIncomingUnreadSinceChatSession(
          messageId: 100,
          isOutgoing: false,
          isService: false,
          savedKnownLatestMessageId: 100,
          currentLastReadInboxId: 90,
        ),
        isFalse,
      );
      expect(
        isNewIncomingUnreadSinceChatSession(
          messageId: 130,
          isOutgoing: false,
          isService: false,
          savedKnownLatestMessageId: 100,
          currentLastReadInboxId: 130,
        ),
        isFalse,
        reason: 'a message already inside the read boundary is not unread',
      );
      expect(
        isNewIncomingUnreadSinceChatSession(
          messageId: 130,
          isOutgoing: false,
          isService: false,
          savedKnownLatestMessageId: 0,
          currentLastReadInboxId: 90,
        ),
        isFalse,
        reason: 'an uncertain saved boundary must preserve the viewport',
      );
    });

    test('history probing requires a nonzero unread count', () {
      expect(
        shouldProbeChatSessionUnreadHistory(
          savedKnownLatestMessageId: 100,
          currentKnownLatestMessageId: 130,
          currentUnreadCount: 0,
        ),
        isFalse,
        reason: 'zero unread must not issue a history query',
      );
      expect(
        shouldProbeChatSessionUnreadHistory(
          savedKnownLatestMessageId: 100,
          currentKnownLatestMessageId: 130,
          currentUnreadCount: 2,
        ),
        isTrue,
      );
      expect(
        shouldProbeChatSessionUnreadHistory(
          savedKnownLatestMessageId: 100,
          currentKnownLatestMessageId: 100,
          currentUnreadCount: 2,
        ),
        isFalse,
      );
    });

    test('an inconclusive bounded probe preserves the saved position', () {
      expect(
        shouldContinueChatSessionUnreadHistoryProbe(pagesScanned: 0),
        isTrue,
      );
      expect(
        shouldContinueChatSessionUnreadHistoryProbe(pagesScanned: 4),
        isTrue,
      );
      expect(
        shouldContinueChatSessionUnreadHistoryProbe(pagesScanned: 5),
        isFalse,
        reason: 'five 100-message pages is the fixed probe budget',
      );
      expect(
        resolveChatReopenDisposition(
          hasExplicitTarget: false,
          hasSavedPosition: true,
          prioritizeUnread: false,
        ),
        ChatReopenDisposition.savedPosition,
      );
    });

    test('an explicit message target overrides session restoration', () {
      expect(
        shouldRestoreChatSessionOffset(
          hasExplicitTarget: true,
          hasSnapshot: true,
          snapshotWasAtBottom: false,
        ),
        isFalse,
      );
      expect(
        shouldOpenChatAtBottom(
          hasExplicitTarget: true,
          openAtLatest: true,
          hasSnapshot: true,
          snapshotWasAtBottom: true,
        ),
        isFalse,
      );
    });

    test('history invalidation discards a cold session anchor', () {
      expect(
        shouldPreserveChatSessionAnchorAcrossWindowChange(
          anchorMaintenanceActive: true,
          hasSavedPivot: true,
          historyWindowInvalidated: true,
        ),
        isFalse,
      );
      expect(
        shouldPreserveChatSessionAnchorAcrossWindowChange(
          anchorMaintenanceActive: true,
          hasSavedPivot: true,
          historyWindowInvalidated: false,
        ),
        isTrue,
      );
    });

    test('a cached latest transcript never paints from offset zero', () {
      expect(
        shouldOpenChatAtBottom(
          hasExplicitTarget: false,
          openAtLatest: false,
          hasSnapshot: false,
          snapshotWasAtBottom: false,
          hasCachedLatestTranscript: true,
        ),
        isTrue,
      );
    });

    test(
      'cached transcript without snapshot still corrects to bottom when opening at bottom',
      () {
        final plan = chatInitialScrollPlan(
          hasCachedTranscript: true,
          savedPixels: null,
          savedAtBottom: false,
          openAtBottom: true,
        );

        expect(plan.initialOffset, 0);
        expect(plan.correctToBottomAfterLayout, isTrue);
      },
    );

    test('cached scrolled-up snapshot does not force a bottom correction', () {
      final plan = chatInitialScrollPlan(
        hasCachedTranscript: true,
        savedPixels: 640,
        savedAtBottom: false,
      );

      expect(plan.initialOffset, 640);
      expect(plan.correctToBottomAfterLayout, isFalse);
    });

    test('openAtBottom alone is enough to correct a cached bottom reopen', () {
      final plan = chatInitialScrollPlan(
        hasCachedTranscript: true,
        savedPixels: 0,
        savedAtBottom: false,
        openAtBottom: true,
      );

      expect(plan.correctToBottomAfterLayout, isTrue);
    });

    test('restores the anchor to the same viewport y position', () {
      expect(
        correctedChatSessionScrollOffset(
          currentPixels: 1200,
          currentAnchorViewportOffset: 76,
          savedAnchorViewportOffset: -14,
          minScrollExtent: 0,
          maxScrollExtent: 3000,
        ),
        1290,
      );
    });

    test('anchor correction is clamped to available history', () {
      expect(
        correctedChatSessionScrollOffset(
          currentPixels: 2900,
          currentAnchorViewportOffset: 200,
          savedAnchorViewportOffset: 0,
          minScrollExtent: 0,
          maxScrollExtent: 3000,
        ),
        3000,
      );
    });
  });
}

void _expectAtBottom(ScrollController controller) {
  expect(controller.position.outOfRange, isFalse);
  expect(
    controller.position.pixels,
    closeTo(controller.position.maxScrollExtent, 0.01),
  );
  expect(controller.position.isScrollingNotifier.value, isFalse);
}

bool _isVisible(WidgetTester tester, Key key) {
  final item = tester.getRect(find.byKey(key));
  final viewport = tester.getRect(find.byType(ListView));
  return item.bottom > viewport.top && item.top < viewport.bottom;
}

class _BottomRestoreHarness extends StatefulWidget {
  const _BottomRestoreHarness({
    super.key,
    required this.plan,
    required this.itemHeight,
  });

  final ChatInitialScrollPlan plan;
  final double itemHeight;

  @override
  State<_BottomRestoreHarness> createState() => _BottomRestoreHarnessState();
}

class _BottomRestoreHarnessState extends State<_BottomRestoreHarness> {
  late final ScrollController controller;
  final _bottomCorrection = ChatBottomCorrectionCoordinator();

  @override
  void initState() {
    super.initState();
    controller = ScrollController(
      initialScrollOffset: widget.plan.initialOffset,
    );
    _scheduleBottomCorrection();
  }

  @override
  void didUpdateWidget(covariant _BottomRestoreHarness oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleBottomCorrection();
  }

  void _scheduleBottomCorrection() {
    _bottomCorrection.schedule(
      enabled: widget.plan.correctToBottomAfterLayout,
      schedulePostFrame: (callback) {
        WidgetsBinding.instance.addPostFrameCallback((_) => callback());
      },
      canCorrect: () => mounted && controller.hasClients,
      correct: () => controller.jumpTo(controller.position.maxScrollExtent),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      physics: const ClampingScrollPhysics(),
      itemCount: 40,
      itemBuilder: (_, index) => SizedBox(
        key: ValueKey('message-$index'),
        height: widget.itemHeight + index % 3 * 4,
        child: Text('Message $index'),
      ),
    );
  }
}
