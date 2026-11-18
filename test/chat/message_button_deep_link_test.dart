import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Regression: a group gate bot message (first follow the channel, then finish
// the captcha with the bot) whose inline URL buttons must open the channel /
// bot chat. Tapping the button must produce a deep link the shell can place —
// the ChatView state's context sits ABOVE InternalChatLinkScope, so the link
// resolves with no source account; with more than one signed-in account the
// shell drops it and both taps die silently.
const groupChatId = -1001234;
const channelUrl = 'https://t.me/announce_channel';
const botUrl = 'https://t.me/verify_gate_bot?start=verify';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <Map<String, dynamic>>[];
  late StreamController<Map<String, dynamic>> updates;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(Map<String, dynamic>.from(request));
          return switch (request['@type']) {
            'getChat' when request['chat_id'] == groupChatId => {
              '@type': 'chat',
              'id': groupChatId,
              'title': 'Gate group',
              'type': {
                '@type': 'chatTypeSupergroup',
                'supergroup_id': 1234,
                'is_channel': false,
              },
              'permissions': {
                '@type': 'chatPermissions',
                'can_send_basic_messages': true,
              },
              'last_read_inbox_message_id': 90,
            },
            'getChat' => {
              '@type': 'chat',
              'id': request['chat_id'],
              'title': 'Announcements',
              'type': {
                '@type': 'chatTypeSupergroup',
                'supergroup_id': 9999,
                'is_channel': true,
              },
            },
            'getSupergroup' => {
              '@type': 'supergroup',
              'id': 1234,
              'is_channel': false,
              'status': {'@type': 'chatMemberStatusMember'},
            },
            'getSupergroupFullInfo' => {
              '@type': 'supergroupFullInfo',
              'description': '',
              'member_count': 3,
            },
            'getUser' || 'getMe' => {
              '@type': 'user',
              'id': request['user_id'] ?? 1,
              'first_name': 'Test',
              'type': {'@type': 'userTypeRegular'},
            },
            'getChatHistory' => {
              '@type': 'messages',
              'total_count': 1,
              'messages': [_gateMessage()],
            },
            'getInternalLinkType' => switch (request['link']) {
              channelUrl => {
                '@type': 'internalLinkTypePublicChat',
                'chat_username': 'announce_channel',
              },
              botUrl => {
                '@type': 'internalLinkTypeBotStart',
                'bot_username': 'verify_gate_bot',
                'start_parameter': 'verify',
                'autostart': true,
              },
              _ => {'@type': 'internalLinkTypeUnknownDeepLink'},
            },
            'searchPublicChat' => {
              '@type': 'chat',
              'id': request['username'] == 'verify_gate_bot' ? 6001 : -1009999,
              'title': request['username'] == 'verify_gate_bot'
                  ? 'Verify gate bot'
                  : 'Announcements',
              'type': {'@type': 'chatTypePrivate', 'user_id': 6002},
            },
            'getOption' => {'@type': 'optionValueInteger', 'value': '1024'},
            'getCountries' => {'@type': 'countries', 'countries': const []},
            'getCurrentState' => {'@type': 'ok'},
            'getBotApiAccountInfo' => {'@type': 'ok'},
            'sendBotStartMessage' => {'@type': 'message'},
            _ => {'@type': 'ok'},
          };
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
    updates.add({
      '@type': 'updateConnectionState',
      'state': {'@type': 'connectionStateReady'},
    });
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });
  setUp(() {
    requests.clear();
    ChatDeepLinkController.shared.consumePending();
    SharedPreferences.setMockInitialValues(const {});
  });

  for (final entry in [
    ('关注频道 (channel URL)', '关注频道', channelUrl, -1009999),
    ('完成人机验证 (bot start)', '完成人机验证', botUrl, 6001),
  ]) {
    testWidgets('two accounts: ${entry.$1} still opens the chat', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      final auth = AuthManager();
      final translation = TranslationController(prefs);
      final drawer = dc.DrawerController();
      // Two signed-in accounts: the deep link names no account, so the shell
      // cannot know which one the tap came from.
      final accounts = _accountStore(prefs, slots: const [0, 7]);
      final deepLinks = ChatDeepLinkController.shared;
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
            home: const ChatView(chatId: groupChatId, title: 'Gate group'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(ValueKey('message-button-${entry.$2}')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      final pendingDebug = ChatDeepLinkController.shared.consumePending();

      // No shell host is mounted in this harness, so the controller keeps the
      // request pending. The regression is the request's identity: it must
      // name the tap's target chat AND the owning account slot, which is what
      // lets a multi-account shell place it instead of dropping it.
      expect(pendingDebug?.chatId, entry.$4);
      expect(pendingDebug?.accountSlot, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}

AccountStore _accountStore(
  SharedPreferences prefs, {
  required List<int> slots,
}) {
  // Two cached signed-in summaries, the same cache shape production writes —
  // resolveDeepLinkAccountSlot then sees 2 accounts and no requested slot.
  prefs.setString(
    'drachma.accountSummaries',
    '[{"slot":0,"userId":1,"name":"A","phone":"+1"},'
        '{"slot":7,"userId":2,"name":"B","phone":"+2"}]',
  );
  return AccountStore(prefs);
}

Map<String, dynamic> _gateMessage() => {
  '@type': 'message',
  'id': 90,
  'chat_id': groupChatId,
  'date': 1785862260,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 555},
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': '请先关注频道，再完成人机验证',
      'entities': <Object>[],
    },
  },
  'reply_markup': {
    '@type': 'replyMarkupInlineKeyboard',
    'rows': [
      [
        {
          '@type': 'inlineKeyboardButton',
          'text': '关注频道',
          'type': {'@type': 'inlineKeyboardButtonTypeUrl', 'url': channelUrl},
        },
      ],
      [
        {
          '@type': 'inlineKeyboardButton',
          'text': '完成人机验证',
          'type': {'@type': 'inlineKeyboardButtonTypeUrl', 'url': botUrl},
        },
      ],
    ],
  },
};
