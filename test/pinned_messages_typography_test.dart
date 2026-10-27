import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/pinned_messages_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  testWidgets('pinned media caption calibrates touch leading only', (
    tester,
  ) async {
    final updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => request['@type'] == 'searchChatMessages'
            ? {
                '@type': 'foundChatMessages',
                'messages': [
                  {
                    '@type': 'message',
                    'id': 1,
                    'chat_id': 42,
                    'date': 1,
                    'content': {
                      '@type': 'messagePhoto',
                      'caption': {
                        '@type': 'formattedText',
                        'text': 'Pinned media caption',
                        'entities': [],
                      },
                      'photo': {
                        'sizes': [
                          {
                            '@type': 'photoSize',
                            'type': 'x',
                            'width': 320,
                            'height': 200,
                            'photo': {'@type': 'file', 'id': 0, 'size': 0},
                          },
                        ],
                      },
                    },
                  },
                  {
                    '@type': 'message',
                    'id': 2,
                    'chat_id': 42,
                    'date': 1,
                    'content': {
                      '@type': 'messageText',
                      'text': {
                        '@type': 'formattedText',
                        'text': 'Pinned plain text',
                        'entities': [],
                      },
                    },
                  },
                ],
              }
            : {'@type': 'ok'},
        send: (_) async {},
        updates: updates.stream,
      ),
    );
    addTearDown(() async {
      debugDefaultTargetPlatformOverride = null;
      await TdClient.shared.closeProxy();
      await updates.close();
    });
    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      final touch =
          platform == TargetPlatform.iOS || platform == TargetPlatform.android;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [AppLocalizations.delegate],
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: PinnedMessagesView(
              key: ValueKey(platform),
              chatId: 42,
              title: 'Fictional',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final caption = tester.widget<Text>(find.text('Pinned media caption'));
      expect(caption.style?.fontSize, 17);
      expect(caption.style?.height, touch ? 22 / 17 : 1.3);
      expect(
        caption.style?.leadingDistribution,
        touch ? TextLeadingDistribution.even : null,
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.text('Pinned media caption'),
          matching: find.byType(RichText),
        ),
      );
      expect(paragraph.textScaler.scale(17), closeTo(27.2, .0001));
      final plain = tester.widget<Text>(find.text('Pinned plain text'));
      expect(plain.style?.fontSize, 18);
      expect(plain.style?.height, 1.3);
      expect(tester.takeException(), isNull);
    }
    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 4));
  });
}
