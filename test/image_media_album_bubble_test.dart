import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/image_media_album_bubble.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('incoming group album uses real tiles, title, and timestamp', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'showMemberTags': true,
      'showPlainMemberRoleTags': true,
      'alwaysShowMessageTime': true,
    });
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final messages = [
      ChatMessage(
        id: 1,
        isOutgoing: false,
        text: '',
        date: 1785862260,
        senderId: 42,
        senderName: 'Mira Chen',
        senderRole: MemberRole.member,
        senderTitle: 'Album Curator',
        contentType: 'messagePhoto',
        mediaAlbumId: 91,
        image: TdFileRef(id: 101),
        imageWidth: 1600,
        imageHeight: 1200,
      ),
      ChatMessage(
        id: 2,
        isOutgoing: false,
        text: 'Two moments from the group album.',
        date: 1785862260,
        senderId: 42,
        senderName: 'Mira Chen',
        senderRole: MemberRole.member,
        senderTitle: 'Album Curator',
        contentType: 'messagePhoto',
        mediaAlbumId: 91,
        image: TdFileRef(id: 102),
        imageWidth: 1200,
        imageHeight: 1600,
      ),
    ];

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: 340,
                  child: ImageMediaAlbumBubble(
                    key: const ValueKey('test-album'),
                    messages: messages,
                    peerTitle: 'Design Circle',
                    isGroup: true,
                    imageBuilder: (context, message, width, height) =>
                        ColoredBox(
                          key: ValueKey('test-album-image-${message.id}'),
                          color: message.id == 1
                              ? const Color(0xFFFFAE80)
                              : const Color(0xFF45C4BE),
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('messageImageAlbumCard-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('messageImageAlbumTile-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('messageImageAlbumTile-2')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('test-album-image-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('test-album-image-2')), findsOneWidget);
    expect(find.text('Mira Chen'), findsOneWidget);
    expect(find.text('Album Curator'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('messageTappedTimestamp')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('test-album'))).height,
      lessThan(280),
    );

    final first = tester.getRect(
      find.byKey(const ValueKey('messageImageAlbumTile-1')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('messageImageAlbumTile-2')),
    );
    expect(first.overlaps(second), isFalse);
  });

  testWidgets('normal group albums use only the compact reply count', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final messages = [
      ChatMessage(
        id: 11,
        isOutgoing: false,
        text: '',
        date: 1,
        contentType: 'messagePhoto',
        mediaAlbumId: 92,
        image: TdFileRef(id: 111),
        imageWidth: 1600,
        imageHeight: 1200,
      ),
      ChatMessage(
        id: 12,
        isOutgoing: false,
        text: '',
        date: 1,
        contentType: 'messagePhoto',
        mediaAlbumId: 92,
        image: TdFileRef(id: 112),
        imageWidth: 1200,
        imageHeight: 1600,
        hasCommentThread: true,
        commentCount: 4,
      ),
    ];

    ChatMessage? opened;
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ImageMediaAlbumBubble(
              messages: messages,
              peerTitle: 'Design Circle',
              isGroup: true,
              onOpenComments: (message) => opened = message,
              imageBuilder: (context, message, width, height) => ColoredBox(
                color: message.id == 11
                    ? const Color(0xFFFFAE80)
                    : const Color(0xFF45C4BE),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('messageCommentsAttachment-12')),
      findsNothing,
    );
    expect(find.text('4 comments'), findsNothing);
    final compact = find.byKey(const ValueKey('messageCompactReplies-12'));
    expect(compact, findsOneWidget);
    expect(
      find.descendant(of: compact, matching: find.text('4')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(compact);
    expect(opened, same(messages[1]));
  });
}
