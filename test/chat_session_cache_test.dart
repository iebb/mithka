import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_first_contact_info.dart';
import 'package:mithka/chat/chat_session_cache.dart';
import 'package:mithka/tdlib/td_models.dart';

ChatMessage _message(int id) =>
    ChatMessage(id: id, isOutgoing: false, text: 'message $id', date: id);

void main() {
  test('stores a defensive transcript snapshot without viewport state', () {
    final cache = ChatSessionCache();
    final messages = [_message(1), _message(2)];

    cache.store(
      accountSlot: 0,
      chatId: 42,
      messages: messages,
      anchoredHistory: false,
      olderHistoryExhausted: true,
      firstContactInfo: const ChatFirstContactInfo(
        countryCode: 'SG',
        registrationMonth: 7,
        registrationYear: 2026,
      ),
    );
    messages.add(_message(3));

    final restored = cache.read(accountSlot: 0, chatId: 42);
    expect(restored?.messages.map((message) => message.id), [1, 2]);
    expect(restored?.anchoredHistory, isFalse);
    expect(restored?.olderHistoryExhausted, isTrue);
    expect(restored?.firstContactInfo?.countryCode, 'SG');
  });

  test('evicts the least recently used transcript', () {
    final cache = ChatSessionCache(capacity: 2);
    cache.store(
      accountSlot: 0,
      chatId: 1,
      messages: [_message(1)],
      anchoredHistory: false,
    );
    cache.store(
      accountSlot: 0,
      chatId: 2,
      messages: [_message(2)],
      anchoredHistory: false,
    );
    expect(cache.read(accountSlot: 0, chatId: 1), isNotNull);

    cache.store(
      accountSlot: 0,
      chatId: 3,
      messages: [_message(3)],
      anchoredHistory: false,
    );

    expect(cache.read(accountSlot: 0, chatId: 1), isNotNull);
    expect(cache.read(accountSlot: 0, chatId: 2), isNull);
    expect(cache.read(accountSlot: 0, chatId: 3), isNotNull);
  });

  test('keeps colliding chat ids isolated by account slot', () {
    final cache = ChatSessionCache();
    cache.store(
      accountSlot: 0,
      chatId: 42,
      messages: [_message(1)],
      anchoredHistory: false,
    );
    cache.store(
      accountSlot: 1,
      chatId: 42,
      messages: [_message(2)],
      anchoredHistory: false,
    );

    expect(cache.read(accountSlot: 0, chatId: 42)?.messages.single.id, 1);
    expect(cache.read(accountSlot: 1, chatId: 42)?.messages.single.id, 2);
  });

  test('keeps forum topics and the whole chat isolated', () {
    final cache = ChatSessionCache();
    cache.store(
      accountSlot: 0,
      chatId: 42,
      forumTopicId: 7,
      messages: [_message(7)],
      anchoredHistory: false,
      olderHistoryExhausted: true,
    );
    cache.store(
      accountSlot: 0,
      chatId: 42,
      forumTopicId: 9,
      messages: [_message(9)],
      anchoredHistory: false,
    );
    cache.store(
      accountSlot: 0,
      chatId: 42,
      messages: [_message(1)],
      anchoredHistory: false,
    );

    final topicA = cache.read(accountSlot: 0, chatId: 42, forumTopicId: 7);
    final topicB = cache.read(accountSlot: 0, chatId: 42, forumTopicId: 9);
    final whole = cache.read(accountSlot: 0, chatId: 42);
    expect(topicA?.messages.single.id, 7);
    expect(topicA?.olderHistoryExhausted, isTrue);
    expect(topicB?.messages.single.id, 9);
    expect(topicB?.olderHistoryExhausted, isFalse);
    expect(whole?.messages.single.id, 1);
    expect(whole?.olderHistoryExhausted, isFalse);
    expect(cache.read(accountSlot: 0, chatId: 42, forumTopicId: 11), isNull);
  });

  test('clear releases every reusable transcript snapshot', () {
    final cache = ChatSessionCache(capacity: 2);
    cache.store(
      accountSlot: 0,
      chatId: 1,
      messages: [_message(1)],
      anchoredHistory: false,
    );
    cache.store(
      accountSlot: 0,
      chatId: 2,
      messages: [_message(2)],
      anchoredHistory: false,
    );

    cache.clear();

    expect(cache.read(accountSlot: 0, chatId: 1), isNull);
    expect(cache.read(accountSlot: 0, chatId: 2), isNull);
  });

  test(
    'write gate skips non-transcript notifications and refreshes on exit',
    () {
      final gate = ChatSessionCacheWriteGate();
      final messages = [_message(1), _message(2)];

      expect(
        gate.shouldStore(
          messages: messages,
          anchoredHistory: false,
          olderHistoryExhausted: false,
          firstContactInfo: null,
        ),
        isTrue,
      );
      expect(
        gate.shouldStore(
          messages: messages,
          anchoredHistory: false,
          olderHistoryExhausted: false,
          firstContactInfo: null,
        ),
        isFalse,
      );
      expect(
        gate.shouldStore(
          messages: messages,
          anchoredHistory: false,
          olderHistoryExhausted: false,
          firstContactInfo: null,
          force: true,
        ),
        isTrue,
      );
      expect(
        gate.shouldStore(
          messages: List<ChatMessage>.of(messages),
          anchoredHistory: false,
          olderHistoryExhausted: false,
          firstContactInfo: null,
        ),
        isTrue,
      );
    },
  );
}
