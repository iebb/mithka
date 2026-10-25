import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_picker_view.dart';
import 'package:mithka/chat/chat_view.dart'
    show ChatView, clearChatMemoryCaches;
import 'package:mithka/chat/forward_options.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

const _sourceChatId = 42;
const _targetChatId = 99;
const _albumMessageIds = <int>[1048576, 2097152];

Map<String, dynamic> _chatJson(int chatId) => {
  '@type': 'chat',
  'id': chatId,
  'title': chatId == _sourceChatId ? 'Source' : 'Destination',
  'type': {'@type': 'chatTypePrivate', 'user_id': 2},
  'last_read_inbox_message_id': _albumMessageIds.last,
  'unread_count': 0,
  'permissions': {'can_send_basic_messages': true},
};

Map<String, dynamic> _photoMessage(int id, String photoPath) => {
  '@type': 'message',
  'id': id,
  'chat_id': _sourceChatId,
  'media_album_id': 91,
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
          'type': 'x',
          'width': 800,
          'height': 600,
          'photo': {
            '@type': 'file',
            'id': id ~/ 1048576,
            'local': {
              '@type': 'localFile',
              'path': photoPath,
              'is_downloading_completed': true,
            },
          },
        },
      ],
    },
    'caption': {'@type': 'formattedText', 'text': '', 'entities': []},
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  L10nFixtures.load().install();

  late Directory photoDirectory;
  late String photoPath;
  late ThemeController theme;
  late TranslationController translation;
  late List<int> forwardedIds;

  setUp(() async {
    clearChatMemoryCaches();
    photoDirectory = await Directory.systemTemp.createTemp(
      'mithka-album-forward-',
    );
    photoPath = '${photoDirectory.path}/photo.png';
    await File(photoPath).writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42uNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    forwardedIds = <int>[];
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getChat' => _chatJson(request['chat_id'] as int),
          'getChatHistory' => {
            '@type': 'messages',
            'total_count': _albumMessageIds.length,
            'messages': [
              for (final id in _albumMessageIds.reversed)
                _photoMessage(id, photoPath),
            ],
          },
          'getUser' || 'getMe' => {
            '@type': 'user',
            'id': request['user_id'] ?? 1,
            'first_name': 'Member',
            'type': {'@type': 'userTypeRegular'},
          },
          'getMessageProperties' => {
            '@type': 'messageProperties',
            'can_be_forwarded': true,
            'can_be_copied': true,
          },
          'getMessageAvailableReactions' => {
            '@type': 'availableReactions',
            'top_reactions': <Map<String, dynamic>>[],
            'recent_reactions': <Map<String, dynamic>>[],
            'popular_reactions': <Map<String, dynamic>>[],
            'allow_custom_emoji': false,
            'are_tags': false,
            'unavailability_reason': null,
          },
          'getChats' => {'@type': 'chats', 'chat_ids': <int>[]},
          'getContacts' => {'@type': 'users', 'user_ids': <int>[]},
          'getFile' || 'downloadFile' => {
            '@type': 'file',
            'id': request['file_id'] ?? 1,
            'local': {
              '@type': 'localFile',
              'path': photoPath,
              'is_downloading_completed': true,
            },
          },
          'forwardMessages' => () {
            forwardedIds = List<int>.from(request['message_ids'] as List);
            return {
              '@type': 'messages',
              'messages': [
                for (final id in forwardedIds) {'@type': 'message', 'id': id},
              ],
            };
          }(),
          _ => {'@type': 'ok'},
        },
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
    SharedPreferences.setMockInitialValues({
      'openChatsAtLatest': true,
      'groupImageMessages': true,
    });
    final preferences = await SharedPreferences.getInstance();
    theme = ThemeController(preferences);
    translation = TranslationController(preferences);
    AppStrings.setLocale(const Locale('en'));
  });

  tearDown(() async {
    clearChatMemoryCaches();
    await TdClient.shared.closeProxy();
    theme.dispose();
    translation.dispose();
    await photoDirectory.delete(recursive: true);
  });

  testWidgets('forwarding a long-pressed visual album forwards every member', (
    tester,
  ) async {
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
            platform: TargetPlatform.android,
            extensions: [AppColors.light],
          ),
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ChatView(chatId: _sourceChatId, title: 'Source'),
        ),
      ),
    );
    final pressedTile = find.byKey(
      ValueKey('messageImageAlbumTile-${_albumMessageIds[0]}'),
    );
    for (var frame = 0; frame < 20 && pressedTile.evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(pressedTile, findsOneWidget);
    expect(
      find.byKey(ValueKey('messageImageAlbumTile-${_albumMessageIds[1]}')),
      findsOneWidget,
    );
    // The transcript reveals through an animated opacity after its initial
    // viewport positioning; wait until the row can actually receive pointers.
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(pressedTile.hitTestable(), findsOneWidget);

    await tester.longPress(pressedTile);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    final forward = find.byKey(const ValueKey('message-action-forward'));
    expect(forward, findsOneWidget);
    await tester.tap(forward);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ChatPickerView), findsOneWidget);

    Navigator.of(tester.element(find.byType(ChatPickerView))).pop(
      ChatPickerResult(
        chat: TDParse.chat(_chatJson(_targetChatId))!,
        forwardOptions: const ForwardOptions(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(forwardedIds, _albumMessageIds);
    // Drain the picker's deferred cache warm-up and the completion toast.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
