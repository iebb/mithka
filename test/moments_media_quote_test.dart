import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/moments/moments_view.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Moments shows forwarding and unresolved reply attribution', (
    tester,
  ) async {
    final message =
        ChatMessage(
            id: 7,
            isOutgoing: false,
            text: '',
            date: 1,
            replyToMessageId: 9,
          )
          ..forwardFromChatId = -44
          ..forwardOrigin = 'Source channel'
          ..forwardAuthorSignature = 'Alice';
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        home: Scaffold(
          body: ChannelPostRow(
            post: ChannelPost(
              channel: ChatSummary(
                id: 42,
                title: 'Channel',
                lastMessage: '',
                lastMessageId: 7,
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
        ),
      ),
    );
    expect(find.text('Forwarded from Source channel (Alice)'), findsOneWidget);
    expect(find.byKey(const ValueKey('momentsReplyQuote')), findsOneWidget);
    expect(find.text('Reply', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Moments shows media-only reply quotes', (tester) async {
    final quotedImage = TdFileRef(
      id: 900,
      localPath: '${Directory.current.path}/assets/penguin.png',
    );
    final channel = ChatSummary(
      id: 42,
      title: 'Channel',
      lastMessage: '',
      lastMessageId: 7,
      date: 1,
      unreadCount: 0,
      order: 1,
      isMuted: false,
      kind: ChatKind.channel,
    );
    final message =
        ChatMessage(
            id: 7,
            isOutgoing: false,
            text: 'Moment',
            date: 1,
            contentType: 'messageText',
            replyToMessageId: 9,
            replyToImage: quotedImage,
            replyToImageWidth: 600,
            replyToImageHeight: 400,
          )
          ..replyToSender = 'Original channel'
          ..replyToPreview = '';

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(extensions: [AppColors.light]),
        home: Scaffold(
          body: ChannelPostRow(
            post: ChannelPost(
              channel: channel,
              message: message,
              accountSlot: 0,
            ),
            meName: 'Me',
            showInlineReply: false,
            showInlineComments: false,
          ),
        ),
      ),
    );
    await tester.pump();

    final mediaPreview = find.byKey(const ValueKey('momentsReplyMediaPreview'));
    expect(mediaPreview, findsOneWidget);
    final image = tester.widget<TDImage>(
      find.descendant(of: mediaPreview, matching: find.byType(TDImage)),
    );
    expect(image.photo, same(quotedImage));
  });
}
