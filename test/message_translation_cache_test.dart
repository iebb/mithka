import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_translation_cache.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = MessageTranslationCacheKey(
    accountSlot: 2,
    chatId: 42,
    messageId: 99,
    sourceText: 'Hello',
    targetLanguageCode: 'zh-Hans',
  );
  const value = MessageTranslationValue(
    text: '你好',
    entities: [
      MessageTextEntity(offset: 0, length: 2, type: 'textEntityTypeBold'),
    ],
    languageCode: 'zh-Hans',
  );

  test(
    'reuses a successful translation throughout the seven-day window',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      var now = DateTime.utc(2026, 8, 9);
      var calls = 0;
      final cache = MessageTranslationCache(preferences, now: () => now);

      final first = await cache.resolve(key, () async {
        calls += 1;
        return value;
      });
      now = now.add(const Duration(days: 6, hours: 23, minutes: 59));
      final reloaded = MessageTranslationCache(preferences, now: () => now);
      final second = await reloaded.resolve(key, () async {
        calls += 1;
        return const MessageTranslationValue(
          text: 'duplicate',
          entities: [],
          languageCode: 'zh-Hans',
        );
      });

      expect(first.text, '你好');
      expect(second.text, '你好');
      expect(second.entities, hasLength(1));
      expect(second.entities.single.type, 'textEntityTypeBold');
      expect(calls, 1);
    },
  );

  test('refreshes an entry once its seven-day retention has elapsed', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var now = DateTime.utc(2026, 8, 9);
    final cache = MessageTranslationCache(preferences, now: () => now);
    await cache.resolve(key, () async => value);

    now = now.add(MessageTranslationCache.retention);
    var calls = 0;
    final refreshed = await cache.resolve(key, () async {
      calls += 1;
      return const MessageTranslationValue(
        text: '您好',
        entities: [],
        languageCode: 'zh-Hans',
      );
    });

    expect(refreshed.text, '您好');
    expect(calls, 1);
  });

  test(
    'scopes entries to account, message, source text, and target language',
    () {
      const otherAccount = MessageTranslationCacheKey(
        accountSlot: 3,
        chatId: 42,
        messageId: 99,
        sourceText: 'Hello',
        targetLanguageCode: 'zh-Hans',
      );
      const editedMessage = MessageTranslationCacheKey(
        accountSlot: 2,
        chatId: 42,
        messageId: 99,
        sourceText: 'Hello!',
        targetLanguageCode: 'zh-Hans',
      );
      const otherTarget = MessageTranslationCacheKey(
        accountSlot: 2,
        chatId: 42,
        messageId: 99,
        sourceText: 'Hello',
        targetLanguageCode: 'ja',
      );
      const otherMessage = MessageTranslationCacheKey(
        accountSlot: 2,
        chatId: 42,
        messageId: 100,
        sourceText: 'Hello',
        targetLanguageCode: 'zh-Hans',
      );

      expect(<String>{
        key.digest,
        otherAccount.digest,
        editedMessage.digest,
        otherTarget.digest,
        otherMessage.digest,
      }, hasLength(5));
    },
  );

  test(
    'coalesces simultaneous requests from separate cache instances',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final firstCache = MessageTranslationCache(preferences);
      final secondCache = MessageTranslationCache(preferences);
      final response = Completer<MessageTranslationValue>();
      var calls = 0;

      final first = firstCache.resolve(key, () {
        calls += 1;
        return response.future;
      });
      final second = secondCache.resolve(key, () async {
        calls += 1;
        return const MessageTranslationValue(
          text: 'duplicate',
          entities: [],
          languageCode: 'zh-Hans',
        );
      });
      response.complete(value);

      final results = await Future.wait([first, second]);
      expect(results.map((result) => result.text), everyElement('你好'));
      expect(calls, 1);
    },
  );
}
