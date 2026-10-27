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

// Forum chats always open as ordinary chat transcripts; the old topic
// feed surface is gone. Wide split shells take that transcript's topic list
// and paint it over the chat list column the way Telegram iOS does; phones
// pick topics from the header sheet instead.

void main() {
  late StreamController<Map<String, dynamic>> updates;
  final requests = <Map<String, dynamic>>[];
  // When set, the next getChat blocks until completed: the in-flight
  // metadata state a fresh pane opens with.
  Completer<void>? gateGetChat;
  setUpAll(() async {
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
          if (request['@type'] == 'getChat' && gateGetChat != null) {
            final gate = gateGetChat;
            gateGetChat = null;
            await gate!.future;
          }
          return _response(request);
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
    // Real TDLib reports the connection state as soon as a client exists and
    // then only when it changes; the chat-list header reads that report rather
    // than asking, so the fake has to say it once here.
    updates.add({
      '@type': 'updateConnectionState',
      'state': {'@type': 'connectionStateReady'},
    });
    await Future<void>.delayed(Duration.zero);
  });
  setUp(() {
    requests.clear();
    clearChatMemoryCaches();
    ForumTopicIndex.shared.clear();
    topicCount = 12;
    gateGetChat = null;
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets('tablet forum chat overlays its topic list on the chat list', (
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

      // No topic feed surface: the chat transcript owns the topic data and the
      // shell paints it over the chat list column, exactly filling it.
      expect(find.byType(TopicChatView), findsNothing);
      expect(find.byType(ChatView), findsOneWidget);
      final sidebar = tester.getRect(find.byType(ChatListView));
      final list = tester.getRect(
        find.byKey(const ValueKey('topic-navigation-left')),
      );
      expect(list.left, sidebar.left);
      expect(list.right, sidebar.right);
      expect(list.top, sidebar.top);
      // The overlay's chevron steps aside to reveal the chat list beneath.
      expect(find.byKey(const ValueKey('topic-list-back')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topic-list-back')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('topic-navigation-left')), findsNothing);
      // The chat header brings the overlay back — no picker sheet needed.
      await tester.tap(find.byKey(const ValueKey('chatHeaderTopics')));
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('topic-navigation-left')),
        findsOneWidget,
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

  testWidgets('overlay rows switch topic transcripts without a route', (
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
      // Topic rows share the chat list's row geometry, so the last topic can
      // start below the fold, where the lazy list has not built it yet.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('topic-navigation-item-88')),
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('topic-navigation-left')),
          matching: find.byType(Scrollable),
        ),
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

  testWidgets('switching topics keeps the overlay scroll position', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      topicCount = 40;
      await _setSurfaceSize(tester, const Size(1180, 820));
      await _pumpMainShell(tester);
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await _settle(tester);

      ScrollableState overlayList() => tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('topic-navigation-left')),
          matching: find.byType(Scrollable),
        ),
      );

      // Scroll the overlay well past its top and pick a row from there.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('topic-navigation-item-95')),
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('topic-navigation-left')),
          matching: find.byType(Scrollable),
        ),
      );
      await _settle(tester);
      final before = overlayList().position.pixels;
      expect(before, greaterThan(300));

      await tester.tap(find.byKey(const ValueKey('topic-navigation-item-95')));
      await _settle(tester);
      expect(tester.widget<ChatView>(find.byType(ChatView)).forumTopicId, 95);
      // The shell owns the pane, so swapping the transcript underneath
      // keeps the overlay's scroll exactly where the user left it.
      expect(overlayList().position.pixels, before);
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('topic switch keeps the overlay while its getChat is in flight', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      topicCount = 12;
      await _setSurfaceSize(tester, const Size(1180, 820));
      await _pumpMainShell(tester);
      // The first visit fills the shared topic index.
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('topic-navigation-left')),
        findsOneWidget,
      );

      // A topic transcript opens a fresh pane whose own getChat is still on
      // the wire; its view model cannot know isForum yet. The shared index
      // keeps the list overlaid so no in-pane rail flashes during the wait.
      final gate = Completer<void>();
      gateGetChat = gate;
      await tester.tap(find.byKey(const ValueKey('topic-navigation-item-78')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('topic-list-back')),
        findsOneWidget,
        reason: 'the overlay owns the topic list, not an in-pane rail',
      );
      expect(
        find.byKey(const ValueKey('topic-navigation-left')),
        findsOneWidget,
        reason: 'exactly one topic list exists while metadata loads',
      );

      gate.complete();
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

  testWidgets('overlay re-show keeps the scroll position', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      topicCount = 40;
      await _setSurfaceSize(tester, const Size(1180, 820));
      await _pumpMainShell(tester);
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await _settle(tester);

      ScrollableState overlayList() => tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('topic-navigation-left')),
          matching: find.byType(Scrollable),
        ),
      );

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('topic-navigation-item-95')),
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('topic-navigation-left')),
          matching: find.byType(Scrollable),
        ),
      );
      await _settle(tester);
      final before = overlayList().position.pixels;
      expect(before, greaterThan(300));

      // Dismiss to the chat list, then bring the overlay back: the host owns
      // the offset, so the list re-enters where the user left it.
      await tester.tap(find.byKey(const ValueKey('topic-list-back')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('topic-navigation-left')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('chatHeaderTopics')));
      await tester.pump();
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('topic-navigation-left')),
        findsOneWidget,
      );
      expect(overlayList().position.pixels, before);
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

var topicCount = 12;

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
      'getForumTopics' => {
        '@type': 'forumTopics',
        'topics': [
          for (var index = 0; index < topicCount; index++)
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
