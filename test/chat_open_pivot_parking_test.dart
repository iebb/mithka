// Regression test for the "opening a previously visited chat freezes the
// entrance animation for seconds" stall.
//
// A ChatSessionCache restore can seed the view model with thousands of cached
// messages in one notification. The transcript used to resolve its initial
// pivot at the OLDEST loaded message, so the entire restored window lived in
// the after-center sliver. The open-at-bottom jump (jumpTo(maxScrollExtent))
// then had to build and lay out every bubble of that window in a single
// entrance frame — a variable-extent SliverList can only reach a scroll offset
// by laying out every row before it. That one frame blocked the platform
// thread for 5–10+ seconds on-device.
//
// With the fix the initial pivot parks everything older than a newest-side
// tail (≈2 viewports) in the before-center sliver: the bottom jump
// materializes only the tail, scrolling up reveals parked rows lazily, and
// the scroll geometry proves it deterministically:
//   - master: maxScrollExtent ≈ the whole window's extent (111k px here),
//     minScrollExtent ≈ 0 — everything after center.
//   - fixed: maxScrollExtent bounded to a few viewports; a large negative
//     minScrollExtent — most rows parked before center.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatId = 41;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          switch (request['@type']) {
            case 'getChat':
              return {
                '@type': 'chat',
                'id': _chatId,
                'type': {'@type': 'chatTypeSupergroup', 'supergroup_id': 410},
                'title': 'Chat',
                'unread_count': 0,
              };
            case 'getSupergroup':
              return {
                '@type': 'supergroup',
                'id': 410,
                'member_count': 10,
                'status': {'@type': 'chatMemberStatusMember'},
              };
            case 'getChatHistory':
              // Newest→oldest, non-positive offset only.
              if ((request['offset'] as num? ?? 0) > 0) {
                return {'@type': 'messages', 'messages': []};
              }
              return {
                '@type': 'messages',
                'messages': [
                  for (var i = 0; i < 40; i++)
                    {
                      '@type': 'message',
                      'id': 100000 - i,
                      'chat_id': _chatId,
                      'date': 1700000000 + i,
                      'is_outgoing': false,
                      'content': {
                        '@type': 'messageText',
                        'text': {
                          '@type': 'formattedText',
                          'text': 'm ${100000 - i}',
                        },
                      },
                    },
                ],
              };
            default:
              return {'@type': 'ok'};
          }
        },
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
  });

  testWidgets(
    'restoring a large cached transcript parks older rows before center',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      // Seed the transcript cache exactly like a previously-visited chat: one
      // big snapshot restored to the view model in a single notification.
      // `sessionMessages` is the merged chronological window: oldest→newest.
      const restoredCount = 2000;
      final restoredMessages = List<ChatMessage>.generate(
        restoredCount,
        (i) => ChatMessage(
          id: 98001 + i,
          isOutgoing: false,
          text: 'm ${98001 + i}',
          date: 1700000000 + i,
          chatId: _chatId,
        ),
      );
      clearChatMemoryCaches();
      seedChatSessionCacheForTesting(
        accountSlot: 0,
        chatId: _chatId,
        messages: restoredMessages,
        anchoredHistory: false,
      );

      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      final accounts = AccountStore(prefs);
      final auth = AuthManager();
      final translation = TranslationController(prefs);
      addTearDown(theme.dispose);
      addTearDown(accounts.dispose);
      addTearDown(auth.dispose);
      addTearDown(translation.dispose);
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
          ],
          child: MaterialApp(
            theme: ThemeData(
              brightness: Brightness.light,
              extensions: [AppColors.light],
              platform: TargetPlatform.iOS,
            ),
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ChatView(chatId: _chatId, title: 'Chat'),
          ),
        ),
      );
      await tester.pump();
      // Let the restore path finish: initial layout, bottom jump, correction
      // passes, and the resolver/hydrate notifications settle.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(seconds: 2));

      final scrollable = find
          .descendant(
            of: find.byType(ChatView),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;

      // The newest-side arm after center must be bounded to a few viewports,
      // not the whole restored window: the open-at-bottom jump only has to
      // materialize that tail.
      expect(
        position.maxScrollExtent,
        lessThan(position.viewportDimension * 6),
        reason:
            'the whole restored window ended up after the center sliver; '
            'opening at the bottom materializes every row in one frame '
            '(maxScrollExtent=${position.maxScrollExtent})',
      );
      // Most of the restored window must be parked BEFORE center, visible as
      // a large negative min scroll extent (rows above the center grow
      // downward as they are revealed).
      expect(
        position.minScrollExtent,
        lessThan(-position.viewportDimension * 8),
        reason:
            'older restored rows were not parked before the center sliver '
            '(minScrollExtent=${position.minScrollExtent})',
      );
      // And the entrance still lands at the newest edge.
      expect(position.pixels, position.maxScrollExtent);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
    },
  );
}
