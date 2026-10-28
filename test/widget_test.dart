// Core composer, privacy, session and message parsing regressions.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mithka/chat/ai_reply_service.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/emoji_text_controller.dart';
import 'package:mithka/chat/gif_item.dart';
import 'package:mithka/chat/gif_store.dart';
import 'package:mithka/chat/group_management_log_view.dart';
import 'package:mithka/chat/secret_chat_service.dart';
import 'package:mithka/chat/sponsored_messages_cache.dart';
import 'package:mithka/chat/sticker_item.dart';
import 'package:mithka/chat/sticker_store.dart';
import 'package:mithka/chat/telegram_ai_service.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/components/app_text_selection_toolbar.dart';
import 'package:mithka/components/keyboard_dismiss_on_tap.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ai_settings_controller.dart';
import 'package:mithka/settings/apple_pcc_api.dart';
import 'package:mithka/settings/country_message_filter.dart';
import 'package:mithka/settings/keyword_blocker.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/json_helpers.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/content_size.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

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

class _ControlledMediaChatViewModel extends ChatViewModel {
  _ControlledMediaChatViewModel()
    : super(chatId: 1, title: 'Test', markReadOnOpen: false);

  final stickerSend = Completer<bool>();
  final gifSend = Completer<bool>();

  @override
  Future<bool> sendSticker(StickerItem sticker) => stickerSend.future;

  @override
  Future<bool> sendGif(GifItem gif) => gifSend.future;
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
    test('inserts pasted text at the current selection', () {
      final controller = EmojiTextEditingController();
      addTearDown(controller.dispose);

      controller.text = 'hello world';
      controller.selection = const TextSelection(
        baseOffset: 6,
        extentOffset: 11,
      );
      controller.insertText('Mithka');

      expect(controller.text, 'hello Mithka');
      expect(controller.selection, const TextSelection.collapsed(offset: 12));
    });

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

