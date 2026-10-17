//
//  forum_topic_overlay_actions_test.dart
//
//  The split shell's topic-list overlay carries the moderation affordances
//  of the live transcript: create gated on the real rights, the row menu
//  gated per TDLib's model, and every action firing its TDLib request.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/app/main_tab_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/forum_topic_index.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late StreamController<Map<String, dynamic>> updates;
  final requests = <Map<String, dynamic>>[];
  var adminRights = false;
  var canCreateTopics = false;
  var adminCanDeleteMessages = false;
  // Per-topic message count the fake getForumTopicHistory returns, for the
  // creator deletion probe (limit 11 messages, none from another user).
  final topicMessageCounts = <int, int>{};
  // Per-topic flag: does the fake history contain another user's message?
  final topicHasOtherSender = <int, bool>{};
  final pinnedTopics = <int>{};
  // Topics a viewMessages read has cleared, so the fake page stops reporting
  // them as unread.
  final readTopics = <int>{};
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('mithka/share_intent'),
          (call) async => null,
        );
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(request);
          if (request['@type'] == 'toggleForumTopicIsPinned') {
            final id = request['forum_topic_id'] as int;
            if (request['is_pinned'] == true) {
              pinnedTopics.add(id);
            } else {
              pinnedTopics.remove(id);
            }
          }
          if (request['@type'] == 'viewMessages' &&
              (request['source'] as Map?)?['@type'] ==
                  'messageSourceForumTopicHistory') {
            // The scoped read names the thread only by its messages, so the
            // fake maps each read id back to the topic whose page carries it
            // (topic 77+index pins message 70-index).
            for (final id in (request['message_ids'] as List).cast<int>()) {
              final index = 70 - id;
              if (index >= 0 && index < 12) readTopics.add(77 + index);
            }
          }
          return _response(
            request,
            adminRights,
            canCreateTopics,
            adminCanDeleteMessages,
            topicMessageCounts,
            topicHasOtherSender,
            pinnedTopics,
            readTopics,
          );
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });
  setUp(() {
    requests.clear();
    clearChatMemoryCaches();
    ForumTopicIndex.shared.clear();
    adminRights = false;
    canCreateTopics = false;
    adminCanDeleteMessages = false;
    topicMessageCounts.clear();
    topicHasOtherSender.clear();
    pinnedTopics.clear();
    readTopics.clear();
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets('member: no create button, row menu offers read and mute only', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _setSurfaceSize(tester, const Size(1180, 820));
      await _pumpMainShell(tester);
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await _settle(tester);

      // No create right: the overlay header hides its '+'.
      expect(find.byKey(const ValueKey('topic-list-create')), findsNothing);

      // Topic 79 arrives unread; its row menu offers mark-read and mute,
      // never pin/edit/close/delete for a plain member.
      await tester.longPress(
        find.byKey(const ValueKey('topic-navigation-item-79')),
      );
      await _settle(tester);
      expect(find.byKey(const ValueKey('topic-row-menu-79')), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-menu-read')), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-menu-mute')), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-menu-pin')), findsNothing);
      expect(find.byKey(const ValueKey('topic-menu-edit')), findsNothing);
      expect(find.byKey(const ValueKey('topic-menu-close')), findsNothing);
      expect(find.byKey(const ValueKey('topic-menu-delete')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('topic-menu-read')));
      await _settle(tester);
      // Mark-read views the topic's newest message (topic 79's row pins
      // message 68 as its last).
      expect(
        requests.any(
          (request) =>
              request['@type'] == 'viewMessages' &&
              (request['message_ids'] as List).contains(68),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('manage-only admin: another user topic offers no delete', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      adminRights = true;
      adminCanDeleteMessages = false;
      await _setSurfaceSize(tester, const Size(1180, 820));
      await _pumpMainShell(tester);
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await _settle(tester);

      // can_manage_topics grants pin/edit, never deletion; topic 79 was
      // created by another user, so the creator carve-out cannot apply.
      await tester.longPress(
        find.byKey(const ValueKey('topic-navigation-item-79')),
      );
      await _settle(tester);
      expect(find.byKey(const ValueKey('topic-menu-pin')), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-menu-edit')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('topic-menu-delete')),
        findsNothing,
        reason: 'can_manage_topics is not permission to delete a topic',
      );
      expect(
        requests.any((request) => request['@type'] == 'deleteForumTopic'),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'creator carve-out: probed history limits gate the delete affordance',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        // Plain member who created topic 88.
        await _setSurfaceSize(tester, const Size(1180, 820));
        await _pumpMainShell(tester);
        tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
          ChatListSelection.fromChat(_chat()),
        );
        await _settle(tester);

        // 12 messages: over TDLib's at-most-11 limit for the carve-out.
        topicMessageCounts[88] = 12;
        await tester.longPress(
          find.byKey(const ValueKey('topic-navigation-item-88')),
        );
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('topic-menu-delete')),
          findsNothing,
          reason: 'a 12th message disqualifies the creator carve-out',
        );
        await tester.tap(find.byKey(const ValueKey('topic-menu-mute')));
        await _settle(tester);

        // Another user's message among 5: also disqualified. The history
        // changed, so real traffic arrives first and drops the cached probe.
        updates.add({
          '@type': 'updateNewMessage',
          'message': {
            '@type': 'message',
            'id': 200,
            'chat_id': -42,
            'date': 200,
            'is_outgoing': false,
            'sender_id': {'@type': 'messageSenderUser', 'user_id': 2},
            'topic_id': {'@type': 'messageTopicForum', 'forum_topic_id': 88},
            'content': {
              '@type': 'messageText',
              'text': {'@type': 'formattedText', 'text': 'Foreign'},
            },
          },
        });
        topicMessageCounts[88] = 5;
        topicHasOtherSender[88] = true;
        await tester.longPress(
          find.byKey(const ValueKey('topic-navigation-item-88')),
        );
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('topic-menu-delete')),
          findsNothing,
          reason: "another user's message disqualifies the carve-out",
        );
        await tester.tap(find.byKey(const ValueKey('topic-menu-mute')));
        await _settle(tester);

        // Five own messages: the carve-out applies and deletion fires after
        // the confirmation. A deletion elsewhere drops the cached probe.
        updates.add({
          '@type': 'updateDeleteMessages',
          'chat_id': -42,
          'message_ids': [200],
          'is_permanent': true,
        });
        topicMessageCounts[88] = 5;
        topicHasOtherSender[88] = false;
        await tester.longPress(
          find.byKey(const ValueKey('topic-navigation-item-88')),
        );
        await _settle(tester);
        expect(find.byKey(const ValueKey('topic-menu-delete')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('topic-menu-delete')));
        await _settle(tester);
        await tester.tap(find.text('Delete').last);
        await _settle(tester);
        expect(
          requests.any(
            (request) =>
                request['@type'] == 'deleteForumTopic' &&
                request['forum_topic_id'] == 88,
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await _disposeShell(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'rights revoked while the delete confirmation is open block the request',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        // Creator of topic 88 with an eligible carve-out: the confirmation
        // opens, then foreign traffic arrives, then the user confirms.
        await _setSurfaceSize(tester, const Size(1180, 820));
        await _pumpMainShell(tester);
        tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
          ChatListSelection.fromChat(_chat()),
        );
        await _settle(tester);

        topicMessageCounts[88] = 3;
        await tester.longPress(
          find.byKey(const ValueKey('topic-navigation-item-88')),
        );
        await _settle(tester);
        expect(find.byKey(const ValueKey('topic-menu-delete')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('topic-menu-delete')));
        await _settle(tester);

        // Another user posts in the topic while the dialog is open: the
        // carve-out dies and the cached probe is dropped.
        updates.add({
          '@type': 'updateNewMessage',
          'message': {
            '@type': 'message',
            'id': 300,
            'chat_id': -42,
            'date': 300,
            'is_outgoing': false,
            'sender_id': {'@type': 'messageSenderUser', 'user_id': 2},
            'topic_id': {'@type': 'messageTopicForum', 'forum_topic_id': 88},
            'content': {
              '@type': 'messageText',
              'text': {'@type': 'formattedText', 'text': 'Foreign reply'},
            },
          },
        });
        await _settle(tester);

        // Confirming anyway must not send anything destructive.
        await tester.tap(find.text('Delete').last);
        await _settle(tester);
        expect(
          requests.any((request) => request['@type'] == 'deleteForumTopic'),
          isFalse,
          reason: 'eligibility is re-checked after the confirmation closes',
        );
        expect(tester.takeException(), isNull);
        await _disposeShell(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('overlay follows pin, unpin, and repin from refreshed rows', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      adminRights = true;
      await _setSurfaceSize(tester, const Size(1180, 820));
      await _pumpMainShell(tester);
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await _settle(tester);
      final marker = find.byKey(const ValueKey('topic-row-pinned-78'));
      expect(marker, findsNothing);

      for (final pinned in [true, false, true]) {
        await tester.longPress(
          find.byKey(const ValueKey('topic-navigation-item-78')),
        );
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('topic-menu-pin')));
        await _settle(tester);
        final request = requests.lastWhere(
          (request) => request['@type'] == 'toggleForumTopicIsPinned',
        );
        expect(request['chat_id'], -42);
        expect(request['forum_topic_id'], 78);
        expect(request['is_pinned'], pinned);
        expect(marker, pinned ? findsOneWidget : findsNothing);
      }
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('admin: the overlay header clears every unread topic', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _setSurfaceSize(tester, const Size(1180, 820));
      await _pumpMainShell(tester);
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await _settle(tester);

      // Topic 79 is the only unread one; its badge shows on the overlay row.
      expect(
        find.byKey(const ValueKey('topic-navigation-unread-79')),
        findsOneWidget,
      );

      // The header's bulk action appears while anything is unread and sends
      // one forum-history read per topic in the list — General (topic 77)
      // included, because a chat-wide read cannot address a thread.
      expect(
        find.byKey(const ValueKey('topic-list-mark-all-read')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('topic-list-mark-all-read')));
      await tester.pump();
      await _settle(tester);

      final reads = [
        for (final request in requests)
          if (request['@type'] == 'viewMessages' &&
              (request['source'] as Map?)?['@type'] ==
                  'messageSourceForumTopicHistory')
            (request['message_ids'] as List).single,
      ];
      expect(reads, [70, 69, 68, 67, 66, 65, 64, 63, 62, 61, 60, 59]);
      expect(
        find.byKey(const ValueKey('topic-navigation-unread-79')),
        findsNothing,
        reason: 'the read cleared the only unread topic',
      );
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('admin: pin and create fire their TDLib requests', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      adminRights = true;
      canCreateTopics = true;
      await _setSurfaceSize(tester, const Size(1180, 820));
      await _pumpMainShell(tester);
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await _settle(tester);

      // The create right lights the overlay header's '+'.
      expect(find.byKey(const ValueKey('topic-list-create')), findsOneWidget);

      await tester.longPress(
        find.byKey(const ValueKey('topic-navigation-item-78')),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('topic-menu-pin')));
      await _settle(tester);
      expect(
        requests.any(
          (request) =>
              request['@type'] == 'toggleForumTopicIsPinned' &&
              request['forum_topic_id'] == 78 &&
              request['is_pinned'] == true,
        ),
        isTrue,
      );

      // Create flows through the shared draft dialog and opens the topic.
      await tester.tap(find.byKey(const ValueKey('topic-list-create')));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('topic-draft-name')),
        'Fresh',
      );
      await tester.tap(find.byKey(const ValueKey('topic-draft-save')));
      await _settle(tester);
      expect(
        requests.any(
          (request) =>
              request['@type'] == 'createForumTopic' &&
              request['name'] == 'Fresh',
        ),
        isTrue,
      );
      expect(tester.widget<ChatView>(find.byType(ChatView)).forumTopicId, 500);
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

ChatSummary _chat() => ChatSummary(
  id: -42,
  title: 'Forum',
  lastMessage: '',
  lastMessageId: 0,
  date: 0,
  unreadCount: 0,
  order: 1,
  isMuted: false,
  kind: ChatKind.group,
  isForum: true,
);

Map<String, dynamic> _message(int id, {bool outgoing = true}) =>
    <String, dynamic>{
      '@type': 'message',
      'id': id,
      'chat_id': -42,
      'date': id,
      'is_outgoing': outgoing,
      'content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'Post $id'},
      },
    };

/// The fake topic history for the creator deletion probe: the requested
/// topic's message count (default 1), with an incoming message when the test
/// asks for another user's message.
List<Map<String, dynamic>> _topicHistoryMessages(
  Map<String, dynamic> request,
  Map<int, int> topicMessageCounts,
  Map<int, bool> topicHasOtherSender,
) {
  final topicId =
      (request['forum_topic_id'] ?? request['message_id']) as int? ?? 77;
  final count = topicMessageCounts[topicId] ?? 1;
  final hasOtherSender = topicHasOtherSender[topicId] ?? false;
  return [
    for (var index = 0; index < count; index++)
      if (hasOtherSender && index == count - 1)
        _message(100 - index, outgoing: false)
      else
        _message(100 - index),
  ];
}

Map<String, dynamic> _response(
  Map<String, dynamic> request,
  bool adminRights,
  bool canCreateTopics,
  bool adminCanDeleteMessages,
  Map<int, int> topicMessageCounts,
  Map<int, bool> topicHasOtherSender,
  Set<int> pinnedTopics,
  Set<int> readTopics,
) => switch (request['@type']) {
  'getChat' => {
    '@type': 'chat',
    'id': request['chat_id'],
    'title': 'Forum',
    'view_as_topics': true,
    'type': {
      '@type': 'chatTypeSupergroup',
      'supergroup_id': 42,
      'is_channel': false,
    },
    'permissions': {
      '@type': 'chatPermissions',
      'can_send_basic_messages': true,
      'can_create_topics': canCreateTopics,
    },
  },
  'getSupergroup' => {
    '@type': 'supergroup',
    'id': 42,
    'is_forum': true,
    'has_forum_tabs': false,
    'status': adminRights
        ? {
            '@type': 'chatMemberStatusAdministrator',
            'rights': {
              '@type': 'chatAdministratorRights',
              'can_manage_topics': true,
              'can_delete_messages': adminCanDeleteMessages,
            },
          }
        : {'@type': 'chatMemberStatusMember'},
  },
  'getConnectionState' => {'@type': 'connectionStateReady'},
  'createForumTopic' => {
    '@type': 'forumTopicInfo',
    'chat_id': -42,
    'forum_topic_id': 500,
    'name': request['name'],
  },
  'getForumTopics' => {
    '@type': 'forumTopics',
    'topics': [
      for (var index = 0; index < 12; index++)
        {
          '@type': 'forumTopic',
          'info': {
            '@type': 'forumTopicInfo',
            'chat_id': -42,
            'forum_topic_id': 77 + index,
            'name': 'Topic $index',
            'creator_id': index == 11
                ? {'@type': 'messageSenderUser', 'user_id': 1}
                : null,
          },
          'last_message': _message(70 - index),
          'is_pinned': pinnedTopics.contains(77 + index),
          'unread_count': index == 2 && !readTopics.contains(79)
              ? 4
              : 0, // topic 79 is unread until it is read
        },
    ],
  },
  'getForumTopicHistory' || 'getMessageThreadHistory' => {
    '@type': 'messages',
    'messages': _topicHistoryMessages(
      request,
      topicMessageCounts,
      topicHasOtherSender,
    ),
  },
  'getMessage' => _message(request['message_id'] as int),
  'getChatHistory' => {
    '@type': 'messages',
    'messages': [_message(70)],
  },
  'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Test'},
  _ => {'@type': 'ok'},
};

