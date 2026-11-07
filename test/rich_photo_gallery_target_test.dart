import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view.dart'
    show ChatView, clearChatMemoryCaches;
import 'package:mithka/chat/full_image_viewer.dart';
import 'package:mithka/components/photo_avatar.dart' show TDImage;
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

const _chatId = -1001234;
const _fileIdSeed = 5000;

int _fileId(int messageId) => _fileIdSeed + messageId;

Map<String, dynamic> _photoJson(int id, {int albumId = 0}) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': 1700000100 + id,
  'is_outgoing': false,
  'media_album_id': albumId,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 7},
  'content': {
    '@type': 'messagePhoto',
    'photo': {
      '@type': 'photo',
      'sizes': [
        {
          '@type': 'photoSize',
          'type': 'x',
          'width': 320,
          'height': 240,
          'photo': {
            '@type': 'file',
            'id': _fileId(id),
            'unique_id': 'u${_fileId(id)}',
          },
        },
      ],
    },
  },
};

/// A `messageRichMessage` whose blocks are a paragraph plus a lone photo
/// block. The photo renders through `_richPhotoBlock`, whose tap hands the
/// transcript's `_openImage` a synthetic `messagePhoto` carrying the rich
/// message's id.
Map<String, dynamic> _richWithPhotoJson(int id) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': 1700000100 + id,
  'is_outgoing': false,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 7},
  'content': {
    '@type': 'messageRichMessage',
    'message': {
      '@type': 'richMessage',
      'is_rtl': false,
      'is_full': true,
      'blocks': [
        {
          '@type': 'pageBlockParagraph',
          'text': {'@type': 'richTextPlain', 'text': 'Rich with a photo'},
        },
        {
          '@type': 'pageBlockPhoto',
          'photo': {
            '@type': 'photo',
            'sizes': [
              {
                '@type': 'photoSize',
                'type': 'x',
                'width': 320,
                'height': 240,
                'photo': {
                  '@type': 'file',
                  'id': _fileId(id),
                  'unique_id': 'u${_fileId(id)}',
                },
              },
            ],
          },
        },
      ],
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  L10nFixtures.load().install();

  late Future<Map<String, dynamic>> Function(Map<String, dynamic>) queryHandler;

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) => queryHandler(request),
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);

  late ThemeController theme;
  late TranslationController translation;

  Future<void> pumpChat(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    clearChatMemoryCaches();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<TranslationController>.value(
            value: translation,
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            extensions: [AppColors.light],
            platform: TargetPlatform.iOS,
          ),
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ChatView(chatId: _chatId, title: 'Group chat'),
        ),
      ),
    );
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  void installTransport(List<Map<String, dynamic>> page) {
    queryHandler = (request) async {
      switch (request['@type']) {
        case 'getChatHistory':
          final offset = request['offset'] as int? ?? 0;
          if (offset > 0) {
            // TDLib rejects positive offsets with 400; hold the same contract
            // so a production-shaped request cannot be silently answered.
            throw StateError('Parameter offset must be non-positive');
          }
          return {
            '@type': 'messages',
            'total_count': page.length,
            'messages': page,
          };
        case 'getChat':
          return {
            '@type': 'chat',
            'id': _chatId,
            'title': 'Group chat',
            'type': {
              '@type': 'chatTypeSupergroup',
              'supergroup_id': -_chatId - 1000000000000,
              'is_channel': false,
            },
          };
        case 'getSupergroup':
          return {'@type': 'supergroup', 'id': -_chatId - 1000000000000};
        case 'getSupergroupFullInfo':
          return {'@type': 'supergroupFullInfo', 'member_count': 4};
        case 'getMe':
          return {
            '@type': 'user',
            'id': 42,
            'first_name': 'Me',
            'type': {'@type': 'userTypeRegular'},
          };
        case 'getUser':
          return {
            '@type': 'user',
            'id': request['user_id'] ?? 7,
            'first_name': 'User ${request['user_id'] ?? 7}',
            'type': {'@type': 'userTypeRegular'},
          };
        case 'downloadFile':
          return {
            '@type': 'file',
            'id': request['file_id'],
            'unique_id': 'dl${request['file_id']}',
            'local': {
              '@type': 'localFile',
              'is_downloading_completed': true,
              'path': '/tmp/rich-photo-${request['file_id']}.jpg',
            },
          };
        default:
          return {'@type': 'ok'};
      }
    };
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeController(await SharedPreferences.getInstance());
    translation = TranslationController(await SharedPreferences.getInstance());
  });

  tearDown(() async {
    clearChatMemoryCaches();
    translation.dispose();
  });

  testWidgets(
    'tapping a lone photo inside a rich message opens the viewer on that photo',
    (tester) async {
      // Newest→oldest: photo 6, photo 5, photo 4, rich message 3 (carrying
      // its own photo 5003), photo 2. The rich photo shares message id 3 but
      // is not a transcript `messagePhoto`, so the gallery must still open on
      // the tapped image instead of falling back to index 0.
      installTransport([
        _photoJson(6),
        _photoJson(5),
        _photoJson(4),
        _richWithPhotoJson(3),
        _photoJson(2),
      ]);
      await pumpChat(tester);

      final richPhoto = find.byWidgetPredicate(
        (w) => w is TDImage && w.photo?.id == _fileId(3),
      );
      expect(richPhoto, findsOneWidget);
      await tester.tap(richPhoto.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final viewer = find.byType(FullImageViewer);
      expect(viewer, findsOneWidget);
      final widget = tester.widget<FullImageViewer>(viewer);
      final items = widget.items.map((file) => file.id).toList();
      // The tapped photo is part of the gallery…
      expect(items, contains(_fileId(3)));
      // …and the viewer opens on it, not on the first chat photo.
      expect(items[widget.startIndex], _fileId(3));
      expect(widget.startIndex, isNot(0));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
    },
  );

  testWidgets(
    'tapping an album tile keeps opening the viewer on the tapped member',
    (tester) async {
      // A photo album (2,3,4 with a shared album id) after standalone photo 6.
      installTransport([
        _photoJson(6),
        _photoJson(4, albumId: 900),
        _photoJson(3, albumId: 900),
        _photoJson(2, albumId: 900),
      ]);
      await pumpChat(tester);

      final tile3 = find.byKey(const ValueKey('messageImageAlbumTile-3'));
      expect(tile3, findsOneWidget);
      await tester.tap(tile3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final viewer = find.byType(FullImageViewer);
      expect(viewer, findsOneWidget);
      final widget = tester.widget<FullImageViewer>(viewer);
      final items = widget.items.map((file) => file.id).toList();
      expect(items[widget.startIndex], _fileId(3));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
    },
  );
}
