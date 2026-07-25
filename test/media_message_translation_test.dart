import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chat/stretchable_message_bubble_background.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/message_bubble_background.dart';
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
    bool channelHasLinkedDiscussion = false,
    bool themingEnabled = true,
    ValueChanged<ChatMessage>? onLongPress,
  }) async {
    SharedPreferences.setMockInitialValues({
      'groupImageMessages': true,
      'appearanceThemingEnabled': themingEnabled,
    });
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
              channelHasLinkedDiscussion: channelHasLinkedDiscussion,
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
    final combinedFinder = find.byKey(
      const ValueKey('messageCombinedBubble-10'),
    );
    final album = tester.widget<Container>(albumFinder);
    final albumRadius =
        (album.decoration! as BoxDecoration).borderRadius! as BorderRadius;
    expect(
      tester.getRect(commentsFinder).top,
      tester.getRect(albumFinder).bottom,
    );
    expect(albumRadius.bottomLeft, isNot(Radius.zero));
    expect(
      tester
          .getRect(combinedFinder)
          .contains(tester.getRect(albumFinder).center),
      isTrue,
    );
    expect(
      tester
          .getRect(combinedFinder)
          .contains(tester.getRect(commentsFinder).center),
      isTrue,
    );

    await tester.longPress(
      find.byKey(const ValueKey('messageDocumentAlbumFile-11')),
    );
    expect(longPressed?.id, 11);
  });

  testWidgets('comments render inside one rounded message surface', (
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
    final combinedFinder = find.byKey(
      const ValueKey('messageCombinedBubble-12'),
    );
    final main = tester.widget<Container>(mainFinder);
    final comments = tester.widget<Container>(commentsFinder);
    final combined = tester.widget<StretchableMessageBubbleBackground>(
      combinedFinder,
    );
    final commentsDecoration = comments.decoration! as BoxDecoration;

    expect(
      tester.getRect(commentsFinder).top,
      tester.getRect(mainFinder).bottom,
    );
    expect(main.decoration, isNull);
    expect(commentsDecoration.color, isNull);
    expect(commentsDecoration.borderRadius, isNull);
    expect((commentsDecoration.border! as Border).top.width, 0.5);
    expect(combined.fallbackBorderRadius, BorderRadius.circular(12));
    expect(
      tester
          .getRect(combinedFinder)
          .contains(tester.getRect(commentsFinder).bottomCenter),
      isTrue,
    );
  });

  testWidgets('linked channel discussion stays visible before first comment', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 13,
      isOutgoing: false,
      text: 'Channel post',
      date: 1,
      contentType: 'messageText',
    );

    await pumpBubble(
      tester,
      message,
      showCommentAttachment: true,
      channelHasLinkedDiscussion: true,
    );

    expect(
      find.byKey(const ValueKey('messageCommentsAttachment-13')),
      findsOneWidget,
    );
    expect(find.text('Leave a comment'), findsOneWidget);
    final messageFinder = find.byKey(const ValueKey('messageTextBubble-13'));
    final commentsFinder = find.byKey(
      const ValueKey('messageCommentsAttachment-13'),
    );
    expect(
      tester.getRect(commentsFinder).width,
      tester.getRect(messageFinder).width,
    );
    final commentRow = tester.widget<Row>(
      find.descendant(of: commentsFinder, matching: find.byType(Row)),
    );
    expect(commentRow.mainAxisSize, MainAxisSize.max);
    expect(
      find.descendant(of: commentsFinder, matching: find.byType(Expanded)),
      findsOneWidget,
    );
    final combinedFinder = find.byKey(
      const ValueKey('messageCombinedBubble-13'),
    );
    final expectedBackground = tester
        .element(messageFinder)
        .colors
        .bubbleIncoming;
    final combined = tester.widget<StretchableMessageBubbleBackground>(
      combinedFinder,
    );
    expect(combined.fallbackColor, expectedBackground);
    expect(
      tester
          .getRect(combinedFinder)
          .contains(tester.getRect(commentsFinder).center),
      isTrue,
    );
  });

  testWidgets('decorative comments paint one center-sliced message surface', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 131,
      isOutgoing: false,
      text: 'One decorated message',
      date: 1,
      contentType: 'messageText',
      commentCount: 3,
    );

    final theme = await pumpBubble(
      tester,
      message,
      showCommentAttachment: true,
    );
    theme.messageBubbleBackground = MessageBubbleBackground.forestFamiliar;
    await tester.pumpAndSettle();

    final combinedFinder = find.byKey(
      const ValueKey('messageCombinedBubble-131'),
    );
    final combined = tester.widget<StretchableMessageBubbleBackground>(
      combinedFinder,
    );
    expect(
      combined.background.selection,
      MessageBubbleBackground.forestFamiliar,
    );
    expect(combined.background.centerSlice, const Rect.fromLTWH(24, 18, 1, 1));
    expect(
      tester
          .widget<Container>(
            find.byKey(const ValueKey('messageTextBubble-131')),
          )
          .decoration,
      isNull,
    );
    expect(
      find.descendant(
        of: combinedFinder,
        matching: find.byType(StretchableMessageBubbleBackground),
      ),
      findsNothing,
    );
  });

  testWidgets('outgoing bubble stays white on blue when theming is off', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 14,
      isOutgoing: true,
      text: 'Own message',
      date: 1,
      contentType: 'messageText',
    );

    await pumpBubble(tester, message, themingEnabled: false);

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(const ValueKey('messageTextBubble-14')),
        matching: find.byType(RichText),
      ),
    );
    expect(richText.text.style?.color, AppTheme.bubbleOutgoingText);
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
