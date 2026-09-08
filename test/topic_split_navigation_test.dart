import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/app/main_tab_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/channels/topic_channels_view.dart';
import 'package:mithka/channels/topic_chat_view.dart';
import 'package:mithka/chat/chat_members_view.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late StreamController<Map<String, dynamic>> updates;
  var hasForumTabs = false;
  var failTopics = false;
  final requests = <Map<String, dynamic>>[];
  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(request);
          if (request['@type'] == 'getForumTopics' && failTopics) {
            throw StateError('Offline');
          }
          return _response(request, hasForumTabs: hasForumTabs);
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });
  setUp(() {
    hasForumTabs = false;
    failTopics = false;
    requests.clear();
    clearChatMemoryCaches();
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets(
      '$platform topic settings, members and search stay in the detail pane',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await _setSurfaceSize(tester, const Size(1180, 820));
          await _pumpMainShell(tester, reducedMotion: true);
          tester
              .widget<ChatListView>(find.byType(ChatListView))
              .onChatSelected!(ChatListSelection.fromChat(_chat()));
          await _settle(tester);
          expect(
            tester.widget<ChatView>(find.byType(ChatView)).headerBottom,
            isNull,
          );
          final sidebar = tester.getRect(find.byType(ChatListView));
          await tester.tap(find.byKey(const ValueKey('chatHeaderTopics')));
          await _settle(tester);
          final topicState = tester.state(find.byType(TopicChatView));
          final navigator = Navigator.of(
            tester.element(find.byType(TopicChatView)),
            rootNavigator: true,
          );
          await tester.tap(find.byKey(const ValueKey('topic-header-settings')));
          await _settle(tester);
          final settings = find.byKey(const ValueKey('topic-settings'));
          expect(
            tester.getRect(settings).left,
            greaterThanOrEqualTo(sidebar.right),
          );
          expect(tester.getRect(find.byType(ChatListView)), sidebar);
          expect(navigator.canPop(), isFalse);

          await tester.tap(
            find.byKey(const ValueKey('topic-settings-members')),
          );
          await _settle(tester);
          expect(
            tester.getRect(find.byType(ChatMembersView)).left,
            greaterThanOrEqualTo(sidebar.right),
          );
          await navigator.maybePop();
          await _settle(tester);
          expect(settings, findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('topic-settings-back')));
          await _settle(tester);
          expect(tester.state(find.byType(TopicChatView)), same(topicState));

          await tester.tap(find.byKey(const ValueKey('topic-header-search')));
          await _settle(tester);
          expect(
            tester.getRect(find.byType(TextField).first).left,
            greaterThanOrEqualTo(sidebar.right),
          );
          expect(tester.getRect(find.byType(ChatListView)), sidebar);
          await navigator.maybePop();
          await _settle(tester);
          expect(tester.state(find.byType(TopicChatView)), same(topicState));
          expect(tester.takeException(), isNull);
          await _disposeShell(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      '$platform message-link topic entry and back preserve the split shell',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await _setSurfaceSize(tester, const Size(1180, 820));
          await _pumpMainShell(tester, reducedMotion: true);
          ChatDeepLinkController.shared.openChat(
            chatId: -42,
            title: 'Forum',
            messageId: 70,
          );
          await _settle(tester);
          expect(find.byType(ChatView), findsOneWidget);
          final sidebar = tester.getRect(find.byType(ChatListView));
          final navigator = Navigator.of(
            tester.element(find.byType(ChatView)),
            rootNavigator: true,
          );
          expect(navigator.canPop(), isFalse);
          expect(
            find.byKey(const ValueKey('topic-navigation-left')),
            findsOneWidget,
          );

          await tester.tap(find.byKey(const ValueKey('chatHeaderTopics')));
          await _settle(tester);
          expect(find.byType(TopicChatView), findsOneWidget);
          expect(find.byType(ChatListView), findsOneWidget);
          expect(tester.getRect(find.byType(ChatListView)), sidebar);
          expect(
            tester.getTopLeft(find.byType(TopicChatView)).dx,
            greaterThanOrEqualTo(sidebar.right),
          );
          expect(navigator.canPop(), isFalse);
          expect(tester.takeException(), isNull);

          await tester.tap(
            find.byKey(const ValueKey('topic-navigation-item-88')),
          );
          await _settle(tester);
          expect(
            requests.lastWhere(
              (request) => request['@type'] == 'getForumTopicHistory',
            )['forum_topic_id'],
            88,
          );

          await tester.tap(find.byKey(const ValueKey('topic-header-back')));
          await _settle(tester);
          expect(find.byType(ChatView), findsOneWidget);
          expect(tester.getRect(find.byType(ChatListView)), sidebar);
          // Repeat using a topic tab and the system back action.
          await tester.tap(
            find.byKey(const ValueKey('topic-navigation-item-77')),
          );
          await _settle(tester);
          expect(
            tester
                .widget<TopicChatView>(find.byType(TopicChatView))
                .initialThreadId,
            77,
          );
          await navigator.maybePop();
          await _settle(tester);
          expect(find.byType(ChatView), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _disposeShell(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets(
    'known forum tabs follow the per-chat setting and live updates in both modes',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        hasForumTabs = true;
        await _setSurfaceSize(tester, const Size(1180, 820));
        await _pumpMainShell(tester, reducedMotion: true);
        tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
          ChatListSelection.fromChat(_chat()),
        );
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('topic-navigation-top')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('topic-navigation-left')),
          findsNothing,
        );
        hasForumTabs = false;
        updates.add({
          '@type': 'updateSupergroup',
          'supergroup': _supergroup(false),
        });
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('topic-navigation-left')),
          findsOneWidget,
        );
        updates.add({
          '@type': 'updateSupergroup',
          'supergroup': {..._supergroup(true), 'id': 99},
        });
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('topic-navigation-left')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('topic-navigation-item-77')),
        );
        await _settle(tester);
        expect(find.byType(TopicChatView), findsOneWidget);
        expect(
          find.byKey(const ValueKey('topic-navigation-left')),
          findsOneWidget,
        );
        hasForumTabs = true;
        updates.add({
          '@type': 'updateSupergroup',
          'supergroup': _supergroup(true),
        });
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('topic-navigation-top')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('topic-navigation-left')),
          findsNothing,
        );
        await tester.drag(
          find.byKey(const ValueKey('topic-navigation-top')),
          const Offset(-1200, 0),
        );
        await _settle(tester);
        await tester.tap(
          find.byKey(const ValueKey('topic-navigation-item-88')),
        );
        await _settle(tester);
        expect(
          requests.lastWhere(
            (request) => request['@type'] == 'getForumTopicHistory',
          )['forum_topic_id'],
          88,
        );
        await tester.tap(find.byKey(const ValueKey('topic-header-chat-mode')));
        await _settle(tester);
        expect(find.byType(ChatView), findsOneWidget);
        expect(
          find.byKey(const ValueKey('topic-navigation-top')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _disposeShell(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'channel-feed topic can switch modes and return without replacing the app route',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _setSurfaceSize(tester, const Size(1180, 820));
        await _pumpMainShell(
          tester,
          reducedMotion: true,
          showChannelsTab: true,
        );
        await tester.tap(
          find.byKey(const ValueKey('desktop-navigation-item-1')),
        );
        await _settle(tester);
        tester
            .widget<TopicChannelsView>(find.byType(TopicChannelsView))
            .onOpenDetail!(
          TopicChatView(
            chat: _chat(),
            initialThreadId: 77,
            initialMessageId: 70,
            showBackButton: false,
          ),
        );
        await _settle(tester);
        final sidebar = tester.getRect(find.byType(TopicChannelsView));
        final navigator = Navigator.of(
          tester.element(find.byType(TopicChatView)),
          rootNavigator: true,
        );
        await tester.tap(find.byKey(const ValueKey('topic-header-chat-mode')));
        await _settle(tester);
        expect(find.byType(ChatView), findsOneWidget);
        expect(navigator.canPop(), isFalse);
        expect(tester.getRect(find.byType(TopicChannelsView)), sidebar);
        await tester.tap(find.byKey(const ValueKey('chatHeaderSearch')));
        await tester.pump();
        await navigator.maybePop();
        await _settle(tester);
        expect(find.byType(ChatView), findsOneWidget);
        tester.widget<ChatView>(find.byType(ChatView)).onBack!();
        await _settle(tester);
        expect(find.byType(TopicChatView), findsOneWidget);
        expect(tester.getRect(find.byType(TopicChannelsView)), sidebar);
        expect(tester.takeException(), isNull);
        await _disposeShell(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('failed topic loading leaves navigation usable', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      failTopics = true;
      await _setSurfaceSize(tester, const Size(1180, 820));
      await _pumpMainShell(tester, reducedMotion: true);
      ChatDeepLinkController.shared.openChat(chatId: -42, title: 'Forum');
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('chatHeaderTopics')));
      await _settle(tester);
      expect(find.byType(TopicChatView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('topic-header-back')));
      await _settle(tester);
      expect(find.byType(ChatView), findsOneWidget);
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
Map<String, dynamic> _supergroup(bool tabs) => {
  '@type': 'supergroup',
  'id': 42,
  'is_forum': true,
  'has_forum_tabs': tabs,
  'status': {'@type': 'chatMemberStatusMember'},
};
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
Map<String, dynamic> _response(
  Map<String, dynamic> request, {
  required bool hasForumTabs,
}) => switch (request['@type']) {
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
  'getSupergroup' => _supergroup(hasForumTabs),
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
        },
    ],
  },
  'getForumTopicHistory' || 'getMessageThreadHistory' => {
    '@type': 'messages',
    'messages': [
      _message(
        70 - ((request['forum_topic_id'] ?? request['message_id']) as int) + 77,
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

class _MainShellHarness {
  const _MainShellHarness({required this.drawer});

  final dc.DrawerController drawer;
}

Future<_MainShellHarness> _pumpMainShell(
  WidgetTester tester, {
  bool reducedMotion = false,
  bool showChannelsTab = false,
  List<NavigatorObserver> navigatorObservers = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    'showChannelsTab': showChannelsTab,
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
        navigatorObservers: navigatorObservers,
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
  return _MainShellHarness(drawer: drawer);
}

Future<void> _disposeShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // Chat-list cache warming uses delayed no-op guards after disposal.
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