    testWidgets(
      'long press opens the Reply model selector without generating',
      (tester) async {
        var generationCount = 0;
        await pumpAiReplyComposer(tester, (_) async {
          generationCount++;
          return const TelegramAiFormattedText(text: 'Generated reply');
        });

        final action = find.byKey(const ValueKey('composerAiReplyButton'));
        await tester.longPress(action);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('aiFeatureModelPicker-reply')),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey(
              'aiFeatureModelOption-reply-builtin:telegram_cocoon',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey('aiFeatureModelOption-reply-builtin:apple_pcc'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey(
              'aiFeatureModelOption-reply-builtin:apple_on_device',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey(
              'aiFeatureModelSelected-reply-builtin:telegram_cocoon',
            ),
          ),
          findsOneWidget,
        );
        expect(generationCount, 0);
        expect(
          find.byKey(const ValueKey('composerAiReplyProgress')),
          findsNothing,
        );

        await tester.tapAt(const Offset(8, 8));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('aiFeatureModelPicker-reply')),
          findsNothing,
        );
        expect(generationCount, 0);
      },
    );

    testWidgets('selected Reply model is persisted and used for generation', (
      tester,
    ) async {
      const channel = MethodChannel(ApplePccApi.channelName);
      MethodCall? summarizeCall;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method != 'summarize') return null;
        summarizeCall = call;
        return const {
          'text': 'I can join at three.',
          'provider': 'apple_on_device',
        };
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      var sentCount = 0;
      await pumpAiReplyComposer(
        tester,
        null,
        appleOnDeviceAvailable: true,
        onMessageSent: () => sentCount++,
      );

      final action = find.byKey(const ValueKey('composerAiReplyButton'));
      final settings = Provider.of<AiSettingsController>(
        tester.element(action),
        listen: false,
      );
      await tester.longPress(action);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('aiFeatureModelOption-reply-builtin:apple_on_device'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        settings.replyModelCandidateId,
        AiSettingsController.appleOnDeviceModelCandidateId,
      );
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString(
          AiSettingsController.replyModelCandidatePreferenceKey,
        ),
        AiSettingsController.appleOnDeviceModelCandidateId,
      );
      expect(summarizeCall?.method, 'summarize');
      expect(
        (summarizeCall?.arguments as Map<Object?, Object?>)['modelMode'],
        AppleAiModel.onDevice.bridgeValue,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'I can join at three.',
      );
      expect(sentCount, 0);
      expect(
        find.byKey(const ValueKey('composerAiReplyProgress')),
        findsNothing,
      );
    });

    testWidgets(
      'shows auto-delete as a gray icon before AI without replacing the hint',
      (tester) async {
        final (vm, _) = await pumpAiReplyComposer(
          tester,
          (_) async => const TelegramAiFormattedText(text: 'Generated reply'),
          messageAutoDeleteTime: 7 * 24 * 60 * 60,
        );

        final inputBox = find.byKey(const ValueKey('composerTextInputBox'));
        final autoDelete = find.byKey(
          const ValueKey('composerAutoDeleteIndicator'),
        );
        final ai = find.byKey(const ValueKey('composerAiReplyButton'));
        final field = tester.widget<TextField>(find.byType(TextField));

        expect(field.decoration?.hintText, 'Message…');
        expect(autoDelete, findsOneWidget);
        expect(
          find.bySemanticsLabel(
            'Message will be automatically deleted in 7 days',
          ),
          findsOneWidget,
        );
        expect(find.descendant(of: inputBox, matching: autoDelete), findsOne);
        expect(ai, findsOneWidget);
        expect(
          tester.getCenter(autoDelete).dx,
          lessThan(tester.getCenter(ai).dx),
        );
        final icon = tester.widget<AppIcon>(
          find.descendant(of: autoDelete, matching: find.byType(AppIcon)),
        );
        expect(icon.icon, HeroAppIcons.stopwatch);
        expect(icon.size, 18);
        expect(icon.color, AppColors.light.textTertiary);
        expect(
          tester
              .widget<GestureDetector>(
                find.descendant(
                  of: autoDelete,
                  matching: find.byType(GestureDetector),
                ),
              )
              .onTap,
          isNotNull,
        );

        await tester.enterText(find.byType(TextField), 'Draft');
        await tester.pump();
        expect(autoDelete, findsNothing);
        await tester.enterText(find.byType(TextField), '');
        await tester.pump();
        expect(autoDelete, findsOneWidget);

        vm.messageAutoDeleteTime = 0;
        vm.notifyListeners();
        await tester.pump();

        expect(autoDelete, findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
          'Message…',
        );
        expect(ai, findsOneWidget);
      },
    );

    testWidgets(
      'keeps AI Reply visible while Cocoon capability discovery is pending',
      (tester) async {
        await pumpAiReplyComposer(
          tester,
          (_) async => const TelegramAiFormattedText(text: 'Generated reply'),
          telegramReplySupported: null,
        );

        expect(
          find.byKey(const ValueKey('composerAiReplyButton')),
          findsOneWidget,
        );
      },
    );

    testWidgets('group can draft after only outgoing sender messages', (
      tester,
    ) async {
      AiReplyRequest? capturedRequest;
      await pumpAiReplyComposer(
        tester,
        (request) async {
          capturedRequest = request;
          return const TelegramAiFormattedText(text: 'A natural follow-up.');
        },
        isGroup: true,
        targetIsOutgoing: true,
      );

      final action = find.byKey(const ValueKey('composerAiReplyButton'));
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(capturedRequest?.targetMessageId, 7);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'A natural follow-up.',
      );
    });

    testWidgets(
      'progressively reveals a completed one-shot AI reply in the input',
      (tester) async {
        final result = Completer<TelegramAiFormattedText>();
        final (vm, _) = await pumpAiReplyComposer(tester, (_) => result.future);
        const completedText =
            'I can join at three, bring the revised notes, and confirm the '
            'room with everyone before the meeting starts.';

        await tester.tap(find.byKey(const ValueKey('composerAiReplyButton')));
        await tester.pump();
        result.complete(
          const TelegramAiFormattedText(
            text: completedText,
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
        await tester.pump();

        final partial = tester
            .widget<TextField>(find.byType(TextField))
            .controller!
            .text;
        expect(partial, isNotEmpty);
        expect(completedText, startsWith(partial));
        expect(partial, isNot(completedText));
        expect(vm.draft, partial);
        expect(
          find.byKey(const ValueKey('composerAiReplyProgress')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<AppInteractiveSurface>(
                find.byKey(const ValueKey('composerSendButton')),
              )
              .enabled,
          isFalse,
        );

        await tester.pumpAndSettle();

        final controller =
            tester.widget<TextField>(find.byType(TextField)).controller!
                as EmojiTextEditingController;
        final (text, entities) = controller.toFormatted();
        expect(text, completedText);
        expect(entities.single['type'], {'@type': 'textEntityTypeBold'});
        expect(vm.draft, completedText);
        expect(
          find.byKey(const ValueKey('composerAiReplyProgress')),
          findsNothing,
        );
        expect(
          tester
              .widget<AppInteractiveSurface>(
                find.byKey(const ValueKey('composerSendButton')),
              )
              .enabled,
          isTrue,
        );
      },
    );

    testWidgets(
      'streams a partial AI reply into the composer and keeps progress visible',
      (tester) async {
        late AiReplyDraftCallback emitDraft;
        final result = Completer<TelegramAiFormattedText>();
        final (vm, _) = await pumpAiReplyComposer(
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
        emitDraft(const TelegramAiFormattedText(text: 'I can'));
        await tester.pump();

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'I can',
        );
        expect(vm.draft, 'I can');
        expect(
          find.byKey(const ValueKey('composerAiReplyProgress')),
          findsOneWidget,
        );

        emitDraft(const TelegramAiFormattedText(text: 'I can join'));
        await tester.pump();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'I can join',
        );
        expect(
          find.byKey(const ValueKey('composerAiReplyProgress')),
          findsOneWidget,
        );

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

        final controller =
            tester.widget<TextField>(find.byType(TextField)).controller!
                as EmojiTextEditingController;
        final (text, entities) = controller.toFormatted();
        expect(text, 'I can join at three.');
        expect(entities.single['type'], {'@type': 'textEntityTypeBold'});
        expect(
          find.byKey(const ValueKey('composerAiReplyProgress')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'keeps generic AI phases collapsed above the send-ready draft',
      (tester) async {
        late AiReplyDraftCallback emitDraft;
        late AiReplyProgressCallback emitProgress;
        final result = Completer<TelegramAiFormattedText>();
        var sentCount = 0;
        final (vm, _) = await pumpAiReplyComposer(
          tester,
          null,
          streamingGenerator:
              (
                request, {
                required AiReplyDraftCallback onDraft,
                AiReplyProgressCallback? onProgress,
              }) {
                emitDraft = onDraft;
                emitProgress = onProgress!;
                return result.future;
              },
          onMessageSent: () => sentCount++,
        );

        await tester.tap(find.byKey(const ValueKey('composerAiReplyButton')));
        await tester.pump();

        final process = find.byKey(const ValueKey('composerAiReplyProcess'));
        final details = find.byKey(
          const ValueKey('composerAiReplyProcessDetails'),
        );
        expect(process, findsOneWidget);
        expect(details, findsNothing);
        expect(vm.draft, isEmpty);

        emitProgress(AiReplyProgressPhase.checkingEarlierContext);
        await tester.pump();
        expect(vm.draft, isEmpty);
        await tester.tap(
          find.byKey(const ValueKey('composerAiReplyProcessToggle')),
        );
        await tester.pump(const Duration(milliseconds: 220));

        expect(details, findsOneWidget);
        expect(
          find.text('Reviewing recent messages and the reply target.'),
          findsOneWidget,
        );
        expect(
          find.text('Checking earlier chat context for relevant details.'),
          findsOneWidget,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );

        emitProgress(AiReplyProgressPhase.writingReply);
        emitDraft(const TelegramAiFormattedText(text: 'Direct reply'));
        result.complete(const TelegramAiFormattedText(text: 'Direct reply'));
        await tester.pumpAndSettle();

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Direct reply',
        );
        expect(
          find.text('Writing a send-ready response in your voice.'),
          findsOneWidget,
        );
        expect(process, findsOneWidget);
        expect(sentCount, 0);

        await tester.enterText(find.byType(TextField), 'My edit');
        await tester.pumpAndSettle();
        expect(process, findsNothing);
        expect(sentCount, 0);
      },
    );

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
      'AI reply history eagerly grounds generation with older messages',
      (tester) async {
        AiReplyRequest? capturedRequest;
        int? capturedBeforeMessageId;
        String? capturedQuery;
        int? capturedLimit;
        var generatorCalls = 0;
        final olderMessages = [
          ChatMessage(
            id: 4,
            isOutgoing: false,
            text: 'The launch is still planned for Friday.',
            date: 4,
            senderName: 'Alice',
            contentType: 'messageText',
          ),
          ChatMessage(
            id: 5,
            isOutgoing: true,
            text: 'Friday works for me.',
            date: 5,
            contentType: 'messageText',
          ),
        ];
        final (_, target) = await pumpAiReplyComposer(
          tester,
          (request) async {
            capturedRequest = request;
            generatorCalls++;
            return const TelegramAiFormattedText(
              text: 'Yes, I can join at three.',
            );
          },
          historyLoader:
              ({
                required beforeMessageId,
                required query,
                required limit,
              }) async {
                capturedBeforeMessageId = beforeMessageId;
                capturedQuery = query;
                capturedLimit = limit;
                return AiReplyChatHistoryPage(
                  messages: olderMessages,
                  hasMore: false,
                );
              },
        );

        await tester.tap(find.byKey(const ValueKey('composerAiReplyButton')));
        await tester.pumpAndSettle();

        expect(generatorCalls, 1);
        expect(capturedBeforeMessageId, target.id);
        expect(capturedQuery, isEmpty);
        expect(capturedLimit, AiReplyRequest.earlierContextFetchLimit);
        expect(capturedRequest?.contextExpanded, isTrue);
        expect(capturedRequest?.contextComplete, isTrue);
        expect(capturedRequest?.messages.map((message) => message.id), [
          4,
          5,
          target.id,
        ]);
        expect(
          capturedRequest?.messages
              .firstWhere((message) => message.id == 5)
              .isCurrentUser,
          isTrue,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Yes, I can join at three.',
        );
      },
    );

    testWidgets(
      'AI reply history loading stops before generation when the user types',
      (tester) async {
        final history = Completer<AiReplyChatHistoryPage>();
        var historyCalls = 0;
        var generatorCalls = 0;
        await pumpAiReplyComposer(
          tester,
          (_) async {
            generatorCalls++;
            return const TelegramAiFormattedText(text: 'Generated reply');
          },
          historyLoader:
              ({required beforeMessageId, required query, required limit}) {
                historyCalls++;
                return history.future;
              },
        );

        await tester.tap(find.byKey(const ValueKey('composerAiReplyButton')));
        await tester.pump();
        expect(historyCalls, 1);
        expect(generatorCalls, 0);
        expect(
          find.byKey(const ValueKey('composerAiReplyProgress')),
          findsOneWidget,
        );

        await tester.enterText(find.byType(TextField), 'My own draft');
        await tester.pump();
        expect(
          find.byKey(const ValueKey('composerAiReplyProgress')),
          findsNothing,
        );

        history.complete(const AiReplyChatHistoryPage.empty());
        await tester.pumpAndSettle();

        expect(generatorCalls, 0);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'My own draft',
        );
      },
    );

    testWidgets(
      'AI reply history loading stops before generation when the target changes',
      (tester) async {
        final history = Completer<AiReplyChatHistoryPage>();
        var historyCalls = 0;
        var generatorCalls = 0;
        final (vm, _) = await pumpAiReplyComposer(
          tester,
          (_) async {
            generatorCalls++;
            return const TelegramAiFormattedText(text: 'Generated reply');
          },
          useExplicitReplyTarget: true,
          historyLoader:
              ({required beforeMessageId, required query, required limit}) {
                historyCalls++;
                return history.future;
              },
        );

        await tester.tap(find.byKey(const ValueKey('composerAiReplyButton')));
        await tester.pump();
        expect(historyCalls, 1);
        expect(generatorCalls, 0);

        final replacement = ChatMessage(
          id: 8,
          isOutgoing: false,
          text: 'Actually, can you join at four?',
          date: 2,
          senderName: 'Alice',
          contentType: 'messageText',
        );
        vm.setReply(replacement);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('composerAiReplyProgress')),
          findsNothing,
        );

        history.complete(const AiReplyChatHistoryPage.empty());
        await tester.pumpAndSettle();

        expect(generatorCalls, 0);
        expect(vm.replyTo, same(replacement));
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
      },
    );

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

    testWidgets('hides contextual AI Reply after the user has answered', (
      tester,
    ) async {
      await pumpAiReplyComposer(
        tester,
        (_) async => const TelegramAiFormattedText(text: 'Generated reply'),
        includeLatestOutgoingMessage: true,
      );

      expect(find.byKey(const ValueKey('composerAiReplyButton')), findsNothing);
    });

    testWidgets(
      'group keeps AI Reply after an outgoing message and supplies more context',
      (tester) async {
        AiReplyRequest? capturedRequest;
        int? capturedHistoryLimit;
        const guidance = 'Reply warmly and address the whole group.';
        final leadingMessages = <ChatMessage>[
          for (var id = 70; id < 95; id++)
            ChatMessage(
              id: id,
              isOutgoing: id % 5 == 0,
              text: 'Earlier group message $id',
              date: id,
              senderName: id.isEven ? 'Alice' : 'Bob',
              senderId: id.isEven ? 11 : 22,
              contentType: 'messageText',
            ),
        ];
        final (_, target) = await pumpAiReplyComposer(
          tester,
          (request) async {
            capturedRequest = request;
            return const TelegramAiFormattedText(text: 'Hello everyone!');
          },
          isGroup: true,
          includeLatestOutgoingMessage: true,
          leadingMessages: leadingMessages,
          targetId: 100,
          aiReplyPrompt: guidance,
          historyLoader:
              ({
                required beforeMessageId,
                required query,
                required limit,
              }) async {
                capturedHistoryLimit = limit;
                return const AiReplyChatHistoryPage.empty();
              },
        );

        expect(
          find.byKey(const ValueKey('composerAiReplyButton')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('composerAiReplyButton')));
        await tester.pumpAndSettle();

        expect(capturedRequest?.targetMessageId, target.id);
        expect(capturedRequest?.isGroupChat, isTrue);
        expect(capturedRequest?.guidance, guidance);
        expect(
          capturedHistoryLimit,
          AiReplyRequest.groupEarlierContextFetchLimit,
        );
        expect(
          capturedRequest?.messages.length,
          greaterThan(AiReplyRequest.maximumMessages),
        );
        expect(
          capturedRequest?.messages.map((message) => message.speaker),
          containsAll(<String>['Alice', 'Bob']),
        );
        expect(
          capturedRequest?.toUntrustedPayload(),
          containsPair('chat_type', 'group'),
        );
      },
    );

    testWidgets(
      'group invalidates an in-flight reply after a new owner message',
      (tester) async {
        late AiReplyDraftCallback emitDraft;
        final result = Completer<TelegramAiFormattedText>();
        final (vm, target) = await pumpAiReplyComposer(
          tester,
          null,
          isGroup: true,
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
        emitDraft(const TelegramAiFormattedText(text: 'Possibly stale'));
        await tester.pump();
        vm.appendMessage(
          ChatMessage(
            id: target.id + 1,
            isOutgoing: true,
            text: 'I have answered this already.',
            date: 2,
            contentType: 'messageText',
          ),
        );
        await tester.pump();

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(
          find.byKey(const ValueKey('composerAiReplyProgress')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('composerAiReplyButton')),
          findsOneWidget,
        );

        emitDraft(const TelegramAiFormattedText(text: 'Late stale chunk'));
        result.complete(
          const TelegramAiFormattedText(text: 'Late stale completion'),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
      },
    );

    testWidgets('revoked non-target context invalidates streamed reply', (
      tester,
    ) async {
      late AiReplyDraftCallback emitDraft;
      final result = Completer<TelegramAiFormattedText>();
      final contextMessage = ChatMessage(
        id: 6,
        isOutgoing: false,
        text: 'Earlier context that was initially shareable.',
        date: 1,
        senderName: 'Bob',
        senderId: 22,
        contentType: 'messageText',
      );
      final (vm, _) = await pumpAiReplyComposer(
        tester,
        null,
        leadingMessages: [contextMessage],
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
      emitDraft(const TelegramAiFormattedText(text: 'Uses old context'));
      await tester.pump();
      vm.replaceMessage(
        ChatMessage(
          id: contextMessage.id,
          isOutgoing: false,
          text: contextMessage.text,
          date: contextMessage.date,
          senderName: contextMessage.senderName,
          senderId: contextMessage.senderId,
          contentType: 'messageText',
          restrictionReason: 'content is no longer shareable',
        ),
      );
      await tester.pump();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(
        find.byKey(const ValueKey('composerAiReplyProgress')),
        findsNothing,
      );

      emitDraft(const TelegramAiFormattedText(text: 'Late revoked chunk'));
      result.complete(
        const TelegramAiFormattedText(text: 'Late revoked completion'),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('anchors contextual AI Reply to the visible group message', (
      tester,
    ) async {
      int? generatedTargetId;
      await pumpAiReplyComposer(
        tester,
        (request) async {
          generatedTargetId = request.targetMessageId;
          return const TelegramAiFormattedText(text: 'Generated reply');
        },
        anchoredHistory: true,
        isGroup: true,
        trailingMessages: [
          ChatMessage(
            id: 8,
            isOutgoing: false,
            text: 'Newer loaded but offscreen message',
            date: 2,
            senderName: 'Bob',
            contentType: 'messageText',
          ),
        ],
      );

      expect(
        find.byKey(const ValueKey('composerAiReplyButton')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('composerAiReplyButton')));
      await tester.pumpAndSettle();
      expect(generatedTargetId, 7);
    });

    testWidgets('lets the in-input progress control cancel AI generation', (
      tester,
    ) async {
      final result = Completer<TelegramAiFormattedText>();
      var requestCount = 0;
      await pumpAiReplyComposer(tester, (_) {
        requestCount++;
        return result.future;
      });

      final action = find.byKey(const ValueKey('composerAiReplyButton'));
      await tester.tap(action);
      await tester.pump();
      final progress = find.byKey(const ValueKey('composerAiReplyProgress'));
      expect(progress, findsOneWidget);
      final thinkingIcon = find.descendant(
        of: progress,
        matching: find.byType(AppIcon),
      );
      expect(thinkingIcon, findsOneWidget);
      expect(
        tester.widget<AppIcon>(thinkingIcon).icon,
        HeroAppIcons.wandMagicSparkles,
      );
      expect(
        find.descendant(
          of: progress,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      final orbit = find.byKey(const ValueKey('composerAiReplyOrbit'));
      final beforeRotation = List<double>.of(
        tester.widget<Transform>(orbit).transform.storage,
      );
      await tester.pump(const Duration(milliseconds: 225));
      final afterRotation = List<double>.of(
        tester.widget<Transform>(orbit).transform.storage,
      );
      expect(afterRotation, isNot(equals(beforeRotation)));
      expect(tester.widget<GestureDetector>(action).onLongPress, isNull);

      await tester.tap(action);
      await tester.pump();
      expect(requestCount, 1);
      expect(
        find.byKey(const ValueKey('composerAiReplyProgress')),
        findsNothing,
      );

      result.complete(
        const TelegramAiFormattedText(text: 'Canceled generated reply'),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(action, findsOneWidget);
    });

    testWidgets('keeps AI rightmost beside a bot keyboard on a narrow input', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpAiReplyComposer(
        tester,
        (_) async => const TelegramAiFormattedText(text: 'Generated reply'),
        includeReplyKeyboard: true,
        includeSenderOptions: true,
        messageAutoDeleteTime: 7 * 24 * 60 * 60,
      );

      final sender = find.byKey(const ValueKey('composerSenderPicker'));
      final keyboard = find.bySemanticsLabel('Show bot keyboard');
      final autoDelete = find.byKey(
        const ValueKey('composerAutoDeleteIndicator'),
      );
      final ai = find.byKey(const ValueKey('composerAiReplyButton'));
      expect(sender, findsOneWidget);
      expect(keyboard, findsOneWidget);
      expect(autoDelete, findsOneWidget);
      expect(ai, findsOneWidget);
      expect(
        tester.getCenter(sender).dx,
        lessThan(tester.getCenter(keyboard).dx),
      );
      expect(
        tester.getCenter(keyboard).dx,
        lessThan(tester.getCenter(autoDelete).dx),
      );
      expect(
        tester.getCenter(autoDelete).dx,
        lessThan(tester.getCenter(ai).dx),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('bottom-aligns the sender identity beside wrapped text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpAiReplyComposer(
        tester,
        (_) async => const TelegramAiFormattedText(text: 'Generated reply'),
        includeSenderOptions: true,
      );

      final field = find.byType(TextField);
      final sender = find.byKey(const ValueKey('composerSenderPicker'));
      await tester.enterText(
        field,
        'This longer message wraps across several lines in the narrow input.',
      );
      await tester.pump();

      expect(
        tester.getSize(field).height,
        greaterThan(tester.getSize(sender).height),
      );
      expect(
        tester.getRect(sender).bottom,
        closeTo(tester.getRect(field).bottom, 0.1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not overwrite text typed while an AI reply is running', (
      tester,
    ) async {
      final result = Completer<TelegramAiFormattedText>();
      await pumpAiReplyComposer(tester, (_) => result.future);

      await tester.tap(find.byKey(const ValueKey('composerAiReplyButton')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('composerAiReplyProgress')),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'My own draft');
      await tester.pump();
      expect(find.byKey(const ValueKey('composerAiReplyButton')), findsNothing);
      expect(
        find.byKey(const ValueKey('composerAiReplyProgress')),
        findsNothing,
      );

      result.complete(
        const TelegramAiFormattedText(text: 'Late generated reply'),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'My own draft',
      );

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('composerAiReplyButton')),
        findsOneWidget,
      );
    });

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

    testWidgets('discards a contextual reply when a newer message arrives', (
      tester,
    ) async {
      final result = Completer<TelegramAiFormattedText>();
      final (vm, _) = await pumpAiReplyComposer(tester, (_) => result.future);

      await tester.tap(find.byKey(const ValueKey('composerAiReplyButton')));
      await tester.pump();
      vm.appendMessage(
        ChatMessage(
          id: 8,
          isOutgoing: false,
          text: 'Actually, can you join at four?',
          date: 2,
          senderName: 'Alice',
          contentType: 'messageText',
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('composerAiReplyProgress')),
        findsNothing,
      );

      result.complete(
        const TelegramAiFormattedText(text: 'Stale generated reply'),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(
        find.byKey(const ValueKey('composerAiReplyButton')),
        findsOneWidget,
      );
    });

    testWidgets('discards contextual generation when explicit Reply starts', (
      tester,
    ) async {
      final result = Completer<TelegramAiFormattedText>();
      final (vm, target) = await pumpAiReplyComposer(
        tester,
        (_) => result.future,
      );

      await tester.tap(find.byKey(const ValueKey('composerAiReplyButton')));
      await tester.pump();
      vm.setReply(target);
      await tester.pump();

      result.complete(
        const TelegramAiFormattedText(text: 'Stale contextual reply'),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(vm.replyTo, same(target));
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

    testWidgets('shows a circular style action above the send button', (
      tester,
    ) async {
      final vm = _FocusTestChatViewModel()
        ..aiCapabilities = const TelegramAiCapabilities(
          tdlibVersion: 'test',
          compositionSupported: true,
          customStylesSupported: true,
          summarySupported: true,
          transcriptionSupported: true,
          styleTitleMax: 64,
          stylePromptMax: 1024,
          addedStyleCountMax: 10,
        );
      addTearDown(vm.dispose);

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
              ),
            ),
          ),
        ),
      );

      final field = find.byType(TextField).first;
      final aiButton = find.byKey(const ValueKey('composerAiPrefixButton'));
      expect(aiButton, findsNothing);

      await tester.enterText(field, 'one\ntwo');
      await tester.pump();

      expect(aiButton, findsOneWidget);
      final sendButton = find.byKey(const ValueKey('composerSendButton'));
      expect(sendButton, findsOneWidget);
      expect(tester.getSize(aiButton), const Size.square(36));
      final styleIcon = tester.widget<AppIcon>(
        find.byKey(const ValueKey('composerAiStyleIcon')),
      );
      expect(styleIcon.icon, HeroAppIcons.palette);
      expect(styleIcon.size, 19);
      expect(
        tester.getCenter(aiButton).dx,
        greaterThan(tester.getRect(field).right),
      );
      expect(
        tester.getCenter(aiButton).dx,
        closeTo(tester.getCenter(sendButton).dx, 0.1),
      );
      expect(
        tester.getCenter(aiButton).dy,
        lessThan(tester.getCenter(sendButton).dy),
      );

      await tester.enterText(field, 'one');
      await tester.pump();
      expect(aiButton, findsNothing);
    });

    test('builds awaitable sticker send requests', () {
      final vm = ChatViewModel(chatId: 42, title: 'Test', markReadOnOpen: false)
        ..paidMessageStarCount = 3;
      addTearDown(vm.dispose);

      final request = vm.stickerMessageRequest(
        const StickerItem(
          id: 100,
          remoteId: 'remote-sticker',
          width: 512,
          height: 384,
          emoji: '🙂',
        ),
      );

      expect(request['@type'], 'sendMessage');
      expect(request['chat_id'], 42);
      expect(request['options'], {
        '@type': 'messageSendOptions',
        'paid_message_star_count': 3,
      });
      expect(request['input_message_content'], {
        '@type': 'inputMessageSticker',
        'sticker': {
          '@type': 'inputSticker',
          'sticker': {'@type': 'inputFileRemote', 'id': 'remote-sticker'},
          'width': 512,
          'height': 384,
        },
        'emoji': '🙂',
      });
    });

    testWidgets(
      'the unified media panel hosts sticker and emoji tabs plus search',
      (tester) async {
        final vm = ChatViewModel(
          chatId: 1,
          title: 'Test chat',
          markReadOnOpen: false,
        );
        addTearDown(vm.dispose);
        var panelGeometryChanges = 0;

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
                  onPanelGeometryChanged: () => panelGeometryChanges++,
                ),
              ),
            ),
          ),
        );

        // One unified media button replaces the former emoji + sticker pair.
        expect(find.byIcon(HeroAppIcons.solidFaceSmile.data), findsOneWidget);
        expect(find.byIcon(HeroAppIcons.grip.data), findsNothing);

        await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data));
        await tester.pump();

        final segments = find.byKey(const ValueKey('mediaKindSegments'));
        final emojiTabs = find.byKey(const ValueKey('emojiPanelTabs'));
        final search = find.byKey(const ValueKey('composerMediaSearch'));
        expect(segments, findsOneWidget);
        expect(emojiTabs, findsOneWidget);
        expect(search, findsNothing);
        expect(panelGeometryChanges, 1);
        expect(find.byIcon(HeroAppIcons.palette.data), findsNothing);

        // The emoji segment's search tab surfaces the shared search field.
        await tester.tap(find.byKey(const ValueKey('emojiSearchTab')));
        await tester.pump();
        expect(search, findsOneWidget);
        expect(
          tester.getTopLeft(emojiTabs).dy,
          lessThan(tester.getTopLeft(search).dy),
        );

        // Switching to the sticker segment swaps the secondary strip.
        await tester.tap(find.byKey(const ValueKey('mediaSegment-sticker')));
        await tester.pump();
        final stickerTabs = find.byKey(const ValueKey('stickerPanelTabs'));
        expect(stickerTabs, findsOneWidget);
        expect(emojiTabs, findsNothing);
        expect(search, findsNothing);

        await tester.tap(find.byKey(const ValueKey('stickerSearchTab')));
        await tester.pump();
        expect(search, findsOneWidget);
        expect(
          tester.getTopLeft(stickerTabs).dy,
          lessThan(tester.getTopLeft(search).dy),
        );

        // The GIF segment has its own saved-GIFs strip and search. The
        // sticker and GIF regions share one search selection, so the field
        // that was showing for sticker search stays up here.
        await tester.tap(find.byKey(const ValueKey('mediaSegment-gif')));
        await tester.pump();
        final gifTabs = find.byKey(const ValueKey('gifPanelTabs'));
        expect(gifTabs, findsOneWidget);
        expect(stickerTabs, findsNothing);
        expect(search, findsOneWidget);
        expect(
          tester.getTopLeft(gifTabs).dy,
          lessThan(tester.getTopLeft(search).dy),
        );

        // Picking the saved-GIFs tab hides the shared search field again.
        await tester.tap(find.byKey(const ValueKey('gifSavedTab')));
        await tester.pump();
        expect(search, findsNothing);

        await tester.tap(find.byKey(const ValueKey('gifSearchTab')));
        await tester.pump();
        expect(search, findsOneWidget);
        expect(
          tester.getTopLeft(gifTabs).dy,
          lessThan(tester.getTopLeft(search).dy),
        );

        // Tapping the media button closes the panel again. The open panel's
        // emoji segment carries the same smiley glyph, so take the toolbar
        // icon (built first in the column).
        await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
        await tester.pump();
        expect(segments, findsNothing);
        expect(panelGeometryChanges, 2);
      },
    );

    testWidgets('media taps request bottom scroll before send completion', (
      tester,
    ) async {
      final vm = _ControlledMediaChatViewModel();
      addTearDown(vm.dispose);
      final store = StickerStore.shared;
      store.replacePacksForTest([
        StickerPack(
          id: StickerStore.recentPackId,
          title: 'Recent',
          loaded: true,
          stickers: const [
            StickerItem(id: 100, width: 128, height: 128, emoji: '🙂'),
          ],
        ),
      ]);
      addTearDown(store.reset);
      final gifStore = GifStore.shared;
      final originalGifs = gifStore.items;
      gifStore.replaceItemsForTest([
        GifItem(
          id: 200,
          duration: 2,
          width: 320,
          height: 180,
          mimeType: 'video/mp4',
          file: TdFileRef(id: 200),
        ),
      ]);
      addTearDown(() => gifStore.replaceItemsForTest(originalGifs));
      var mediaSendTaps = 0;
      var messageSentCallbacks = 0;
      var everySentCallbackSawClosedPanel = true;

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
                gifPreviewBuilder: (_) => const SizedBox.expand(),
                onMediaSendTapped: () => mediaSendTaps++,
                onMessageSent: () {
                  messageSentCallbacks++;
                  everySentCallbackSawClosedPanel =
                      everySentCallbackSawClosedPanel &&
                      find
                          .byKey(const ValueKey('stickerPanelTabs'))
                          .evaluate()
                          .isEmpty;
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mediaSegment-sticker')));
      await tester.pump();
      expect(find.byKey(const ValueKey('sticker-100')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sticker-100')));
      await tester.pump();

      expect(mediaSendTaps, 1);
      expect(messageSentCallbacks, 0);
      expect(find.byKey(const ValueKey('stickerPanelTabs')), findsOneWidget);

      vm.stickerSend.complete(true);
      await tester.pump();
      await tester.pump();
      expect(messageSentCallbacks, 1);
      expect(everySentCallbackSawClosedPanel, isTrue);

      await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mediaSegment-gif')));
      await tester.pump();
      expect(find.byKey(const ValueKey('gif-200')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('gif-200')));
      await tester.pump();

      expect(mediaSendTaps, 2);
      expect(messageSentCallbacks, 1);
      expect(find.byKey(const ValueKey('gifPanelTabs')), findsOneWidget);

      vm.gifSend.complete(true);
      await tester.pump();
      await tester.pump();
      expect(messageSentCallbacks, 2);
      expect(everySentCallbackSawClosedPanel, isTrue);
    });

    testWidgets('composer and panel paint one continuous bottom surface', (
      tester,
    ) async {
      final themedColors = AppColors.light.copyWith(
        inputBarBackground: const Color(0xA0224466),
        panelBackground: const Color(0x99664422),
      );
      final vm = ChatViewModel(
        chatId: 1,
        title: 'Test chat',
        markReadOnOpen: false,
      );
      addTearDown(vm.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [themedColors]),
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInputBar(
                  vm: vm,
                  onStartCall: (_) {},
                  onMessageSent: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final safeAreaBackground = find.byKey(
        const ValueKey('chat-input-safe-area-background'),
      );
      final panelSafeAreaBackground = find.byKey(
        const ValueKey('chat-input-panel-safe-area-background'),
      );
      final colors = tester.element(safeAreaBackground).colors;
      expect(
        tester.widget<ColoredBox>(safeAreaBackground).color,
        colors.inputBarBackground,
      );
      expect(panelSafeAreaBackground, findsNothing);

      await tester.tap(find.byIcon(HeroAppIcons.circlePlus.data));
      await tester.pump();

      expect(
        tester.widget<ColoredBox>(safeAreaBackground).color,
        colors.inputBarBackground,
      );
      // The panel extends the bar's surface through the home indicator; the
      // recessed panelBackground (still distinct in this palette) must not
      // reappear below the panel.
      expect(
        tester.widget<ColoredBox>(panelSafeAreaBackground).color,
        colors.inputBarBackground,
      );
      expect(
        tester.widget<ColoredBox>(panelSafeAreaBackground).color,
        isNot(colors.panelBackground),
      );
    });

    testWidgets('pastes images from menus, shortcuts, and inserted content', (
      tester,
    ) async {
      const clipboardChannel = MethodChannel('mithka/clipboard');
      const pathProviderChannel = MethodChannel(
        'plugins.flutter.io/path_provider',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final clipboardMethods = <String>[];
      messenger.setMockMethodCallHandler(clipboardChannel, (call) async {
        clipboardMethods.add(call.method);
        if (call.method != 'readImage' && call.method != 'readImageUri') {
          return null;
        }
        return <String, dynamic>{
          'mimeType': 'image/png',
          'data': base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        };
      });
      messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
        if (call.method == 'getTemporaryDirectory') {
          return Directory.systemTemp.path;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(clipboardChannel, null);
        messenger.setMockMethodCallHandler(pathProviderChannel, null);
      });
      final vm = ChatViewModel(chatId: 1, title: 'Test', markReadOnOpen: false);
      var vmDisposed = false;
      addTearDown(() {
        if (!vmDisposed) vm.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatInputBar(
                vm: vm,
                onStartCall: (_) {},
                onMessageSent: () {},
              ),
            ),
          ),
        ),
      );
      final textFieldFinder = find.byType(TextField).first;
      final textField = tester.widget<TextField>(textFieldFinder);
      final editableTextState = tester.state<EditableTextState>(
        find.descendant(
          of: textFieldFinder,
          matching: find.byType(EditableText),
        ),
      );
      final toolbar = textField.contextMenuBuilder!(
        tester.element(textFieldFinder),
        editableTextState,
      );
      final toolbarScope = toolbar as MediaQuery;
      expect(
        toolbarScope.data.textScaler,
        ContentSizeScope.of(tester.element(textFieldFinder)).systemTextScaler,
      );
      final buttonItems =
          (toolbarScope.child as AdaptiveTextSelectionToolbar).buttonItems;

      final pasteItems = buttonItems!.where(
        (item) => item.type == ContextMenuButtonType.paste,
      );
      expect(pasteItems, hasLength(1));

      await tester.runAsync(() async {
        Actions.invoke(
          tester.element(
            find.descendant(
              of: textFieldFinder,
              matching: find.byType(EditableText),
            ),
          ),
          const PasteTextIntent(SelectionChangedCause.keyboard),
        );
      });
      await _settleUntilFound(
        tester,
        find.byKey(const ValueKey('clipboardAttachment-0')),
      );
      expect(
        find.byKey(const ValueKey('clipboardAttachmentStrip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('clipboardAttachment-0')),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        Actions.invoke(
          tester.element(
            find.descendant(
              of: textFieldFinder,
              matching: find.byType(EditableText),
            ),
          ),
          const PasteTextIntent(SelectionChangedCause.keyboard),
        );
      });
      await _settleUntilFound(
        tester,
        find.byKey(const ValueKey('clipboardAttachment-1')),
      );
      expect(
        find.byKey(const ValueKey('clipboardAttachment-1')),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        textField.contentInsertionConfiguration!.onContentInserted(
          const KeyboardInsertedContent(
            mimeType: 'image/png',
            uri: 'content://mithka/pasted-image',
          ),
        );
      });
      await _settleUntilFound(
        tester,
        find.byKey(const ValueKey('clipboardAttachment-2')),
      );
      expect(
        find.byKey(const ValueKey('clipboardAttachment-2')),
        findsOneWidget,
      );
      expect(
        clipboardMethods.where((method) => method == 'readImage'),
        hasLength(2),
      );
      expect(clipboardMethods, contains('readImageUri'));

      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
      vmDisposed = true;
    });

    testWidgets('format menu keeps input focused until tapping outside', (
      tester,
    ) async {
      final vm = _FocusTestChatViewModel();
      addTearDown(vm.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              AppKeyboardDismissOnTap(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatInputBar(
                vm: vm,
                onStartCall: (_) {},
                onMessageSent: () {},
              ),
            ),
          ),
        ),
      );

      final textFieldFinder = find.byType(TextField).first;
      final textField = tester.widget<TextField>(textFieldFinder);
      final controller = textField.controller!;
      final focusNode = textField.focusNode!;
      await tester.tap(textFieldFinder);
      await tester.enterText(textFieldFinder, 'format me');
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 6,
      );
      await tester.pump();

      void openFormatMenu() {
        final editableTextState = tester.state<EditableTextState>(
          find.descendant(
            of: textFieldFinder,
            matching: find.byType(EditableText),
          ),
        );
        final toolbar = textField.contextMenuBuilder!(
          tester.element(textFieldFinder),
          editableTextState,
        );
        final toolbarScope = toolbar as MediaQuery;
        expect(
          toolbarScope.data.textScaler,
          ContentSizeScope.of(tester.element(textFieldFinder)).systemTextScaler,
        );
        final items =
            (toolbarScope.child as AppTextSelectionToolbar).buttonItems!;
        items.singleWhere((item) => item.label == 'Format').onPressed!();
      }

      expect(focusNode.hasFocus, isTrue);
      openFormatMenu();
      await tester.pumpAndSettle();
      expect(find.text('Bold'), findsOneWidget);
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.text('Bold'));
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isTrue);

      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 6,
      );
      openFormatMenu();
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Bold'), findsNothing);
      expect(focusNode.hasFocus, isFalse);
    });

    testWidgets(
      'uses a bot menu Mini App action and toggles the reply keyboard',
      (tester) async {
        final vm =
            ChatViewModel(chatId: 1, title: 'Test bot', markReadOnOpen: false)
              ..peerIsBot = true
              ..botMenu = const BotMenuInfo(
                type: 'botMenuButton',
                text: '小程序购买',
                url: 'menu://https://example.com/webapp',
              )
              ..botCommands = const [
                BotCommandOption(
                  command: 'start',
                  description: 'Start the bot',
                ),
              ]
              ..messages = [
                ChatMessage(
                  id: 1,
                  isOutgoing: false,
                  text: '',
                  date: 1,
                  buttonRows: [
                    [
                      const MessageButton(
                        text: '购买套餐',
                        type: 'keyboardButtonTypeText',
                        isReplyKeyboard: true,
                      ),
                    ],
                  ],
                ),
              ];
        addTearDown(vm.dispose);

        await tester.pumpWidget(
          MaterialApp(
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
                ),
              ),
            ),
          ),
        );

        // The mini-app launcher lives in the chat header now, not on the
        // composer row — the composer shows the standard bot-menu icon.
        expect(find.text('小程序购买'), findsNothing);
        expect(find.bySemanticsLabel('Open bot menu'), findsOneWidget);
        expect(find.bySemanticsLabel('Show bot keyboard'), findsOneWidget);
        expect(find.text('购买套餐'), findsNothing);

        await tester.tap(find.bySemanticsLabel('Show bot keyboard'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Hide bot keyboard'), findsOneWidget);
        expect(find.text('购买套餐'), findsOneWidget);

        // Long-press forces the command sheet (tap may launch a legacy
        // menu:// web app instead), matching the old pill's long-press.
        await tester.longPress(find.bySemanticsLabel('Open bot menu'));
        await tester.pumpAndSettle();
        expect(find.text('/start'), findsOneWidget);
      },
    );

    testWidgets('only shows the bot keyboard toggle for an empty draft', (
      tester,
    ) async {
      final vm =
          ChatViewModel(chatId: 1, title: 'Test bot', markReadOnOpen: false)
            ..draft = 'already typing'
            ..messages = [
              ChatMessage(
                id: 1,
                isOutgoing: false,
                text: '',
                date: 1,
                buttonRows: const [
                  [
                    MessageButton(
                      text: '购买套餐',
                      type: 'keyboardButtonTypeText',
                      isReplyKeyboard: true,
                    ),
                  ],
                ],
              ),
            ];
      addTearDown(vm.dispose);

      await tester.pumpWidget(
        MaterialApp(
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
              ),
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Show bot keyboard'), findsNothing);
      expect(find.bySemanticsLabel('Hide bot keyboard'), findsNothing);
    });
  });

  group('JSON helpers', () {
    test('management log resolves modern and legacy actor ids', () {
      expect(
        chatEventActorUserId({
          'member_id': {'@type': 'messageSenderUser', 'user_id': '42'},
        }),
        42,
      );
      expect(chatEventActorUserId({'user_id': 17}), 17);
    });

    test('parses TDLib int64-as-string', () {
      final obj = <String, dynamic>{'order': '123456789012345', 'n': 7};
      expect(obj.int64('order'), 123456789012345);
      expect(obj.integer('n'), 7);
      expect(obj.str('missing'), isNull);
    });
  });

  group('ChatMessage album visual media', () {
    test('parses a TDLib pending outgoing message', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': -7,
        'date': 1,
        'is_outgoing': true,
        'sending_state': {'@type': 'messageSendingStatePending'},
        'content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'Sending'},
        },
      });

      expect(message, isNotNull);
      expect(message!.isSending, isTrue);
    });

    test('keeps messageSenderChat identity through parsing', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': 30,
        'date': 1,
        'is_outgoing': true,
        'sender_id': {'@type': 'messageSenderChat', 'chat_id': '-100123'},
        'content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'channel post'},
        },
      });

      expect(message, isNotNull);
      expect(message!.senderIsChat, isTrue);
      expect(message.senderId, -100123);
    });

    test(
      'includes photos and videos, excludes thumbnail-only placeholders',
      () {
        ChatMessage message(String type) => ChatMessage(
          id: 1,
          isOutgoing: false,
          text: '',
          date: 1,
          contentType: type,
          image: TdFileRef(id: 10),
        );

        expect(message('messagePhoto').isAlbumVisualMedia, isTrue);
        expect(message('messageVideo').isAlbumVisualMedia, isTrue);
        expect(message('messageSticker').isAlbumVisualMedia, isFalse);
        expect(message('messageAnimation').isAlbumVisualMedia, isFalse);
      },
    );

    test('photo messages keep a downloadable thumbnail before full image', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': 42,
        'date': 1,
        'is_outgoing': false,
        'content': {
          '@type': 'messagePhoto',
          'photo': {
            '@type': 'photo',
            'sizes': [
              {
                '@type': 'photoSize',
                'type': 'm',
                'width': 320,
                'height': 180,
                'photo': {'@type': 'file', 'id': 10},
              },
              {
                '@type': 'photoSize',
                'type': 'y',
                'width': 1920,
                'height': 1080,
                'photo': {'@type': 'file', 'id': 20},
              },
            ],
          },
        },
      });

      expect(message, isNotNull);
      expect(message!.image?.id, 20);
      expect(message.image?.thumbnail?.id, 10);
      expect(message.imageWidth, 1920);
      expect(message.imageHeight, 1080);
    });
  });

  group('SecretChatService', () {
    test('parses TDLib secret chat readiness', () {
      Map<String, dynamic> secretChat(String state) => {
        '@type': 'secretChat',
        'state': {'@type': state},
      };

      expect(
        SecretChatService.readiness(secretChat('secretChatStatePending')),
        SecretChatReadiness.pending,
      );
      expect(
        SecretChatService.readiness(secretChat('secretChatStateReady')),
        SecretChatReadiness.ready,
      );
      expect(
        SecretChatService.readiness(secretChat('secretChatStateClosed')),
        SecretChatReadiness.closed,
      );
      expect(
        SecretChatService.readiness(secretChat('futureSecretChatState')),
        SecretChatReadiness.unknown,
      );
    });

    test('loads a known TDLib secret chat', () async {
      Map<String, dynamic>? request;
      final result = await SecretChatService.get(
        17,
        query: (value) async {
          request = value;
          return {
            '@type': 'secretChat',
            'id': 17,
            'state': {'@type': 'secretChatStateReady'},
          };
        },
      );

      expect(request, {'@type': 'getSecretChat', 'secret_chat_id': 17});
      expect(SecretChatService.readiness(result), SecretChatReadiness.ready);
    });

    test('creates and validates a TDLib secret chat', () async {
      Map<String, dynamic>? request;
      final result = await SecretChatService.create(
        42,
        query: (value) async {
          request = value;
          return {
            '@type': 'chat',
            'id': '-123',
            'title': 'Ada',
            'type': {
              '@type': 'chatTypeSecret',
              'secret_chat_id': 17,
              'user_id': 42,
            },
          };
        },
      );

      expect(request, {'@type': 'createNewSecretChat', 'user_id': 42});
      expect(result.id, -123);
      expect(result.title, 'Ada');
    });

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

  group('SponsoredMessagesCache', () {
    test('caches an account and channel response for five minutes', () async {
      var now = DateTime(2026, 7, 13, 12);
      final cache = SponsoredMessagesCache(now: () => now);
      var calls = 0;
      Future<Map<String, dynamic>> fetch() async {
        calls++;
        return {
          '@type': 'sponsoredMessages',
          'messages': [
            {'@type': 'sponsoredMessage', 'message_id': calls},
          ],
        };
      }

      final first = await cache.retrieve(cacheKey: '0:-1001', fetch: fetch);
      now = now.add(const Duration(minutes: 4, seconds: 59));
      final cached = await cache.retrieve(cacheKey: '0:-1001', fetch: fetch);
      now = now.add(const Duration(seconds: 2));
      final refreshed = await cache.retrieve(cacheKey: '0:-1001', fetch: fetch);

      expect(calls, 2);
      expect(cached, same(first));
      expect(refreshed.response['messages'], [
        {'@type': 'sponsoredMessage', 'message_id': 2},
      ]);
    });

    test('refreshes an open chat even while the result is cached', () async {
      final cache = SponsoredMessagesCache();
      var calls = 0;
      Future<Map<String, dynamic>> fetch() async {
        calls++;
        return {'@type': 'sponsoredMessages', 'messages': const []};
      }

      await cache.retrieve(cacheKey: '0:-1001', fetch: fetch);
      await cache.retrieve(cacheKey: '0:-1001', refresh: true, fetch: fetch);

      expect(calls, 2);
    });

    test('coalesces simultaneous requests for the same channel', () async {
      final gate = Completer<Map<String, dynamic>>();
      final cache = SponsoredMessagesCache();
      var calls = 0;

      Future<Map<String, dynamic>> fetch() {
        calls++;
        return gate.future;
      }

      final first = cache.retrieve(cacheKey: '0:-1001', fetch: fetch);
      final second = cache.retrieve(cacheKey: '0:-1001', fetch: fetch);
      gate.complete({'@type': 'sponsoredMessages', 'messages': const []});

      expect(await first, same(await second));
      expect(calls, 1);
    });
  });

  group('TDParse.messageText', () {
    test('protected-content toggles are non-interactive service messages', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': 9,
        'chat_id': -1001,
        'date': 1,
        'content': {
          '@type': 'messageChatHasProtectedContentToggled',
          'new_has_protected_content': true,
        },
      });

      expect(message, isNotNull);
      expect(message!.isService, isTrue);
      expect(message.contentType, 'messageChatHasProtectedContentToggled');
    });

    test('photo with no caption uses localized placeholder', () {
      final content = <String, dynamic>{'@type': 'messagePhoto'};
      expect(
        TDParse.messageText(content),
        AppStrings.t(AppStringKeys.composerImagePreview),
      );
    });

    test('plain text passes through', () {
      final content = <String, dynamic>{
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'hello'},
      };
      expect(TDParse.messageText(content), 'hello');
    });

    test('GIF without a caption uses a GIF placeholder', () {
      final content = <String, dynamic>{
        '@type': 'messageAnimation',
        'caption': {'@type': 'formattedText', 'text': ''},
      };

      expect(TDParse.messageText(content), '[GIF]');
    });

    test('caption-bearing media keep preview labels out of message text', () {
      final contents = <Map<String, dynamic>>[
        {
          '@type': 'messagePhoto',
          'caption': {'@type': 'formattedText', 'text': ''},
        },
        {
          '@type': 'messageVideo',
          'caption': {'@type': 'formattedText', 'text': ''},
        },
        {
          '@type': 'messageAnimation',
          'caption': {'@type': 'formattedText', 'text': ''},
        },
        {
          '@type': 'messageAudio',
          'caption': {'@type': 'formattedText', 'text': ''},
        },
        {
          '@type': 'messageDocument',
          'caption': {'@type': 'formattedText', 'text': ''},
          'document': {'@type': 'document', 'file_name': 'report.pdf'},
        },
        {
          '@type': 'messageVoiceNote',
          'caption': {'@type': 'formattedText', 'text': ''},
        },
        {
          '@type': 'messagePaidMedia',
          'caption': {'@type': 'formattedText', 'text': ''},
        },
      ];

      for (final content in contents) {
        expect(
          TDParse.messageText(content),
          isNotEmpty,
          reason: '${content['@type']} needs a useful list preview',
        );
        expect(
          TDParse.messageContentText(content),
          isEmpty,
          reason: '${content['@type']} has no user-authored caption',
        );
        final parsed = TDParse.message({
          '@type': 'message',
          'id': 100,
          'date': 1,
          'content': content,
        });
        expect(
          parsed?.text,
          isEmpty,
          reason: '${content['@type']} parser text',
        );
      }
    });

    test('captions that equal preview labels remain real message text', () {
      final content = <String, dynamic>{
        '@type': 'messageVideo',
        'caption': {'@type': 'formattedText', 'text': 'Video'},
      };

      expect(TDParse.messageContentText(content), 'Video');
      expect(
        TDParse.message({
          '@type': 'message',
          'id': 101,
          'date': 1,
          'content': content,
        })?.text,
        'Video',
      );
    });

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

    test('classifies porno restrictions separately from ToS restrictions', () {
      const notice =
          "This message couldn't be displayed on your device because it contains pornographic materials.";
      final restrictedObject = <String, dynamic>{
        'restriction_info': {
          '@type': 'restrictionInfo',
          'reason': 'porno',
          'restriction_reason': notice,
          'has_sensitive_content': true,
        },
      };

      expect(TDParse.restrictionReasonFor(restrictedObject), notice);
      expect(TDParse.restrictionReasonCodeFor(restrictedObject), 'porno');
      expect(TDParse.hasSensitiveRestriction(restrictedObject), isTrue);
      expect(TDParse.isBlockingRestriction(restrictedObject), isTrue);
      expect(TDParse.isPornographicRestriction(restrictedObject), isTrue);
      expect(TDParse.isPornographicRestrictionText(notice), isTrue);
      expect(TDParse.isTelegramTermsRestrictionText(notice), isFalse);
      expect(TDParse.isTermsRestriction(restrictedObject), isFalse);

      expect(
        TDParse.isBlockingRestriction({
          'restriction_info': {
            '@type': 'restrictionInfo',
            'restriction_reason':
                'This channel cannot be displayed due to porn-ios.',
            'has_sensitive_content': true,
          },
        }),
        isTrue,
      );
      expect(
        TDParse.isPornographicRestriction({
          'restriction_info': {
            '@type': 'restrictionInfo',
            'reason': 'porn-ios',
            'restriction_reason': 'Sensitive content is unavailable.',
          },
        }),
        isTrue,
      );
      expect(
        TDParse.isTermsRestriction({
          'restriction_info': {
            '@type': 'restrictionInfo',
            'restriction_reason': 'Sensitive content is unavailable.',
            'has_sensitive_content': true,
          },
        }),
        isFalse,
      );
      expect(
        TDParse.isBlockingRestriction({
          'restriction_info': {
            '@type': 'restrictionInfo',
            'restriction_reason': '',
            'has_sensitive_content': true,
          },
        }),
        isFalse,
      );
    });

    test('classifies Telegram ToS restrictions as safety restrictions', () {
      const notice =
          "This message can't be displayed because it violated Telegram's Terms of Service.";
      final restrictedObject = <String, dynamic>{
        'restriction_info': {
          '@type': 'restrictionInfo',
          'reason': 'terms',
          'restriction_reason': notice,
        },
      };

      expect(TDParse.isPornographicRestrictionText(notice), isFalse);
      expect(TDParse.isTelegramTermsRestrictionText(notice), isTrue);
      expect(TDParse.isBlockingRestriction(restrictedObject), isTrue);
      expect(TDParse.isTermsRestriction(restrictedObject), isTrue);
    });

    test('dice keeps emoji preview and parsed value', () {
      final message = TDParse.message({
        'id': 10,
        'date': 1,
        'content': {'@type': 'messageDice', 'emoji': '🎲', 'value': 6},
      });
      expect(message, isNotNull);
      expect(message!.text, '🎲');
      expect(message.diceEmoji, '🎲');
      expect(message.diceValue, 6);
      expect(message.isDice, isTrue);
    });

    test('flattens Telegram core RichText markdown nodes', () {
      final rich = <String, dynamic>{
        '@type': 'textConcat',
        'texts': [
          {'@type': 'textPlain', 'text': 'Hello '},
          {
            '@type': 'textBold',
            'text': {'@type': 'textPlain', 'text': 'bold'},
          },
          {'@type': 'textPlain', 'text': ' '},
          {
            '@type': 'textUrl',
            'text': {'@type': 'textPlain', 'text': 'site'},
            'url': 'https://example.com',
          },
        ],
      };

      expect(TDParse.richTextText(rich), 'Hello bold site');
      final entities = TDParse.richTextEntities(rich);
      expect(entities.map((e) => e.type), [
        'textEntityTypeBold',
        'textEntityTypeTextUrl',
      ]);
      expect(entities[1].url, 'https://example.com');
    });

    test('supports Bot API rich text class names', () {
      Map<String, dynamic> plain(String text) => {
        '@type': 'RichTextPlain',
        'text': text,
      };
      Map<String, dynamic> wrap(String type, String text) => {
        '@type': type,
        'text': plain(text),
      };

      final rich = <String, dynamic>{
        '@type': 'RichText',
        'texts': [
          wrap('RichTextBold', 'bold'),
          plain(' '),
          wrap('RichTextItalic', 'italic'),
          plain(' '),
          wrap('RichTextUnderline', 'underline'),
          plain(' '),
          wrap('RichTextStrikethrough', 'strike'),
          plain(' '),
          wrap('RichTextSpoiler', 'spoiler'),
          plain(' '),
          wrap('RichTextDateTime', 'tomorrow'),
          plain(' '),
          {
            '@type': 'RichTextTextMention',
            'text': plain('Alice'),
            'user': {'@type': 'User', 'id': 42},
          },
          plain(' '),
          wrap('RichTextSubscript', 'sub'),
          plain(' '),
          wrap('RichTextSuperscript', 'super'),
          plain(' '),
          wrap('RichTextMarked', 'marked'),
          plain(' '),
          wrap('RichTextCode', 'code'),
          plain(' '),
          {
            '@type': 'RichTextCustomEmoji',
            'text': '🙂',
            'custom_emoji_id': '123456',
          },
          plain(' '),
          {'@type': 'RichTextMathematicalExpression', 'expression': r'x^2'},
          plain(' '),
          {
            '@type': 'RichTextUrl',
            'text': plain('site'),
            'url': 'https://example.com',
          },
          plain(' '),
          {
            '@type': 'RichTextEmailAddress',
            'text': plain('a@example.com'),
            'email_address': 'a@example.com',
          },
          plain(' '),
          {
            '@type': 'RichTextPhoneNumber',
            'text': plain('+123456789'),
            'phone_number': '+123456789',
          },
          plain(' '),
          {
            '@type': 'RichTextBankCardNumber',
            'text': plain('4242 4242 4242 4242'),
            'bank_card_number': '4242 4242 4242 4242',
          },
          plain(' '),
          {
            '@type': 'RichTextMention',
            'text': plain('@telegram'),
            'username': 'telegram',
          },
          plain(' '),
          {
            '@type': 'RichTextHashtag',
            'text': plain('#topic'),
            'hashtag': 'topic',
          },
          plain(' '),
          {
            '@type': 'RichTextCashtag',
            'text': plain(r'$USD'),
            'cashtag': 'USD',
          },
          plain(' '),
          {
            '@type': 'RichTextBotCommand',
            'text': plain('/start'),
            'bot_command': 'start',
          },
          plain(' '),
          {'@type': 'RichTextAnchor', 'name': 'chapter-1'},
          {
            '@type': 'RichTextAnchorLink',
            'text': plain('chapter'),
            'anchor_name': 'chapter-1',
          },
          plain(' '),
          {
            '@type': 'RichTextReference',
            'name': 'note-1',
            'text': plain('reference'),
          },
          plain(' '),
          {
            '@type': 'RichTextReferenceLink',
            'text': plain('note'),
            'reference_name': 'note-1',
          },
        ],
      };

      expect(
        TDParse.richTextText(rich),
        contains(
          'bold italic underline strike spoiler tomorrow Alice sub super marked '
          'code 🙂 x^2 site a@example.com +123456789 '
          '4242 4242 4242 4242 @telegram #topic \$USD /start chapter reference note',
        ),
      );
      final entities = TDParse.richTextEntities(rich);
      expect(entities.map((e) => e.type), [
        'textEntityTypeBold',
        'textEntityTypeItalic',
        'textEntityTypeUnderline',
        'textEntityTypeStrikethrough',
        'textEntityTypeSpoiler',
        'textEntityTypeDateTime',
        'textEntityTypeMentionName',
        'textEntityTypeSubscript',
        'textEntityTypeSuperscript',
        'textEntityTypeMarked',
        'textEntityTypeCode',
        'textEntityTypeCustomEmoji',
        'textEntityTypeMathematicalExpression',
        'textEntityTypeTextUrl',
        'textEntityTypeEmailAddress',
        'textEntityTypePhoneNumber',
        'textEntityTypeBankCardNumber',
        'textEntityTypeTextUrl',
        'textEntityTypeHashtag',
        'textEntityTypeCashtag',
        'textEntityTypeBotCommand',
        'textEntityTypeTextUrl',
        'textEntityTypeTextUrl',
      ]);
      expect(
        entities
            .firstWhere((e) => e.type == 'textEntityTypeMentionName')
            .userId,
        42,
      );
      expect(
        entities
            .firstWhere((e) => e.type == 'textEntityTypeCustomEmoji')
            .customEmojiId,
        123456,
      );
      expect(entities.where((e) => e.url == '#chapter-1'), hasLength(1));
      expect(entities.where((e) => e.url == '#note-1'), hasLength(1));
    });

    test('parses TDLib messageRichMessage in chat messages', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': 100,
        'date': 1,
        'is_outgoing': false,
        'content': {
          '@type': 'messageRichMessage',
          'message': {
            '@type': 'richMessage',
            'is_rtl': false,
            'is_full': true,
            'blocks': [
              {
                '@type': 'pageBlockParagraph',
                'text': {
                  '@type': 'richTexts',
                  'texts': [
                    {'@type': 'richTextPlain', 'text': 'Hello '},
                    {
                      '@type': 'richTextBold',
                      'text': {'@type': 'richTextPlain', 'text': 'bold'},
                    },
                    {'@type': 'richTextPlain', 'text': ' and '},
                    {
                      '@type': 'richTextUrl',
                      'text': {'@type': 'richTextPlain', 'text': 'link'},
                      'url': 'https://example.com',
                      'is_cached': false,
                    },
                  ],
                },
              },
              {
                '@type': 'pageBlockPreformatted',
                'language': 'dart',
                'text': {'@type': 'richTextPlain', 'text': 'final x = 1;'},
              },
              {
                '@type': 'pageBlockMathematicalExpression',
                'expression': r'x^2',
              },
              {
                '@type': 'pageBlockTable',
                'is_bordered': true,
                'is_striped': true,
                'caption': {
                  '@type': 'pageBlockCaption',
                  'text': {'@type': 'richTextPlain', 'text': 'Metrics'},
                },
                'cells': [
                  [
                    {
                      '@type': 'richBlockTableCell',
                      'is_header': true,
                      'align': 'center',
                      'valign': 'middle',
                      'text': {'@type': 'richTextPlain', 'text': 'Name'},
                    },
                    {
                      '@type': 'richBlockTableCell',
                      'is_header': true,
                      'text': {'@type': 'richTextPlain', 'text': 'Value'},
                    },
                  ],
                  [
                    {
                      '@type': 'richBlockTableCell',
                      'text': {'@type': 'richTextPlain', 'text': 'Speed'},
                    },
                    {
                      '@type': 'richBlockTableCell',
                      'text': {
                        '@type': 'richTextBold',
                        'text': {'@type': 'richTextPlain', 'text': '42'},
                      },
                    },
                  ],
                ],
              },
            ],
          },
        },
      });

      expect(message, isNotNull);
      expect(message!.richMessageIsFull, isTrue);
      expect(message.text, isEmpty);
      expect(message.textEntities, isEmpty);
      expect(message.richBlocks, hasLength(4));
      final paragraph = message.richBlocks[0];
      expect(paragraph.kind, RichMessageBlockKind.paragraph);
      expect(paragraph.text, 'Hello bold and link');
      expect(paragraph.textEntities.map((e) => e.type), [
        'textEntityTypeBold',
        'textEntityTypeTextUrl',
      ]);
      expect(paragraph.textEntities[1].url, 'https://example.com');
      final preformatted = message.richBlocks[1];
      expect(preformatted.kind, RichMessageBlockKind.preformatted);
      expect(preformatted.text, 'final x = 1;');
      expect(preformatted.language, 'dart');
      expect(message.richBlocks[2].mathExpression, r'x^2');
      final table = message.richBlocks.last;
      expect(table.caption, 'Metrics');
      expect(table.isBordered, isTrue);
      expect(table.isStriped, isTrue);
      expect(table.tableRows, hasLength(2));
      expect(table.tableRows.first.first.text, 'Name');
      expect(table.tableRows.first.first.isHeader, isTrue);
      expect(table.tableRows.first.first.horizontalAlignment, 'center');
      expect(table.tableRows.first.first.verticalAlignment, 'middle');
      expect(table.tableRows[1][1].text, '42');
      expect(table.tableRows[1][1].entities.single.type, 'textEntityTypeBold');
    });

    test(
      'does not render the generic placeholder for table-only rich messages',
      () {
        final message = TDParse.message({
          '@type': 'message',
          'id': 102,
          'date': 1,
          'is_outgoing': true,
          'content': {
            '@type': 'messageRichMessage',
            'message': {
              '@type': 'richMessage',
              'is_rtl': false,
              'is_full': false,
              'blocks': [
                {
                  '@type': 'pageBlockTable',
                  'cells': [
                    [
                      {
                        '@type': 'pageBlockTableCell',
                        'is_header': true,
                        'text': {'@type': 'richTextPlain', 'text': 'Name'},
                      },
                    ],
                  ],
                },
              ],
            },
          },
        });

        expect(message, isNotNull);
        expect(message!.text, isEmpty);
        expect(message.richBlocks, hasLength(1));
        expect(message.richMessageIsFull, isFalse);
      },
    );

    test('parses rich map blocks and suppresses the generic placeholder', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': 103,
        'date': 1,
        'is_outgoing': true,
        'content': {
          '@type': 'messageRichMessage',
          'message': {
            '@type': 'richMessage',
            'is_full': true,
            'blocks': [
              {
                '@type': 'pageBlockMap',
                'location': {
                  '@type': 'location',
                  'latitude': 35.681236,
                  'longitude': 139.767125,
                },
                'zoom': 17,
                'width': 640,
                'height': 360,
                'caption': {
                  '@type': 'pageBlockCaption',
                  'text': {'@type': 'richTextPlain', 'text': 'Tokyo'},
                },
              },
            ],
          },
        },
      });

      expect(message, isNotNull);
      expect(message!.text, isEmpty);
      expect(message.richBlocks, hasLength(1));
      final map = message.richBlocks.single;
      expect(map.isMap, isTrue);
      expect(map.mapLocation?.latitude, 35.681236);
      expect(map.mapLocation?.longitude, 139.767125);
      expect(map.mapZoom, 17);
      expect(map.mapWidth, 640);
      expect(map.mapHeight, 360);
      expect(map.caption, 'Tokyo');
    });

    test('extracts markdown pipe tables into rich table blocks', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': 101,
        'date': 1,
        'is_outgoing': true,
        'content': {
          '@type': 'messageText',
          'text': {
            '@type': 'formattedText',
            'text':
                'Before\n\n| Name | Value |\n| ---- | ----- |\n| Speed | 42 |\n\nAfter',
          },
        },
      });

      expect(message, isNotNull);
      expect(message!.text, 'Before\n\nAfter');
      expect(message.richBlocks, hasLength(1));
      final table = message.richBlocks.single;
      expect(table.tableRows, hasLength(2));
      expect(table.tableRows.first.first.text, 'Name');
      expect(table.tableRows.first.first.isHeader, isTrue);
      expect(table.tableRows[1][1].text, '42');
    });
  });

  group('TDParse.chat', () {
    test('preserves unread mention count for chat-list indicators', () {
      final chat = TDParse.chat({
        '@type': 'chat',
        'id': 42,
        'title': 'Mentioned chat',
        'unread_count': 3,
        'unread_mention_count': 2,
        'type': {'@type': 'chatTypeBasicGroup', 'basic_group_id': 42},
        'positions': <Object>[],
      });

      expect(chat, isNotNull);
      expect(chat!.unreadMentionCount, 2);
    });
  });

  group('TDParse.messageButtonRows', () {
    test('parses inline keyboard url and callback buttons', () {
      final rows = TDParse.messageButtonRows({
        '@type': 'replyMarkupInlineKeyboard',
        'rows': [
          [
            {
              '@type': 'inlineKeyboardButton',
              'text': 'Open',
              'type': {
                '@type': 'inlineKeyboardButtonTypeUrl',
                'url': 'https://example.com',
              },
            },
            {
              '@type': 'inlineKeyboardButton',
              'text': 'Tap',
              'type': {
                '@type': 'inlineKeyboardButtonTypeCallback',
                'data': 'abc',
              },
            },
          ],
        ],
      });

      expect(rows, hasLength(1));
      expect(rows.first, hasLength(2));
      expect(rows.first[0].text, 'Open');
      expect(rows.first[0].url, 'https://example.com');
      expect(rows.first[1].isCallback, isTrue);
      expect(rows.first[1].data, 'abc');
    });

    test('parses reply keyboard text buttons', () {
      final rows = TDParse.messageButtonRows({
        '@type': 'replyMarkupShowKeyboard',
        'rows': [
          [
            {
              '@type': 'keyboardButton',
              'text': 'OK',
              'type': {'@type': 'keyboardButtonTypeText'},
            },
          ],
        ],
      });

      expect(rows.single.single.text, 'OK');
      expect(rows.single.single.type, 'keyboardButtonTypeText');
      expect(rows.single.single.isReplyKeyboard, isTrue);
    });

    test('marks inline and reply keyboard Web App buttons', () {
      final inlineRows = TDParse.messageButtonRows({
        '@type': 'replyMarkupInlineKeyboard',
        'rows': [
          [
            {
              '@type': 'inlineKeyboardButton',
              'text': 'Mini App',
              'type': {
                '@type': 'inlineKeyboardButtonTypeWebApp',
                'url': 'https://example.com/app',
              },
            },
          ],
        ],
      });
      final replyRows = TDParse.messageButtonRows({
        '@type': 'replyMarkupShowKeyboard',
        'rows': [
          [
            {
              '@type': 'keyboardButton',
              'text': 'Launch',
              'type': {
                '@type': 'keyboardButtonTypeWebApp',
                'url': 'https://example.com/reply-app',
              },
            },
          ],
        ],
      });

      expect(inlineRows.single.single.isWebApp, isTrue);
      expect(inlineRows.single.single.url, 'https://example.com/app');
      expect(replyRows.single.single.isWebApp, isTrue);
      expect(replyRows.single.single.isReplyKeyboard, isTrue);
      expect(replyRows.single.single.url, 'https://example.com/reply-app');
    });
  });

  group('TDParse.linkPreview', () {
    test('parses title, full description, and article photo', () {
      final preview = TDParse.linkPreview({
        '@type': 'linkPreview',
        'url': 'https://example.com/rich',
        'display_url': 'example.com/rich',
        'site_name': 'Example',
        'title': 'Rich Message Demo',
        'description': {
          '@type': 'formattedText',
          'text': 'Select a screen\n- Text Formatting\n- Code & Pre',
          'entities': [
            {
              '@type': 'textEntity',
              'offset': 18,
              'length': 15,
              'type': {'@type': 'textEntityTypeBold'},
            },
          ],
        },
        'type': {
          '@type': 'linkPreviewTypeArticle',
          'photo': {
            '@type': 'photo',
            'sizes': [
              {
                '@type': 'photoSize',
                'width': 320,
                'height': 180,
                'photo': {'@type': 'file', 'id': 42},
              },
            ],
          },
        },
        'show_large_media': true,
        'show_media_above_description': true,
        'show_above_text': false,
      });

      expect(preview, isNotNull);
      expect(preview!.title, 'Rich Message Demo');
      expect(preview.description, contains('Text Formatting'));
      expect(preview.descriptionEntities.single.type, 'textEntityTypeBold');
      expect(preview.image?.id, 42);
      expect(preview.imageWidth, 320);
      expect(preview.imageHeight, 180);
      expect(preview.showLargeMedia, isTrue);
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

  group('CountryMessageFilter', () {
    test(
      'matches selected countries and applies configured exemptions',
      () async {
        SharedPreferences.setMockInitialValues({
          'countryMessageFilter.selectedCountries': ['JP', 'US'],
        });
        final prefs = await SharedPreferences.getInstance();
        final filter = CountryMessageFilter()..initialize(prefs);

        expect(filter.matchesUser(phoneNumber: '+81 90 1234 5678'), isTrue);
        expect(
          filter.matchesUser(isContact: true, phoneNumber: '+81 90 1234 5678'),
          isTrue,
        );
        expect(filter.matchesUser(phoneNumber: '+44 20 7946 0958'), isFalse);
        expect(filter.matchesUser(), isFalse);
        expect(
          filter.shouldExempt(
            hasCommonPrivateGroup: false,
            commonGroupCount: 0,
            isPlainTextWithoutLinks: true,
            hasNonDefaultAvatar: false,
          ),
          isTrue,
        );
      },
    );
  });

  group('TranslationController', () {
    test('defaults off and persists target/provider preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = TranslationController(prefs);

      expect(controller.enabled, isFalse);
      expect(controller.translateChats, isTrue);
      expect(controller.aiTranslationEnabled, isFalse);
      expect(controller.provider, TranslationProvider.tdlib);
      expect(controller.targetLanguageCode, 'zh-Hans');
      expect(controller.displayStyle, TranslationDisplayStyle.quote);
      expect(
        controller.lingvaEndpoint,
        TranslationController.defaultLingvaEndpoint,
      );
      expect(controller.libreTranslateEndpoint, isEmpty);
      expect(controller.libreTranslateApiKey, isEmpty);
      expect(controller.ignoredLanguageCodes, isEmpty);

      controller.enabled = true;
      controller.translateChats = false;
      controller.aiTranslationEnabled = true;
      controller.provider = TranslationProvider.lingva;
      controller.targetLanguageCode = 'ja';
      controller.displayStyle = TranslationDisplayStyle.both;
      controller.lingvaEndpoint = 'https://lingva.example.com/';
      controller.libreTranslateEndpoint = ' https://libre.example.com// ';
      controller.libreTranslateApiKey = ' secret-key ';
      controller.setIgnoredLanguage('ja-JP', true);
      controller.setAutoTranslateEnabledFor(42, true);

      final reloaded = TranslationController(prefs);
      expect(reloaded.enabled, isTrue);
      expect(reloaded.translateChats, isFalse);
      expect(reloaded.aiTranslationEnabled, isTrue);
      expect(reloaded.provider, TranslationProvider.lingva);
      expect(reloaded.targetLanguageCode, 'ja');
      expect(reloaded.displayStyle, TranslationDisplayStyle.both);
      expect(reloaded.lingvaEndpoint, 'https://lingva.example.com');
      expect(reloaded.libreTranslateEndpoint, 'https://libre.example.com');
      expect(reloaded.libreTranslateApiKey, 'secret-key');
      expect(reloaded.ignoredLanguageCodes, {'ja'});
      expect(reloaded.autoTranslateEnabledFor(42), isTrue);
      expect(reloaded.shouldTranslateLanguage('ja'), isFalse);
      expect(reloaded.shouldTranslateLanguage('zh-CN'), isTrue);
      expect(reloaded.shouldTranslateLanguage('de'), isTrue);

      reloaded.dismissAutoTranslateSuggestionFor(42);
      final dismissed = TranslationController(prefs);
      expect(dismissed.autoTranslateEnabledFor(42), isFalse);
      expect(dismissed.autoTranslateSuggestionDismissedFor(42), isTrue);
    });

    test(
      'keeps simplified and traditional Chinese exclusions independent',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final controller = TranslationController(prefs);
        controller.targetLanguageCode = 'en';

        controller.setIgnoredLanguage('zh-CN', true);
        expect(controller.ignoredLanguageCodes, {'zh-Hans'});
        controller.setIgnoredLanguage('zh-TW', true);
        expect(controller.ignoredLanguageCodes, {'zh-Hans', 'zh-Hant'});
        controller.setIgnoredLanguage('zh-Hans', false);
        expect(controller.ignoredLanguageCodes, {'zh-Hant'});
        expect(controller.shouldTranslateLanguage('zh-CN'), isTrue);
        expect(controller.shouldTranslateLanguage('zh-HK'), isFalse);
      },
    );

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

    test(
      'loads stored provider and falls back to Telegram for unavailable values',
      () async {
        SharedPreferences.setMockInitialValues({
          'translation.provider': 'tdlib',
        });
        final prefs = await SharedPreferences.getInstance();
        final controller = TranslationController(prefs);

        expect(controller.provider, TranslationProvider.tdlib);
        controller.provider = TranslationProvider.myMemory;
        expect(controller.provider, TranslationProvider.myMemory);

        SharedPreferences.setMockInitialValues({
          'translation.provider': 'not_a_provider',
        });
        final fallbackPrefs = await SharedPreferences.getInstance();
        final fallback = TranslationController(fallbackPrefs);
        expect(fallback.provider, TranslationProvider.tdlib);

        SharedPreferences.setMockInitialValues({
          'translation.provider': 'native_on_device',
        });
        final nativePrefs = await SharedPreferences.getInstance();
        final nativeFallback = TranslationController(nativePrefs);
        expect(nativeFallback.provider, TranslationProvider.tdlib);
      },
    );
  });

  group('AppLocaleController', () {
    tearDown(() {
      Intl.defaultLocale = null;
    });

    test('AppStrings follows script and regional locale tags', () {
      Intl.defaultLocale = 'zh_Hans';
      expect(AppStrings.t(AppStringKeys.apiCredentialsTitle), '自定义 API 凭据');

      Intl.defaultLocale = 'zh-Hant';
      expect(
        AppLocalizations.localeKeyFor(
          AppLocalizations.resolve(
            AppLocalizations.localeFromTag(Intl.getCurrentLocale())!,
          ),
        ),
        'zhHant',
      );

      Intl.defaultLocale = 'zh_HK';
      expect(
        AppLocalizations.localeKeyFor(
          AppLocalizations.resolve(
            AppLocalizations.localeFromTag(Intl.getCurrentLocale())!,
          ),
        ),
        'zhHant',
      );

      Intl.defaultLocale = 'en_US';
      expect(
        AppLocalizations.localeKeyFor(
          AppLocalizations.resolve(
            AppLocalizations.localeFromTag(Intl.getCurrentLocale())!,
          ),
        ),
        'en',
      );
    });

    test('non-Chinese locales do not surface Chinese fallback strings', () {
      final source = File('lib/l10n/app_localizations.dart').readAsStringSync();
      final keys = RegExp(
        r"static const [A-Za-z0-9_]+ = '([^']+)';",
      ).allMatches(source).map((match) => match.group(1)!).toSet();
      final zhValues = L10nFixtures.load().messages('zhHans');
      // The content-size preview samples are deliberately bilingual
      // (identical Latin + Han + emoji text in every catalogue) so the
      // preview shows how both scripts scale together.
      final intentionalHan = RegExp(
        r'^(appLocale|country|markdown|theme|'
        r'contentSizePreview(Incoming|Outgoing|Name\d|Line\d)$)',
      );
      final han = RegExp(r'[\u3400-\u9fff]');
      final failures = <String>[];
      for (final localeKey in ['en', 'ko', 'fr', 'es', 'de']) {
        for (final key in keys) {
          if (intentionalHan.hasMatch(key)) continue;
          final value = AppStrings.tForLocale(localeKey, key);
          if (han.hasMatch(value)) failures.add('$localeKey.$key=$value');
        }
      }
      final jaSameAsChinese = <String>[];
      for (final key in keys) {
        if (intentionalHan.hasMatch(key)) continue;
        final value = AppStrings.tForLocale('ja', key);
        final zhValue = zhValues[key];
        if (zhValue != null && value == zhValue && han.hasMatch(value)) {
          jaSameAsChinese.add('ja.$key=$value');
        }
      }
      if (jaSameAsChinese.length > 80) {
        failures.add(
          'ja appears to be using Chinese fallback for '
          '${jaSameAsChinese.length} keys: ${jaSameAsChinese.take(5).join(', ')}',
        );
      }
      expect(failures, isEmpty);
    });

    test('country names resolve from the split country map', () {
      expect(AppStrings.tForLocale('en', AppStringKeys.countryJP), 'Japan');
      expect(AppStrings.tForLocale('ja', AppStringKeys.countryJP), '日本');
      expect(AppStrings.tForLocale('ko', AppStringKeys.countryKR), '대한민국');
      expect(AppStrings.tForLocale('zhHant', AppStringKeys.countryTW), '中國台灣');
    });

    test('defaults to system and persists explicit locale choices', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppLocaleController(prefs);

      expect(controller.followsSystem, isTrue);
      expect(controller.locale, isNull);

      controller.locale = const Locale('ja');
      expect(controller.followsSystem, isFalse);
      expect(controller.locale, const Locale('ja'));

      final reloaded = AppLocaleController(prefs);
      expect(reloaded.locale, const Locale('ja'));

      reloaded.locale = null;
      expect(reloaded.followsSystem, isTrue);

      final systemAgain = AppLocaleController(prefs);
      expect(systemAgain.locale, isNull);
    });

    testWidgets('rebuilds localized text when language changes', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppLocaleController(prefs)
        ..locale = const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
        );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: Consumer<AppLocaleController>(
            builder: (context, locale, _) {
              return MaterialApp(
                locale: locale.locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                ],
                home: Builder(
                  builder: (context) => Text(
                    AppStringKeys.tabMessages.l10n(context),
                    textDirection: ui.TextDirection.ltr,
                  ),
                ),
              );
            },
          ),
        ),
      );
      expect(find.text('消息'), findsOneWidget);

      controller.locale = const Locale('en');
      await tester.pumpAndSettle();
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('消息'), findsNothing);
    });

    testWidgets('global AppStrings text follows language changes', (
      tester,
    ) async {
      Intl.defaultLocale = null;
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppLocaleController(prefs)
        ..locale = const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
        );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: Consumer<AppLocaleController>(
            builder: (context, locale, _) {
              return MaterialApp(
                locale: locale.locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                ],
                home: Text(
                  AppStrings.t(AppStringKeys.businessSettingsTitle),
                  textDirection: ui.TextDirection.ltr,
                ),
              );
            },
          ),
        ),
      );
      expect(find.text('企业资料'), findsOneWidget);

      controller.locale = const Locale('en');
      await tester.pumpAndSettle();
      expect(find.text('Business Profile'), findsOneWidget);
      expect(find.text('企业资料'), findsNothing);
    });
  });
}

/// Pumps until [finder] matches, or gives up and lets the caller's expectation
/// report the failure.
///
/// A paste crosses a platform channel and writes a temp file, so how long it
/// takes depends on the machine and on whatever else the suite is running in
/// parallel. Waiting a fixed span passes on an idle box and fails on a loaded
/// one; waiting for the outcome is true on both.
Future<void> _settleUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    await tester.pumpAndSettle();
    if (finder.evaluate().isNotEmpty) return;
    if (!DateTime.now().isBefore(deadline)) return;
    // Real time has to pass for the platform channel reply to arrive, which
    // only runAsync allows.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
}
