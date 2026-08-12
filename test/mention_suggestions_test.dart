import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/bot_platform_service.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/emoji_text_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';

class _MentionTestChatViewModel extends ChatViewModel {
  _MentionTestChatViewModel()
    : super(chatId: 1, title: 'Group', markReadOnOpen: false) {
    isGroup = true;
  }

  @override
  void sendTyping() {}

  @override
  void setDraft(
    String value, {
    String? formattedText,
    List<Map<String, dynamic>> entities = const [],
  }) {
    draft = value;
  }

  @override
  Future<List<MentionCandidate>> searchMentionCandidates(String query) async {
    return const [
      MentionCandidate(userId: 123456, name: 'Natu Profile', username: 'natu'),
    ];
  }
}

Future<_MentionTestChatViewModel> _pumpComposer(
  WidgetTester tester, {
  BotPlatformService? botPlatform,
}) async {
  final vm = _MentionTestChatViewModel();
  addTearDown(vm.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ChatInputBar(
            vm: vm,
            onStartCall: (_) {},
            onMessageSent: () {},
            botPlatformForTesting: botPlatform,
          ),
        ),
      ),
    ),
  );
  return vm;
}

void main() {
  group('mention query detection', () {
    test('finds an active mention at the cursor', () {
      final query = activeMentionQuery(
        'hello @nat',
        const TextSelection.collapsed(offset: 10),
      );

      expect(query, isNotNull);
      expect(query!.start, 6);
      expect(query.end, 10);
      expect(query.query, 'nat');
    });

    test('opens the menu immediately after at-sign', () {
      final query = activeMentionQuery(
        '@',
        const TextSelection.collapsed(offset: 1),
      );

      expect(query?.query, isEmpty);
    });

    test('does not treat email addresses or selections as mention queries', () {
      expect(
        activeMentionQuery(
          'mail@example.com',
          const TextSelection.collapsed(offset: 16),
        ),
        isNull,
      );
      expect(
        activeMentionQuery(
          '@natu',
          const TextSelection(baseOffset: 1, extentOffset: 5),
        ),
        isNull,
      );
    });

    test('stops at punctuation and only follows a caret at the token end', () {
      expect(
        activeMentionQuery('@natu.', const TextSelection.collapsed(offset: 6)),
        isNull,
      );
      expect(
        activeMentionQuery(
          '@natu later',
          const TextSelection.collapsed(offset: 3),
        ),
        isNull,
      );
      expect(
        activeMentionQuery(
          '你好 @小明',
          const TextSelection.collapsed(offset: 6),
        )?.query,
        '小明',
      );
    });
  });

  test('selected member is inserted as an ID-backed mention', () {
    final controller = EmojiTextEditingController();
    addTearDown(controller.dispose);
    controller.value = const TextEditingValue(
      text: 'hello @na later',
      selection: TextSelection.collapsed(offset: 9),
    );

    controller.insertTextMention(
      start: 6,
      end: 9,
      label: 'Natu Profile',
      userId: 123456,
    );

    final (text, entities) = controller.toFormatted();
    expect(text, 'hello @Natu Profile later');
    expect(controller.selection.extentOffset, 20);
    expect(entities, hasLength(1));
    expect(entities.single['offset'], 6);
    expect(entities.single['length'], '@Natu Profile'.length);
    expect(entities.single['type'], {
      '@type': 'textEntityTypeMentionName',
      'user_id': 123456,
    });
  });

  test('selected member gets a trailing space at the end of the draft', () {
    final controller = EmojiTextEditingController();
    addTearDown(controller.dispose);
    controller.value = const TextEditingValue(
      text: '@na',
      selection: TextSelection.collapsed(offset: 3),
    );

    controller.insertTextMention(
      start: 0,
      end: 3,
      label: 'Natu Profile',
      userId: 123456,
    );

    expect(controller.text, '@Natu Profile ');
    expect(controller.selection.extentOffset, controller.text.length);
  });

  testWidgets('mention hints track focus and punctuation without a card', (
    tester,
  ) async {
    await _pumpComposer(tester);
    final field = find.byType(TextField).first;

    await tester.tap(field);
    await tester.enterText(field, '@na');
    await tester.pump(const Duration(milliseconds: 121));
    await tester.pump();

    final menu = find.byKey(const ValueKey('mentionSuggestions'));
    expect(menu, findsOneWidget);
    expect(tester.widget(menu), isA<Padding>());

    await tester.enterText(field, '@na.');
    await tester.pump(const Duration(milliseconds: 121));
    expect(menu, findsNothing);

    await tester.enterText(field, '@na');
    await tester.pump(const Duration(milliseconds: 121));
    await tester.pump();
    expect(menu, findsOneWidget);

    final outsideFocus = FocusNode();
    addTearDown(outsideFocus.dispose);
    FocusManager.instance.rootScope.requestFocus(outsideFocus);
    await tester.pump();
    await tester.pump();
    expect(outsideFocus.hasFocus, isTrue);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
    expect(menu, findsNothing);
  });

  testWidgets('selecting a mention appends a space', (tester) async {
    await _pumpComposer(tester);
    final field = find.byType(TextField).first;

    await tester.tap(field);
    await tester.enterText(field, '@na');
    await tester.pump(const Duration(milliseconds: 121));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mentionCandidate-123456')));
    await tester.pump();

    final controller = tester.widget<TextField>(field).controller!;
    expect(controller.text, '@Natu Profile ');
    expect(controller.selection.extentOffset, controller.text.length);
  });

  testWidgets(
    'mouse selection keeps focus and does not query an ID-backed mention',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      await _pumpComposer(
        tester,
        botPlatform: BotPlatformService(
          query: (request) async {
            requests.add(request);
            throw StateError('unexpected inline-bot lookup');
          },
        ),
      );
      final field = find.byType(TextField).first;

      await tester.tap(field, kind: PointerDeviceKind.mouse);
      await tester.enterText(field, '@na');
      await tester.pump(const Duration(milliseconds: 121));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('mentionCandidate-123456')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      final textField = tester.widget<TextField>(field);
      expect(textField.focusNode!.hasFocus, isTrue);
      expect(textField.controller!.text, '@Natu Profile ');

      await tester.pump(const Duration(milliseconds: 300));
      expect(requests, isEmpty);
    },
  );

  testWidgets('inline results stay hidden until a response is loaded', (
    tester,
  ) async {
    await _pumpComposer(tester);
    final field = find.byType(TextField).first;

    await tester.tap(field);
    await tester.enterText(field, '@some_bot ');
    await tester.pump();

    expect(find.byKey(const ValueKey('inlineBotResultMenu')), findsNothing);
    expect(find.text('Searching inline results…'), findsNothing);
  });
}
