import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_message_merge.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/message_action_menu.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chat/message_replies_sheet.dart';
import 'package:mithka/chat/rich_text_format.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/moments/moments_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;
  late Future<Map<String, dynamic>> Function(Map<String, dynamic> request)
  queryHandler;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 4,
        query: (request) => queryHandler(request),
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    queryHandler = (request) async => <String, dynamic>{'@type': 'ok'};
  });

  tearDownAll(() async {
    await updates.close();
  });

  test('reply sheet requests share channel and nested reply routing', () {
    const formatted = FormattedTextPayload('Nested reply', []);
    final forum = buildReplySheetTextRequest(
      chatId: -1001,
      formatted: formatted,
      topicId: const {'@type': 'messageTopicForum', 'forum_topic_id': 77},
      legacyMessageThreadId: 77,
      replyToMessageId: 42,
    );
    expect((forum['topic_id'] as Map)['@type'], 'messageTopicForum');
    expect(forum['message_thread_id'], 77);
    expect((forum['reply_to'] as Map)['message_id'], 42);

    final thread = buildReplySheetTextRequest(
      chatId: -2002,
      formatted: formatted,
      topicId: const {'@type': 'messageTopicThread', 'message_thread_id': 99},
    );
    expect((thread['topic_id'] as Map)['@type'], 'messageTopicThread');
    expect(thread, isNot(contains('reply_to')));
  });

  test('view in chat targets the linked discussion root message', () {
    final target = resolveMessageRepliesViewTarget(
      sourceChatId: -1001,
      sourceMessageId: 42,
      sourceTitle: 'Channel',
      threadChatId: -2002,
      threadRootMessageId: 99,
      threadTitle: 'Discussion',
    );

    expect(target.chatId, -2002);
    expect(target.messageId, 99);
    expect(target.title, 'Discussion');
  });

  test('view in chat keeps same-chat replies on their source message', () {
    final target = resolveMessageRepliesViewTarget(
      sourceChatId: -1001,
      sourceMessageId: 42,
      sourceTitle: 'Group',
      threadChatId: -1001,
      rootReplyToMessageId: 42,
    );

    expect(target.chatId, -1001);
    expect(target.messageId, 42);
    expect(target.title, 'Group');
  });

  test('view in chat never crosses chats without a resolved thread root', () {
    final target = resolveMessageRepliesViewTarget(
      sourceChatId: -1001,
      sourceMessageId: 42,
      sourceTitle: 'Channel',
      threadChatId: -2002,
      threadTitle: 'Discussion',
    );

    expect(target.chatId, -1001);
    expect(target.messageId, 42);
    expect(target.title, 'Channel');
  });

  testWidgets('reply sheet items render video and structured rich content', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    final video = ChatMessage(
      id: 41,
      isOutgoing: false,
      text: '[Video]',
      date: 1,
      contentType: 'messageVideo',
      senderName: 'Video sender',
      video: TdFileRef(id: 401),
      videoDuration: 75,
      imageWidth: 1280,
      imageHeight: 720,
    );
    final rich = ChatMessage(
      id: 42,
      isOutgoing: false,
      text: '',
      date: 2,
      contentType: 'messageRichMessage',
      senderName: 'Rich sender',
      richBlocks: const [
        RichMessageBlock.text(
          kind: RichMessageBlockKind.heading,
          text: 'Structured reply heading',
          size: 2,
        ),
        RichMessageBlock.text(
          kind: RichMessageBlockKind.paragraph,
          text: 'Formatted reply body',
          entities: [
            MessageTextEntity(offset: 0, length: 9, type: 'textEntityTypeBold'),
          ],
        ),
      ],
    );
    ChatMessage? played;
    ChatMessage? replied;
    ChatMessage? longPressed;

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  MessageReplySheetItem(
                    message: video,
                    peerTitle: 'Discussion',
                    senderName: 'Video sender',
                    onPlayVideo: (message) => played = message,
                  ),
                  MessageReplySheetItem(
                    message: rich,
                    peerTitle: 'Discussion',
                    senderName: 'Rich sender',
                    onReply: (message) => replied = message,
                    onLongPress: (message, bounds, source) {
                      longPressed = message;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MessageBubble), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('messageTappedTimestamp')),
      findsNWidgets(2),
    );
    expect(find.text('[Video]'), findsNothing);
    expect(
      find.text('Structured reply heading', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Formatted reply body', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rich-message-block-0-heading')),
      findsOneWidget,
    );

    final richBubble = tester.widget<MessageBubble>(
      find.byKey(const ValueKey('messageRepliesSheetMessage-42')),
    );
    richBubble.onReply?.call(rich);
    expect(replied, same(rich));
    richBubble.onLongPress?.call(rich, Rect.zero, MessageActionSource.normal);
    expect(longPressed, same(rich));

    final play = find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.icon == HeroAppIcons.play,
    );
    expect(play, findsOneWidget);
    await tester.tap(play);
    expect(played, same(video));
    expect(tester.takeException(), isNull);
  });

  test(
    'mergeChatMessages preserves resolved reply anchor fields on refresh',
    () {
      final existing =
          ChatMessage(
              id: 301,
              isOutgoing: false,
              text: 'Comment reply',
              date: 10,
              replyToMessageId: 201,
              replyToDate: 5,
              replyToEntities: const [
                MessageTextEntity(
                  offset: 0,
                  length: 4,
                  type: 'textEntityTypeBold',
                ),
              ],
            )
            ..replyToSender = 'Bob'
            ..replyToPreview = 'Bold parent comment';

      final refreshed = ChatMessage(
        id: 301,
        isOutgoing: false,
        text: 'Comment reply',
        date: 10,
        replyToMessageId: 201,
        commentCount: 1,
        commentThreadMetadataKnown: true,
      );

      final merged = mergeChatMessages([existing], [refreshed]);
      expect(merged.single.replyToSender, 'Bob');
      expect(merged.single.replyToPreview, 'Bold parent comment');
      expect(merged.single.replyToDate, 5);
      expect(merged.single.replyToEntities, hasLength(1));
    },
  );

  test(
    'ChatViewModel resolves cross-chat reply targets using replyToChatId',
    () async {
      final getMessagesRequests = <Map<String, dynamic>>[];
      queryHandler = (request) async {
        switch (request['@type']) {
          case 'getMessages':
            getMessagesRequests.add(Map<String, dynamic>.from(request));
            final chatId = request['chat_id'] as int;
            if (chatId == -1001) {
              return <String, dynamic>{
                '@type': 'messages',
                'messages': [
                  <String, dynamic>{
                    '@type': 'message',
                    'id': 42,
                    'chat_id': -1001,
                    'is_outgoing': false,
                    'date': 10,
                    'sender_id': {
                      '@type': 'messageSenderChat',
                      'chat_id': -1001,
                    },
                    'content': {
                      '@type': 'messageText',
                      'text': {
                        '@type': 'formattedText',
                        'text': 'Channel post anchor',
                        'entities': <Map<String, dynamic>>[],
                      },
                    },
                  },
                ],
              };
            }
            return <String, dynamic>{
              '@type': 'messages',
              'messages': <Map<String, dynamic>>[],
            };
          case 'getChat':
            return <String, dynamic>{
              '@type': 'chat',
              'id': request['chat_id'],
              'title': request['chat_id'] == -1001
                  ? 'News Channel'
                  : 'Discussion Group',
            };
          case 'getChatHistory':
            return <String, dynamic>{
              '@type': 'messages',
              'messages': [
                <String, dynamic>{
                  '@type': 'message',
                  'id': 501,
                  'chat_id': -2002,
                  'is_outgoing': false,
                  'date': 20,
                  'sender_id': {'@type': 'messageSenderUser', 'user_id': 7},
                  'reply_to': {
                    '@type': 'messageReplyToMessage',
                    'chat_id': -1001,
                    'message_id': 42,
                  },
                  'content': {
                    '@type': 'messageText',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'Commenting on the channel post',
                      'entities': <Map<String, dynamic>>[],
                    },
                  },
                },
              ],
            };
          default:
            return <String, dynamic>{'@type': 'ok'};
        }
      };

      final vm = ChatViewModel(
        chatId: -2002,
        title: 'Discussion Group',
        markReadOnOpen: true,
      );
      addTearDown(vm.dispose);
      vm.onAppear();
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(getMessagesRequests, isNotEmpty);
      expect(getMessagesRequests.first['chat_id'], -1001);
      expect(getMessagesRequests.first['message_ids'], [42]);
      expect(vm.messages.single.replyToPreview, 'Channel post anchor');
      expect(vm.messages.single.replyToSender, 'News Channel');
    },
  );

  test(
    'reply sheet asks a discussion thread through its resolved coordinates',
    () {
      // A post whose thread lives in the linked group: TDLib cannot replay the
      // reply search for that thread in the group unless it is told which group
      // and which root to read, so the post's own coordinates must not be used.
      final bridged = buildReplySheetHistoryRequest(
        chatId: -1001,
        messageId: 42,
        threadChatId: -2002,
        threadRootMessageId: 99,
      );
      expect(bridged['chat_id'], -2002);
      expect(bridged['message_id'], 99);
      expect(bridged['limit'], 100);
      expect(bridged['offset'], 0);
      expect(bridged['from_message_id'], 0);

      // A thread the source message already addresses (same chat) stays on the
      // source coordinates: no cross-chat resolution happens there.
      final sameChat = buildReplySheetHistoryRequest(
        chatId: -1001,
        messageId: 42,
        threadChatId: -1001,
        threadRootMessageId: 42,
      );
      expect(sameChat['chat_id'], -1001);
      expect(sameChat['message_id'], 42);

      // Without a resolved root the source coordinates are the only ones known.
      final unresolved = buildReplySheetHistoryRequest(
        chatId: -1001,
        messageId: 42,
      );
      expect(unresolved['chat_id'], -1001);
      expect(unresolved['message_id'], 42);
    },
  );

  testWidgets(
    'a channel post with no comments yet still opens its thread and composer',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);

      final historyRequests = <Map<String, dynamic>>[];
      queryHandler = (request) async {
        switch (request['@type']) {
          case 'getMessageProperties':
            // A post nobody has commented on yet reports a thread whenever the
            // channel has a linked group, even before that root is resolved.
            return <String, dynamic>{
              '@type': 'messageProperties',
              'can_get_message_thread': true,
              'can_be_replied': false,
            };
          case 'getMessageThread':
            return <String, dynamic>{
              '@type': 'messageThreadInfo',
              'chat_id': -2002,
              'message_thread_id': 99,
              'messages': <Map<String, dynamic>>[],
            };
          case 'getChat':
            final id = request['chat_id'] as int;
            return <String, dynamic>{
              '@type': 'chat',
              'id': id,
              'title': id == -2002 ? 'Discussion Group' : 'News Channel',
              'permissions': {'can_send_basic_messages': true},
            };
          case 'getMessageThreadHistory':
            historyRequests.add(Map<String, dynamic>.from(request));
            // The post's own coordinates are the ones TDLib answers a fresh
            // post's thread with a 500 for; only the resolved thread
            // coordinates address the empty thread.
            if (request['chat_id'] != -2002 || request['message_id'] != 99) {
              return <String, dynamic>{
                '@type': 'error',
                'code': 500,
                'message': 'Receive messages in an unexpected chat',
              };
            }
            return <String, dynamic>{
              '@type': 'messages',
              'total_count': 0,
              'messages': <Map<String, dynamic>>[],
            };
          default:
            return <String, dynamic>{'@type': 'ok'};
        }
      };

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(extensions: [AppColors.light]),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showMessageRepliesSheet(
                      context: context,
                      chatId: -1001,
                      message: ChatMessage(
                        id: 42,
                        isOutgoing: false,
                        text: 'Channel post',
                        date: 10,
                        chatId: -1001,
                      ),
                      peerTitle: 'News Channel',
                    );
                  },
                  child: const Text('Open comments'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open comments'));
      await tester.pumpAndSettle();

      expect(historyRequests, hasLength(1));
      expect(historyRequests.single['chat_id'], -2002);
      expect(historyRequests.single['message_id'], 99);
      // The unavailable state is for a message TDLib refuses to thread at all;
      // an empty thread must read as "no comments yet" and keep the composer.
      expect(
        find.text(AppStrings.t(AppStringKeys.messageRepliesUnavailable)),
        findsNothing,
      );
      expect(
        find.text(AppStrings.t(AppStringKeys.messageRepliesEmpty)),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('messageRepliesComposer')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('channel post comments are read through the resolved thread', () {
    final channel = ChatSummary(
      id: -1001,
      title: 'News Channel',
      lastMessage: '',
      lastMessageId: 0,
      date: 0,
      unreadCount: 0,
      order: 0,
      isMuted: false,
      kind: ChatKind.channel,
    );
    final post = ChannelPost(
      channel: channel,
      message: ChatMessage(
        id: 42,
        isOutgoing: false,
        text: 'Channel post',
        date: 10,
      ),
      accountSlot: 4,
    );

    final resolved = channelPostCommentsRequest(
      post: post,
      target: const ChannelPostThreadTarget(chatId: -2002, messageThreadId: 99),
      limit: 5,
    );
    expect(resolved['@type'], 'getMessageThreadHistory');
    expect(resolved['chat_id'], -2002);
    expect(resolved['message_id'], 99);
    expect(resolved['limit'], 5);

    final unresolved = channelPostCommentsRequest(post: post);
    expect(unresolved['chat_id'], -1001);
    expect(unresolved['message_id'], 42);
  });

  testWidgets(
    'reply sheet resolves uncached comment reply anchors and jumps to discussion targets',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);

      final getMessagesRequests = <Map<String, dynamic>>[];

      queryHandler = (request) async {
        switch (request['@type']) {
          case 'getMessageProperties':
            return <String, dynamic>{
              '@type': 'messageProperties',
              'can_get_message_thread': true,
              'can_be_replied': true,
            };
          case 'getMessageThread':
            return <String, dynamic>{
              '@type': 'messageThreadInfo',
              'chat_id': -2002,
              'message_thread_id': 99,
            };
          case 'getChat':
            final id = request['chat_id'] as int;
            return <String, dynamic>{
              '@type': 'chat',
              'id': id,
              'title': id == -2002 ? 'Discussion Group' : 'News Channel',
              'permissions': {'can_send_basic_messages': true},
            };
          case 'getUser':
            final id = request['user_id'] as int;
            return <String, dynamic>{
              '@type': 'user',
              'id': id,
              'first_name': id == 11 ? 'Alice' : 'Bob',
              'last_name': '',
            };
          case 'getMessageThreadHistory':
            return <String, dynamic>{
              '@type': 'messages',
              'messages': [
                <String, dynamic>{
                  '@type': 'message',
                  'id': 300,
                  'chat_id': -2002,
                  'is_outgoing': false,
                  'date': 30,
                  'sender_id': {'@type': 'messageSenderUser', 'user_id': 11},
                  'reply_to': {
                    '@type': 'messageReplyToMessage',
                    'chat_id': -2002,
                    'message_id': 200,
                  },
                  'content': {
                    '@type': 'messageText',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'Reply to an older comment',
                      'entities': <Map<String, dynamic>>[],
                    },
                  },
                },
              ],
            };
          case 'getMessages':
            getMessagesRequests.add(Map<String, dynamic>.from(request));
            return <String, dynamic>{
              '@type': 'messages',
              'messages': [
                <String, dynamic>{
                  '@type': 'message',
                  'id': 200,
                  'chat_id': -2002,
                  'is_outgoing': false,
                  'date': 20,
                  'sender_id': {'@type': 'messageSenderUser', 'user_id': 22},
                  'content': {
                    '@type': 'messageText',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'Older parent comment',
                      'entities': <Map<String, dynamic>>[],
                    },
                  },
                },
              ],
            };
          default:
            return <String, dynamic>{'@type': 'ok'};
        }
      };

      MessageRepliesViewTarget? viewedInChat;
      int? openedInSourceChat;

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(extensions: [AppColors.light]),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showMessageRepliesSheet(
                      context: context,
                      chatId: -1001,
                      message: ChatMessage(
                        id: 42,
                        isOutgoing: false,
                        text: 'Channel post',
                        date: 10,
                        chatId: -1001,
                        commentCount: 2,
                        hasCommentThread: true,
                      ),
                      peerTitle: 'News Channel',
                      onOpenReply: (id) => openedInSourceChat = id,
                      onViewInChat: (target) => viewedInChat = target,
                    );
                  },
                  child: const Text('Open comments'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open comments'));
      await tester.pumpAndSettle();

      expect(getMessagesRequests, hasLength(1));
      expect(getMessagesRequests.single['chat_id'], -2002);
      expect(getMessagesRequests.single['message_ids'], [200]);
      expect(find.byKey(const ValueKey('messageReplyQuote')), findsOneWidget);
      expect(
        find.text('Older parent comment', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Bob', findRichText: true), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('messageReplyOpenOriginal')));
      await tester.pumpAndSettle();

      expect(openedInSourceChat, isNull);
      expect(viewedInChat, isNotNull);
      expect(viewedInChat!.chatId, -2002);
      expect(viewedInChat!.messageId, 200);
      expect(viewedInChat!.title, 'Discussion Group');
    },
  );

  testWidgets(
    'ChannelPostDetailView resolves parent sender anchor when parent comment is outside the thread window',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);

      queryHandler = (request) async {
        switch (request['@type']) {
          case 'getMe':
            return <String, dynamic>{
              '@type': 'user',
              'id': 1,
              'first_name': 'Me',
              'last_name': '',
            };
          case 'getUser':
            final id = request['user_id'] as int;
            return <String, dynamic>{
              '@type': 'user',
              'id': id,
              'first_name': id == 11 ? 'Alice' : 'Bob',
              'last_name': '',
            };
          case 'getMessageThreadHistory':
            return <String, dynamic>{
              '@type': 'messages',
              'messages': [
                <String, dynamic>{
                  '@type': 'message',
                  'id': 300,
                  'chat_id': 99,
                  'is_outgoing': false,
                  'date': 30,
                  'sender_id': {'@type': 'messageSenderUser', 'user_id': 11},
                  'reply_to': {
                    '@type': 'messageReplyToMessage',
                    'chat_id': 99,
                    'message_id': 200,
                  },
                  'content': {
                    '@type': 'messageText',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'Child comment body',
                      'entities': <Map<String, dynamic>>[],
                    },
                  },
                },
              ],
            };
          case 'getMessages':
            return <String, dynamic>{
              '@type': 'messages',
              'messages': [
                <String, dynamic>{
                  '@type': 'message',
                  'id': 200,
                  'chat_id': 99,
                  'is_outgoing': false,
                  'date': 20,
                  'sender_id': {'@type': 'messageSenderUser', 'user_id': 22},
                  'content': {
                    '@type': 'messageText',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'Parent comment body',
                      'entities': <Map<String, dynamic>>[],
                    },
                  },
                },
              ],
            };
          case 'getMessageAvailableReactions':
            return <String, dynamic>{
              '@type': 'availableReactions',
              'top_reactions': <Map<String, dynamic>>[],
              'recent_reactions': <Map<String, dynamic>>[],
              'popular_reactions': <Map<String, dynamic>>[],
              'allow_custom_emoji': false,
              'are_tags': false,
            };
          default:
            return <String, dynamic>{'@type': 'ok'};
        }
      };

      final channel = ChatSummary(
        id: 42,
        title: 'Channel',
        lastMessage: '',
        lastMessageId: 7,
        date: 1,
        unreadCount: 0,
        order: 1,
        isMuted: false,
        kind: ChatKind.channel,
      );
      final post = ChannelPost(
        channel: channel,
        message: ChatMessage(
          id: 7,
          isOutgoing: false,
          text: 'Moment post',
          date: 1,
          contentType: 'messageText',
          hasCommentThread: true,
        ),
        accountSlot: 4,
        threadTarget: const ChannelPostThreadTarget(
          chatId: 99,
          messageThreadId: 500,
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(extensions: [AppColors.light]),
            home: ChannelPostDetailView(post: post, showBackButton: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Bob', findRichText: true), findsOneWidget);
      expect(
        find.text('Child comment body', findRichText: true),
        findsOneWidget,
      );
    },
  );

  test(
    'mergeChatMessages drops stale reply metadata when reply target is cleared or changed',
    () {
      final existing =
          ChatMessage(
              id: 301,
              isOutgoing: false,
              text: 'Comment reply',
              date: 10,
              replyToMessageId: 201,
              replyToChatId: -2002,
              replyToDate: 5,
              replyToEntities: const [
                MessageTextEntity(
                  offset: 0,
                  length: 3,
                  type: 'textEntityTypeBold',
                ),
              ],
            )
            ..replyToSender = 'Bob'
            ..replyToPreview = 'Old parent comment';

      final cleared = ChatMessage(
        id: 301,
        isOutgoing: false,
        text: 'Comment reply',
        date: 10,
      );
      final afterClear = mergeChatMessages([existing], [cleared]).single;
      expect(afterClear.replyToSender, isNull);
      expect(afterClear.replyToPreview, isNull);
      expect(afterClear.replyToDate, isNull);
      expect(afterClear.replyToEntities, isEmpty);

      final changedChat = ChatMessage(
        id: 301,
        isOutgoing: false,
        text: 'Comment reply',
        date: 10,
        replyToMessageId: 201,
        replyToChatId: -3003,
      );
      final afterChangedChat = mergeChatMessages(
        [existing],
        [changedChat],
      ).single;
      expect(afterChangedChat.replyToSender, isNull);
      expect(afterChangedChat.replyToPreview, isNull);
    },
  );

  test(
    'ChatViewModel bumps materialized message revision when async reply quote and sender resolve',
    () async {
      final getMessagesCompleter = Completer<Map<String, dynamic>>();
      final getUserCompleter = Completer<Map<String, dynamic>>();
      queryHandler = (request) async {
        switch (request['@type']) {
          case 'getChatHistory':
            return <String, dynamic>{
              '@type': 'messages',
              'messages': [
                <String, dynamic>{
                  '@type': 'message',
                  'id': 501,
                  'chat_id': -2002,
                  'is_outgoing': false,
                  'date': 20,
                  'sender_id': {'@type': 'messageSenderUser', 'user_id': 7},
                  'reply_to': {
                    '@type': 'messageReplyToMessage',
                    'chat_id': -1001,
                    'message_id': 42,
                  },
                  'content': {
                    '@type': 'messageText',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'Commenting on the channel post',
                      'entities': <Map<String, dynamic>>[],
                    },
                  },
                },
              ],
            };
          case 'getMessages':
            return getMessagesCompleter.future;
          case 'getUser':
            if (request['user_id'] == 99) return getUserCompleter.future;
            return <String, dynamic>{
              '@type': 'user',
              'id': request['user_id'],
              'first_name': 'Alice',
              'last_name': '',
            };
          default:
            return <String, dynamic>{'@type': 'ok'};
        }
      };

      final vm = ChatViewModel(
        chatId: -2002,
        title: 'Discussion Group',
        markReadOnOpen: true,
      );
      addTearDown(vm.dispose);
      vm.onAppear();
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Materialize the per-message revision listenable while the reply target
      // lookup is still in flight (as ChatView's ValueListenableBuilder does).
      final revision = vm.messageRevisionListenable(501);
      final initialRevision = revision.value;
      expect(vm.messages.single.replyToPreview, isNull);

      getMessagesCompleter.complete(<String, dynamic>{
        '@type': 'messages',
        'messages': [
          <String, dynamic>{
            '@type': 'message',
            'id': 42,
            'chat_id': -1001,
            'is_outgoing': false,
            'date': 10,
            'sender_id': {'@type': 'messageSenderUser', 'user_id': 99},
            'content': {
              '@type': 'messageText',
              'text': {
                '@type': 'formattedText',
                'text': 'Channel post anchor',
                'entities': <Map<String, dynamic>>[],
              },
            },
          },
        ],
      });
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final afterQuoteRevision = revision.value;
      expect(vm.messages.single.replyToPreview, 'Channel post anchor');
      expect(afterQuoteRevision, greaterThan(initialRevision));

      getUserCompleter.complete(<String, dynamic>{
        '@type': 'user',
        'id': 99,
        'first_name': 'QuotedAuthor',
        'last_name': '',
      });
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(vm.messages.single.replyToSender, 'QuotedAuthor');
      expect(revision.value, greaterThan(afterQuoteRevision));
    },
  );

  testWidgets(
    'reply sheet disambiguates cross-chat reply targets with colliding message IDs and opens the target chat',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);

      final getMessagesRequests = <Map<String, dynamic>>[];
      queryHandler = (request) async {
        switch (request['@type']) {
          case 'getMessageProperties':
            return <String, dynamic>{
              '@type': 'messageProperties',
              'can_get_message_thread': true,
              'can_be_replied': true,
            };
          case 'getMessageThread':
            return <String, dynamic>{
              '@type': 'messageThreadInfo',
              'chat_id': -2002,
              'message_thread_id': 99,
            };
          case 'getChat':
            final id = request['chat_id'] as int;
            return <String, dynamic>{
              '@type': 'chat',
              'id': id,
              'title': switch (id) {
                -2002 => 'Discussion Group',
                -3003 => 'External Channel',
                _ => 'News Channel',
              },
              'permissions': {'can_send_basic_messages': true},
            };
          case 'getUser':
            final id = request['user_id'] as int;
            return <String, dynamic>{
              '@type': 'user',
              'id': id,
              'first_name': switch (id) {
                11 => 'Alice',
                22 => 'LocalBob',
                33 => 'ExternalCarol',
                _ => 'User',
              },
              'last_name': '',
            };
          case 'getMessageThreadHistory':
            return <String, dynamic>{
              '@type': 'messages',
              'messages': [
                // In-sheet comment with id 200 in the discussion chat (-2002)
                <String, dynamic>{
                  '@type': 'message',
                  'id': 200,
                  'chat_id': -2002,
                  'is_outgoing': false,
                  'date': 20,
                  'sender_id': {'@type': 'messageSenderUser', 'user_id': 22},
                  'content': {
                    '@type': 'messageText',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'In-sheet discussion comment 200',
                      'entities': <Map<String, dynamic>>[],
                    },
                  },
                },
                // Comment 300 replying to message 200 in a DIFFERENT chat (-3003)
                <String, dynamic>{
                  '@type': 'message',
                  'id': 300,
                  'chat_id': -2002,
                  'is_outgoing': false,
                  'date': 30,
                  'sender_id': {'@type': 'messageSenderUser', 'user_id': 11},
                  'reply_to': {
                    '@type': 'messageReplyToMessage',
                    'chat_id': -3003,
                    'message_id': 200,
                  },
                  'content': {
                    '@type': 'messageText',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'Reply to external message 200',
                      'entities': <Map<String, dynamic>>[],
                    },
                  },
                },
              ],
            };
          case 'getMessages':
            getMessagesRequests.add(Map<String, dynamic>.from(request));
            return <String, dynamic>{
              '@type': 'messages',
              'messages': [
                <String, dynamic>{
                  '@type': 'message',
                  'id': 200,
                  'chat_id': -3003,
                  'is_outgoing': false,
                  'date': 15,
                  'sender_id': {'@type': 'messageSenderUser', 'user_id': 33},
                  'content': {
                    '@type': 'messageText',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'External channel message 200',
                      'entities': <Map<String, dynamic>>[],
                    },
                  },
                },
              ],
            };
          default:
            return <String, dynamic>{'@type': 'ok'};
        }
      };

      MessageRepliesViewTarget? viewedInChat;
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(extensions: [AppColors.light]),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showMessageRepliesSheet(
                      context: context,
                      chatId: -1001,
                      message: ChatMessage(
                        id: 42,
                        isOutgoing: false,
                        text: 'Channel post',
                        date: 10,
                        chatId: -1001,
                        commentCount: 2,
                        hasCommentThread: true,
                      ),
                      peerTitle: 'News Channel',
                      onViewInChat: (target) => viewedInChat = target,
                    );
                  },
                  child: const Text('Open comments'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open comments'));
      await tester.pumpAndSettle();

      // Must fetch (-3003, 200) via getMessages rather than reusing (-2002, 200).
      expect(getMessagesRequests, hasLength(1));
      expect(getMessagesRequests.single['chat_id'], -3003);
      expect(getMessagesRequests.single['message_ids'], [200]);
      expect(
        find.text('External channel message 200', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('ExternalCarol', findRichText: true),
        findsOneWidget,
      );

      // Tapping the quote opens chat -3003 ('External Channel'), not the
      // in-sheet comment or the discussion group -2002.
      await tester.tap(find.byKey(const ValueKey('messageReplyOpenOriginal')));
      await tester.pumpAndSettle();

      expect(viewedInChat, isNotNull);
      expect(viewedInChat!.chatId, -3003);
      expect(viewedInChat!.messageId, 200);
      expect(viewedInChat!.title, 'External Channel');
    },
  );

  testWidgets(
    'ChannelPostDetailView keys reply targets by (chatId, messageId) when IDs collide across chats',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);

      final getMessagesRequests = <Map<String, dynamic>>[];
      queryHandler = (request) async {
        switch (request['@type']) {
          case 'getMe':
            return <String, dynamic>{
              '@type': 'user',
              'id': 1,
              'first_name': 'Me',
              'last_name': '',
            };
          case 'getUser':
            final id = request['user_id'] as int;
            return <String, dynamic>{
              '@type': 'user',
              'id': id,
              'first_name': switch (id) {
                11 => 'Alice',
                22 => 'LocalBob',
                33 => 'ExternalCarol',
                _ => 'User',
              },
              'last_name': '',
            };
          case 'getMessageThreadHistory':
            return <String, dynamic>{
              '@type': 'messages',
              'messages': [
                // In-thread comment 200 in discussion chat 99
                <String, dynamic>{
                  '@type': 'message',
                  'id': 200,
                  'chat_id': 99,
                  'is_outgoing': false,
                  'date': 20,
                  'sender_id': {'@type': 'messageSenderUser', 'user_id': 22},
                  'content': {
                    '@type': 'messageText',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'In-thread comment 200',
                      'entities': <Map<String, dynamic>>[],
                    },
                  },
                },
                // Comment 300 in discussion chat 99 replying to external message
                // (chat 777, message 200) which shares id 200
                <String, dynamic>{
                  '@type': 'message',
                  'id': 300,
                  'chat_id': 99,
                  'is_outgoing': false,
                  'date': 30,
                  'sender_id': {'@type': 'messageSenderUser', 'user_id': 11},
                  'reply_to': {
                    '@type': 'messageReplyToMessage',
                    'chat_id': 777,
                    'message_id': 200,
                  },
                  'content': {
                    '@type': 'messageText',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'Reply to external message 200',
                      'entities': <Map<String, dynamic>>[],
                    },
                  },
                },
              ],
            };
          case 'getMessages':
            getMessagesRequests.add(Map<String, dynamic>.from(request));
            return <String, dynamic>{
              '@type': 'messages',
              'messages': [
                <String, dynamic>{
                  '@type': 'message',
                  'id': 200,
                  'chat_id': 777,
                  'is_outgoing': false,
                  'date': 15,
                  'sender_id': {'@type': 'messageSenderUser', 'user_id': 33},
                  'content': {
                    '@type': 'messageText',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'External message 200',
                      'entities': <Map<String, dynamic>>[],
                    },
                  },
                },
              ],
            };
          case 'getMessageAvailableReactions':
            return <String, dynamic>{
              '@type': 'availableReactions',
              'top_reactions': <Map<String, dynamic>>[],
              'recent_reactions': <Map<String, dynamic>>[],
              'popular_reactions': <Map<String, dynamic>>[],
              'allow_custom_emoji': false,
              'are_tags': false,
            };
          default:
            return <String, dynamic>{'@type': 'ok'};
        }
      };

      final channel = ChatSummary(
        id: 42,
        title: 'Channel',
        lastMessage: '',
        lastMessageId: 7,
        date: 1,
        unreadCount: 0,
        order: 1,
        isMuted: false,
        kind: ChatKind.channel,
      );
      final post = ChannelPost(
        channel: channel,
        message: ChatMessage(
          id: 7,
          isOutgoing: false,
          text: 'Moment post',
          date: 1,
          contentType: 'messageText',
          hasCommentThread: true,
        ),
        accountSlot: 4,
        threadTarget: const ChannelPostThreadTarget(
          chatId: 99,
          messageThreadId: 500,
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(extensions: [AppColors.light]),
            home: ChannelPostDetailView(post: post, showBackButton: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(getMessagesRequests, hasLength(1));
      expect(getMessagesRequests.single['chat_id'], 777);
      expect(getMessagesRequests.single['message_ids'], [200]);
      expect(
        find.textContaining('ExternalCarol', findRichText: true),
        findsOneWidget,
      );
    },
  );

  test(
    'ChatViewModel drops a held reply lookup once the reply retargets to another chat with the same message id',
    () async {
      final heldResponses = <int, Future<Map<String, dynamic>>>{};
      final heldChatIds = <int>[];
      queryHandler = (request) async {
        switch (request['@type']) {
          case 'getChatHistory':
            return <String, dynamic>{
              '@type': 'messages',
              'messages': [
                <String, dynamic>{
                  '@type': 'message',
                  'id': 501,
                  'chat_id': -2002,
                  'is_outgoing': false,
                  'date': 20,
                  'sender_id': {'@type': 'messageSenderUser', 'user_id': 7},
                  'reply_to': {
                    '@type': 'messageReplyToMessage',
                    'chat_id': -1001,
                    'message_id': 42,
                  },
                  'content': {
                    '@type': 'messageText',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'Commenting on the channel post',
                      'entities': <Map<String, dynamic>>[],
                    },
                  },
                },
              ],
            };
          case 'getMessages':
            final chatId = request['chat_id'] as int;
            heldChatIds.add(chatId);
            return heldResponses[chatId]!;
          default:
            return <String, dynamic>{'@type': 'ok'};
        }
      };

      // Hold the lookup for chat A / message 42.
      final heldForChannel = Completer<Map<String, dynamic>>();
      heldResponses[-1001] = heldForChannel.future;
      final vm = ChatViewModel(
        chatId: -2002,
        title: 'Discussion Group',
        markReadOnOpen: true,
      );
      addTearDown(vm.dispose);
      vm.onAppear();
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(heldChatIds, contains(-1001));
      expect(vm.messages.single.replyToPreview, isNull);

      // The reply refreshes pointing at chat B / message 42 — same numeric id,
      // different chat. Its own lookup is held too, so both responses arrive
      // out of order.
      final refreshed = ChatMessage(
        id: 501,
        isOutgoing: false,
        text: 'Commenting on the other channel post',
        date: 21,
        chatId: -2002,
        replyToMessageId: 42,
        replyToChatId: -3003,
      );
      final heldForOther = Completer<Map<String, dynamic>>();
      heldResponses[-3003] = heldForOther.future;
      vm.mergeMessageForTesting(refreshed);
      vm.applyLiveUpdateForTesting(<String, dynamic>{
        '@type': 'updateNewMessage',
        'message': <String, dynamic>{
          '@type': 'message',
          'id': 501,
          'chat_id': -2002,
          'is_outgoing': false,
          'date': 21,
          'sender_id': {'@type': 'messageSenderUser', 'user_id': 7},
          'reply_to': {
            '@type': 'messageReplyToMessage',
            'chat_id': -3003,
            'message_id': 42,
          },
          'content': {
            '@type': 'messageText',
            'text': {
              '@type': 'formattedText',
              'text': 'Commenting on the other channel post',
              'entities': <Map<String, dynamic>>[],
            },
          },
        },
      });
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(heldChatIds, contains(-3003));

      // Now complete the STALE lookup for chat A.
      heldForChannel.complete(<String, dynamic>{
        '@type': 'messages',
        'messages': [
          <String, dynamic>{
            '@type': 'message',
            'id': 42,
            'chat_id': -1001,
            'is_outgoing': false,
            'date': 10,
            'sender_id': {'@type': 'messageSenderUser', 'user_id': 99},
            'content': {
              '@type': 'messageText',
              'text': {
                '@type': 'formattedText',
                'text': 'Channel A anchor',
                'entities': <Map<String, dynamic>>[],
              },
            },
          },
        ],
      });
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(vm.messages.single.replyToPreview, isNull);

      heldForOther.complete(<String, dynamic>{
        '@type': 'messages',
        'messages': [
          <String, dynamic>{
            '@type': 'message',
            'id': 42,
            'chat_id': -3003,
            'is_outgoing': false,
            'date': 12,
            'sender_id': {'@type': 'messageSenderUser', 'user_id': 33},
            'content': {
              '@type': 'messageText',
              'text': {
                '@type': 'formattedText',
                'text': 'Channel B anchor',
                'entities': <Map<String, dynamic>>[],
              },
            },
          },
        ],
      });
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(vm.messages.single.replyToPreview, 'Channel B anchor');
    },
  );

  test(
    'ChatViewModel never rehydrates a restriction-redacted reply from plaintext or a redacted quote',
    () async {
      final heldResponses = <int, Future<Map<String, dynamic>>>{};
      final heldChatIds = <int>[];
      queryHandler = (request) async {
        switch (request['@type']) {
          case 'getChatHistory':
            return <String, dynamic>{
              '@type': 'messages',
              'messages': [
                <String, dynamic>{
                  '@type': 'message',
                  'id': 501,
                  'chat_id': -2002,
                  'is_outgoing': false,
                  'date': 20,
                  'sender_id': {'@type': 'messageSenderUser', 'user_id': 7},
                  'reply_to': {
                    '@type': 'messageReplyToMessage',
                    'chat_id': -1001,
                    'message_id': 42,
                  },
                  'content': {
                    '@type': 'messageText',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'Commenting on the channel post',
                      'entities': <Map<String, dynamic>>[],
                    },
                  },
                },
              ],
            };
          case 'getMessages':
            final chatId = request['chat_id'] as int;
            heldChatIds.add(chatId);
            return heldResponses[chatId]!;
          default:
            return <String, dynamic>{'@type': 'ok'};
        }
      };

      final heldForChannel = Completer<Map<String, dynamic>>();
      heldResponses[-1001] = heldForChannel.future;
      final vm = ChatViewModel(
        chatId: -2002,
        title: 'Discussion Group',
        markReadOnOpen: true,
      );
      addTearDown(vm.dispose);
      vm.onAppear();
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(heldChatIds, contains(-1001));

      // A restriction-redacted refresh of the same reply arrives first: it
      // withdraws the quote entirely.
      vm.mergeMessageForTesting(
        ChatMessage(
          id: 501,
          isOutgoing: false,
          text: 'Commenting on the channel post',
          date: 21,
          chatId: -2002,
          restrictionReason: 'pornography',
        ),
      );
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(vm.messages.single.isContentRestricted, isTrue);
      expect(vm.messages.single.replyToMessageId, isNull);

      // The held response lands after the restriction: no cached plaintext may
      // be rehydrated onto the redacted message.
      heldForChannel.complete(<String, dynamic>{
        '@type': 'messages',
        'messages': [
          <String, dynamic>{
            '@type': 'message',
            'id': 42,
            'chat_id': -1001,
            'is_outgoing': false,
            'date': 10,
            'sender_id': {'@type': 'messageSenderUser', 'user_id': 99},
            'content': {
              '@type': 'messageText',
              'text': {
                '@type': 'formattedText',
                'text': 'Channel post anchor',
                'entities': <Map<String, dynamic>>[],
              },
            },
          },
        ],
      });
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(vm.messages.single.replyToPreview, isNull);
      expect(vm.messages.single.replyToSender, isNull);
      expect(vm.messages.single.replyToDate, isNull);

      // And a redacted RESPONSE is a withdrawal, not an anchor: a fresh reply
      // waiting on the same (chat, message) must stay unquoted.
      final heldForRedacted = Completer<Map<String, dynamic>>();
      heldResponses[-4004] = heldForRedacted.future;
      vm.historyReachesLatestForTesting();
      vm.applyLiveUpdateForTesting(<String, dynamic>{
        '@type': 'updateNewMessage',
        'message': <String, dynamic>{
          '@type': 'message',
          'id': 502,
          'chat_id': -2002,
          'is_outgoing': false,
          'date': 22,
          'sender_id': {'@type': 'messageSenderUser', 'user_id': 7},
          'reply_to': {
            '@type': 'messageReplyToMessage',
            'chat_id': -4004,
            'message_id': 9,
          },
          'content': {
            '@type': 'messageText',
            'text': {
              '@type': 'formattedText',
              'text': 'Reply to a redacted parent',
              'entities': <Map<String, dynamic>>[],
            },
          },
        },
      });
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(heldChatIds, contains(-4004));
      heldForRedacted.complete(<String, dynamic>{
        '@type': 'messages',
        'messages': [
          <String, dynamic>{
            '@type': 'message',
            'id': 9,
            'chat_id': -4004,
            'is_outgoing': false,
            'date': 11,
            'restriction_info': {'restriction_reason': 'pornography'},
            'content': {
              '@type': 'messageText',
              'text': {
                '@type': 'formattedText',
                'text': 'Redacted parent text',
                'entities': <Map<String, dynamic>>[],
              },
            },
          },
        ],
      });
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final quoted = vm.messages.firstWhere((message) => message.id == 502);
      expect(quoted.replyToPreview, isNull);
      expect(quoted.replyToSender, isNull);
    },
  );

  testWidgets(
    'reply sheet keeps a discussion comment whose id collides with the channel post id',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);

      final comments = <Map<String, dynamic>>[
        <String, dynamic>{
          '@type': 'message',
          'id': 42,
          'chat_id': -2002,
          'is_outgoing': false,
          'date': 21,
          'sender_id': {'@type': 'messageSenderUser', 'user_id': 11},
          'content': {
            '@type': 'messageText',
            'text': {
              '@type': 'formattedText',
              'text': 'Discussion comment sharing the post id',
              'entities': <Map<String, dynamic>>[],
            },
          },
        },
        <String, dynamic>{
          '@type': 'message',
          'id': 300,
          'chat_id': -2002,
          'is_outgoing': false,
          'date': 30,
          'sender_id': {'@type': 'messageSenderUser', 'user_id': 12},
          'content': {
            '@type': 'messageText',
            'text': {
              '@type': 'formattedText',
              'text': 'Second discussion comment',
              'entities': <Map<String, dynamic>>[],
            },
          },
        },
      ];
      queryHandler = (request) async {
        switch (request['@type']) {
          case 'getMessageProperties':
            return <String, dynamic>{
              '@type': 'messageProperties',
              'can_get_message_thread': true,
              'can_be_replied': true,
            };
          case 'getMessageThread':
            return <String, dynamic>{
              '@type': 'messageThreadInfo',
              'chat_id': -2002,
              'message_thread_id': 99,
            };
          case 'getChat':
            final id = request['chat_id'] as int;
            return <String, dynamic>{
              '@type': 'chat',
              'id': id,
              'title': id == -2002 ? 'Discussion Group' : 'News Channel',
              'permissions': {'can_send_basic_messages': true},
            };
          case 'getUser':
            final id = request['user_id'] as int;
            return <String, dynamic>{
              '@type': 'user',
              'id': id,
              'first_name': 'User $id',
              'last_name': '',
            };
          case 'getMessageThreadHistory':
            return <String, dynamic>{'@type': 'messages', 'messages': comments};
          default:
            return <String, dynamic>{'@type': 'ok'};
        }
      };

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(extensions: [AppColors.light]),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showMessageRepliesSheet(
                      context: context,
                      chatId: -1001,
                      message: ChatMessage(
                        id: 42,
                        isOutgoing: false,
                        text: 'Channel post',
                        date: 10,
                        chatId: -1001,
                        commentCount: 2,
                        hasCommentThread: true,
                      ),
                      peerTitle: 'News Channel',
                      onViewInChat: (_) {},
                    );
                  },
                  child: const Text('Open comments'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open comments'));
      await tester.pumpAndSettle();

      // Both comments render: the (-2002, 42) comment is NOT the (-1001, 42)
      // channel root, even though the ids match.
      expect(find.byType(MessageBubble), findsNWidgets(2));
      expect(
        find.text('Discussion comment sharing the post id', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text('Second discussion comment', findRichText: true),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'reply sheet jump materializes a parent comment below long variable-height rows',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);

      // 100 discussion comments; comments 1..10 carry 100 lines each, so the
      // target (50) sits far below ~1750px of text and above a comment 100
      // that replies to it. A proportional jump cannot land on it.
      const tallRowMessageCount = 10;
      const commentCount = 100;
      const targetMessageId = 40050;
      const bottomMessageId = 40100;
      final longText = List.generate(
        100,
        (i) => 'Line $i of a long comment',
      ).join('\n');
      final comments = <Map<String, dynamic>>[
        for (var i = 1; i <= commentCount; i++)
          <String, dynamic>{
            '@type': 'message',
            'id': 40000 + i,
            'chat_id': -2002,
            'is_outgoing': false,
            'date': i,
            'sender_id': {'@type': 'messageSenderUser', 'user_id': 11},
            if (i == commentCount)
              'reply_to': {
                '@type': 'messageReplyToMessage',
                'chat_id': -2002,
                'message_id': targetMessageId,
              },
            'content': {
              '@type': 'messageText',
              'text': {
                '@type': 'formattedText',
                'text': i <= tallRowMessageCount ? longText : 'Comment $i',
                'entities': <Map<String, dynamic>>[],
              },
            },
          },
      ];
      queryHandler = (request) async {
        switch (request['@type']) {
          case 'getMessageProperties':
            return <String, dynamic>{
              '@type': 'messageProperties',
              'can_get_message_thread': true,
              'can_be_replied': true,
            };
          case 'getMessageThread':
            return <String, dynamic>{
              '@type': 'messageThreadInfo',
              'chat_id': -2002,
              'message_thread_id': 99,
            };
          case 'getChat':
            final id = request['chat_id'] as int;
            return <String, dynamic>{
              '@type': 'chat',
              'id': id,
              'title': id == -2002 ? 'Discussion Group' : 'News Channel',
              'permissions': {'can_send_basic_messages': true},
            };
          case 'getUser':
            final id = request['user_id'] as int;
            return <String, dynamic>{
              '@type': 'user',
              'id': id,
              'first_name': 'User $id',
              'last_name': '',
            };
          case 'getMessageThreadHistory':
            return <String, dynamic>{'@type': 'messages', 'messages': comments};
          case 'getMessages':
            return <String, dynamic>{
              '@type': 'messages',
              'messages': [
                <String, dynamic>{
                  '@type': 'message',
                  'id': targetMessageId,
                  'chat_id': -2002,
                  'is_outgoing': false,
                  'date': 50,
                  'sender_id': {'@type': 'messageSenderUser', 'user_id': 22},
                  'content': {
                    '@type': 'messageText',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'Parent comment 50',
                      'entities': <Map<String, dynamic>>[],
                    },
                  },
                },
              ],
            };
          default:
            return <String, dynamic>{'@type': 'ok'};
        }
      };

      MessageRepliesViewTarget? viewedInChat;
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(extensions: [AppColors.light]),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showMessageRepliesSheet(
                      context: context,
                      chatId: -1001,
                      message: ChatMessage(
                        id: 42,
                        isOutgoing: false,
                        text: 'Channel post',
                        date: 10,
                        chatId: -1001,
                        commentCount: commentCount,
                        hasCommentThread: true,
                      ),
                      peerTitle: 'News Channel',
                      onViewInChat: (target) => viewedInChat = target,
                    );
                  },
                  child: const Text('Open comments'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open comments'));
      await tester.pumpAndSettle();

      // Rows lazily built: only the top of the sheet exists so far.
      expect(find.byType(MessageBubble), findsWidgets);
      expect(
        find.byKey(
          const ValueKey('messageRepliesSheetMessage-$targetMessageId'),
        ),
        findsNothing,
      );

      // The user scrolls to the bottom first; the bottom row quotes comment 50.
      final sheetScrollable = find.byType(Scrollable).first;
      final sheetPosition = tester
          .state<ScrollableState>(sheetScrollable)
          .position;
      final bottomRow = find.byKey(
        const ValueKey('messageRepliesSheetMessage-$bottomMessageId'),
      );
      for (var i = 0; i < 60 && bottomRow.evaluate().isEmpty; i++) {
        sheetPosition.jumpTo(sheetPosition.maxScrollExtent);
        await tester.pump();
      }
      expect(bottomRow, findsOneWidget);

      // Tap comment 100's quote → the in-sheet jump to comment 50.
      await tester.tap(find.byKey(const ValueKey('messageReplyOpenOriginal')));
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // The jump only succeeded if the target row is materialized AND visible
      // in the viewport.
      final targetFinder = find.byKey(
        const ValueKey('messageRepliesSheetMessage-$targetMessageId'),
      );
      expect(targetFinder, findsOneWidget);
      final sheetBox = tester.getRect(sheetScrollable);
      final targetRect = tester.getRect(targetFinder);
      expect(
        targetRect.bottom > sheetBox.top && targetRect.top < sheetBox.bottom,
        isTrue,
        reason: 'parent comment 50 must be visible after the jump',
      );
      expect(viewedInChat, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the in-sheet jump reaches a parent under phone-width strongly non-uniform rows',
    (tester) async {
      // The reviewer's distribution at a real phone size: a 390x844 sheet, 100
      // discussion comments, and comments 1..10 each carrying 100 lines of
      // long, wrapping text — roughly 4,000 logical pixels per tall row, so
      // the parent of comment 100 sits ~45,000 pixels above it and no
      // proportional offset can land on it.
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);

      const tallRowMessageCount = 10;
      const commentCount = 100;
      const targetMessageId = 40050;
      const bottomMessageId = 40100;
      final longText = List.generate(
        100,
        (i) =>
            'Line $i of a long comment that wraps over several visual '
            'lines in a phone-width sheet, which is what makes the row '
            'height impossible to guess.',
      ).join('\n');
      final comments = <Map<String, dynamic>>[
        for (var i = 1; i <= commentCount; i++)
          <String, dynamic>{
            '@type': 'message',
            'id': 40000 + i,
            'chat_id': -2002,
            'is_outgoing': false,
            'date': i,
            'sender_id': {'@type': 'messageSenderUser', 'user_id': 11},
            if (i == commentCount)
              'reply_to': {
                '@type': 'messageReplyToMessage',
                'chat_id': -2002,
                'message_id': targetMessageId,
              },
            'content': {
              '@type': 'messageText',
              'text': {
                '@type': 'formattedText',
                'text': i <= tallRowMessageCount ? longText : 'Comment $i',
                'entities': <Map<String, dynamic>>[],
              },
            },
          },
      ];
      queryHandler = (request) async {
        switch (request['@type']) {
          case 'getMessageProperties':
            return <String, dynamic>{
              '@type': 'messageProperties',
              'can_get_message_thread': true,
              'can_be_replied': true,
            };
          case 'getMessageThread':
            return <String, dynamic>{
              '@type': 'messageThreadInfo',
              'chat_id': -2002,
              'message_thread_id': 99,
            };
          case 'getChat':
            final id = request['chat_id'] as int;
            return <String, dynamic>{
              '@type': 'chat',
              'id': id,
              'title': id == -2002 ? 'Discussion Group' : 'News Channel',
              'permissions': {'can_send_basic_messages': true},
            };
          case 'getUser':
            final id = request['user_id'] as int;
            return <String, dynamic>{
              '@type': 'user',
              'id': id,
              'first_name': 'User $id',
              'last_name': '',
            };
          case 'getMessageThreadHistory':
            return <String, dynamic>{'@type': 'messages', 'messages': comments};
          case 'getMessages':
            return <String, dynamic>{
              '@type': 'messages',
              'messages': [
                <String, dynamic>{
                  '@type': 'message',
                  'id': targetMessageId,
                  'chat_id': -2002,
                  'is_outgoing': false,
                  'date': 50,
                  'sender_id': {'@type': 'messageSenderUser', 'user_id': 22},
                  'content': {
                    '@type': 'messageText',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'Parent comment 50',
                      'entities': <Map<String, dynamic>>[],
                    },
                  },
                },
              ],
            };
          default:
            return <String, dynamic>{'@type': 'ok'};
        }
      };

      MessageRepliesViewTarget? viewedInChat;
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(extensions: [AppColors.light]),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showMessageRepliesSheet(
                      context: context,
                      chatId: -1001,
                      message: ChatMessage(
                        id: 42,
                        isOutgoing: false,
                        text: 'Channel post',
                        date: 10,
                        chatId: -1001,
                        commentCount: commentCount,
                        hasCommentThread: true,
                      ),
                      peerTitle: 'News Channel',
                      onViewInChat: (target) => viewedInChat = target,
                    );
                  },
                  child: const Text('Open comments'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open comments'));
      await tester.pumpAndSettle();

      final sheetScrollable = find.byType(Scrollable).first;
      final sheetPosition = tester
          .state<ScrollableState>(sheetScrollable)
          .position;

      // Scroll to the bottom the way a reader would, letting the sliver
      // refine its extent estimate as the late rows materialize.
      final bottomRow = find.byKey(
        const ValueKey('messageRepliesSheetMessage-$bottomMessageId'),
      );
      for (var i = 0; i < 200 && bottomRow.evaluate().isEmpty; i++) {
        sheetPosition.jumpTo(sheetPosition.maxScrollExtent);
        await tester.pump();
      }
      expect(bottomRow, findsOneWidget);
      final targetFinder = find.byKey(
        const ValueKey('messageRepliesSheetMessage-$targetMessageId'),
      );
      expect(
        targetFinder,
        findsNothing,
        reason: 'comment 50 must start out unmaterialized',
      );

      // Tap comment 100's quote: the sheet must sweep to comment 50 and prove
      // it visible.
      await tester.tap(find.byKey(const ValueKey('messageReplyOpenOriginal')));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 16));

      expect(targetFinder, findsOneWidget);
      final sheetBox = tester.getRect(sheetScrollable);
      final targetRect = tester.getRect(targetFinder);
      expect(
        targetRect.bottom > sheetBox.top && targetRect.top < sheetBox.bottom,
        isTrue,
        reason: 'parent comment 50 must be visible after the jump',
      );
      expect(viewedInChat, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed in-sheet jump falls back to verified in-chat navigation',
    (tester) async {
      debugForceSheetReplyScrollFailure = true;
      addTearDown(() => debugForceSheetReplyScrollFailure = false);

      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);

      const targetMessageId = 40002;
      final comments = <Map<String, dynamic>>[
        for (var i = 1; i <= 10; i++)
          <String, dynamic>{
            '@type': 'message',
            'id': 40000 + i,
            'chat_id': -2002,
            'is_outgoing': false,
            'date': i,
            'sender_id': {'@type': 'messageSenderUser', 'user_id': 11},
            if (i == 10)
              'reply_to': {
                '@type': 'messageReplyToMessage',
                'chat_id': -2002,
                'message_id': targetMessageId,
              },
            'content': {
              '@type': 'messageText',
              'text': {
                '@type': 'formattedText',
                'text': 'Comment $i',
                'entities': <Map<String, dynamic>>[],
              },
            },
          },
      ];
      queryHandler = (request) async {
        switch (request['@type']) {
          case 'getMessageProperties':
            return <String, dynamic>{
              '@type': 'messageProperties',
              'can_get_message_thread': true,
              'can_be_replied': true,
            };
          case 'getMessageThread':
            return <String, dynamic>{
              '@type': 'messageThreadInfo',
              'chat_id': -2002,
              'message_thread_id': 99,
            };
          case 'getChat':
            final id = request['chat_id'] as int;
            return <String, dynamic>{
              '@type': 'chat',
              'id': id,
              'title': id == -2002 ? 'Discussion Group' : 'News Channel',
              'permissions': {'can_send_basic_messages': true},
            };
          case 'getUser':
            final id = request['user_id'] as int;
            return <String, dynamic>{
              '@type': 'user',
              'id': id,
              'first_name': 'User $id',
              'last_name': '',
            };
          case 'getMessageThreadHistory':
            return <String, dynamic>{'@type': 'messages', 'messages': comments};
          default:
            return <String, dynamic>{'@type': 'ok'};
        }
      };

      final viewed = <MessageRepliesViewTarget>[];
      final opened = <int>[];
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(extensions: [AppColors.light]),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showMessageRepliesSheet(
                      context: context,
                      chatId: -1001,
                      message: ChatMessage(
                        id: 42,
                        isOutgoing: false,
                        text: 'Channel post',
                        date: 10,
                        chatId: -1001,
                        commentCount: 10,
                        hasCommentThread: true,
                      ),
                      peerTitle: 'News Channel',
                      onOpenReply: opened.add,
                      onViewInChat: viewed.add,
                    );
                  },
                  child: const Text('Open comments'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open comments'));
      await tester.pumpAndSettle();

      // Comment 10 quotes comment 2; the scroll cannot reach it, so the tap
      // must not be swallowed: it opens the same (chat, message) pair through
      // the verified route.
      // The sheet is taller than the viewport: bring the quoting row into view
      // the way a reader would before tapping it.
      final sheetPosition = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      for (
        var i = 0;
        i < 20 &&
            find
                .byKey(const ValueKey('messageReplyOpenOriginal'))
                .evaluate()
                .isEmpty;
        i++
      ) {
        sheetPosition.jumpTo(sheetPosition.maxScrollExtent);
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('messageReplyOpenOriginal')));
      await tester.pumpAndSettle();

      expect(viewed, hasLength(1));
      expect(viewed.single.chatId, -2002);
      expect(viewed.single.messageId, targetMessageId);
      expect(
        opened,
        isEmpty,
        reason: 'the addressed fallback wins over id-only',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
