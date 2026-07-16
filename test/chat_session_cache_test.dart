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

    final restored = cache.read(42);
    expect(restored?.messages.map((message) => message.id), [1, 2]);
    expect(restored?.anchoredHistory, isFalse);
    expect(restored?.olderHistoryExhausted, isTrue);
    expect(restored?.firstContactInfo?.countryCode, 'SG');
  });

  test('evicts the least recently used transcript', () {
    final cache = ChatSessionCache(capacity: 2);
    cache.store(chatId: 1, messages: [_message(1)], anchoredHistory: false);
    cache.store(chatId: 2, messages: [_message(2)], anchoredHistory: false);
    expect(cache.read(1), isNotNull);

    cache.store(chatId: 3, messages: [_message(3)], anchoredHistory: false);

    expect(cache.read(1), isNotNull);
    expect(cache.read(2), isNull);
    expect(cache.read(3), isNotNull);
  });
}
