import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_message_merge.dart';
import 'package:mithka/tdlib/td_models.dart';

ChatMessage _message(int id, String text) =>
    ChatMessage(id: id, isOutgoing: false, text: text, date: id);

ChatMessage _pending(int id, int date) => ChatMessage(
  id: id,
  isOutgoing: true,
  text: 'pending $id',
  date: date,
  isSending: true,
);

void main() {
  test(
    'background history hydration fills the middle without clearing tail',
    () {
      final previouslyLoaded = [_message(10, 'old'), _message(20, 'anchor')];
      final current = [...previouslyLoaded, _message(50, 'latest')];
      final hydrated = [
        _message(20, 'anchor refreshed'),
        _message(30, 'middle one'),
        _message(40, 'middle two'),
        _message(50, 'latest refreshed'),
      ];

      final merged = mergeChatHistoryWindow(
        currentAtRequestStart: previouslyLoaded,
        currentAtCompletion: current,
        fetched: hydrated,
        replaceCurrentWindow: false,
      );

      expect(merged.map((message) => message.id), [10, 20, 30, 40, 50]);
      expect(merged.last.text, 'latest refreshed');
    },
  );

  test('explicit target replacement preserves messages arriving in flight', () {
    final atStart = [_message(100, 'old window')];
    final atCompletion = [...atStart, _message(500, 'live arrival')];
    final aroundTarget = [
      _message(200, 'target'),
      _message(300, 'after target'),
      _message(400, 'before live'),
    ];

    final merged = mergeChatHistoryWindow(
      currentAtRequestStart: atStart,
      currentAtCompletion: atCompletion,
      fetched: aroundTarget,
      replaceCurrentWindow: true,
    );

    expect(merged.map((message) => message.id), [200, 300, 400, 500]);
    expect(merged.any((message) => message.id == 100), isFalse);
  });

  test('disconnected target replacement drops newer live arrivals', () {
    final atStart = [_message(400, 'latest before jump')];
    final atCompletion = [...atStart, _message(500, 'live arrival')];
    final aroundOldTarget = [_message(100, 'old target'), _message(200, 'old')];

    final merged = mergeChatHistoryWindow(
      currentAtRequestStart: atStart,
      currentAtCompletion: atCompletion,
      fetched: aroundOldTarget,
      replaceCurrentWindow: true,
      preserveLiveArrivals: false,
    );

    expect(merged.map((message) => message.id), [100, 200]);
  });

  test('live messages only append to a window that reaches latest history', () {
    expect(
      shouldMergeLiveMessageIntoChatWindow(historyReachesLatest: true),
      isTrue,
    );
    expect(
      shouldMergeLiveMessageIntoChatWindow(historyReachesLatest: false),
      isFalse,
    );
  });

  test('TDLib sending-state messages remain at the latest edge', () {
    final merged = mergeChatMessages(
      [_message(100, 'old'), _message(200, 'latest')],
      [_pending(1001, 300), _pending(1002, 301)],
    );

    expect(merged.map((message) => message.id), [100, 200, 1001, 1002]);
  });

  test('same-second pending messages keep send order', () {
    final merged = mergeChatMessages(const <ChatMessage>[], [
      _pending(1001, 300),
      _pending(1002, 300),
    ]);

    expect(merged.map((message) => message.id), [1001, 1002]);
  });

  test('latest server ID ignores pending messages at the tail', () {
    expect(
      latestServerMessageId([
        _message(100, 'old'),
        _message(200, 'latest'),
        _pending(1001, 300),
      ]),
      200,
    );
    expect(latestServerMessageId([_pending(1001, 300)]), 0);
  });

  test('read boundary falls back when filtering leaves only pending', () {
    expect(
      latestServerMessageReadBoundary(
        visibleMessages: [_pending(1001, 300)],
        allMessages: [
          _message(100, 'filtered'),
          _message(200, 'filtered latest'),
          _pending(1001, 300),
        ],
      ),
      200,
    );
  });

  test('pending outgoing messages are never reported as peer-read', () {
    expect(
      isOutgoingServerMessageRead(
        message: _pending(1001, 300),
        lastReadOutboxId: 200,
      ),
      isFalse,
    );
    expect(
      isOutgoingServerMessageRead(
        message: ChatMessage(
          id: 150,
          isOutgoing: true,
          text: 'sent',
          date: 300,
        ),
        lastReadOutboxId: 200,
      ),
      isTrue,
    );
  });

  test('an empty local page does not exhaust remote older history', () {
    expect(confirmsOlderHistoryExhausted(onlyLocal: true), isFalse);
    expect(confirmsOlderHistoryExhausted(onlyLocal: false), isTrue);
    expect(confirmsOlderHistoryExhausted(onlyLocal: false), isTrue);
  });
}
