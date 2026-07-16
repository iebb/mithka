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

  test('sending a message releases a preserved viewport', () {
    final policy = ChatAutoScrollPolicy(preserveViewport: true);

    policy.noteMessageSent();

    expect(policy.preservesViewport, isFalse);
    expect(policy.shouldFollowAppendedMessage(wasNearBottom: true), isTrue);
  });
}
