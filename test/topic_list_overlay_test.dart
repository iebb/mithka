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
import 'package:mithka/channels/topic_chat_view.dart';
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

  testWidgets('tablet topic chat overlays its topic list on the chat list', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _setSurfaceSize(tester, const Size(1180, 820));
      await _pumpMainShell(tester);
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('chatHeaderTopics')));
      await _settle(tester);

      final sidebar = tester.getRect(find.byType(ChatListView));
      // The list covers the chat list column (tab bar included) instead of
      // carving a rail out of the conversation pane.
      final overlay = tester.getRect(
        find.byKey(const ValueKey('topic-navigation-left')),
      );
      expect(overlay.left, sidebar.left);
      expect(overlay.right, sidebar.right);
      expect(overlay.top, sidebar.top);
      expect(overlay.bottom, greaterThan(sidebar.bottom));
      expect(tester.getRect(find.byType(TopicChatView)).left, sidebar.right);
      expect(
        find.descendant(
          of: find.byType(TopicChatView),
          matching: find.byKey(const ValueKey('topic-navigation-left')),
        ),
        findsNothing,
      );
      // Unread counters stay round dots, never row-height strips.
      final badge = tester.getSize(
        find.byKey(const ValueKey('topic-navigation-unread-78')),
      );
      expect(badge.height, AppMetric.unreadBadgeMin);
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('overlay rows select topics and back reveals the chat list', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _setSurfaceSize(tester, const Size(1180, 820));
      await _pumpMainShell(tester);
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('chatHeaderTopics')));
      await _settle(tester);

      await tester.tap(find.byKey(const ValueKey('topic-navigation-item-88')));
      await _settle(tester);
      expect(
        requests.lastWhere(
          (request) => request['@type'] == 'getForumTopicHistory',
        )['forum_topic_id'],
        88,
      );
      expect(
        find.byKey(const ValueKey('topic-navigation-left')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('topic-list-back')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('topic-navigation-left')), findsNothing);
      expect(find.byType(TopicChatView), findsOneWidget);
      // The topic surface offers the list again from its header.
      await tester.tap(find.byKey(const ValueKey('topic-header-list')));
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('topic-navigation-left')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS topic overlay follows resizing and owner replacement', (
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
      await tester.tap(find.byKey(const ValueKey('chatHeaderTopics')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('topic-list-back')), findsOneWidget);
      expect(
        tester.getRect(find.byType(TopicChatView)).left,
        tester.getRect(find.byType(ChatListView)).right,
      );

      tester.view.physicalSize = const Size(500, 820);
      await _settle(tester);
      expect(find.byKey(const ValueKey('topic-list-back')), findsNothing);
      expect(find.byType(TopicChatView), findsOneWidget);

      tester.view.physicalSize = const Size(1180, 820);
      await _settle(tester);
      expect(find.byKey(const ValueKey('topic-list-back')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topic-header-chat-mode')));
      await _settle(tester);
      expect(find.byType(ChatView), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-list-back')), findsNothing);
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('phones keep the inline topic strip', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _setSurfaceSize(tester, const Size(390, 844));
      await _pumpMainShell(tester);
      ChatDeepLinkController.shared.openChat(chatId: -42, title: 'Forum');
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('chatHeaderTopics')));
      await _settle(tester);
      expect(find.byType(TopicChatView), findsOneWidget);
      expect(
        find.byKey(const ValueKey('topic-navigation-top')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('topic-navigation-left')), findsNothing);
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

Map<String, dynamic> _message(int id) => <String, dynamic>{
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
              'unread_count': index == 1 ? 12 : 0,
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
}) async {
  SharedPreferences.setMockInitialValues({
    'showChannelsTab': false,
    'forumTopicsAsGroupChat': false,
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
