import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_message_merge.dart';
import 'package:mithka/tdlib/td_models.dart';

ChatMessage _message(int id, String text, {int? date}) =>
    ChatMessage(id: id, isOutgoing: false, text: text, date: date ?? id);

ChatMessage _pending(int id, int date) => ChatMessage(
  id: id,
  isOutgoing: true,
  text: 'pending $id',
  date: date,
  isSending: true,
);

ChatMessage _document(
  int id, {
  int albumId = 0,
  int senderId = 7,
  bool outgoing = false,
}) => ChatMessage(
  id: id,
  isOutgoing: outgoing,
  text: '',
  date: id,
  senderId: senderId,
  contentType: 'messageDocument',
  mediaAlbumId: albumId,
  document: MessageDocument(
    fileName: 'file-$id.zip',
    size: 1024,
    ext: 'ZIP',
    file: null,
  ),
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

  test('album grouping never merges unrelated or incompatible files', () {
    expect(areMessagesInSameMediaAlbum(_document(1), _document(2)), isFalse);
    expect(
      areMessagesInSameMediaAlbum(
        _document(1, albumId: 9),
        _document(2, albumId: 9, senderId: 8),
      ),
      isFalse,
    );
    expect(
      areMessagesInSameMediaAlbum(
        _document(1, albumId: 9),
        ChatMessage(
          id: 2,
          isOutgoing: false,
          text: '',
          date: 2,
          senderId: 7,
          contentType: 'messagePhoto',
          mediaAlbumId: 9,
          image: TdFileRef(id: 2),
        ),
      ),
      isFalse,
    );
  });
}
