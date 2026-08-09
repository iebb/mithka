import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/translation_fallback.dart';
import 'package:mithka/settings/ai_settings_controller.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'Bot API accounts hide Telegram translation without a fallback',
    () async {
      SharedPreferences.setMockInitialValues({
        'translation.options.order.v1': [
          TranslationOptionIds.provider(TranslationProvider.tdlib),
          TranslationOptionIds.provider(TranslationProvider.myMemory),
        ],
        'translation.options.enabled.v1': [
          TranslationOptionIds.provider(TranslationProvider.tdlib),
        ],
      });
      final prefs = await SharedPreferences.getInstance();
      final translation = TranslationController(prefs);
      final ai = AiSettingsController(
        prefs,
        secureRead: (_) async => null,
        secureWrite: (_, _) async {},
      );
      addTearDown(translation.dispose);
      addTearDown(ai.dispose);

      expect(
        effectiveTranslationOptionIds(
          translation: translation,
          ai: ai,
          nativeProviders: const {},
          isBotApiAccount: true,
        ),
        isEmpty,
      );

      final myMemory = TranslationOptionIds.provider(
        TranslationProvider.myMemory,
      );
      translation.setTranslationOptionEnabled(myMemory, true);
      expect(
        effectiveTranslationOptionIds(
          translation: translation,
          ai: ai,
          nativeProviders: const {},
          isBotApiAccount: true,
        ),
        [myMemory],
      );
    },
  );

  test(
    'Telegram rate limits activate a persisted ten-minute fallback',
    () async {
      SharedPreferences.setMockInitialValues({
        'translation.options.order.v1': [
          TranslationOptionIds.provider(TranslationProvider.tdlib),
          TranslationOptionIds.provider(TranslationProvider.myMemory),
        ],
        'translation.options.enabled.v1': [
          TranslationOptionIds.provider(TranslationProvider.tdlib),
          TranslationOptionIds.provider(TranslationProvider.myMemory),
        ],
      });
      final prefs = await SharedPreferences.getInstance();
      final translation = TranslationController(prefs);
      final ai = AiSettingsController(
        prefs,
        secureRead: (_) async => null,
        secureWrite: (_, _) async {},
      );
      addTearDown(translation.dispose);
      addTearDown(ai.dispose);
      final now = DateTime.now();

      translation.markTelegramTranslationUnavailable(now: now);

      expect(translation.isTelegramTranslationAvailable(now: now), isFalse);
      expect(
        translation.telegramTranslationUnavailableUntil,
        now.add(const Duration(minutes: 10)),
      );
      expect(
        prefs.getInt('translation.telegramUnavailableUntil.v1'),
        now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
      );
      expect(
        effectiveTranslationOptionIds(
          translation: translation,
          ai: ai,
          nativeProviders: const {},
          isBotApiAccount: false,
        ),
        [TranslationOptionIds.provider(TranslationProvider.myMemory)],
      );
    },
  );

  test('recognizes TDLib translation flood responses', () {
    expect(
      isTelegramTranslationRateLimit(
        TdError({
          '@type': 'error',
          'code': 429,
          'message': 'Too Many Requests',
        }),
      ),
      isTrue,
    );
    expect(
      isTelegramTranslationRateLimit(
        TdError({'@type': 'error', 'code': 400, 'message': 'FLOOD_WAIT_30'}),
      ),
      isTrue,
    );
    expect(
      isTelegramTranslationRateLimit(
        TdError({'@type': 'error', 'code': 400, 'message': 'Bad Request'}),
      ),
      isFalse,
    );
  });

  test('sortable option order persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final translation = TranslationController(prefs);
    addTearDown(translation.dispose);
    final options = [
      TranslationOptionIds.provider(TranslationProvider.tdlib),
      TranslationOptionIds.provider(TranslationProvider.myMemory),
      TranslationOptionIds.provider(TranslationProvider.lingva),
    ];

    translation.reorderTranslationOptions(options, 0, 2);

    expect(translation.orderedTranslationOptions(options), [
      options[1],
      options[2],
      options[0],
    ]);
    expect(prefs.getStringList('translation.options.order.v1'), [
      options[1],
      options[2],
      options[0],
    ]);
  });
}
