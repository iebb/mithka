import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/content_size.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  L10nFixtures.load().install();

  const chatId = 4242;
  var title = 'DD Liriku';
  late ThemeController theme;
  late TranslationController translation;

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getChat' => {
            '@type': 'chat',
            'id': chatId,
            'title': title,
            'type': {'@type': 'chatTypePrivate', 'user_id': 2},
            'permissions': {'can_send_basic_messages': true},
          },
          'getUser' => {
            '@type': 'user',
            'id': 2,
            'first_name': title,
            'type': {'@type': 'userTypeRegular'},
            'status': {'@type': 'userStatusOnline', 'expires': 2147483647},
          },
          'getMe' => {
            '@type': 'user',
            'id': 1,
            'first_name': 'Me',
            'type': {'@type': 'userTypeRegular'},
          },
          'getChatHistory' => {
            '@type': 'messages',
            'total_count': 0,
            'messages': <Map<String, dynamic>>[],
          },
          'getOption' => {'@type': 'optionValueBoolean', 'value': false},
          _ => {'@type': 'ok'},
        },
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);

  setUp(() async {
    clearChatMemoryCaches();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    theme = ThemeController(preferences);
    translation = TranslationController(preferences);
  });
  tearDown(() {
    clearChatMemoryCaches();
    theme.dispose();
    translation.dispose();
  });

  for (final scale in [1.0, 2.5, 3.2]) {
    for (final longTitle in [false, true]) {
      testWidgets('chat header fits scale $scale, long title: $longTitle', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          title = longTitle
              ? 'DD Liriku and a very long conversation title that must ellipsize'
              : 'DD Liriku';
          // Narrow portrait viewport, also constrained by an open keyboard.
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          var backTaps = 0;
          var infoTaps = 0;

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeController>.value(value: theme),
                ChangeNotifierProvider<TranslationController>.value(
                  value: translation,
                ),
              ],
              child: MaterialApp(
                theme: ThemeData(
                  extensions: [AppColors.light],
                  platform: TargetPlatform.iOS,
                ),
                locale: const Locale('en'),
                localizationsDelegates: const [AppLocalizations.delegate],
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    viewInsets: const EdgeInsets.only(bottom: 300),
                  ),
                  child: ContentSizeRoot(
                    appScale: 1.6,
                    child: ChatView(
                      chatId: chatId,
                      title: title,
                      onBack: () => backTaps++,
                      onInfoPressed: () => infoTaps++,
                    ),
                  ),
                ),
              ),
            ),
          );
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 120));
          }

          final toolbar = find.byKey(const ValueKey('chatHeaderToolbar'));
          final titleFinder = find.descendant(
            of: toolbar,
            matching: find.text(title),
          );
          final status = find.descendant(
            of: toolbar,
            matching: find.text(AppStrings.t(AppStringKeys.presenceOnline)),
          );
          expect(titleFinder, findsOneWidget);
          expect(status, findsOneWidget);
          expect(tester.takeException(), isNull);
          final headerRect = tester.getRect(toolbar);
          expect(headerRect.height, greaterThanOrEqualTo(48));
          if (scale == 1) {
            expect(headerRect.height, lessThanOrEqualTo(56));
          } else {
            expect(headerRect.height, greaterThan(56));
          }
          expect(
            headerRect.bottom - tester.getRect(status).bottom,
            greaterThanOrEqualTo(8),
          );
          expect(
            tester.getRect(titleFinder).top,
            greaterThanOrEqualTo(headerRect.top),
          );
          final paragraph = tester.renderObject<RenderParagraph>(titleFinder);
          expect(paragraph.textScaler.scale(16), closeTo(16 * scale, 0.001));
          expect(paragraph.maxLines, 1);
          expect(paragraph.overflow, TextOverflow.ellipsis);

          for (final key in [
            'chatHeaderBack',
            'chatHeaderSearch',
            'chatHeaderInfo',
          ]) {
            final action = find.byKey(ValueKey(key));
            expect(action, findsOneWidget);
            expect(tester.getSize(action).width, greaterThanOrEqualTo(44));
            expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
            expect(headerRect.contains(tester.getCenter(action)), isTrue);
          }
          await tester.tap(find.byKey(const ValueKey('chatHeaderInfo')));
          expect(infoTaps, 1);
          await tester.tap(find.byKey(const ValueKey('chatHeaderBack')));
          expect(backTaps, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 6));
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
