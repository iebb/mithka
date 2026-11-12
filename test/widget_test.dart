// Core composer, privacy, session and message parsing regressions.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/ai_reply_service.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/emoji_text_controller.dart';
import 'package:mithka/chat/secret_chat_service.dart';
import 'package:mithka/chat/telegram_ai_service.dart';
import 'package:mithka/components/keyboard_dismiss_on_tap.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ai_settings_controller.dart';
import 'package:mithka/settings/apple_pcc_api.dart';
import 'package:mithka/settings/keyword_blocker.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FocusTestChatViewModel extends ChatViewModel {
  _FocusTestChatViewModel({
    super.title = 'Test',
    super.sessionMessages = const [],
    super.sessionAnchorMessageId,
  }) : super(chatId: 1, markReadOnOpen: false);

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

  void appendMessage(ChatMessage message) {
    messages = [...messages, message];
    notifyListeners();
  }

  void replaceMessage(ChatMessage replacement) {
    messages = [
      for (final message in messages)
        if (message.id == replacement.id) replacement else message,
    ];
    notifyListeners();
  }

  void completeInitialLoad({String remoteDraft = ''}) {
    draft = remoteDraft;
    initialLoaded = true;
    notifyListeners();
  }
}

void main() {
  group('AppKeyboardDismissOnTap', () {
    testWidgets('lets system text actions run before dismissing focus', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'Selected text');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AppKeyboardDismissOnTap(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: Stack(
              children: [
                const Positioned.fill(
                  child: ColoredBox(
                    key: ValueKey('keyboard-dismiss-background'),
                    color: Colors.transparent,
                  ),
                ),
                Center(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final field = find.byType(TextField);
      final fieldTopLeft = tester.getTopLeft(field);
      await tester.longPressAt(fieldTopLeft + const Offset(45, 24));
      await tester.pumpAndSettle();
      expect(find.text('Cut'), findsOneWidget);
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.text('Cut'));
      await tester.pumpAndSettle();
      expect(controller.text, isNot('Selected text'));

      await tester.tap(field);
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      await tester.tapAt(const Offset(12, 12));
      await tester.pump();
      expect(focusNode.hasFocus, isFalse);
    });
  });

  group('EmojiTextEditingController', () {
    test('inserts preformatted table without corrupting existing entities', () {
      final controller = EmojiTextEditingController();
      addTearDown(controller.dispose);

      controller.text = 'hello world';
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      controller.toggleFormat('textEntityTypeBold');
      controller.selection = const TextSelection.collapsed(offset: 5);
      controller.insertFormattedText(
        '\n| A | B |\n|---|---|\n|   |   |\n',
        type: 'textEntityTypePre',
      );

      final (text, entities) = controller.toFormatted();
      expect(text, startsWith('hello\n| A | B |'));
      expect(entities.map((e) => e['type']['@type']), [
        'textEntityTypeBold',
        'textEntityTypePre',
      ]);
      expect(entities[0]['offset'], 0);
      expect(entities[0]['length'], 5);
      expect(entities[1]['offset'], 5);
    });
  });

  group('ChatInputBar', () {
    Future<(_FocusTestChatViewModel, ChatMessage)> pumpAiReplyComposer(
      WidgetTester tester,
      AiReplyGenerator? generator, {
      AiReplyStreamingGenerator? streamingGenerator,
      AiReplyChatHistoryLoader? historyLoader,
      bool includeReplyKeyboard = false,
      bool includeSenderOptions = false,
      bool useExplicitReplyTarget = false,
      bool includeLatestOutgoingMessage = false,
      bool anchoredHistory = false,
      bool isGroup = false,
      String? aiReplyPrompt,
      int messageAutoDeleteTime = 0,
      bool targetIsOutgoing = false,
      bool? telegramReplySupported = true,
      bool appleOnDeviceAvailable = false,
      VoidCallback? onMessageSent,
      List<ChatMessage> leadingMessages = const [],
      List<ChatMessage> trailingMessages = const [],
      int targetId = 7,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final theme = ThemeController(preferences);
      addTearDown(theme.dispose);
      final settings = AiSettingsController(
        preferences,
        pccApi: ApplePccApi(
          invokeMethod: (_, _) async => {
            'available': false,
            'sdkAvailable': false,
            'onDeviceSdkAvailable': appleOnDeviceAvailable,
            'onDeviceAvailable': appleOnDeviceAvailable,
            'onDeviceReason': appleOnDeviceAvailable
                ? 'available'
                : 'unavailable',
            if (appleOnDeviceAvailable) 'onDeviceContextSize': 4096,
          },
        ),
        secureRead: (_) async => null,
        secureWrite: (_, _) async {},
      );
      await settings.initialize();
      if (aiReplyPrompt != null) {
        await settings.setAiReplyPrompt(aiReplyPrompt);
      }
      addTearDown(settings.dispose);

      final target = ChatMessage(
        id: targetId,
        isOutgoing: targetIsOutgoing,
        text: 'Can you join at three?',
        date: 1,
        senderName: 'Alice',
        contentType: 'messageText',
        buttonRows: includeReplyKeyboard
            ? const [
                [
                  MessageButton(
                    text: 'Reply option',
                    type: 'keyboardButtonTypeText',
                    isReplyKeyboard: true,
                  ),
                ],
              ]
            : const [],
      );
      final vm =
          _FocusTestChatViewModel(
              title: 'Project',
              sessionMessages: [
                ...leadingMessages,
                target,
                ...trailingMessages,
                if (includeLatestOutgoingMessage)
                  ChatMessage(
                    id: targetId + 1,
                    isOutgoing: true,
                    text: 'I already answered.',
                    date: 2,
                    contentType: 'messageText',
                  ),
              ],
              sessionAnchorMessageId: anchoredHistory ? targetId : null,
            )
            ..aiCapabilities = telegramReplySupported == null
                ? null
                : TelegramAiCapabilities(
                    tdlibVersion: '1.8.66',
                    compositionSupported: true,
                    richCompositionSupported: true,
                    replySupported: telegramReplySupported,
                    customStylesSupported: true,
                    summarySupported: true,
                    transcriptionSupported: true,
                    styleTitleMax: 64,
                    stylePromptMax: 1024,
                    addedStyleCountMax: 10,
                  )
            ..isGroup = isGroup
            ..messageAutoDeleteTime = messageAutoDeleteTime;
      vm.anchoredHistory = anchoredHistory;
      if (includeSenderOptions) {
        vm.availableMessageSenders = const [
          MessageSenderOption(
            sender: {'@type': 'messageSenderUser', 'user_id': 1},
            id: 1,
            title: 'Me',
          ),
          MessageSenderOption(
            sender: {'@type': 'messageSenderChat', 'chat_id': 2},
            id: 2,
            title: 'Project',
          ),
        ];
        vm.selectedMessageSender = vm.availableMessageSenders.first;
      }
      if (useExplicitReplyTarget) vm.setReply(target);
      addTearDown(vm.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeController>.value(value: theme),
            ChangeNotifierProvider<AiSettingsController>.value(value: settings),
          ],
          child: MaterialApp(
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
                  onMessageSent: onMessageSent ?? () {},
                  aiReplyGenerator: generator,
                  aiReplyStreamingGenerator: streamingGenerator,
                  aiReplyHistoryLoader:
                      historyLoader ??
                      ({
                        required beforeMessageId,
                        required query,
                        required limit,
                      }) async => const AiReplyChatHistoryPage.empty(),
                ),
              ),
            ),
          ),
        ),
      );

      return (vm, target);
    }

    testWidgets('quick reply focuses only after restoring the remote draft', (
      tester,
    ) async {
      final vm = _FocusTestChatViewModel();
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
                requestInitialFocus: true,
                onStartCall: (_) {},
                onMessageSent: () {},
              ),
            ),
          ),
        ),
      );

      var field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode?.hasFocus, isFalse);
      expect(field.controller?.text, isEmpty);

      vm.completeInitialLoad(remoteDraft: 'Preserved Telegram draft');
      await tester.pump();
      await tester.pump();

      field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'Preserved Telegram draft');
      expect(field.focusNode?.hasFocus, isTrue);
    });

    testWidgets('shows AI Reply inside an empty input and inserts its draft', (
      tester,
    ) async {
      final result = Completer<TelegramAiFormattedText>();
      AiReplyRequest? capturedRequest;
      var requestCount = 0;
      final (vm, target) = await pumpAiReplyComposer(tester, (request) {
        capturedRequest = request;
        requestCount++;
        return result.future;
      });
      vm.meUsernames = const {'nekoko14'};

      final action = find.byKey(const ValueKey('composerAiReplyButton'));
      final inputBox = find.byKey(const ValueKey('composerTextInputBox'));
      expect(action, findsOneWidget);
      expect(find.descendant(of: inputBox, matching: action), findsOneWidget);
      expect(tester.widget<GestureDetector>(action).child, isA<SizedBox>());
      expect(
        tester.getCenter(action).dx,
        greaterThan(tester.getCenter(find.byType(TextField)).dx),
      );
      await tester.tap(action);
      await tester.pump();

      expect(
        find.byKey(const ValueKey('composerAiReplyProgress')),
        findsOneWidget,
      );
      expect(find.text('AI Reply'), findsNothing);

      result.complete(
        const TelegramAiFormattedText(
          text: 'I can join at three.',
          entities: [
            {
              '@type': 'textEntity',
              'offset': 0,
              'length': 1,
              'type': {'@type': 'textEntityTypeBold'},
            },
          ],
        ),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      final controller = field.controller! as EmojiTextEditingController;
      final (text, entities) = controller.toFormatted();
      expect(field.controller!.text, 'I can join at three.');
      expect(text, 'I can join at three.');
      expect(entities, hasLength(1));
      expect(entities.single['type'], {'@type': 'textEntityTypeBold'});
      expect(vm.draft, 'I can join at three.');
      expect(vm.replyTo, isNull);
      expect(capturedRequest?.targetMessageId, target.id);
      expect(capturedRequest?.currentUserUsernames, contains('nekoko14'));
      expect(requestCount, 1);
      expect(action, findsNothing);
      expect(find.byKey(const ValueKey('composerSendButton')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('composerAiReplyProgress')),
        findsNothing,
      );
    });

    testWidgets('typing after a streamed draft rejects later AI chunks', (
      tester,
    ) async {
      late AiReplyDraftCallback emitDraft;
      final result = Completer<TelegramAiFormattedText>();
      await pumpAiReplyComposer(
        tester,
        null,
        streamingGenerator:
            (
              request, {
              required AiReplyDraftCallback onDraft,
              AiReplyProgressCallback? onProgress,
            }) {
              emitDraft = onDraft;
              return result.future;
            },
      );

      await tester.tap(find.byKey(const ValueKey('composerAiReplyButton')));
      await tester.pump();
      emitDraft(const TelegramAiFormattedText(text: 'Partial reply'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'My own draft');
      await tester.pump();

      emitDraft(const TelegramAiFormattedText(text: 'Late streamed reply'));
      result.complete(
        const TelegramAiFormattedText(text: 'Late completed reply'),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'My own draft',
      );
      expect(
        find.byKey(const ValueKey('composerAiReplyProgress')),
        findsNothing,
      );
    });

    testWidgets('cancel after a streamed draft rejects later AI chunks', (
      tester,
    ) async {
      late AiReplyDraftCallback emitDraft;
      final result = Completer<TelegramAiFormattedText>();
      await pumpAiReplyComposer(
        tester,
        null,
        streamingGenerator:
            (
              request, {
              required AiReplyDraftCallback onDraft,
              AiReplyProgressCallback? onProgress,
            }) {
              emitDraft = onDraft;
              return result.future;
            },
      );

      await tester.tap(find.byKey(const ValueKey('composerAiReplyButton')));
      await tester.pump();
      emitDraft(const TelegramAiFormattedText(text: 'Useful partial'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composerAiReplyButton')));
      await tester.pump();

      emitDraft(const TelegramAiFormattedText(text: 'Late streamed reply'));
      result.complete(
        const TelegramAiFormattedText(text: 'Late completed reply'),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Useful partial',
      );
      expect(
        find.byKey(const ValueKey('composerAiReplyProgress')),
        findsNothing,
      );
    });

    testWidgets(
      'AI reply does not generate when blocked-user privacy cannot be verified',
      (tester) async {
        var generatorCalls = 0;
        await pumpAiReplyComposer(
          tester,
          (_) async {
            generatorCalls++;
            return const TelegramAiFormattedText(text: 'Generated reply');
          },
          historyLoader:
              ({
                required beforeMessageId,
                required query,
                required limit,
              }) async =>
                  throw const AiReplyPrivacyException('Block list unavailable'),
        );

        await tester.tap(find.byKey(const ValueKey('composerAiReplyButton')));
        await tester.pumpAndSettle();

        expect(generatorCalls, 0);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(
          find.byKey(const ValueKey('composerAiReplyProgress')),
          findsNothing,
        );
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets('does not apply an AI reply after the reply target changes', (
      tester,
    ) async {
      final result = Completer<TelegramAiFormattedText>();
      final (vm, _) = await pumpAiReplyComposer(
        tester,
        (_) => result.future,
        useExplicitReplyTarget: true,
      );

      await tester.tap(find.byKey(const ValueKey('composerAiReplyButton')));
      await tester.pump();
      final replacement = ChatMessage(
        id: 8,
        isOutgoing: false,
        text: 'What about four?',
        date: 2,
        senderName: 'Alice',
        contentType: 'messageText',
      );
      vm.setReply(replacement);
      await tester.pump();

      result.complete(
        const TelegramAiFormattedText(text: 'Stale generated reply'),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(vm.replyTo, same(replacement));
    });

    testWidgets('keeps the draft intact and allows retry after AI failure', (
      tester,
    ) async {
      var requestCount = 0;
      await pumpAiReplyComposer(tester, (_) {
        requestCount++;
        if (requestCount == 1) {
          return Future<TelegramAiFormattedText>.error(
            const AiReplyException('Reply failed'),
          );
        }
        return Future.value(
          const TelegramAiFormattedText(text: 'Reply after retry'),
        );
      });

      final action = find.byKey(const ValueKey('composerAiReplyButton'));
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(
        find.byKey(const ValueKey('composerAiReplyProgress')),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(requestCount, 2);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Reply after retry',
      );
    });

    for (final simpleMode in [false, true]) {
      testWidgets(
        'reports text field height changes (simpleMode: $simpleMode)',
        (tester) async {
          final vm = _FocusTestChatViewModel();
          addTearDown(vm.dispose);
          var inputHeightChanges = 0;

          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: const [
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
                    simpleMode: simpleMode,
                    onInputHeightChanged: () => inputHeightChanges++,
                  ),
                ),
              ),
            ),
          );
          expect(inputHeightChanges, 0);

          final field = find.byType(TextField).first;
          await tester.enterText(field, 'a\nb\nc');
          await tester.pump();
          await tester.pump();
          expect(inputHeightChanges, greaterThanOrEqualTo(1));

          // Deleting back to one line reports the shrink too.
          final grown = inputHeightChanges;
          await tester.enterText(field, 'a');
          await tester.pump();
          await tester.pump();
          expect(inputHeightChanges, greaterThan(grown));
        },
      );
    }
  });

  group('SecretChatService', () {
    test('rejects a non-secret TDLib response', () async {
      await expectLater(
        SecretChatService.create(
          42,
          query: (_) async => {
            '@type': 'chat',
            'id': '-123',
            'type': {'@type': 'chatTypePrivate', 'user_id': 42},
          },
        ),
        throwsFormatException,
      );
    });
  });

  group('TDParse.messageText', () {
    test('redacts only a message carrying restriction info', () {
      const notice =
          "This message can't be displayed because it violated Telegram's Terms of Service.";
      final restricted = TDParse.message({
        'id': 11,
        'date': 1,
        'content': {
          '@type': 'messagePhoto',
          'caption': {'@type': 'formattedText', 'text': 'Original photo'},
        },
        'restriction_info': {
          '@type': 'restrictionInfo',
          'reason': 'terms',
          'restriction_reason': notice,
        },
      });
      final ordinary = TDParse.message({
        'id': 12,
        'date': 2,
        'content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': notice},
        },
      });

      expect(restricted, isNotNull);
      expect(restricted!.text, notice);
      expect(restricted.isContentRestricted, isTrue);
      expect(restricted.restrictionReasonCode, 'terms');
      expect(restricted.restrictedContentText, 'Original photo');
      expect(restricted.hasRestrictedRevealContent, isTrue);
      expect(restricted.isPhoto, isFalse);
      expect(restricted.image, isNull);
      expect(restricted.buttonRows, isEmpty);
      expect(restricted.canRepeat, isFalse);

      expect(ordinary, isNotNull);
      expect(ordinary!.text, notice);
      expect(ordinary.isContentRestricted, isFalse);
    });
  });

  group('KeywordBlocker', () {
    test('matches plain keywords and regex rules', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final blocker = KeywordBlocker.shared;
      blocker.initialize(prefs);
      blocker.replaceAll(['free money', r're:\b\d{5}\b', r'/hello\s+world/i']);

      expect(blocker.matches('Claim FREE MONEY now'), isTrue);
      expect(blocker.matches('code 12345 please'), isTrue);
      expect(blocker.matches('HELLO     WORLD'), isTrue);
      expect(blocker.matches('normal message'), isFalse);
    });
  });

  group('TranslationController', () {
    test(
      'migrates the legacy generic Chinese exclusion to both scripts',
      () async {
        SharedPreferences.setMockInitialValues({
          'translation.ignoredLanguages': ['zh'],
        });
        final prefs = await SharedPreferences.getInstance();
        final controller = TranslationController(prefs);

        expect(controller.ignoredLanguageCodes, {'zh-Hans', 'zh-Hant'});
        expect(prefs.getStringList('translation.ignoredLanguages'), [
          'zh-Hans',
          'zh-Hant',
        ]);
      },
    );
  });
}
