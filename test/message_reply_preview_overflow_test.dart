import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
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
        query: (request) async => switch (request['@type']) {
          'getCustomEmojiStickers' => <String, dynamic>{
            '@type': 'stickers',
            'stickers': const <Map<String, dynamic>>[],
          },
          _ => throw StateError('Unexpected TDLib request: $request'),
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  tearDownAll(() => updates.close());

  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  const longPreview =
      '🍎 iPhone 20 Pro 曝光：全固态按键、无开孔正面，'
      '还有更多细节需要展开阅读才能看到的第三行内容，'
      '以及继续延伸的第四行内容。';

  Future<RichText> pumpReplyPreview(
    WidgetTester tester,
    List<MessageTextEntity> entities,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final message =
        ChatMessage(
            id: 2,
            isOutgoing: false,
            text: '好',
            date: 1,
            contentType: 'messageText',
            replyToMessageId: 1,
            replyToDate: 1,
            replyToEntities: entities,
          )
          ..replyToSender = 'Channel'
          ..replyToPreview = longPreview;
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              peerTitle: 'Discussion',
              isGroup: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return tester
        .widgetList<RichText>(
          find.descendant(
            of: find.byKey(const ValueKey('messageReplyQuote')),
            matching: find.byType(RichText),
          ),
        )
        .firstWhere((text) => text.maxLines == 2);
  }

  testWidgets('a reply preview with inline custom emoji never fades', (
    tester,
  ) async {
    // The fade's save layer breaks when a resolved emoji composites, which
    // misplaced the rest of the bubble in the comments sheet.
    final preview = await pumpReplyPreview(tester, const [
      MessageTextEntity(
        offset: 0,
        length: 2,
        type: 'textEntityTypeCustomEmoji',
        customEmojiId: 5000,
      ),
    ]);
    expect(preview.overflow, TextOverflow.ellipsis);
  });

  testWidgets('a plain-text reply preview keeps its fade', (tester) async {
    final preview = await pumpReplyPreview(tester, const []);
    expect(preview.overflow, TextOverflow.fade);
  });
}
