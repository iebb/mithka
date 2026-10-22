//
//  topic_pinned_message_bar_test.dart
//
//  A forum topic transcript pins its topic-scoped pinned message: opening a
//  topic shows the bar, and switching topics reloads it for the new topic
//  instead of keeping the old one around.
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
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final requests = <Map<String, dynamic>>[];
  late StreamController<Map<String, dynamic>> updates;
  // When set, the fake pinned search returns nothing for the topic — the
  // 'unpinned elsewhere' state.
  var topicPinnedRemoved = false;
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
          return _response(request, topicPinnedRemoved);
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
    // Native TDLib supplies this pushed state; it cannot be queried.
    TdClient.shared.routeUpdateForTesting({
      '@type': 'updateConnectionState',
      '@client_id': 1,
      'state': {'@type': 'connectionStateReady'},
    });
  });
  setUp(() {
    requests.clear();
    clearChatMemoryCaches();
    topicPinnedRemoved = false;
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets('topic transcript shows the topic pinned message', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await _pumpMainShell(tester);
      await _settle(tester);

      ChatDeepLinkController.shared.openChat(chatId: -42, title: 'Forum');
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('chatHeaderTopics')));
      await _settle(tester);
      await tester.tap(find.text('Topic 1'));
      await _settle(tester);

      expect(tester.widget<ChatView>(find.byType(ChatView)).forumTopicId, 78);
      expect(find.text('Pinned in 78'), findsOneWidget);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('topic-to-topic switch keeps loading the pinned message', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 820);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await _pumpMainShell(tester);
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await _settle(tester);

      await tester.tap(find.byKey(const ValueKey('topic-navigation-item-78')));
      await _settle(tester);
      expect(find.text('Pinned in 78'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('topic-navigation-item-88')));
      await _settle(tester);
      expect(tester.widget<ChatView>(find.byType(ChatView)).forumTopicId, 88);
      expect(find.text('Pinned in 78'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('topic-navigation-item-78')));
      await _settle(tester);
      expect(tester.widget<ChatView>(find.byType(ChatView)).forumTopicId, 78);
      expect(find.text('Pinned in 78'), findsOneWidget);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('updateMessageIsPinned refreshes the topic pinned bar', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 820);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await _pumpMainShell(tester);
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await _settle(tester);

      await tester.tap(find.byKey(const ValueKey('topic-navigation-item-78')));
      await _settle(tester);
      expect(find.text('Pinned in 78'), findsOneWidget);

      // Someone pins a different message while the transcript is open: the
      // bar swaps to it without a transcript re-entry.
      topicPinnedRemoved = true;
      updates.add({
        '@type': 'updateMessageIsPinned',
        'chat_id': -42,
        'message_id': 61,
        'is_pinned': true,
      });
      await _settle(tester);
      expect(find.text('Pinned in 78'), findsNothing);
      expect(find.text('Pinned in 61'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('tablet topic transcript shows the topic pinned message', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 820);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await _pumpMainShell(tester);
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await _settle(tester);

      await tester.tap(find.byKey(const ValueKey('topic-navigation-item-78')));
      await _settle(tester);
      expect(tester.widget<ChatView>(find.byType(ChatView)).forumTopicId, 78);
      expect(find.text('Pinned in 78'), findsOneWidget);
      expect(find.text('Pinned General'), findsNothing);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // The pinned-message bar floats over the transcript; it is painted on the
  // composer's own surface colour so it reads as one family with the docked
  // panels, without a translucent card fill or a drop shadow.
  testWidgets('group pinned bar uses the solid composer surface', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 820);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await _pumpMainShell(tester);
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await _settle(tester);

      expect(find.text('Pinned General'), findsOneWidget);
      final container = tester.widget<Container>(
        find.byKey(const ValueKey('chatPinnedBar')),
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.light.inputBarBackground);
      expect(decoration.boxShadow ?? const <BoxShadow>[], isEmpty);
      expect(decoration.borderRadius, BorderRadius.circular(AppRadius.card));
      expect(
        tester.getSize(find.byKey(const ValueKey('chatPinnedBar'))).height,
        48,
      );
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

Map<String, dynamic> _message(int id, {String? text}) => <String, dynamic>{
  '@type': 'message',
  'id': id,
  'chat_id': -42,
  'date': id,
  'is_outgoing': true,
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': text ?? 'Post $id'},
  },
};

Map<String, dynamic> _response(
  Map<String, dynamic> request,
  bool topicPinnedRemoved,
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
    },
  },
  'getSupergroup' => {
    '@type': 'supergroup',
    'id': 42,
    'is_forum': true,
    'has_forum_tabs': false,
    'status': {'@type': 'chatMemberStatusMember'},
  },
  'getForumTopic' => {
    '@type': 'forumTopic',
    'info': {
      '@type': 'forumTopicInfo',
      'chat_id': -42,
      'forum_topic_id': request['forum_topic_id'],
      'name': 'Topic ${(request['forum_topic_id'] as int) - 77}',
    },
  },
  'getConnectionState' => {'@type': 'connectionStateReady'},
  'getForumTopics' => {
    '@type': 'forumTopics',
    'topics': [
      for (var index = 0; index < 40; index++)
        {
          '@type': 'forumTopic',
          'info': {
            '@type': 'forumTopicInfo',
            'chat_id': -42,
            'forum_topic_id': 77 + index,
            'name': 'Topic $index',
          },
          'last_message': _message(70 - index),
        },
    ],
  },
  'searchChatMessages'
      when (request['filter'] as Map?)?['@type'] ==
          'searchMessagesFilterPinned' =>
    {
      '@type': 'foundChatMessages',
      'total_count': 1,
      'messages': [
        if (request['topic_id'] == null)
          _message(50, text: 'Pinned General')
        else if (topicPinnedRemoved)
          _message(61, text: 'Pinned in 61')
        else
          _message(
            60,
            text: 'Pinned in ${(request['topic_id'] as Map)['forum_topic_id']}',
          ),
      ],
    },
  'getForumTopicHistory' || 'getMessageThreadHistory' => {
    '@type': 'messages',
    'messages': [_message(70)],
  },
  'getMessage' => _message(request['message_id'] as int),
  'getChatHistory' => {
    '@type': 'messages',
    'messages': [_message(70)],
  },
  'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Test'},
  _ => {'@type': 'ok'},
};

Future<void> _pumpMainShell(WidgetTester tester) async {
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
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: true, textScaler: TextScaler.noScaling),
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

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 3),
  );
}
