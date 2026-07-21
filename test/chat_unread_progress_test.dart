import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_unread_progress.dart';

void main() {
  test('AI summary attachment requires at least 100 unread messages', () {
    expect(
      shouldShowUnreadChatSummaryAttachment(
        unreadMessageCount: 99,
        providerAvailable: true,
      ),
      isFalse,
    );
    expect(
      shouldShowUnreadChatSummaryAttachment(
        unreadMessageCount: 100,
        providerAvailable: true,
      ),
      isTrue,
    );
    expect(
      shouldShowUnreadChatSummaryAttachment(
        unreadMessageCount: 1000,
        providerAvailable: false,
      ),
      isFalse,
    );
  });

  testWidgets('unread badge remains when the AI attachment is absent', (
    tester,
  ) async {
    Future<void> pump({required bool attachAi}) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ChatNewMessagesControlShell(
          unreadBadge: const Text('90 unread'),
          aiAttachment: attachAi ? const Text('AI') : null,
        ),
      ),
    );

    await pump(attachAi: false);
    expect(
      find.byKey(ChatNewMessagesControlShell.unreadBadgeKey),
      findsOneWidget,
    );
    expect(
      find.byKey(ChatNewMessagesControlShell.aiAttachmentKey),
      findsNothing,
    );
    expect(find.text('90 unread'), findsOneWidget);

    await pump(attachAi: true);
    expect(
      find.byKey(ChatNewMessagesControlShell.unreadBadgeKey),
      findsOneWidget,
    );
    expect(
      find.byKey(ChatNewMessagesControlShell.aiAttachmentKey),
      findsOneWidget,
    );
    expect(find.text('90 unread'), findsOneWidget);
  });

  testWidgets('AI attachment is overlaid on the unread badge right edge', (
    tester,
  ) async {
    const badgeKey = ValueKey('badgeBounds');
    const attachmentKey = ValueKey('attachmentBounds');
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ChatNewMessagesControlShell(
          unreadBadge: SizedBox(key: badgeKey, width: 160, height: 32),
          aiAttachment: SizedBox(key: attachmentKey, width: 40, height: 40),
        ),
      ),
    );

    final badgeRect = tester.getRect(find.byKey(badgeKey));
    final attachmentRect = tester.getRect(find.byKey(attachmentKey));
    expect(attachmentRect.right, badgeRect.right);
    expect(attachmentRect.left, lessThan(badgeRect.right));
    expect(attachmentRect.center.dy, badgeRect.center.dy);
  });

  test('new messages replace the jump-to-bottom button while scrolled up', () {
    expect(
      chatBottomIndicator(isScrolledUp: true, hasNewMessages: true),
      ChatBottomIndicator.newMessages,
    );
    expect(
      chatBottomIndicator(isScrolledUp: true, hasNewMessages: false),
      ChatBottomIndicator.jumpToBottom,
    );
    expect(
      chatBottomIndicator(isScrolledUp: false, hasNewMessages: true),
      ChatBottomIndicator.none,
    );
  });

  test('entry unread control is placed at the top when already latest', () {
    expect(
      chatNewMessagesControlPlacement(
        isScrolledUp: false,
        hasNewMessages: true,
        isEntryUnread: true,
      ),
      ChatNewMessagesControlPlacement.top,
    );
  });

  test('new messages are placed at the bottom while scrolled up', () {
    expect(
      chatNewMessagesControlPlacement(
        isScrolledUp: true,
        hasNewMessages: true,
        isEntryUnread: false,
      ),
      ChatNewMessagesControlPlacement.bottom,
    );
  });

  test('live messages do not cover the transcript while already latest', () {
    expect(
      chatNewMessagesControlPlacement(
        isScrolledUp: false,
        hasNewMessages: true,
        isEntryUnread: false,
      ),
      ChatNewMessagesControlPlacement.hidden,
    );
  });

  test('live message buffer reports each TDLib arrival only once', () {
    final buffer = ChatLiveMessageBuffer();

    expect(buffer.add(20), isTrue);
    expect(buffer.add(20), isFalse);
    expect(buffer.add(21), isTrue);
    expect(buffer.takeAll(), [20, 21]);
    expect(buffer.takeAll(), isEmpty);
  });

  test('first live server message is surfaced after pending-only history', () {
    expect(
      appendedLiveIncomingMessageIds(
        previousNewestMessageId: null,
        liveIncomingMessageIds: const [10],
        currentMessageIds: const [-1, 10],
      ),
      [10],
    );
  });

  test(
    'entry read boundary still resolves after the live boundary advances',
    () {
      const incomingIds = [103, 101, 102];

      expect(
        firstUnreadMessageIdAfterBoundary(
          incomingMessageIds: incomingIds,
          lastReadInboxId: 100,
        ),
        101,
      );
      expect(
        firstUnreadMessageIdAfterBoundary(
          incomingMessageIds: incomingIds,
          lastReadInboxId: 103,
        ),
        isNull,
      );
    },
  );

  test('initial unread count decreases as messages become visible', () {
    final progress = ChatUnreadProgress();

    expect(progress.remaining(initialUnreadCount: 5), 5);
    expect(progress.markVisible(messageId: 10, initialUnread: true), isTrue);
    expect(progress.remaining(initialUnreadCount: 5), 4);
    expect(progress.markVisible(messageId: 11, initialUnread: true), isTrue);
    expect(progress.remaining(initialUnreadCount: 5), 3);
  });

  test('the same message is consumed only once', () {
    final progress = ChatUnreadProgress();

    progress.markVisible(messageId: 10, initialUnread: true);
    expect(progress.markVisible(messageId: 10, initialUnread: true), isFalse);
    expect(progress.remaining(initialUnreadCount: 2), 1);
  });

  test('live messages decrement without double-counting initial unread', () {
    final progress = ChatUnreadProgress();

    progress.addLiveMessage(20);
    expect(progress.remaining(initialUnreadCount: 3), 4);
    expect(progress.markVisible(messageId: 20, initialUnread: true), isTrue);
    expect(progress.remaining(initialUnreadCount: 3), 3);
  });

  test('batched live arrivals increase the indicator once per message', () {
    final progress = ChatUnreadProgress();

    expect(progress.addLiveMessages([21, 22, 23]), isTrue);
    expect(progress.liveCount, 3);
    expect(progress.remaining(initialUnreadCount: 0), 3);

    expect(progress.addLiveMessages([22, 23]), isFalse);
    expect(progress.liveCount, 3);
  });
}
