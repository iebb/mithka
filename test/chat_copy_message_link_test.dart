import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view.dart'
    show ChatView, clearChatMemoryCaches;
import 'package:mithka/chat/message_action_menu.dart' show MessageActionSource;
import 'package:mithka/chat/message_bubble.dart' show MessageBubble;
import 'package:mithka/chat/sticker_store.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

// Shell-level regression for "复制消息链接": the long-press action menu gains a
// Copy Message Link entry gated on the server-reported
// messageProperties.can_get_link, and selecting it copies the TDLib-generated
// getMessageLink URL. Pumped through the real ChatView against the TdClient
// proxy so the actual scoped TDLib requests are pinned.

const _chatId = -1000000004242;

Map<String, dynamic> _textMessage(int id) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': 1785862260 + id,
  'is_outgoing': false,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 2},
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': 'shareable message $id',
      'entities': <Map<String, dynamic>>[],
    },
  },
};

const _discussionChatId = -1000000009292;

Map<String, dynamic> _discussionChatJson() => {
  '@type': 'chat',
  'id': _discussionChatId,
  'title': 'Discussion group',
  'type': {
    '@type': 'chatTypeSupergroup',
    'supergroup_id': -_discussionChatId - 1000000000000,
    'is_channel': false,
  },
  'permissions': {'can_send_basic_messages': true},
};

