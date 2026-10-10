//
//  forum_topic_chat_form_test.dart
//
//  Forum/topic groups always open in the topic-chat (regular transcript)
//  form. The old "forum / channel feed" presentation and both switches that
//  selected it — the appearance toggle and the persisted topicGroup display
//  mode — are gone, so this pins the invariant: no toggle exists, and a
//  forum chat opens as an ordinary ChatView transcript.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late StreamController<Map<String, dynamic>> updates;
  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => _response(request),
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });
  setUp(clearChatMemoryCaches);
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  // The toggle's absence is a compile-time property (the getter/setter and
  // the settings row no longer exist); the widget test below is the runtime
  // half: old persisted values cannot change which surface opens.

  testWidgets('a stale persisted toggle cannot change the opening form', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    try {
      // Both old keys present and "off" — the old code would have opened the
      // forum feed surface for this chat.
      SharedPreferences.setMockInitialValues({
        'forumTopicsAsGroupChat': false,
        'topicGroup.displayMode': 'channel',
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
            ChangeNotifierProvider<TranslationController>.value(
              value: translation,
            ),
            ChangeNotifierProvider<ChatDeepLinkController>.value(
              value: deepLinks,
            ),
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
                disableAnimations: true,
                textScaler: TextScaler.noScaling,
              ),
              child: child!,
            ),
            home: const MainSplitRootView(),
          ),
        ),
      );
      await tester.pump();
      tester.widget<ChatListView>(find.byType(ChatListView)).onChatSelected!(
        ChatListSelection.fromChat(_chat()),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 3),
      );

      // Chat form, always: an ordinary transcript opens and no topic feed
      // surface is ever constructed.
      expect(find.byType(ChatView), findsOneWidget);
      expect(find.byType(TopicChatView), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

ChatSummary _chat() => ChatSummary(
  id: -42,
  title: 'Forum',
  lastMessage: 'Latest',
  lastMessageId: 90,
  date: 0,
  unreadCount: 0,
  order: 1,
  isMuted: false,
  kind: ChatKind.group,
  isForum: true,
);

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
          {
            '@type': 'forumTopic',
            'info': {
              '@type': 'forumTopicInfo',
              'forum_topic_id': 77,
              'name': 'Topic 0',
            },
            'last_message': {
              '@type': 'message',
              'id': 70,
              'chat_id': -42,
              'date': 1,
              'content': {
                '@type': 'messageText',
                'text': {'@type': 'formattedText', 'text': 'Post 70'},
              },
            },
          },
        ],
      },
      'getChatHistory' => {'@type': 'messages', 'messages': const []},
      'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Test'},
      _ => {'@type': 'ok'},
    };
