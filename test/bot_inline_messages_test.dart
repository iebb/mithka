import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/bot_api/bot_api_store.dart';
import 'package:mithka/bot_api/bot_api_td_converter.dart';
import 'package:mithka/channels/topic_post_content.dart';
import 'package:mithka/chat/bot_button_presentation.dart';
import 'package:mithka/chat/bot_platform_service.dart';
import 'package:mithka/chat/chat_message_merge.dart';
import 'package:mithka/chat/chat_picker_view.dart';
import 'package:mithka/chat/chat_view.dart'
    show ChatView, clearChatMemoryCaches;
import 'package:mithka/chat/internal_chat_link_router.dart';
import 'package:mithka/chat/link_handler.dart' show openInternalLinkType;
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

const _chatId = -1000000005151;
const _otherChatId = 3001;
const _botUserId = 990011;

Map<String, dynamic> _inlineMessageJson({
  int id = 10,
  int viaBotUserId = _botUserId,
  List<List<Map<String, dynamic>>>? rows,
}) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': 1785862260 + id,
  'is_outgoing': true,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 1},
  'via_bot_user_id': viaBotUserId,
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': 'Inline result card $id',
      'entities': <Map<String, dynamic>>[],
    },
  },
  if (rows != null)
    'reply_markup': {'@type': 'replyMarkupInlineKeyboard', 'rows': rows},
};

Map<String, dynamic> _chatJson(int chatId, {String title = 'Group chat'}) => {
  '@type': 'chat',
  'id': chatId,
  'title': title,
  'type': chatId < 0
      ? {
          '@type': 'chatTypeSupergroup',
          'supergroup_id': -chatId - 1000000000000,
          'is_channel': false,
        }
      : {'@type': 'chatTypePrivate', 'user_id': chatId},
  'last_read_inbox_message_id': 10,
  'unread_count': 0,
  'permissions': {'can_send_basic_messages': true},
  'positions': [
    {
      '@type': 'chatPosition',
      'list': {'@type': 'chatListMain'},
      'order': '${999999 - chatId.abs()}',
      'is_pinned': false,
    },
  ],
};

/// A channel-shaped chat: the current-chat switch-inline flow has to ask
/// getSupergroup for the poster's rights before it may write a draft.
Map<String, dynamic> _channelChatJson(int chatId) => {
  '@type': 'chat',
  'id': chatId,
  'title': 'Announcements',
  'type': {
    '@type': 'chatTypeSupergroup',
    'supergroup_id': -chatId - 1000000000000,
    'is_channel': true,
  },
  'permissions': {'can_send_basic_messages': true},
};

Map<String, dynamic> _supergroupForChat(
  int chatId, {
  String statusType = 'chatMemberStatusCreator',
}) => {
  '@type': 'supergroup',
  'id': -chatId - 1000000000000,
  'status': {'@type': statusType},
};

/// A message whose inline keyboard carries a current-chat switch-inline
/// button — the shape TopicPostContent renders inside a topic post.
Map<String, dynamic> _topicInlineMessageJson({int id = 41}) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': 1785862260 + id,
  'is_outgoing': true,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 1},
  'via_bot_user_id': _botUserId,
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': 'Topic inline card',
      'entities': <Map<String, dynamic>>[],
    },
  },
  'reply_markup': {
    '@type': 'replyMarkupInlineKeyboard',
    'rows': [
      [
        {
          '@type': 'inlineKeyboardButton',
          'text': 'Topic Inline Here',
          'type': {
            '@type': 'inlineKeyboardButtonTypeSwitchInline',
            'query': 'cats',
            'target_chat': {'@type': 'targetChatCurrent'},
          },
        },
      ],
    ],
  },
};

Future<void> _noopOpenMessage(int messageId) async {}

