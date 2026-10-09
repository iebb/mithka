import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/app_navigator.dart';
import 'package:mithka/chat/chat_view.dart'
    show ChatView, clearChatMemoryCaches;
import 'package:mithka/chat/full_image_viewer.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

// ChatView-to-gallery navigation coverage from review: the built-in menu's
// View in Chat must jump back to the chat AND actually close the viewer —
// for a private chat (positive id) and a supergroup (negative id, which the
// old `chatId <= 0` guard wrongly excluded from message anchors).

const _privateChatId = 70001;
const _groupChatId = -1004242;

Map<String, dynamic> _photoMessage({
  required int chatId,
  required int id,
  required String photoPath,
}) => {
  '@type': 'message',
  'id': id,
  'chat_id': chatId,
  'date': 1785862260,
  'is_outgoing': false,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 2},
  'content': {
    '@type': 'messagePhoto',
    'photo': {
      '@type': 'photo',
      'sizes': [
        {
          '@type': 'photoSize',
          'type': 'y',
          'width': 320,
          'height': 180,
          'photo': {
            '@type': 'file',
            'id': 10 + id,
            'local': {
              '@type': 'localFile',
              'path': photoPath,
              'is_downloading_completed': true,
            },
          },
        },
      ],
    },
  },
};

Map<String, dynamic> _chatJson(int chatId) => {
  '@type': 'chat',
  'id': chatId,
  'title': chatId < 0 ? 'Group chat' : 'Private chat',
  'type': chatId < 0
      ? {
          '@type': 'chatTypeSupergroup',
          'supergroup_id': -chatId - 1000000000000,
          'is_channel': false,
        }
      : {'@type': 'chatTypePrivate', 'user_id': 2},
  'last_read_inbox_message_id': 5,
  'unread_count': 0,
  'permissions': {'can_send_basic_messages': true},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  L10nFixtures.load().install();

  int activeChatId = _privateChatId;
  late Directory photoDirectory;
  late String photoPath;
  late GlobalKey<NavigatorState> navigatorKey;

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getChat' => _chatJson(activeChatId),
          'downloadFile' || 'getFile' => {
            '@type': 'file',
            'id': request['file_id'] ?? 10,
            'local': {
              '@type': 'localFile',
              // The path must really exist: TdFileCenter.pathFor stats the
              // file and TDImage keeps an IgnorePointer progress overlay
              // above a photo whose bytes cannot be decoded.
              'path': photoPath,
              'is_downloading_completed': true,
            },
          },
          'getChatHistory' => {
            '@type': 'messages',
            'total_count': 1,
            'messages': [
              _photoMessage(chatId: activeChatId, id: 5, photoPath: photoPath),
            ],
          },
          'getSupergroup' => {
            '@type': 'supergroup',
            'id': -activeChatId - 1000000000000,
          },
          'getSupergroupFullInfo' => {
            '@type': 'supergroupFullInfo',
            'member_count': 3,
          },
          'getMe' => {
            '@type': 'user',
            'id': 1,
            'type': {'@type': 'userTypeRegular'},
          },
          'getUser' => {
            '@type': 'user',
            'id': request['user_id'] ?? 2,
            'first_name': 'Member',
            'type': {'@type': 'userTypeRegular'},
          },
          _ => {'@type': 'ok'},
        },
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);

  late ThemeController theme;
  late TranslationController translation;

  setUp(() async {
    photoDirectory = await Directory.systemTemp.createTemp(
      'mithka-image-navigation-',
    );
    photoPath = '${photoDirectory.path}/photo.png';
    await File(photoPath).writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42uNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    navigatorKey = GlobalKey<NavigatorState>();
    SharedPreferences.setMockInitialValues({'openChatsAtLatest': true});
    theme = ThemeController(await SharedPreferences.getInstance());
    translation = TranslationController(await SharedPreferences.getInstance());
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    clearChatMemoryCaches();
    photoDirectory.deleteSync(recursive: true);
    theme.dispose();
    translation.dispose();
  });

  Widget app(int chatId, {bool pushed = false}) => MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      ChangeNotifierProvider<TranslationController>.value(value: translation),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      theme: ThemeData(
        extensions: [AppColors.light],
        // The Linux host would arm the bubbles' desktop pointer-listener
        // gestures; an Android theme keeps the ordinary tap path.
        platform: TargetPlatform.android,
      ),
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: pushed
          ? const Scaffold(body: Text('Navigation fixture'))
          : ChatView(chatId: chatId, title: chatId < 0 ? 'Group' : 'Private'),
    ),
  );

  Future<void> openGalleryFromChat(
    WidgetTester tester,
    int chatId, {
    bool pushed = false,
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    clearChatMemoryCaches();
    activeChatId = chatId;
    await tester.pumpWidget(app(chatId, pushed: pushed));
    if (pushed) {
      unawaited(
        navigatorKey.currentState!.push(
          AppChatPageRoute<void>(
            builder: (_) => ChatView(
              chatId: chatId,
              title: chatId < 0 ? 'Group' : 'Private',
            ),
          ),
        ),
      );
    }
    // The chat surface keeps timers alive (progress polling), so bounded
    // pumps instead of pumpAndSettle. The initial positioning runs three
    // endOfFrame passes before it reveals the transcript, so give it room.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // Tap the photo itself (the inner GestureDetector opens the gallery;
    // the bubble tap target only toggles the timestamp).
    final bubble = find.byKey(const ValueKey('messageTapTarget-5'));
    expect(bubble, findsOneWidget, reason: 'the photo message must render');
    // The first TDImage in the tree is the sender avatar's placeholder;
    // the photo is the one inside the message's media clip.
    final image = find
        .descendant(
          of: find.byKey(const ValueKey('messageMediaClip-5')),
          matching: find.byType(TDImage),
        )
        .first;
    await tester.tap(image, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byType(FullImageViewer),
      findsOneWidget,
      reason: 'the gallery opened from the chat',
    );
  }

  for (final entry in [(_privateChatId, 'private'), (_groupChatId, 'group')]) {
    final (chatId, label) = entry;
    testWidgets('view in chat closes the viewer and jumps ($label)', (
      tester,
    ) async {
      await openGalleryFromChat(tester, chatId);

      await tester.tap(find.byKey(const ValueKey('image-viewer-more')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byKey(const ValueKey('image-viewer-action-view-in-chat')),
        findsOneWidget,
        reason: 'both private and group chats supply message anchors',
      );

      await tester.tap(
        find.byKey(const ValueKey('image-viewer-action-view-in-chat')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byType(FullImageViewer),
        findsNothing,
        reason: 'the viewer must close after jumping back to the chat',
      );
      expect(find.byType(ChatView), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
      clearChatMemoryCaches();
    });
  }

  testWidgets('view in chat preserves a conversation pushed above home', (
    tester,
  ) async {
    await openGalleryFromChat(tester, _privateChatId, pushed: true);
    await tester.tap(find.byKey(const ValueKey('image-viewer-more')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(
      find.byKey(const ValueKey('image-viewer-action-view-in-chat')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FullImageViewer), findsNothing);
    expect(
      find.byType(ChatView),
      findsOneWidget,
      reason: 'only the gallery may close; its owning chat must stay open',
    );
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
    clearChatMemoryCaches();
  });
}
