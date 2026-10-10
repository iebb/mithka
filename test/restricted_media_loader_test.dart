import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/sensitive_content_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _notice =
    "This message can't be displayed because it violated Telegram's Terms of Service.";

/// A restricted photo whose retained file is NOT local, so rendering it can
/// only go through the media loader's TDLib requests.
ChatMessage _restrictedRemotePhoto(int id) => TDParse.message({
  '@type': 'message',
  'id': id,
  'date': 1,
  'content': {
    '@type': 'messagePhoto',
    'photo': {
      '@type': 'photo',
      'sizes': [
        {
          '@type': 'photoSize',
          'type': 'x',
          'width': 800,
          'height': 600,
          'photo': {
            '@type': 'file',
            'id': 7000 + id,
            'size': 100,
            'local': {
              '@type': 'localFile',
              'path': '',
              'is_downloading_completed': false,
            },
            'remote': {'@type': 'remoteFile', 'id': 'remote-$id'},
          },
        },
      ],
    },
    'caption': {'@type': 'formattedText', 'text': ''},
  },
  'restriction_info': {
    '@type': 'restrictionInfo',
    'reason': 'terms',
    'restriction_reason': _notice,
  },
})!;

void main() {
  // Every TDLib request in this file is answered by the recording proxy; the
  // app process is never started.
  final loaderRequests = <Map<String, dynamic>>[];
  TdClient.shared.configureProxy(
    TdClientProxyTransport(
      accountSlot: 1,
      accountUserId: 1,
      query: (request) async {
        loaderRequests.add(request);
        switch (request['@type']) {
          case 'getFile':
            return {
              '@type': 'file',
              'id': request['file_id'],
              'size': 100,
              'local': {
                '@type': 'localFile',
                'path': '',
                'is_downloading_completed': false,
              },
              'remote': {'@type': 'remoteFile', 'id': 'remote'},
            };
          case 'downloadFile':
            return {
              '@type': 'file',
              'id': request['file_id'],
              'size': 100,
              'local': {
                '@type': 'localFile',
                'path': '',
                'is_downloading_completed': false,
                'is_downloading_active': true,
              },
              'remote': {'@type': 'remoteFile', 'id': 'remote'},
            };
          default:
            return {'@type': 'ok'};
        }
      },
      send: (_) async {},
      updates: const Stream<Map<String, dynamic>>.empty(),
    ),
  );

  Future<(ThemeController, SensitiveContentController)> pump(
    WidgetTester tester, {
    required ChatMessage message,
    required bool autoReveal,
    required List<Map<String, dynamic>> controllerRequests,
  }) async {
    SharedPreferences.setMockInitialValues({
      'autoRevealRestrictedMedia': autoReveal,
    });
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    final controller = SensitiveContentController.forTesting(
      query: (request) async {
        controllerRequests.add(request);
        return {'@type': 'ok'};
      },
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageBubble(
              message: message,
              peerTitle: 'Test',
              isGroup: false,
              sensitiveContentController: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (theme, controller);
  }

  List<String> loaderTypes() => [
    for (final request in loaderRequests) request['@type'] as String,
  ];

  testWidgets(
    'revealing retained media mounts the loader; the reveal itself sends nothing',
    (tester) async {
      final controllerRequests = <Map<String, dynamic>>[];
      final message = _restrictedRemotePhoto(1);
      expect(message.image, isNotNull);
      expect(message.image!.localPath, isNull);
      final (theme, controller) = await pump(
        tester,
        message: message,
        autoReveal: false,
        controllerRequests: controllerRequests,
      );
      addTearDown(theme.dispose);
      addTearDown(controller.dispose);

      // Masked: the restriction notice renders instead of the media, and no
      // loader traffic exists because nothing asked for the file.
      expect(find.byType(TDImage), findsNothing);
      expect(loaderTypes(), isEmpty);
      expect(controllerRequests, isEmpty);

      // The preference flips and the bubble reveals the retained photo: the
      // ordinary media loader mounts and issues its own getFile/downloadFile.
      theme.autoRevealRestrictedMedia = true;
      await tester.pump();
      await tester.pump();
      expect(find.byType(TDImage), findsOneWidget);
      expect(loaderTypes(), contains('downloadFile'));

      // The two channels stay separate: everything TDLib heard is the media
      // loader asking for the file; the reveal never wrote an account option.
      expect(
        loaderTypes().toSet(),
        everyElement(anyOf('getFile', 'downloadFile')),
      );
      expect(
        controllerRequests.where((request) => request['@type'] == 'setOption'),
        isEmpty,
      );

      // Let the bounded path waiter expire and its single recovery timer fire
      // so no fake timer is pending at teardown.
      await tester.pump(const Duration(seconds: 181));
      await tester.pump(const Duration(seconds: 16));
    },
  );
}
