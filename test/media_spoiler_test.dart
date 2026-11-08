import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/looping_video_view.dart';
import 'package:mithka/chat/media_spoiler.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/moments/moments_view.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChatMessage _message(
  int id, {
  String type = 'messagePhoto',
  bool spoiler = true,
}) => ChatMessage(
  id: id,
  chatId: 42,
  isOutgoing: false,
  text: '',
  date: 1,
  contentType: type,
  hasSpoiler: spoiler,
  image: TdFileRef(id: id + 100),
  imageWidth: 320,
  imageHeight: 240,
  video: type == 'messagePhoto' ? null : TdFileRef(id: id + 200),
  videoFileSize: 1000,
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
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 600),
              disableAnimations: true,
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('video stays unmounted behind its message spoiler', (
    tester,
  ) async {
    final message = _message(1, type: 'messageVideo');
    await _pump(
      tester,
      MessageBubble(message: message, peerTitle: 'Chat', isGroup: false),
    );
    expect(find.byType(MediaSpoiler), findsOneWidget);
    expect(find.byType(TDImage), findsNothing);
    expect(find.byType(LoopingVideoView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('gallery swipe and video queues cannot expose other spoilers', () {
    final selected = _message(1);
    final other = _message(2);
    final public = _message(3, spoiler: false);
    expect(
      [
        selected,
        other,
        public,
      ].where((m) => canPreviewMediaAlongside(m, selected)),
      [selected, public],
    );
    other.chatId = 99;
    final sameIdElsewhere = _message(1)..chatId = 99;
    expect(canPreviewMediaAlongside(sameIdElsewhere, selected), isFalse);
  });

  test('non-interactive quote and search previews omit spoiler images', () {
    final hidden = _message(1);
    expect(hidden.previewImage, isNull);
    hidden.hasSpoiler = false;
    expect(hidden.previewImage, same(hidden.image));
  });

  testWidgets('reveal resets for another message, file or account', (
    tester,
  ) async {
    final message = _message(7);
    var slot = 0;
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return SizedBox(
            width: 200,
            height: 160,
            child: MessageMediaSpoiler(
              message: message,
              accountSlot: slot,
              child: const Text('revealed'),
            ),
          );
        },
      ),
    );
    await tester.tap(find.byType(MediaSpoiler));
    await tester.pump();
    update(() {});
    await tester.pump();
    expect(find.text('revealed'), findsOneWidget);
    update(() => slot = 1);
    await tester.pump();
    expect(find.text('revealed'), findsNothing);
    await tester.tap(find.byType(MediaSpoiler));
    await tester.pump();
    update(() => message.image = TdFileRef(id: 999));
    await tester.pump();
    expect(find.text('revealed'), findsNothing);
    update(() => message.hasSpoiler = false);
    await tester.pump();
    expect(find.text('revealed'), findsOneWidget);
    update(() => message.hasSpoiler = true);
    await tester.pump();
    expect(find.text('revealed'), findsNothing);
  });

  testWidgets('Moments masks spoiler media before fetching its full preview', (
    tester,
  ) async {
    final message = _message(1);
    await _pump(
      tester,
      ChannelPostRow(
        post: ChannelPost(
          channel: ChatSummary(
            id: 42,
            title: 'Channel',
            lastMessage: '',
            lastMessageId: 1,
            date: 1,
            unreadCount: 0,
            order: 1,
            isMuted: false,
            kind: ChatKind.channel,
          ),
          message: message,
          accountSlot: 0,
        ),
        meName: 'Me',
        showInlineReply: false,
        showInlineComments: false,
      ),
    );
    expect(find.byType(MediaSpoiler), findsOneWidget);
    expect(find.byType(TDImage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
