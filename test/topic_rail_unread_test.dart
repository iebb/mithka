import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(request);
          return _response(request);
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
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets('switching topics keeps the rail painted with every topic', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _setSurfaceSize(tester, const Size(1180, 820));
      await _pumpMainShell(tester, forumTopicsAsGroupChat: true);
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('topic-navigation-left')),
        findsOneWidget,
      );
      expect(_visibleTopicRailItems(), 13); // "All" + 12 topics.

      await tester.tap(find.byKey(const ValueKey('topic-navigation-item-88')));
      await _settle(tester);
      expect(tester.widget<ChatView>(find.byType(ChatView)).forumTopicId, 88);
      // The rebuilt pane must paint the full rail on its first frame: no
      // lone-"All" collapse, no waiting for getChat to resolve.
      expect(
        find.byKey(const ValueKey('topic-navigation-left')),
        findsOneWidget,
      );
      expect(_visibleTopicRailItems(), 13);
      expect(find.byType(ChatView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('rail rows carry unread counters', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _setSurfaceSize(tester, const Size(1180, 820));
      await _pumpMainShell(tester, forumTopicsAsGroupChat: true);
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await _settle(tester);

      // Traffic in another topic moves the rail counter live.
      updates.add({
        '@type': 'updateNewMessage',
        'message': {
          '@type': 'message',
          'id': 300,
          'chat_id': -42,
          'is_outgoing': false,
          'topic_id': {'@type': 'messageTopicForum', 'forum_topic_id': 77},
          'content': {
            '@type': 'messageText',
            'text': {'@type': 'formattedText', 'text': 'live'},
          },
        },
      });
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('topic-navigation-unread-77')),
        findsOneWidget,
      );

      // Reading to the newest message clears it again.
      updates.add({
        '@type': 'updateForumTopic',
        'chat_id': -42,
        'forum_topic_id': 77,
        'last_read_inbox_message_id': 300,
      });
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('topic-navigation-unread-77')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('phone picker rows show unread badges', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _setSurfaceSize(tester, const Size(390, 844));
      await _pumpMainShell(tester, forumTopicsAsGroupChat: true);
      ChatDeepLinkController.shared.openChat(chatId: -42, title: 'Forum');
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('chatHeaderTopics')));
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('topic-selector-unread-79')),
        findsOneWidget,
      );
      await tester.tap(find.text('Topic 1'));
      await _settle(tester);
      expect(tester.widget<ChatView>(find.byType(ChatView)).forumTopicId, 78);
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

// The vertical rail is a scrolling list; only visible rows are in the tree.
int _visibleTopicRailItems() {
  var count = 0;
  void visit(Element element) {
    final key = element.widget.key;
    if (key is ValueKey<String> &&
        key.value.startsWith('topic-navigation-item-')) {
      count++;
    }
    element.visitChildren(visit);
  }

  visit(find.byKey(const ValueKey('topic-navigation-left')).evaluate().first);
  return count;
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

Map<String, dynamic> _message(int id) => {
  '@type': 'message',
  'id': id,
  'chat_id': -42,
  'date': id,
  'is_outgoing': true,
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': 'Post $id'},
  },
};

Map<String, dynamic> _response(Map<String, dynamic> request) =>
    switch (request['@type']) {
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
        },
      },
      'getSupergroup' => {
        '@type': 'supergroup',
        'id': 42,
        'is_forum': true,
        'has_forum_tabs': false,
        'status': {'@type': 'chatMemberStatusMember'},
      },
      'getConnectionState' => {'@type': 'connectionStateReady'},
      'getForumTopics' => {
        '@type': 'forumTopics',
        'topics': [
          for (var index = 0; index < 12; index++)
            {
              '@type': 'forumTopic',
              'info': {
                '@type': 'forumTopicInfo',
                'forum_topic_id': 77 + index,
                'name': 'Topic $index',
              },
              'last_message': _message(70 - index),
              'unread_count': index == 2 ? 4 : 0, // topic 79 is unread
            },
        ],
      },
      'getForumTopicHistory' || 'getMessageThreadHistory' => {
        '@type': 'messages',
        'messages': [
          _message(
            70 -
                ((request['forum_topic_id'] ?? request['message_id']) as int) +
                77,
          ),
        ],
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
  bool showChannelsTab = false,
  bool forumTopicsAsGroupChat = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'showChannelsTab': showChannelsTab,
    'forumTopicsAsGroupChat': forumTopicsAsGroupChat,
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
        builder: (context, child) {
          final content = MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reducedMotion,
              textScaler: TextScaler.noScaling,
            ),
            child: child!,
          );
          return content;
        },
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
