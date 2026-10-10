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

// Forum chats always open as ordinary chat transcripts now; the old topic
// feed surface and its overlay are gone. These tests pin what the split
// shells do instead: the topic rail lives inside the conversation pane.

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

  testWidgets('tablet forum chat keeps its topic rail inside the pane', (
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

      // No topic feed surface: the chat transcript carries the rail, inside
      // the conversation pane beside the chat list — never over it.
      expect(find.byType(TopicChatView), findsNothing);
      expect(find.byType(ChatView), findsOneWidget);
      final sidebar = tester.getRect(find.byType(ChatListView));
      final rail = tester.getRect(
        find.byKey(const ValueKey('topic-navigation-left')),
      );
      expect(rail.left, greaterThanOrEqualTo(sidebar.right));
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

  testWidgets('rail rows switch topic transcripts without pushing a route', (
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

      final navigator = Navigator.of(
        tester.element(find.byType(ChatView)),
        rootNavigator: true,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('topic-navigation-item-88')),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('topic-navigation-item-88')));
      await _settle(tester);
      expect(tester.widget<ChatView>(find.byType(ChatView)).forumTopicId, 88);
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
      expect(navigator.canPop(), isFalse);
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS forum rail follows resizing without losing the chat', (
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
      expect(
        find.byKey(const ValueKey('topic-navigation-left')),
        findsOneWidget,
      );

      // A desktop shell keeps the split layout at any width, so the rail
      // stays with the transcript instead of collapsing.
      tester.view.physicalSize = const Size(500, 820);
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('topic-navigation-left')),
        findsOneWidget,
      );
      expect(find.byType(ChatView), findsOneWidget);

      tester.view.physicalSize = const Size(1180, 820);
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('topic-navigation-left')),
        findsOneWidget,
      );
      expect(
        tester.widget<ChatView>(find.byType(ChatView)).forumTopicId,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('phones pick a topic from the header sheet', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _setSurfaceSize(tester, const Size(390, 844));
      await _pumpMainShell(tester);
      ChatDeepLinkController.shared.openChat(chatId: -42, title: 'Forum');
      await _settle(tester);
      expect(find.byType(ChatView), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-navigation-left')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('chatHeaderTopics')));
      await _settle(tester);
      expect(find.text('Topic 1'), findsOneWidget);
      await tester.tap(find.text('Topic 1'));
      await _settle(tester);
      expect(find.byType(TopicChatView), findsNothing);
      expect(tester.widget<ChatView>(find.byType(ChatView)).forumTopicId, 78);
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