Map<String, dynamic> _botUserJson() => {
  '@type': 'user',
  'id': _botUserId,
  'first_name': 'PicBot',
  'usernames': {
    '@type': 'usernames',
    'active_usernames': ['picbot'],
    'editable_username': 'picbot',
    'disabled_usernames': <String>[],
  },
  'type': {
    '@type': 'userTypeBot',
    'is_inline': true,
    'inline_query_placeholder': 'Search photos...',
    'need_location': false,
    'supports_guest_queries': false,
    'has_topics': false,
    'allows_users_to_create_topics': false,
    'can_manage_bots': false,
    'can_be_added_to_attachment_menu': false,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  L10nFixtures.load().install();

  late Future<Map<String, dynamic>> Function(Map<String, dynamic>) queryHandler;
  late List<Map<String, dynamic>> requests;

  // Requests that were routed through an explicit account slot, with the slot
  // they were pinned to. Only engineered ownership crosses this hop.
  late List<(int, Map<String, dynamic>)> routedRequests;

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) => queryHandler(request),
        queryForSlot: (request, slot) {
          routedRequests.add((slot, request));
          return queryHandler(request);
        },
        send: (request) async {
          requests.add(Map<String, dynamic>.from(request));
        },
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);

  late ThemeController theme;
  late TranslationController translation;

  setUp(() async {
    requests = [];
    routedRequests = [];
    ChatDeepLinkController.shared.consumePending();
    SharedPreferences.setMockInitialValues({});
    theme = ThemeController(await SharedPreferences.getInstance());
    translation = TranslationController(await SharedPreferences.getInstance());
    queryHandler = (request) async {
      requests.add(Map<String, dynamic>.from(request));
      return switch (request['@type']) {
        'getChat' => switch (request['chat_id']) {
          _otherChatId => _chatJson(_otherChatId, title: 'Alice'),
          _ => _chatJson(_chatId),
        },
        'getChats' => {
          '@type': 'chats',
          'total_count': 2,
          'chat_ids': [_chatId, _otherChatId],
        },
        'getChatHistory' => {
          '@type': 'messages',
          'total_count': 1,
          'messages': [
            _inlineMessageJson(
              rows: [
                [
                  {
                    '@type': 'inlineKeyboardButton',
                    'text': 'Try Inline Here',
                    'type': {
                      '@type': 'inlineKeyboardButtonTypeSwitchInline',
                      'query': 'cats',
                      'target_chat': {'@type': 'targetChatCurrent'},
                    },
                  },
                  {
                    '@type': 'inlineKeyboardButton',
                    'text': 'Share Inline',
                    'type': {
                      '@type': 'inlineKeyboardButtonTypeSwitchInline',
                      'query': 'dogs',
                      'target_chat': {
                        '@type': 'targetChatChosen',
                        'types': {
                          '@type': 'targetChatTypes',
                          'allow_user_chats': true,
                          'allow_bot_chats': false,
                          'allow_group_chats': false,
                          'allow_channel_chats': false,
                        },
                      },
                    },
                  },
                ],
              ],
            ),
          ],
        },
        'getMe' => {
          '@type': 'user',
          'id': 1,
          'first_name': 'Me',
          'type': {'@type': 'userTypeRegular'},
        },
        'getUser' =>
          (request['user_id'] == _botUserId)
              ? _botUserJson()
              : {
                  '@type': 'user',
                  'id': request['user_id'] ?? 1,
                  'first_name': 'User',
                  'type': {'@type': 'userTypeRegular'},
                },
        'searchPublicChat' => {
          '@type': 'chat',
          'id': _botUserId,
          'title': 'PicBot',
          'type': {'@type': 'chatTypePrivate', 'user_id': _botUserId},
        },
        'getInlineQueryResults' => {
          '@type': 'inlineQueryResults',
          'inline_query_id': '778899',
          'next_offset': request['offset'] == 'page-2' ? '' : 'page-2',
          'is_gallery': false,
          'button': {
            '@type': 'inlineQueryResultsButton',
            'text': 'Open PicBot App',
            'type': {
              '@type': 'inlineQueryResultsButtonTypeStartBot',
              'parameter': 'from_inline',
            },
          },
          'results': request['offset'] == 'page-2'
              ? [
                  {
                    '@type': 'inlineQueryResultArticle',
                    'id': 'res-2',
                    'title': 'Second Page Cat',
                    'description': 'Page 2 item',
                  },
                ]
              : [
                  {
                    '@type': 'inlineQueryResultArticle',
                    'id': 'res-1',
                    'title': 'First Cat',
                    'description': 'Cute cat photo',
                  },
                ],
        },
        'getSupergroup' => {
          '@type': 'supergroup',
          'id': -_chatId - 1000000000000,
        },
        'getSupergroupFullInfo' => {
          '@type': 'supergroupFullInfo',
          'member_count': 4,
        },
        'getRecentInlineBots' => {
          '@type': 'users',
          'total_count': 1,
          'user_ids': [_botUserId],
        },
        'searchChatMembers' => {
          '@type': 'chatMembers',
          'total_count': 0,
          'members': <Map<String, dynamic>>[],
        },
        'getContacts' => {'@type': 'users', 'total_count': 0, 'user_ids': []},
        'getOption' => {'@type': 'optionValueBoolean', 'value': false},
        _ => {'@type': 'ok'},
      };
    };
  });

  tearDown(() {
    ChatDeepLinkController.shared.consumePending();
    clearChatMemoryCaches();
    theme.dispose();
    translation.dispose();
  });

  test(
    'TDParse parses via_bot_user_id, target_chat variants, and Bot API chosen chat',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mithka-bot-inline-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final store = BotApiStore('${tempDir.path}/store.sqlite');
      await store.open();
      addTearDown(store.close);
      final converter = BotApiTdConverter(
        store: store,
        bot: const {'id': 777, 'is_bot': true, 'first_name': 'SelfBot'},
      );
      final converted = converter.message({
        'message_id': 91,
        'date': 1700000000,
        'chat': {'id': 123, 'type': 'private'},
        'from': {'id': 1, 'is_bot': false, 'first_name': 'Alice'},
        'via_bot': {
          'id': _botUserId,
          'is_bot': true,
          'first_name': 'PicBot',
          'username': 'picbot',
        },
        'text': 'Picked via inline',
        'reply_markup': {
          'inline_keyboard': [
            [
              {'text': 'Current', 'switch_inline_query_current_chat': 'here'},
              {
                'text': 'Chosen',
                'switch_inline_query_chosen_chat': {
                  'query': 'filter',
                  'allow_user_chats': true,
                  'allow_group_chats': true,
                },
              },
            ],
          ],
        },
      });
      expect(
        converted.users.any(
          (u) => u['id'] == _botUserId && u['type']?['@type'] == 'userTypeBot',
        ),
        isTrue,
      );

      final parsed = TDParse.message(converted.message)!;
      expect(parsed.viaBotUserId, _botUserId);
      expect(parsed.hasViaBotAttribution, isTrue);
      expect(parsed.buttonRows.single, hasLength(2));

      final currentBtn = parsed.buttonRows.single[0];
      expect(currentBtn.isSwitchInline, isTrue);
      expect(currentBtn.isSwitchInlineCurrentChat, isTrue);
      expect(currentBtn.switchInlineQuery, 'here');
      expect(botButtonBadgeIcon(currentBtn), HeroAppIcons.at);

      final chosenBtn = parsed.buttonRows.single[1];
      expect(chosenBtn.isSwitchInline, isTrue);
      expect(chosenBtn.isSwitchInlineCurrentChat, isFalse);
      expect(chosenBtn.switchInlineQuery, 'filter');
      expect(chosenBtn.switchInlineTarget?.allowedChatKinds, {
        ChatKind.privateChat,
        ChatKind.group,
      });
      expect(botButtonBadgeIcon(chosenBtn), HeroAppIcons.share);

      // Preserve resolved viaBotUsername across mergeChatMessages refreshes.
      parsed.viaBotUsername = '@picbot';
      final refreshed = TDParse.message(converted.message)!;
      final merged = mergeChatMessages([parsed], [refreshed]).single;
      expect(merged.viaBotUsername, '@picbot');
    },
  );

  test(
    'BotInlineResultsPage parses header button, gallery mode, and merges pages',
    () {
      final page1 = BotInlineResultsPage.fromJson({
        '@type': 'inlineQueryResults',
        'inline_query_id': '100',
        'next_offset': '2',
        'is_gallery': true,
        'button': {
          '@type': 'inlineQueryResultsButton',
          'text': 'Create Sticker',
          'type': {
            '@type': 'inlineQueryResultsButtonTypeWebApp',
            'url': 'https://example.com/webapp',
          },
        },
        'results': [
          {
            '@type': 'inlineQueryResultSticker',
            'id': 'stk-1',
            'sticker': {
              '@type': 'sticker',
              'emoji': '😺',
              'format': {'@type': 'stickerFormatTgs'},
            },
          },
        ],
      });
      expect(page1.rendersAsGallery, isTrue);
      expect(page1.hasMore, isTrue);
      expect(page1.button?.text, 'Create Sticker');
      expect(page1.button?.isWebApp, isTrue);
      expect(page1.button?.webAppUrl, 'https://example.com/webapp');
      expect(page1.results.single.emoji, '😺');

      final page2 = BotInlineResultsPage.fromJson({
        '@type': 'inlineQueryResults',
        'inline_query_id': '101',
        'next_offset': '',
        'is_gallery': true,
        'results': [
          {
            '@type': 'inlineQueryResultSticker',
            'id': 'stk-1',
            'sticker': {
              '@type': 'sticker',
              'emoji': '😺',
              'format': {'@type': 'stickerFormatTgs'},
            },
          },
          {
            '@type': 'inlineQueryResultSticker',
            'id': 'stk-2',
            'sticker': {
              '@type': 'sticker',
              'emoji': '🐶',
              'format': {'@type': 'stickerFormatTgs'},
            },
          },
        ],
      });
      final merged = page1.mergeNextPage(page2);
      expect(merged.queryId, 101);
      expect(merged.hasMore, isFalse);
      expect(merged.results.map((r) => r.id), ['stk-1', 'stk-2']);
    },
  );

  Future<void> pumpChat(WidgetTester tester) async {
    clearChatMemoryCaches();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<TranslationController>.value(
            value: translation,
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            extensions: [AppColors.light],
            platform: TargetPlatform.iOS,
          ),
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ChatView(chatId: _chatId, title: 'Group chat'),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets(
    'ChatView renders via @bot header, tapping it or current-chat switch button activates inline bot query in composer',
    (tester) async {
      await pumpChat(tester);

      // 1. Verify via @picbot header is resolved and rendered on the bubble.
      final viaHeader = find.byKey(const ValueKey('messageViaBotHeader-10'));
      expect(viaHeader, findsOneWidget);
      expect(find.text('via @picbot'), findsOneWidget);

      // Verify badge icons on switch_inline buttons.
      expect(
        find.byKey(const ValueKey('message-button-badge-Try Inline Here')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('message-button-badge-Share Inline')),
        findsOneWidget,
      );

      // 2. Tap via @picbot header -> pre-fills "@picbot " in the composer.
      await tester.tap(viaHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField).first);
      expect(textField.controller!.text, '@picbot ');
      expect(find.byKey(const ValueKey('inlineBotResultMenu')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('inlineBotResultsHeaderButton')),
        findsOneWidget,
      );
      expect(find.text('Open PicBot App'), findsOneWidget);
      expect(find.text('First Cat'), findsOneWidget);

      // 3. Tap the "Try Inline Here" current-chat switch button -> replaces
      // composer draft with "@picbot cats" and queries TDLib getInlineQueryResults
      // without showing "Inline switch buttons are not supported yet".
      await tester.tap(
        find.byKey(const ValueKey('message-button-Try Inline Here')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(textField.controller!.text, '@picbot cats');
      expect(
        find.text('Inline switch buttons are not supported yet'),
        findsNothing,
      );
      expect(
        requests.any(
          (r) =>
              r['@type'] == 'getInlineQueryResults' &&
              r['bot_user_id'] == _botUserId &&
              r['query'] == 'cats',
        ),
        isTrue,
      );

      // 4. Tap the inline result to send it.
      await tester.tap(find.byKey(const ValueKey('inlineBotResult-res-1')));
      await tester.pump();

      expect(
        requests.any(
          (r) =>
              r['@type'] == 'sendInlineQueryResultMessage' &&
              r['chat_id'] == _chatId &&
              r['query_id'] == 778899 &&
              r['result_id'] == 'res-1',
        ),
        isTrue,
      );
      expect(textField.controller!.text, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    },
  );

  testWidgets(
    'Chosen-chat switch inline button opens filtered ChatPickerView, saves inline draft, and routes to target chat',
    (tester) async {
      await pumpChat(tester);

      await tester.tap(
        find.byKey(const ValueKey('message-button-Share Inline')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // ChatPickerView filters to user chats only (Alice is shown, Group chat is excluded).
      expect(find.text('Alice'), findsOneWidget);

      await tester.tap(find.text('Alice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        requests.any(
          (r) =>
              r['@type'] == 'setChatDraftMessage' &&
              r['chat_id'] == _otherChatId &&
              ((r['draft_message'] as Map?)?['content'] as Map?)?['text']
                  is Map &&
              ((((r['draft_message'] as Map)['content'] as Map)['text']
                      as Map)['text'] ==
                  '@picbot dogs'),
        ),
        isTrue,
      );
      expect(find.text('Alice'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    },
  );

  testWidgets(
    'Typing @ at the start of the composer suggests recent inline bots and picking one enters inline mode',
    (tester) async {
      await pumpChat(tester);

      final field = find.byType(TextField).first;
      await tester.tap(field);
      await tester.enterText(field, '@pic');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();

      final botCandidate = find.byKey(
        const ValueKey('mentionCandidate-990011'),
      );
      expect(botCandidate, findsOneWidget);
      expect(find.text('PicBot'), findsOneWidget);
      expect(find.text('@picbot'), findsOneWidget);

      await tester.tap(botCandidate);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      final textField = tester.widget<TextField>(field);
      expect(textField.controller!.text, '@picbot ');
      expect(
        requests.any(
          (r) =>
              r['@type'] == 'getInlineQueryResults' &&
              r['bot_user_id'] == _botUserId &&
              r['query'] == '',
        ),
        isTrue,
      );
      expect(find.byKey(const ValueKey('inlineBotResultMenu')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    },
  );

  // ---------------------------------------------------------------------------
  // TopicPostContent current-chat switch-inline ownership.
  //
  // The transcript this button lives in can be unmounted (the user leaves the
  // topic view) or re-accounted (the active account switches) while the
  // permission lookups are still in flight. Every await in the chain has to
  // re-check both, and the draft write must never be reached afterwards —
  // chat ids are account-scoped, so a late write lands in the wrong account.
  // ---------------------------------------------------------------------------
  group('TopicPostContent switch-inline ownership', () {
    late Future<Map<String, dynamic>> Function(Map<String, dynamic>)
    topicHandler;
    late List<Map<String, dynamic>> topicRequests;

    final routedTopicRequests = <(int?, Map<String, dynamic>)>[];

    setUp(() {
      // Installed in this order (mounted per test, after the outer setUp):
      //   1. record the response, so the slot is read at request time
      //   2. record the request through `topicRequests`
      //   3. the per-test `topicHandler` decides the response, holding it if the
      //      test needs to resolve it after the screen has gone away.
      topicHandler = (request) async => switch (request['@type']) {
        'getChat' => _channelChatJson(_chatId),
        'getSupergroup' => _supergroupForChat(_chatId),
        _ => {'@type': 'ok'},
      };
      topicRequests = [];
      routedTopicRequests.clear();
      queryHandler = (request) async {
        topicRequests.add(request);
        final response = topicHandler(request);
        // The pinned account hop (queryForSlot) carries the owning slot; a
        // request that only resolved the foreground account records whatever
        // slot is active at request time, which is exactly the hazard under
        // test.
        int? pinned;
        while (routedRequests.isNotEmpty) {
          final candidate = routedRequests.removeAt(0);
          if (identical(candidate.$2, request)) {
            pinned = candidate.$1;
            break;
          }
        }
        routedTopicRequests.add((pinned, request));
        return response;
      };
    });

    // The composer for this chat stays on the same providers the app shell
    // supplies, so the live flow can actually open the current chat.
    Widget topicApp(Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<TranslationController>.value(value: translation),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate],
        theme: ThemeData(
          platform: TargetPlatform.iOS,
          extensions: [AppColors.light],
        ),
        home: home,
      ),
    );

    Future<void> pumpTopicPost(WidgetTester tester, ChatMessage message) async {
      await tester.pumpWidget(
        topicApp(
          Scaffold(
            body: TopicPostContent(
              chatId: _chatId,
              message: message,
              text: message.text,
              textStyle: const TextStyle(fontSize: 15),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    List<Map<String, dynamic>> draftWrites() => [
      for (final request in topicRequests)
        if (request['@type'] == 'setChatDraftMessage') request,
    ];

    List<Map<String, dynamic>> getChatRequests() => [
      for (final request in topicRequests)
        if (request['@type'] == 'getChat') request,
    ];

    List<Map<String, dynamic>> getSupergroupRequests() => [
      for (final request in topicRequests)
        if (request['@type'] == 'getSupergroup') request,
    ];

    testWidgets(
      'a held getChat that resolves after the topic post unmounted never writes the draft',
      (tester) async {
        final message = TDParse.message(_topicInlineMessageJson())!;
        final held = Completer<Map<String, dynamic>>();
        topicHandler = (request) async => switch (request['@type']) {
          'getUser' => _botUserJson(),
          'getChat' => held.future,
          // Rights are fine; only the timing of the getChat response matters.
          'getSupergroup' => _supergroupForChat(_chatId),
          _ => {'@type': 'ok'},
        };

        await pumpTopicPost(tester, message);
        await tester.tap(find.text('Topic Inline Here'));
        await tester.pump();
        expect(getChatRequests(), hasLength(1));

        // The user leaves the topic view while the permission lookup is held.
        await tester.pumpWidget(const SizedBox.shrink());
        held.complete(_channelChatJson(_chatId));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
        expect(
          draftWrites(),
          isEmpty,
          reason:
              'a draft resolved after unmount is still the old flow writing',
        );
      },
    );

    testWidgets(
      'a held getSupergroup that resolves after the topic post unmounted never writes the draft',
      (tester) async {
        final message = TDParse.message(_topicInlineMessageJson())!;
        final held = Completer<Map<String, dynamic>>();
        topicHandler = (request) async => switch (request['@type']) {
          'getUser' => _botUserJson(),
          'getChat' => _channelChatJson(_chatId),
          'getSupergroup' => held.future,
          _ => {'@type': 'ok'},
        };

        await pumpTopicPost(tester, message);
        await tester.tap(find.text('Topic Inline Here'));
        await tester.pump();
        expect(getSupergroupRequests(), hasLength(1));

        await tester.pumpWidget(const SizedBox.shrink());
        held.complete(_supergroupForChat(_chatId));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
        expect(draftWrites(), isEmpty);
      },
    );

    testWidgets(
      'switching the active account mid-lookup voids the topic post draft write',
      (tester) async {
        final message = TDParse.message(_topicInlineMessageJson())!;
        final held = Completer<Map<String, dynamic>>();
        topicHandler = (request) async => switch (request['@type']) {
          'getUser' => _botUserJson(),
          'getChat' => held.future,
          // Rights are fine; only the timing of the getChat response matters.
          'getSupergroup' => _supergroupForChat(_chatId),
          _ => {'@type': 'ok'},
        };

        await pumpTopicPost(tester, message);
        await tester.tap(find.text('Topic Inline Here'));
        await tester.pump();
        expect(getChatRequests(), hasLength(1));
        expect(getChatRequests().single['chat_id'], _chatId);

        // The account switcher moves the foreground to a fresh login slot, as
        // replaceActiveWithFreshLoginSlot does after a logout.
        TdClient.shared.debugSetActiveAccountForTesting(41, 4101);
        addTearDown(
          () => TdClient.shared.debugSetActiveAccountForTesting(0, 1),
        );

        held.complete(_channelChatJson(_chatId));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
        expect(
          draftWrites(),
          isEmpty,
          reason:
              'the draft is account-scoped and must not be written after the switch',
        );
      },
    );

    testWidgets(
      'a live current-chat switch-inline still writes the draft to the owning account',
      (tester) async {
        final message = TDParse.message(_topicInlineMessageJson())!;
        topicHandler = (request) async => switch (request['@type']) {
          'getUser' => _botUserJson(),
          'getChat' => _channelChatJson(_chatId),
          'getSupergroup' => _supergroupForChat(_chatId),
          _ => {'@type': 'ok'},
        };
        await pumpTopicPost(tester, message);

        await tester.tap(find.text('Topic Inline Here'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final draft = draftWrites().single;
        expect(draft['chat_id'], _chatId);
        final content =
            ((draft['draft_message'] as Map)['content'] as Map)['text'] as Map;
        expect(content['text'], '@picbot cats');
        // Every lookup and the write travelled through the pinned account, even
        // though a bug would have re-resolved the foreground slot each time.
        const flowTypes = {
          'getUser',
          'getChat',
          'getSupergroup',
          'setChatDraftMessage',
        };
        // Only the switch-inline chain is under test: the chat view it opens
        // afterwards bootstraps its own transcript on the foreground account.
        final flowRequests = <(int?, String?)>[];
        for (final entry in routedTopicRequests) {
          final type = entry.$2['@type'];
          if (!flowTypes.contains(type)) continue;
          flowRequests.add((entry.$1, type));
          if (type == 'setChatDraftMessage') break;
        }
        expect(
          flowRequests.map((entry) => entry.$2).toSet(),
          containsAll(<String>['getUser', 'getChat', 'setChatDraftMessage']),
        );
        expect(
          flowRequests.map((entry) => entry.$1).toSet(),
          {0},
          reason: 'the flow must keep asking across the originating account',
        );
      },
    );

    testWidgets(
      'the inline-query picker hydrates its rows on the account that launched it',
      (tester) async {
        final loadChats = Completer<Map<String, dynamic>>();
        topicHandler = (request) async => switch (request['@type']) {
          'loadChats' => loadChats.future,
          'getChats' => {
            '@type': 'chats',
            'total_count': 1,
            'chat_ids': [_otherChatId],
          },
          'getChat' => _chatJson(_otherChatId, title: 'Alice'),
          'getContacts' => {
            '@type': 'users',
            'total_count': 0,
            'user_ids': <int>[],
          },
          'getOption' => {'@type': 'optionValueBoolean', 'value': false},
          _ => {'@type': 'ok'},
        };

        // The picker is launched from the composer's inline-query flow, which
        // runs on a client pinned to the account that owns the chat.
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeController>.value(value: theme),
              ChangeNotifierProvider<TranslationController>.value(
                value: translation,
              ),
            ],
            child: MaterialApp(
              theme: ThemeData(
                extensions: [AppColors.light],
                platform: TargetPlatform.iOS,
              ),
              locale: const Locale('en'),
              localizationsDelegates: const [AppLocalizations.delegate],
              supportedLocales: AppLocalizations.supportedLocales,
              home: const InternalChatLinkScope(
                target: InternalChatLinkTarget(
                  chatId: _chatId,
                  accountSlot: 7,
                  openMessage: _noopOpenMessage,
                ),
                child: ChatPickerView(allowedKinds: {ChatKind.privateChat}),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          topicRequests.any((request) => request['@type'] == 'loadChats'),
          isTrue,
        );

        // The foreground account switches while the picker is still loading.
        TdClient.shared.debugSetActiveAccountForTesting(3, 3003);
        addTearDown(
          () => TdClient.shared.debugSetActiveAccountForTesting(0, 1),
        );

        loadChats.complete({'@type': 'ok'});
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        final rowLookups = [
          for (final (slot, request) in routedTopicRequests)
            if (request['@type'] == 'getChat') (slot, request['chat_id']),
        ];
        expect(rowLookups, isNotEmpty);
        expect(
          rowLookups.map((lookup) => lookup.$1).toSet(),
          {7},
          reason:
              'a row hydrated after the account switch still used the '
              'launching account',
        );
        expect(rowLookups.map((lookup) => lookup.$2).toSet(), {_otherChatId});
        expect(find.text('Alice'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 6));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Picker ownership at the route and contact boundaries.
  //
  // A picker pushed by a link handler is a sibling route of the transcript that
  // launched it, so it inherits no [InternalChatLinkScope]; and its contact
  // rows are loaded by a different path than its chat list. Both have to stay
  // on the account that owns the source chat: chat ids and user ids are only
  // meaningful inside the account that produced them, so a slot-7 transcript
  // under a slot-0 foreground must never list — or draft into — slot 0.
  // ---------------------------------------------------------------------------
  group('ChatPickerView source-account ownership', () {
    const sourceSlot = 7;
    const foregroundSlot = 0;
    const sourceChatId = 7001;
    const sourceContactId = 7002;
    const foregroundChatId = 3001;
    const foregroundContactId = 3002;

    // Every request the picker flow issued, with the account it was resolved
    // on. A request that only resolved the foreground account records slot 0,
    // which is exactly the hazard under test.
    final slotLog = <(int, Map<String, dynamic>)>[];

    Map<String, dynamic> slotUser(int id, String name) => {
      '@type': 'user',
      'id': id,
      'first_name': name,
      'type': {'@type': 'userTypeRegular'},
    };

    /// Disjoint account contents: ids and names only exist in one slot, so a
    /// cross-account read is visible in the rendered rows as well as the log.
    Future<Map<String, dynamic>> respond(
      int slot,
      Map<String, dynamic> request,
    ) async {
      final isSource = slot == sourceSlot;
      final chatId = isSource ? sourceChatId : foregroundChatId;
      final contactId = isSource ? sourceContactId : foregroundContactId;
      final chatTitle = isSource ? 'Source chat 7001' : 'Foreground chat 3001';
      final contactName = isSource ? 'SourceContact' : 'ForeignContact';
      return switch (request['@type']) {
        'getChats' => {
          '@type': 'chats',
          'total_count': 1,
          'chat_ids': [chatId],
        },
        'getChat' => _chatJson(chatId, title: chatTitle),
        'getContacts' => {
          '@type': 'users',
          'total_count': 1,
          'user_ids': [contactId],
        },
        'getUser' =>
          request['user_id'] == contactId
              ? slotUser(contactId, contactName)
              : slotUser((request['user_id'] as int?) ?? 1, 'User'),
        'createPrivateChat' => _chatJson(contactId, title: contactName),
        'getOption' => {'@type': 'optionValueBoolean', 'value': false},
        _ => {'@type': 'ok'},
      };
    }

    /// Pairs each in-flight request with the slot `queryForSlot` pinned it to.
    /// The slot-aware transport hands the same map instance to both, so
    /// identity separates a pinned request from an active-account one.
    int pinnedSlotOf(Map<String, dynamic> request) {
      for (var i = 0; i < routedRequests.length; i++) {
        final candidate = routedRequests[i];
        if (identical(candidate.$2, request)) {
          routedRequests.removeAt(i);
          return candidate.$1;
        }
      }
      return foregroundSlot;
    }

    void installSlotData() {
      slotLog.clear();
      queryHandler = (request) async {
        final slot = pinnedSlotOf(request);
        slotLog.add((slot, request));
        return respond(slot, request);
      };
    }

    Iterable<(int, Map<String, dynamic>)> requestsOf(Set<String> types) => [
      for (final entry in slotLog)
        if (types.contains(entry.$2['@type'])) entry,
    ];

    Widget pickerApp(Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<TranslationController>.value(value: translation),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate],
        theme: ThemeData(
          platform: TargetPlatform.iOS,
          extensions: [AppColors.light],
        ),
        home: home,
      ),
    );

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    Future<void> teardownPicker(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    }

    testWidgets(
      'a draft-share link keeps the picker, draft, and open on the source account',
      (tester) async {
        installSlotData();
        final drafts = <(int, Object?)>[];

        await tester.pumpWidget(
          pickerApp(
            InternalChatLinkScope(
              target: const InternalChatLinkTarget(
                chatId: 7000,
                accountSlot: sourceSlot,
                openMessage: _noopOpenMessage,
              ),
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    key: const ValueKey('open-draft-link'),
                    onPressed: () => openInternalLinkType(context, {
                      '@type': 'internalLinkTypeMessageDraft',
                      'text': {
                        '@type': 'formattedText',
                        'text': 'hello from the source',
                        'entities': <Map<String, dynamic>>[],
                      },
                      'url': 'tg://draft',
                    }),
                    child: const Text('open draft link'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('open-draft-link')));
        await settle(tester);

        // The real handler pushed the real picker onto the ancestor navigator,
        // outside the scope above: it must still list the slot-7 account.
        expect(
          find.text('Source chat 7001'),
          findsOneWidget,
          reason:
              'the pushed picker listed chats from outside the source route',
        );
        expect(find.text('Foreground chat 3001'), findsNothing);
        expect(find.text('SourceContact'), findsOneWidget);
        expect(find.text('ForeignContact'), findsNothing);
        expect(
          {
            for (final (slot, _) in requestsOf({
              'getChats',
              'getChat',
              'getContacts',
              'getUser',
            }))
              slot,
          },
          {sourceSlot},
          reason: 'picker reads resolved an account other than the source',
        );

        await tester.tap(find.text('Source chat 7001'));
        await settle(tester);

        for (final (slot, request) in slotLog) {
          if (request['@type'] == 'setChatDraftMessage') {
            drafts.add((slot, request['chat_id']));
          }
        }
        expect(drafts, [(sourceSlot, sourceChatId)]);
        // The hazard this pins: the picker used to resolve the foreground
        // account, list its chat 3001, and draft there. Name those two exact
        // misses so a regression fails as itself, not as a bare tuple diff.
        expect(
          drafts.where(
            (draft) =>
                draft.$1 == foregroundSlot || draft.$2 == foregroundChatId,
          ),
          isEmpty,
          reason: 'the draft went to the foreground account instead of slot 7',
        );

        final opened = ChatDeepLinkController.shared.consumePending();
        expect(opened, isNotNull, reason: 'the picked chat was never opened');
        expect(opened!.chatId, sourceChatId);
        expect(
          opened.accountSlot,
          sourceSlot,
          reason: 'the conversation opened on an account it does not belong to',
        );

        await teardownPicker(tester);
      },
    );

    testWidgets(
      'ChatPickerView pins contact hydration and creation to its account slot',
      (tester) async {
        installSlotData();
        ChatSummary? picked;

        await tester.pumpWidget(
          pickerApp(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  key: const ValueKey('open-picker'),
                  onPressed: () async {
                    picked = await Navigator.of(context).push<ChatSummary>(
                      MaterialPageRoute(
                        builder: (_) => const ChatPickerView(
                          allowedKinds: {ChatKind.privateChat},
                          accountSlot: sourceSlot,
                        ),
                      ),
                    );
                  },
                  child: const Text('open picker'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('open-picker')));
        await settle(tester);

        expect(
          [
            for (final (slot, _) in requestsOf({'getContacts'})) slot,
          ],
          [sourceSlot],
          reason: 'getContacts resolved the foreground account',
        );
        final contactUserIds = {sourceContactId, foregroundContactId};
        expect(
          [
            for (final (slot, request) in requestsOf({'getUser'}))
              if (contactUserIds.contains(request['user_id']))
                (slot, request['user_id']),
          ],
          [(sourceSlot, sourceContactId)],
          reason: 'contact hydration resolved the foreground account',
        );
        expect(
          {
            for (final (slot, _) in requestsOf({'getUser'})) slot,
          },
          {sourceSlot},
          reason: 'a picker row described its peer with another account',
        );
        expect(find.text('SourceContact'), findsOneWidget);
        expect(find.text('ForeignContact'), findsNothing);
        expect(find.text('Source chat 7001'), findsOneWidget);
        expect(find.text('Foreground chat 3001'), findsNothing);

        await tester.tap(find.text('SourceContact'));
        await settle(tester);

        expect(
          [
            for (final (slot, request) in requestsOf({'createPrivateChat'}))
              (slot, request['user_id']),
          ],
          [(sourceSlot, sourceContactId)],
          reason: 'the contact row created its private chat elsewhere',
        );
        expect(picked?.id, sourceContactId);
        expect(picked?.title, 'SourceContact');
        expect(
          requestsOf({
            'getContacts',
            'getUser',
            'createPrivateChat',
          }).where((entry) => entry.$1 == foregroundSlot),
          isEmpty,
          reason: 'slot-0 contact data leaked into a slot-7 picker',
        );

        await teardownPicker(tester);
      },
    );
  });
}
