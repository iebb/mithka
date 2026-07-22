import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/auto_translate_policy.dart';
import 'package:mithka/chat/chat_translation_panel.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  ChatMessage message(
    int id,
    String text, {
    bool outgoing = false,
    bool service = false,
    String? translation,
    String? translationLanguage,
    bool translating = false,
    List<MessageTextEntity> entities = const [],
  }) => ChatMessage(
    id: id,
    isOutgoing: outgoing,
    text: text,
    date: id,
    isService: service,
    contentType: 'messageText',
    translationText: translation,
    translationLanguageCode: translationLanguage,
    isTranslating: translating,
    textEntities: entities,
  );

  test(
    'automatic translation selects newest untranslated incoming messages',
    () {
      final candidates = automaticTranslationCandidates(
        [
          message(1, 'old incoming'),
          message(2, 'outgoing', outgoing: true),
          message(3, 'service', service: true),
          message(
            4,
            'already translated',
            translation: 'übersetzt',
            translationLanguage: 'de-DE',
          ),
          message(5, 'loading', translating: true),
          message(6, 'failed earlier'),
          message(7, 'new incoming'),
        ],
        targetLanguageCode: 'de',
        excludedMessageIds: const {6},
      );

      expect(candidates.map((message) => message.id), [7, 1]);
    },
  );

  test('language sample follows Telegram incoming-message thresholds', () {
    final samples = automaticTranslationLanguageSamples([
      message(1, 'short'),
      message(2, 'This outgoing text is long enough', outgoing: true),
      message(3, 'This incoming text is long enough'),
      message(4, 'Another incoming message for detection'),
    ]);

    expect(samples, [
      'This incoming text is long enough',
      'Another incoming message for detection',
    ]);
  });

  test('chat language combines per-message confidence and text length', () {
    final language = dominantAutomaticTranslationLanguage(const [
      AutomaticTranslationLanguageEvidence(
        languageCode: 'en-US',
        confidence: 0.92,
        characterCount: 80,
      ),
      AutomaticTranslationLanguageEvidence(
        languageCode: 'fr',
        confidence: 0.99,
        characterCount: 20,
      ),
      AutomaticTranslationLanguageEvidence(
        languageCode: 'en-GB',
        confidence: 0.75,
        characterCount: 40,
      ),
    ]);

    expect(language, 'en');
  });

  test('language samples remove code, links, mentions, and hashtags', () {
    const text = 'https://example.com hello world';
    final samples = automaticTranslationLanguageSamples([
      message(
        1,
        text,
        entities: const [
          MessageTextEntity(offset: 0, length: 19, type: 'textEntityTypeUrl'),
        ],
      ),
    ]);

    expect(samples, ['hello world']);
  });

  testWidgets('chat translation panel toggles, configures, and dismisses', (
    tester,
  ) async {
    var toggled = false;
    var configured = false;
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatTranslationPanel(
            active: false,
            targetLanguageLabel: 'German',
            isTranslating: false,
            onToggle: () => toggled = true,
            onChooseLanguage: () => configured = true,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );

    expect(find.text('Translate to German'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-translation-toggle')));
    await tester.tap(find.byKey(const ValueKey('chat-translation-language')));
    await tester.tap(find.byKey(const ValueKey('chat-translation-dismiss')));
    expect(toggled, isTrue);
    expect(configured, isTrue);
    expect(dismissed, isTrue);
  });
}
