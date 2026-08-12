import 'dart:convert';

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
    expect(prefs.getStringList('translation.options.order.v1')!.take(3), [
      options[1],
      options[2],
      options[0],
    ]);
  });

  test('fresh installs use the requested default priorities', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final translation = TranslationController(prefs);
    addTearDown(translation.dispose);

    expect(TranslationOptionIds.defaultPriorities, {
      TranslationOptionIds.telegramTranslation: 100,
      TranslationOptionIds.telegramCocoon: 200,
      TranslationOptionIds.googleTranslate: 500,
      TranslationOptionIds.iosSystemTranslation: 800,
      TranslationOptionIds.androidMlKitTranslation: 800,
      TranslationOptionIds.appleOnDeviceModel: 1000,
    });
    expect(translation.translationOptionOrder.take(6), [
      TranslationOptionIds.telegramTranslation,
      TranslationOptionIds.telegramCocoon,
      TranslationOptionIds.googleTranslate,
      TranslationOptionIds.iosSystemTranslation,
      TranslationOptionIds.androidMlKitTranslation,
      TranslationOptionIds.appleOnDeviceModel,
    ]);
  });

  test(
    'dragging assigns the midpoint priority and reset restores defaults',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final translation = TranslationController(prefs);
      addTearDown(translation.dispose);
      final options = [
        TranslationOptionIds.telegramTranslation,
        TranslationOptionIds.telegramCocoon,
        TranslationOptionIds.googleTranslate,
      ];

      translation.reorderTranslationOptions(options, 2, 1);

      expect(
        translation.translationOptionPriority(
          TranslationOptionIds.googleTranslate,
          options,
        ),
        150,
      );
      final stored =
          jsonDecode(prefs.getString('translation.options.priorities.v1')!)
              as Map<String, dynamic>;
      expect(stored[TranslationOptionIds.googleTranslate], 150);
      final restored = TranslationController(prefs);
      addTearDown(restored.dispose);
      expect(
        restored.translationOptionPriority(
          TranslationOptionIds.googleTranslate,
          options,
        ),
        150,
      );

      translation.resetTranslationOptionPriorities();

      expect(
        translation.translationOptionPriority(
          TranslationOptionIds.googleTranslate,
          options,
        ),
        500,
      );
      expect(translation.translationOptionPriorityOverrides, isEmpty);
    },
  );

  test('ordinary AI translation priorities default to 900+n', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final translation = TranslationController(prefs);
    addTearDown(translation.dispose);
    final applePcc = TranslationOptionIds.ai(
      AiSettingsController.applePccModelCandidateId,
    );
    final firstServer = TranslationOptionIds.ai(
      AiSettingsController.serverModelCandidateId('first'),
    );
    final secondServer = TranslationOptionIds.ai(
      AiSettingsController.serverModelCandidateId('second'),
    );
    final options = [
      TranslationOptionIds.telegramCocoon,
      applePcc,
      TranslationOptionIds.appleOnDeviceModel,
      firstServer,
      secondServer,
    ];

    expect(translation.translationOptionPriority(applePcc, options), 900);
    expect(translation.translationOptionPriority(firstServer, options), 901);
    expect(translation.translationOptionPriority(secondServer, options), 902);
    expect(
      translation.translationOptionPriority(
        TranslationOptionIds.appleOnDeviceModel,
        options,
      ),
      1000,
    );
  });

  test('Google Translate is an available external fallback', () async {
    final google = TranslationOptionIds.provider(
      TranslationProvider.googleTranslate,
    );
    SharedPreferences.setMockInitialValues({
      'translation.options.order.v1': [google],
      'translation.options.enabled.v1': [google],
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
        isBotApiAccount: false,
      ),
      [google],
    );
  });

  test(
    'multiple Google Cloud providers keep independent secure keys and options',
    () async {
      SharedPreferences.setMockInitialValues({
        'translation.options.enabled.v1': <String>[],
      });
      final prefs = await SharedPreferences.getInstance();
      final secureValues = <String, String>{};
      Future<String?> secureRead(String key) async => secureValues[key];
      Future<void> secureWrite(String key, String? value) async {
        if (value == null) {
          secureValues.remove(key);
        } else {
          secureValues[key] = value;
        }
      }

      final translation = TranslationController(
        prefs,
        secureRead: secureRead,
        secureWrite: secureWrite,
      );
      addTearDown(translation.dispose);
      final first = await translation.saveGoogleCloudProvider(
        name: 'Personal Google',
        apiKey: 'first-test-key',
      );
      final second = await translation.saveGoogleCloudProvider(
        name: 'Work Google',
        apiKey: 'second-test-key',
      );
      final firstOption = TranslationOptionIds.googleCloud(first.id);
      final secondOption = TranslationOptionIds.googleCloud(second.id);
      final options = [
        TranslationOptionIds.googleTranslate,
        firstOption,
        secondOption,
      ];

      expect(first.id, isNot(second.id));
      expect(translation.googleCloudProviders, [first, second]);
      expect(
        await translation.googleCloudApiKeyForProvider(first.id),
        'first-test-key',
      );
      expect(
        await translation.googleCloudApiKeyForProvider(second.id),
        'second-test-key',
      );
      expect(translation.isTranslationOptionEnabled(firstOption), isFalse);
      expect(translation.translationOptionPriority(firstOption, options), 501);
      expect(translation.translationOptionPriority(secondOption, options), 502);

      final storedMetadata = prefs.getString(
        'translation.googleCloud.providers.v1',
      )!;
      expect(storedMetadata, contains('Personal Google'));
      expect(storedMetadata, isNot(contains('first-test-key')));
      expect(storedMetadata, isNot(contains('second-test-key')));

      translation.setTranslationOptionEnabled(firstOption, true);
      translation.setTranslationOptionEnabled(secondOption, true);
      final ai = AiSettingsController(
        prefs,
        secureRead: (_) async => null,
        secureWrite: (_, _) async {},
      );
      addTearDown(ai.dispose);
      expect(
        effectiveTranslationOptionIds(
          translation: translation,
          ai: ai,
          nativeProviders: const {},
          isBotApiAccount: false,
        ),
        [firstOption, secondOption],
      );

      final restored = TranslationController(
        prefs,
        secureRead: secureRead,
        secureWrite: secureWrite,
      );
      addTearDown(restored.dispose);
      expect(restored.googleCloudProviders.map((value) => value.name), [
        'Personal Google',
        'Work Google',
      ]);
      expect(
        await restored.googleCloudApiKeyForProvider(second.id),
        'second-test-key',
      );

      await translation.deleteGoogleCloudProvider(first.id);
      expect(translation.googleCloudProviderById(first.id), isNull);
      expect(
        translation.enabledTranslationOptionIds,
        isNot(contains(firstOption)),
      );
      expect(secureValues.values, isNot(contains('first-test-key')));
      expect(
        await translation.googleCloudApiKeyForProvider(second.id),
        'second-test-key',
      );
    },
  );
}
