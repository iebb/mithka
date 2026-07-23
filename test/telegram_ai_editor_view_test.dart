import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/telegram_ai_editor_view.dart';
import 'package:mithka/chat/telegram_ai_service.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('rewrites with a selected style and exposes add-style flow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final requests = <Map<String, dynamic>>[];
    final service = TelegramAiService(
      queryOverride: (request) async {
        requests.add(Map<String, dynamic>.of(request));
        return switch (request['@type']) {
          'getOption' => _option(request['name'] as String),
          'addTextCompositionStyle' => {'@type': 'ok'},
          'fixTextWithAi' => {
            '@type': 'formattedText',
            'text': 'Fixed draft',
            'entities': <Map<String, dynamic>>[],
          },
          'composeTextWithAi' => {
            '@type': 'formattedText',
            'text': 'Formal rewrite',
            'entities': <Map<String, dynamic>>[],
          },
          _ => throw StateError('Unexpected request: $request'),
        };
      },
    );
    addTearDown(service.dispose);
    await service.capabilities();
    expect(service.capabilitiesSnapshot?.customStylesSupported, isTrue);
    const style = TelegramAiStyle(
      name: 'formal',
      title: 'Formal',
      customEmojiId: 0,
      isCustom: true,
      isCreator: false,
      installCount: 5,
      prompt: 'Rewrite using formal language.',
      creatorUserId: 42,
    );
    await service.addStyle(style.name, style: style);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: TelegramAiEditorView(
            service: service,
            source: const TelegramAiFormattedText(
              text: 'A draft that should be rewritten.',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Translate'), findsOneWidget);
    expect(find.text('Style'), findsOneWidget);
    expect(find.text('Fix'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('telegramAiMode-translate')));
    await tester.pumpAndSettle();
    expect(find.text('Choose language'), findsOneWidget);
    expect(find.text('Add Emoji'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('telegramAiMode-fix')));
    await tester.pumpAndSettle();
    expect(find.text('Add Emoji'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('telegramAiMode-style')));
    await tester.pumpAndSettle();
    expect(find.text('Formal'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('telegramAiStyleIcon-formal')),
      findsOneWidget,
    );
    final addStyle = find.byKey(const ValueKey('telegramAiAddStyle'));
    expect(addStyle, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('telegramAiStyle-formal')));
    await tester.pumpAndSettle();
    expect(find.text('Rewrite'), findsOneWidget);

    await tester.tap(addStyle);
    await tester.pumpAndSettle();
    expect(find.text('AI Writing Styles'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rewrite'));
    await tester.pumpAndSettle();
    expect(find.text('Formal rewrite'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
    expect(
      requests
          .where((request) => request['@type'] == 'composeTextWithAi')
          .single,
      containsPair('style_name', 'formal'),
    );
  });

  test('Simplified Chinese editor labels contain no broken placeholders', () {
    expect(
      AppStrings.tForLocale('zhHans', AppStringKeys.telegramAiEditorAddEmoji),
      '添加表情',
    );
    expect(
      AppStrings.tForLocale(
        'zhHans',
        AppStringKeys.telegramAiEditorRewriteTitle,
      ),
      'AI 改写',
    );
    for (final key in [
      AppStringKeys.telegramAiEditorOriginal,
      AppStringKeys.telegramAiEditorResult,
      AppStringKeys.telegramAiEditorTranslate,
      AppStringKeys.telegramAiEditorStyle,
      AppStringKeys.telegramAiEditorFix,
      AppStringKeys.telegramAiEditorSelectStyle,
    ]) {
      final value = AppStrings.tForLocale('zhHans', key);
      expect(value, isNot(key));
      expect(value, isNot(contains('%1')));
    }
  });
}

Map<String, dynamic> _option(String name) => switch (name) {
  'version' => {'@type': 'optionValueString', 'value': 'test'},
  'text_composition_style_title_length_max' => {
    '@type': 'optionValueInteger',
    'value': 64,
  },
  'text_composition_style_prompt_length_max' => {
    '@type': 'optionValueInteger',
    'value': 1024,
  },
  'added_text_composition_style_count_max' => {
    '@type': 'optionValueInteger',
    'value': 10,
  },
  'speech_recognition_trial_weekly_count' => {
    '@type': 'optionValueInteger',
    'value': 0,
  },
  _ => {'@type': 'optionValueEmpty'},
};