Map<String, dynamic> _chatJson({bool channel = false}) => {
  '@type': 'chat',
  'id': _chatId,
  'title': channel ? 'Read-only channel' : 'Group chat',
  'type': {
    '@type': 'chatTypeSupergroup',
    'supergroup_id': -_chatId - 1000000000000,
    'is_channel': channel,
  },
  'last_read_inbox_message_id': 5,
  'unread_count': 0,
  'permissions': {'can_send_basic_messages': !channel},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  L10nFixtures.load().install();

  // Clipboard.setData never returns in a plain widget test (no platform
  // plugin) — mock the platform channel and record what the app copied.
  final clipboard = <String>[];
  Completer<void>? clipboardCompletion;
  Completer<Map<String, dynamic>>? linkCompletion;
  Completer<Map<String, dynamic>>? propertiesCompletion;
  var clipboardFails = false;
  var propertiesFail = false;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
          if (clipboardCompletion case final completion?) {
            await completion.future;
          }
          if (clipboardFails) {
            throw PlatformException(code: 'clipboard_unavailable');
          }
        }
        return null;
      });

  late List<Map<String, dynamic>> requests;
  late bool canGetLink;
  var canBeReplied = true;
  var channelChat = false;
  var channelOwner = false;
  var linkedDiscussion = false;
  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(Map<String, dynamic>.from(request));
          if (request['@type'] == 'getMessageProperties' && propertiesFail) {
            throw StateError('properties unavailable');
          }
          if (request['@type'] == 'getMessageProperties' &&
              propertiesCompletion != null) {
            return propertiesCompletion!.future;
          }
          if (request['@type'] == 'getMessageLink') {
            if (linkCompletion case final completion?) {
              return completion.future;
            }
          }
          return switch (request['@type']) {
            'getChat' =>
              request['chat_id'] == _discussionChatId
                  ? _discussionChatJson()
                  : _chatJson(channel: channelChat),
            'getMessageThread' => {
              '@type': 'messageThreadInfo',
              'chat_id': _discussionChatId,
              'message_thread_id': 5,
            },
            'getMessageThreadHistory' => {
              '@type': 'messages',
              'total_count': 0,
              'messages': <Map<String, dynamic>>[],
            },
            'getChatHistory' => {
              '@type': 'messages',
              'total_count': 1,
              'messages': [_textMessage(5)],
            },
            'getMe' => {
              '@type': 'user',
              'id': 1,
              'type': {'@type': 'userTypeRegular'},
            },
            'getUser' => {
              '@type': 'user',
              'id': request['user_id'] ?? 2,
              'first_name': 'Member',
              'type': {'@type': 'userTypeRegular'},
            },
            'getSupergroup' => {
              '@type': 'supergroup',
              'id': -_chatId - 1000000000000,
              'is_channel': channelChat,
              if (channelChat)
                'status': {
                  '@type': channelOwner
                      ? 'chatMemberStatusCreator'
                      : 'chatMemberStatusMember',
                  if (channelOwner) 'is_member': true,
                },
            },
            'getSupergroupFullInfo' => {
              '@type': 'supergroupFullInfo',
              'member_count': 3,
              if (linkedDiscussion) 'linked_chat_id': _discussionChatId,
            },
            'getMessageProperties' => {
              '@type': 'messageProperties',
              'can_get_link': canGetLink,
              'can_be_replied': canBeReplied,
            },
            'getMessageLink' => {
              '@type': 'messageLink',
              'link': 'https://t.me/c/4242/5',
              'is_public': false,
            },
            'getMessageAvailableReactions' => {
              '@type': 'availableReactions',
              'top_reactions': <Map<String, dynamic>>[],
              'recent_reactions': <Map<String, dynamic>>[],
              'popular_reactions': <Map<String, dynamic>>[],
              'allow_custom_emoji': false,
              'are_tags': false,
              'unavailability_reason': null,
            },
            'getOption' => {'@type': 'optionValueBoolean', 'value': false},
            _ => {'@type': 'ok'},
          };
        },
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);

  late ThemeController theme;
  late TranslationController translation;

  setUp(() async {
    requests = [];
    canGetLink = true;
    canBeReplied = true;
    channelChat = false;
    channelOwner = false;
    linkedDiscussion = false;
    clipboard.clear();
    clipboardCompletion = null;
    linkCompletion = null;
    propertiesCompletion = null;
    clipboardFails = false;
    propertiesFail = false;
    SharedPreferences.setMockInitialValues({});
    theme = ThemeController(await SharedPreferences.getInstance());
    translation = TranslationController(await SharedPreferences.getInstance());
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    clearChatMemoryCaches();
    theme.dispose();
    translation.dispose();
  });

  Future<void> openMenuOnMessage(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
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
          theme: ThemeData(extensions: [AppColors.light], platform: platform),
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ChatView(chatId: _chatId, title: 'Group'),
        ),
      ),
    );
    // The chat surface keeps timers alive (progress polling): bounded pumps
    // instead of pumpAndSettle.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(
      find.byKey(const ValueKey('messageTapTarget-5')),
      findsOneWidget,
      reason: 'the fixture message must render',
    );
    if (platform == TargetPlatform.macOS) {
      // Exercise the actual bubble-to-chat action callback and desktop menu.
      // Pointer hit-testing is outside this clipboard/lifecycle regression.
      final bubble = tester
          .widgetList<MessageBubble>(find.byType(MessageBubble))
          .singleWhere((bubble) => bubble.message.id == 5);
      bubble.onLongPress!(bubble.message, null, MessageActionSource.normal);
    } else {
      await tester.longPress(find.byKey(const ValueKey('messageTapTarget-5')));
    }
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('a linkable message offers Copy Message Link and copies it', (
    tester,
  ) async {
    await openMenuOnMessage(tester);

    final linkAction = find.byKey(
      const ValueKey('message-action-copyMessageLink'),
    );
    expect(linkAction, findsOneWidget);
    expect(find.byKey(const ValueKey('message-action-reply')), findsOneWidget);
    expect(
      requests.whereType<Map<String, dynamic>>().any(
        (request) =>
            request['@type'] == 'getMessageProperties' &&
            request['message_id'] == 5,
      ),
      isTrue,
      reason: 'availability is decided by the server-provided flag',
    );
    expect(
      requests.where(
        (request) =>
            request['@type'] == 'getMessageProperties' &&
            request['message_id'] == 5,
      ),
      hasLength(1),
      reason: 'the link and reply gates share one properties query',
    );

    await tester.tap(linkAction);
    await tester.pump(const Duration(milliseconds: 300));
    expect(clipboard, ['https://t.me/c/4242/5']);
    expect(
      requests.whereType<Map<String, dynamic>>().any(
        (request) =>
            request['@type'] == 'getMessageLink' && request['message_id'] == 5,
      ),
      isTrue,
      reason: 'the copied URL is the TDLib-generated link',
    );
    expect(find.text('Link copied'), findsOneWidget);

    // Drain the toast (visibleFor + hold timer) and the chat surface.
    debugDefaultTargetPlatformOverride = null;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a message without a linkable flag keeps the entry hidden', (
    tester,
  ) async {
    canGetLink = false;
    await openMenuOnMessage(tester);

    expect(
      find.byKey(const ValueKey('message-action-copyMessageLink')),
      findsNothing,
    );
    expect(
      requests.whereType<Map<String, dynamic>>().any(
        (request) => request['@type'] == 'getMessageLink',
      ),
      isFalse,
      reason: 'no link request is sent for a message the server excluded',
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('desktop link copy waits for clipboard completion', (
    tester,
  ) async {
    clipboardCompletion = Completer<void>();
    await openMenuOnMessage(tester, platform: TargetPlatform.macOS);
    await tester.tap(
      find.byKey(const ValueKey('message-action-copyMessageLink')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final reportedSuccessEarly = find.text('Link copied').evaluate().isNotEmpty;
    expect(clipboard, ['https://t.me/c/4242/5']);
    clipboardCompletion!.complete();
    await tester.pump(const Duration(milliseconds: 300));
    try {
      expect(reportedSuccessEarly, isFalse);
      expect(find.text('Link copied'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    }
  });

  testWidgets('clipboard failure reports failure without an uncaught error', (
    tester,
  ) async {
    clipboardFails = true;
    await openMenuOnMessage(tester);
    await tester.tap(
      find.byKey(const ValueKey('message-action-copyMessageLink')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    try {
      expect(tester.takeException(), isNull);
      expect(find.text('Link copied'), findsNothing);
      expect(find.text('Could not copy link'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    }
  });

  testWidgets('closing the chat cancels a pending link clipboard write', (
    tester,
  ) async {
    linkCompletion = Completer<Map<String, dynamic>>();
    await openMenuOnMessage(tester, platform: TargetPlatform.iOS);
    await tester.tap(
      find.byKey(const ValueKey('message-action-copyMessageLink')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      requests.where((request) => request['@type'] == 'getMessageLink'),
      hasLength(1),
    );
    expect(clipboard, isEmpty);
    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox.shrink());
    linkCompletion!.complete({
      '@type': 'messageLink',
      'link': 'https://t.me/c/4242/5',
      'is_public': false,
    });
    await tester.pump(const Duration(seconds: 6));
    expect(clipboard, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed link permissions keep the menu action hidden', (
    tester,
  ) async {
    propertiesFail = true;
    await openMenuOnMessage(tester);
    try {
      expect(
        find.byKey(const ValueKey('message-action-copyMessageLink')),
        findsNothing,
      );
      expect(
        requests.where((request) => request['@type'] == 'getMessageLink'),
        isEmpty,
      );
      expect(clipboard, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    }
  });

  testWidgets('a message the server refuses to reply to loses Reply', (
    tester,
  ) async {
    canBeReplied = false;
    await openMenuOnMessage(tester);
    final reply = find.byKey(const ValueKey('message-action-reply'));
    try {
      expect(reply, findsNothing);
      expect(
        find.byKey(const ValueKey('message-action-quote')),
        findsNothing,
        reason: 'a quote is a reply, so it goes with it',
      );
      expect(
        find.byKey(const ValueKey('message-action-copyMessageLink')),
        findsOneWidget,
        reason: 'the same properties answer still carries the link flag',
      );
      expect(
        requests.where(
          (request) =>
              request['@type'] == 'getMessageProperties' &&
              request['message_id'] == 5,
        ),
        hasLength(1),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    }
  });

  testWidgets('Reply stays hidden while the properties answer is in flight', (
    tester,
  ) async {
    propertiesCompletion = Completer<Map<String, dynamic>>();
    await openMenuOnMessage(tester);
    final reply = find.byKey(const ValueKey('message-action-reply'));
    final link = find.byKey(const ValueKey('message-action-copyMessageLink'));
    try {
      expect(
        reply,
        findsNothing,
        reason: 'fail closed instead of offering a row that may vanish',
      );
      expect(link, findsNothing);
      propertiesCompletion!.complete({
        '@type': 'messageProperties',
        'can_get_link': true,
        'can_be_replied': true,
      });
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));
      expect(reply, findsOneWidget);
      expect(link, findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    }
  });

  testWidgets(
    'a channel owner cannot quote a post that forbids same-chat replies',
    (tester) async {
      channelChat = true;
      channelOwner = true;
      linkedDiscussion = true;
      canBeReplied = false;
      await openMenuOnMessage(tester);
      try {
        expect(
          find.byKey(const ValueKey('message-action-reply')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('message-action-quote')),
          findsNothing,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 6));
      }
    },
  );

  testWidgets(
    'a channel owner replies in discussion when same-chat replies are forbidden',
    (tester) async {
      StickerStore.shared.reset();
      channelChat = true;
      channelOwner = true;
      linkedDiscussion = true;
      canBeReplied = false;
      await openMenuOnMessage(tester);
      try {
        await tester.tap(find.byKey(const ValueKey('message-action-reply')));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 120));
        }
        expect(
          requests.any((request) => request['@type'] == 'getMessageThread'),
          isTrue,
        );
        expect(
          find.byKey(const ValueKey('messageRepliesComposer')),
          findsOneWidget,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 6));
      }
    },
  );

  testWidgets(
    'a channel owner can quote a post with same-chat reply permission',
    (tester) async {
      channelChat = true;
      channelOwner = true;
      linkedDiscussion = true;
      await openMenuOnMessage(tester);
      try {
        expect(
          find.byKey(const ValueKey('message-action-reply')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('message-action-quote')),
          findsOneWidget,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 6));
      }
    },
  );

  testWidgets('a read-only channel with no discussion group offers no Reply', (
    tester,
  ) async {
    channelChat = true;
    await openMenuOnMessage(tester);
    try {
      expect(find.byKey(const ValueKey('message-action-reply')), findsNothing);
      expect(
        find.byKey(const ValueKey('message-action-quote')),
        findsNothing,
        reason: 'a quote is a reply, so it needs a composer too',
      );
      expect(
        find.byKey(const ValueKey('message-action-copyMessageLink')),
        findsOneWidget,
        reason: 'the link row is server-gated, not composer-gated',
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    }
  });
  testWidgets(
    'a read-only channel with a linked group offers Reply and opens its comments',
    (tester) async {
      channelChat = true;
      linkedDiscussion = true;
      await openMenuOnMessage(tester);
      final reply = find.byKey(const ValueKey('message-action-reply'));
      try {
        expect(
          reply,
          findsOneWidget,
          reason:
              'a channel post is answered in the group it is linked to, '
              'so the channel taking no messages does not hide the row',
        );
        expect(
          find.byKey(const ValueKey('message-action-quote')),
          findsNothing,
          reason: 'quoting is composing here, and this channel has no composer',
        );

        await tester.tap(reply);
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 120));
        }

        expect(
          requests.any((request) => request['@type'] == 'getMessageThread'),
          isTrue,
          reason: 'the action resolves the discussion thread',
        );
        expect(
          find.byKey(const ValueKey('messageRepliesComposer')),
          findsOneWidget,
          reason:
              'the comment composer of the linked group is where a reply '
              'to a channel post is written',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 6));
      }
    },
  );
}
