import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ThemeController> pumpBubble(
    WidgetTester tester,
    ChatMessage message, {
    List<ChatMessage> groupedMedia = const <ChatMessage>[],
    bool showCommentAttachment = false,
    ValueChanged<ChatMessage>? onLongPress,
  }) async {
    SharedPreferences.setMockInitialValues({'groupImageMessages': true});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageBubble(
              message: message,
              groupedMedia: groupedMedia,
              peerTitle: 'Test',
              isGroup: false,
              showCommentAttachment: showCommentAttachment,
              onLongPress: onLongPress == null
                  ? null
                  : (message, _, _) => onLongPress(message),
            ),
          ),
        ),
      ),
    );
    return theme;
  }

  testWidgets('grouped photo captions render their translation', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 1,
      isOutgoing: false,
      text: 'Original caption',
      date: 1,
      contentType: 'messagePhoto',
      image: TdFileRef(
        id: 101,
        miniThumb: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      ),
      imageWidth: 600,
      imageHeight: 400,
      translationText: 'Translated caption',
      translationLanguageCode: 'en',
    );

    await pumpBubble(tester, message);

    expect(find.text('Original caption', findRichText: true), findsOneWidget);
    expect(find.text('Translated caption', findRichText: true), findsOneWidget);
    expect(
      find.byKey(const ValueKey('messageTranslationBlock')),
      findsOneWidget,
    );

    // Expire the mocked TDLib image lookup timeout before test teardown.
    await tester.pump(const Duration(minutes: 3, seconds: 1));
  });

  testWidgets('document captions render their translation', (tester) async {
    final message = ChatMessage(
      id: 2,
      isOutgoing: false,
      text: 'Document caption',
      date: 1,
      contentType: 'messageDocument',
      document: MessageDocument(
        fileName: 'report.pdf',
        size: 1024,
        ext: 'PDF',
        file: null,
      ),
      translationText: 'Translated document caption',
      translationLanguageCode: 'en',
    );

    await pumpBubble(tester, message);

    expect(find.text('Document caption', findRichText: true), findsOneWidget);
    expect(
      find.text('Translated document caption', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('messageTranslationBlock')),
      findsOneWidget,
    );
  });

  testWidgets('document albums render as one bubble with one shared caption', (
    tester,
  ) async {
    final first =
        ChatMessage(
            id: 10,
            isOutgoing: false,
            text: '',
            date: 1,
            contentType: 'messageDocument',
            mediaAlbumId: 99,
            commentCount: 420,
            document: MessageDocument(
              fileName: 'first.deb',
              size: 1024 * 1024,
              ext: 'DEB',
              file: null,
            ),
          )
          ..reactions = const [
            MessageReaction(emoji: '❤️', count: 50, chosen: false),
          ];
    final second = ChatMessage(
      id: 11,
      isOutgoing: false,
      text: 'One caption for both files',
      date: 1,
      contentType: 'messageDocument',
      mediaAlbumId: 99,
      translationText: 'Translated album caption',
      translationLanguageCode: 'en',
      document: MessageDocument(
        fileName: 'second.dylib',
        size: 3 * 1024 * 1024,
        ext: 'DYLIB',
        file: null,
      ),
    );

    ChatMessage? longPressed;
    await pumpBubble(
      tester,
      first,
      groupedMedia: [first, second],
      showCommentAttachment: true,
      onLongPress: (message) => longPressed = message,
    );

    expect(find.byKey(const ValueKey('messageTapTarget-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('messageTapTarget-11')), findsNothing);
    expect(find.text('first.deb'), findsOneWidget);
    expect(find.text('second.dylib'), findsOneWidget);
    expect(
      find.text('One caption for both files', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Translated album caption', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('420 comments'), findsOneWidget);
    expect(find.text('❤️'), findsOneWidget);

    final albumFinder = find.byKey(
      const ValueKey('messageDocumentAlbumCard-10'),
    );
    final commentsFinder = find.byKey(
      const ValueKey('messageCommentsAttachment-10'),
    );
    final album = tester.widget<Container>(albumFinder);
    final albumRadius =
        (album.decoration! as BoxDecoration).borderRadius! as BorderRadius;
    expect(
      tester.getRect(commentsFinder).top,
      tester.getRect(albumFinder).bottom,
    );
    expect(albumRadius.bottomLeft, Radius.zero);

    await tester.longPress(
      find.byKey(const ValueKey('messageDocumentAlbumFile-11')),
    );
    expect(longPressed?.id, 11);
  });

  testWidgets('comments attach flush with squared meeting corners', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 12,
      isOutgoing: false,
      text: 'Channel post',
      date: 1,
      contentType: 'messageText',
      commentCount: 108,
    );

    await pumpBubble(tester, message, showCommentAttachment: true);

    final mainFinder = find.byKey(const ValueKey('messageTextBubble-12'));
    final commentsFinder = find.byKey(
      const ValueKey('messageCommentsAttachment-12'),
    );
    final main = tester.widget<Container>(mainFinder);
    final comments = tester.widget<Container>(commentsFinder);
    final mainRadius = (main.decoration! as BoxDecoration).borderRadius!;
    final commentsRadius =
        (comments.decoration! as BoxDecoration).borderRadius!;

    expect(
      tester.getRect(commentsFinder).top,
      tester.getRect(mainFinder).bottom,
    );
    expect(mainRadius, isA<BorderRadius>());
    expect((mainRadius as BorderRadius).bottomLeft, Radius.zero);
    expect(commentsRadius, isA<BorderRadius>());
    expect((commentsRadius as BorderRadius).topLeft, Radius.zero);
    expect(commentsRadius.topRight, Radius.zero);
    expect(commentsRadius.bottomLeft, const Radius.circular(12));
    expect(commentsRadius.bottomRight, const Radius.circular(12));
  });

  testWidgets('captionless media labels never render as captions', (
    tester,
  ) async {
    final message = TDParse.message({
      '@type': 'message',
      'id': 20,
      'date': 1,
      'content': {
        '@type': 'messageVideo',
        'caption': {'@type': 'formattedText', 'text': ''},
        'video': {
          '@type': 'video',
          'duration': 48,
          'width': 320,
          'height': 180,
          'video': {'@type': 'file', 'id': 201},
        },
      },
    });

    expect(message, isNotNull);
    expect(message!.text, isEmpty);
    await pumpBubble(tester, message);

    expect(find.text('Video', findRichText: true), findsNothing);
  });

  testWidgets('a real caption equal to a media label still renders', (
    tester,
  ) async {
    final message = TDParse.message({
      '@type': 'message',
      'id': 21,
      'date': 1,
      'content': {
        '@type': 'messageVideo',
        'caption': {'@type': 'formattedText', 'text': 'Video'},
        'video': {
          '@type': 'video',
          'duration': 48,
          'width': 320,
          'height': 180,
          'video': {'@type': 'file', 'id': 202},
        },
      },
    });

    expect(message, isNotNull);
    await pumpBubble(tester, message!);

    expect(find.text('Video', findRichText: true), findsOneWidget);
  });
}
