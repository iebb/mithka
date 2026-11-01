import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/image_media_album_bubble.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chat/message_direction.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChatMessage _channelMessage(int id, {bool media = false}) => ChatMessage(
  id: id,
  isOutgoing: true,
  senderId: -100123,
  senderIsChat: true,
  senderName: 'Channel',
  text: media ? '' : 'Channel text',
  date: id,
  contentType: media ? 'messagePhoto' : 'messageText',
  mediaAlbumId: media ? 91 : 0,
  image: media ? TdFileRef(id: id) : null,
  imageWidth: media ? 320 : 0,
  imageHeight: media ? 240 : 0,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues({});
  final theme = ThemeController(await SharedPreferences.getInstance());
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  test('channel-sent posts use sender identity for transcript direction', () {
    final channelPost = _channelMessage(1);
    expect(isOutgoingTranscriptMessage(channelPost, 42), isFalse);
    expect(isOutgoingTranscriptMessage(channelPost, null), isTrue);

    channelPost.senderId = 42;
    expect(isOutgoingTranscriptMessage(channelPost, 42), isTrue);
  });

  testWidgets('channel text and photo album both appear on the left', (
    tester,
  ) async {
    await _pump(
      tester,
      Column(
        children: [
          MessageBubble(
            message: _channelMessage(1),
            peerTitle: 'Channel',
            isGroup: true,
            meId: 42,
          ),
          ImageMediaAlbumBubble(
            messages: [
              _channelMessage(2, media: true),
              _channelMessage(3, media: true),
            ],
            peerTitle: 'Channel',
            isGroup: true,
            meId: 42,
            imageBuilder: (_, message, _, _) => ColoredBox(
              key: ValueKey('album-image-${message.id}'),
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );

    final avatars = find.byType(PhotoAvatar);
    expect(avatars, findsNWidgets(2));
    expect(tester.getTopLeft(avatars.at(0)).dx, lessThan(100));
    expect(
      tester.getTopLeft(avatars.at(1)).dx,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('album-image-2'))).dx,
      ),
    );
  });

  testWidgets('a user-sent photo album still appears on the right', (
    tester,
  ) async {
    final first = _channelMessage(2, media: true)
      ..senderId = 42
      ..senderIsChat = false;
    final second = _channelMessage(3, media: true)
      ..senderId = 42
      ..senderIsChat = false;
    await _pump(
      tester,
      ImageMediaAlbumBubble(
        messages: [first, second],
        peerTitle: 'Chat',
        isGroup: false,
        meId: 42,
        imageBuilder: (_, message, _, _) => ColoredBox(
          key: ValueKey('album-image-${message.id}'),
          color: Colors.blue,
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.byType(PhotoAvatar)).dx,
      greaterThan(
        tester.getTopLeft(find.byKey(const ValueKey('album-image-2'))).dx,
      ),
    );
  });
}