Future<void> _pumpMainShell(
  WidgetTester tester, {
  bool reducedMotion = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'showChannelsTab': false,
    'showMomentsTab': false,
    'communitiesEnabled': false,
  });
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  final accounts = AccountStore(prefs);
  final auth = AuthManager();
  final translation = TranslationController(prefs);
  final drawer = dc.DrawerController();
  final deepLinks = ChatDeepLinkController.shared;
  deepLinks.consumePending();

  addTearDown(theme.dispose);
  addTearDown(accounts.dispose);
  addTearDown(auth.dispose);
  addTearDown(translation.dispose);
  addTearDown(drawer.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<AppLocaleController>.value(
          value: AppLocaleController(prefs),
        ),
        ChangeNotifierProvider<AccountStore>.value(value: accounts),
        ChangeNotifierProvider<AuthManager>.value(value: auth),
        ChangeNotifierProvider<TranslationController>.value(value: translation),
        ChangeNotifierProvider<ChatDeepLinkController>.value(value: deepLinks),
        ChangeNotifierProvider<dc.DrawerController>.value(value: drawer),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
            textScaler: TextScaler.noScaling,
          ),
          child: child!,
        ),
        home: const MainSplitRootView(),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _disposeShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

Future<void> _setSurfaceSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 3),
  );
}
