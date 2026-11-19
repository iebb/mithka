import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/media_spoiler.dart';
import 'package:mithka/chat/messages/message_bubble.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 1,
        accountUserId: 1,
        query: (request) async => <String, dynamic>{'@type': 'ok'},
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  tearDownAll(() => updates.close());

  for (final grouped in [true, false]) {
    testWidgets('a captioned tall screenshot letterboxes without a filter '
        'layer (grouped captions: $grouped)', (tester) async {
      SharedPreferences.setMockInitialValues({'groupImageMessages': grouped});
      final theme = ThemeController(await SharedPreferences.getInstance());
      addTearDown(theme.dispose);
      tester.view
        ..physicalSize = const Size(1260, 2736)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final message =
          ChatMessage(
              id: 45123,
              isOutgoing: false,
              text: '谷歌钱包新增支付宝 Plus「旅行二维码」支付',
              date: 1,
              contentType: 'messagePhoto',
              image: TdFileRef(id: 9, thumbnail: TdFileRef(id: 10)),
              imageWidth: 1179,
              imageHeight: 6000,
              replyToMessageId: 45000,
              replyToDate: 1,
            )
            ..replyToSender = '在花科技圈'
            ..replyToPreview = 'PayPal';
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  MessageBubble(
                    message: message,
                    peerTitle: '在花科技圈',
                    isGroup: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final bubble = find.byType(MessageBubble);
      // The letterbox really is in play: the photo is narrower than its frame.
      final images = tester
          .widgetList<TDImage>(
            find.descendant(of: bubble, matching: find.byType(TDImage)),
          )
          .toList();
      expect(images.map((image) => image.photo?.id), containsAll([9, 10]));
      // An image-filter layer inside the bubble's clip drew the photo and its
      // caption shifted out of the bubble on iOS, leaving it blank.
      expect(
        find.descendant(of: bubble, matching: find.byType(ImageFiltered)),
        findsNothing,
      );
      final frame = tester.getRect(
        find.descendant(of: bubble, matching: find.byType(MessageMediaSpoiler)),
      );
      final photo = tester.getRect(
        find.byWidgetPredicate((w) => w is TDImage && w.photo?.id == 9),
      );
      if (grouped) {
        // Like Telegram, the caption widens the bubble past the narrow photo,
        // which stays centred over the side fill.
        expect(frame.width, greaterThan(200));
        expect(photo.center.dx, moreOrLessEquals(frame.center.dx));
      } else {
        // Media shown apart from its caption keeps the minimum preview box.
        expect(frame.width, lessThanOrEqualTo(100));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      // Outlast the file loader's longest download wait.
      await tester.pump(const Duration(minutes: 11));
    });
  }
}
