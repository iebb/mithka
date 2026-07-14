import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_message_merge.dart';
import 'package:mithka/tdlib/td_models.dart';

ChatMessage _message(int id, String text) =>
    ChatMessage(id: id, isOutgoing: false, text: text, date: id);

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
}
