import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/music_player_controller.dart';
import 'package:mithka/chat/music_playlist_service.dart';
import 'package:mithka/chat/shared_media_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _audio({
  required int chatId,
  required int messageId,
  required int fileId,
}) => {
  '@type': 'message',
  'id': messageId,
  'chat_id': chatId,
  'date': 1,
  'is_outgoing': true,
  'content': {
    '@type': 'messageAudio',
    'audio': {
      '@type': 'audio',
      'duration': 120,
      'title': 'Song',
      'performer': 'Artist',
      'file_name': 'Song.mp3',
      'audio': {'@type': 'file', 'id': fileId},
    },
  },
};

Map<String, dynamic> _folderPush() => {
  '@type': 'updateChatFolders',
  'chat_folders': [
    {
      '@type': 'chatFolderInfo',
      'id': 7,
      'name': {
        '@type': 'chatFolderName',
        'text': {
          '@type': 'formattedText',
          'text': '_Playlist',
          'entities': <Map<String, dynamic>>[],
        },
      },
    },
  ],
  'main_chat_list_position': 0,
  'are_tags_enabled': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          return switch (request['@type']) {
            'getChatFolder' => {
              '@type': 'chatFolder',
              'name': {
                '@type': 'chatFolderName',
                'text': {
                  '@type': 'formattedText',
                  'text': '_Playlist',
                  'entities': <Map<String, dynamic>>[],
                },
              },
              'included_chat_ids': [900],
            },
            'getChat' => {'@type': 'chat', 'id': 900, 'title': 'Favourites'},
            'searchChatMessages' => {
              '@type': 'foundChatMessages',
              'messages': [_audio(chatId: 900, messageId: 11, fileId: 44)],
            },
            'searchMessages' => {
              '@type': 'foundMessages',
              'messages': [],
              'next_offset': '',
            },
            _ => {'@type': 'ok'},
          };
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  setUp(() {
    MusicPlayerController.shared.playlists = const [];
    // The folder cache is a singleton across tests: a push from the previous
    // test must not make this one start warm.
    TdClient.shared.clearChatFoldersForTesting();
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  Future<void> openHub(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: SharedMediaView(
            chatId: 0,
            title: 'Music',
            initialTab: 5,
            displayTitle: AppStringKeys.momentsMusic,
            lockedTab: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Playlists').first);
    await tester.pump();
  }

  List<String> visibleTexts(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data)
      .whereType<String>()
      .toList();

  testWidgets('the playlists tab shows a loading state, not an empty library', (
    tester,
  ) async {
    await openHub(tester);
    await tester.pump(const Duration(milliseconds: 50));

    final player = MusicPlayerController.shared;
    expect(player.playlistsLoading, isTrue);
    expect(
      visibleTexts(tester),
      isNot(contains(AppStrings.t(AppStringKeys.musicPlayerNoPlaylists))),
      reason: 'a pending load must not read as "you have no playlists"',
    );
    expect(
      find.byKey(const ValueKey('music-playlists-loading')),
      findsOneWidget,
    );

    // Push the folders so the bounded wait resolves and no timer is left.
    updates.add(_folderPush());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(player.playlistsLoading, isFalse);
  });

  testWidgets(
    'a folder push that outlives the bounded wait still fills the library',
    (tester) async {
      await openHub(tester);
      final player = MusicPlayerController.shared;

      // Let the service's bounded wait expire with nothing pushed, so the hub
      // settles on an empty library.
      await tester.pump(MusicPlaylistService.folderWaitTimeout);
      await tester.pump(const Duration(milliseconds: 200));
      expect(player.playlistsLoading, isFalse);
      expect(player.playlists, isEmpty);
      expect(
        visibleTexts(tester),
        contains(AppStrings.t(AppStringKeys.musicPlayerNoPlaylists)),
      );

      // TDLib finishes getDifference and pushes the folder list late. The tab
      // is open and must pick the library up without the user reopening it.
      updates.add(_folderPush());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        player.playlists.map((playlist) => playlist.title),
        contains('Favourites'),
        reason: 'an open hub must recover when the folders finally arrive',
      );
      expect(find.text('Favourites'), findsOneWidget);
    },
  );
}
