import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/music_playlist_service.dart';

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

Map<String, dynamic> _folderInfo(int id) => {
  '@type': 'chatFolderInfo',
  'id': id,
  'name': {
    '@type': 'chatFolderName',
    'text': {
      '@type': 'formattedText',
      'text': MusicPlaylistService.folderTitle,
      'entities': <Map<String, dynamic>>[],
    },
  },
};

Map<String, dynamic> _snapshot(List<Map<String, dynamic>> infos) => {
  '@type': 'updateChatFolders',
  'chat_folders': infos,
};

Map<String, dynamic> _playlistFolder(List<int> chatIds) => {
  '@type': 'chatFolder',
  'name': {
    '@type': 'chatFolderName',
    'text': {
      '@type': 'formattedText',
      'text': MusicPlaylistService.folderTitle,
      'entities': <Map<String, dynamic>>[],
    },
  },
  'included_chat_ids': chatIds,
};

void main() {
  group('a cold folder cache does not read as an empty library', () {
    test(
      'waits for the pushed folder list and resolves the playlists',
      () async {
        final requests = <Map<String, dynamic>>[];
        // TDLib has not pushed updateChatFolders yet: the session just finished
        // getDifference and the push lands a moment later.
        final pushed = Completer<Map<String, dynamic>>();
        var waited = false;

        final service = MusicPlaylistService(
          folderUpdate: () => null,
          folderWait: (cached) async {
            waited = true;
            return pushed.future;
          },
          query: (request) async {
            requests.add(request);
            return switch (request['@type']) {
              'getChatFolder' => _playlistFolder([900]),
              'getChat' => {'@type': 'chat', 'id': 900, 'title': 'Favourites'},
              'searchChatMessages' => {
                '@type': 'foundChatMessages',
                'messages': [_audio(chatId: 900, messageId: 11, fileId: 44)],
              },
              _ => {'@type': 'ok'},
            };
          },
        );

        final load = service.loadPlaylists();
        await Future<void>.delayed(Duration.zero);
        expect(waited, isTrue, reason: 'a cold cache must be waited on');

        pushed.complete(_snapshot([_folderInfo(7)]));
        final playlists = await load;

        expect(playlists, hasLength(1));
        expect(playlists.single.title, 'Favourites');
        expect(playlists.single.tracks.single.music?.file?.id, 44);
        expect(
          requests.map((request) => request['@type']),
          contains('getChatFolder'),
        );
      },
    );

    test(
      'a folder-less account resolves empty once the wait gives up',
      () async {
        final service = MusicPlaylistService(
          folderUpdate: () => null,
          folderWait: (cached) async => null,
          query: (request) async => {'@type': 'ok'},
        );

        expect(await service.loadPlaylists(), isEmpty);
      },
    );

    test(
      'the cached snapshot is still the fast path and skips the wait',
      () async {
        final requests = <Map<String, dynamic>>[];
        var waited = false;
        final service = MusicPlaylistService(
          folderUpdate: () => _snapshot([_folderInfo(7)]),
          folderWait: (cached) async {
            waited = true;
            return cached;
          },
          query: (request) async {
            requests.add(request);
            return switch (request['@type']) {
              'getChatFolder' => _playlistFolder([900]),
              'getChat' => {'@type': 'chat', 'id': 900, 'title': 'Favourites'},
              'searchChatMessages' => {
                '@type': 'foundChatMessages',
                'messages': [],
              },
              _ => {'@type': 'ok'},
            };
          },
        );

        final playlists = await service.loadPlaylists();

        expect(playlists, hasLength(1));
        expect(waited, isFalse, reason: 'a warm cache must not stall');
      },
    );

    test(
      'a create on a cold cache joins the folder instead of making one',
      () async {
        final requests = <Map<String, dynamic>>[];
        final service = MusicPlaylistService(
          folderUpdate: () => null,
          folderWait: (cached) async => _snapshot([_folderInfo(7)]),
          query: (request) async {
            requests.add(request);
            return switch (request['@type']) {
              'createNewSupergroupChat' => {
                '@type': 'chat',
                'id': 951,
                'title': 'Mix',
              },
              'getChatFolder' => _playlistFolder([900]),
              _ => {'@type': 'ok'},
            };
          },
        );

        final playlist = await service.createPlaylist('Mix');

        expect(playlist.chatId, 951);
        final types = requests.map((request) => request['@type']).toList();
        expect(types, contains('editChatFolder'));
        expect(
          types,
          isNot(contains('createChatFolder')),
          reason: 'a second _Playlist folder splits the library',
        );
      },
    );
  });
}
