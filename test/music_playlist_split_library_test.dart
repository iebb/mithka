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
      'title': 'Song $messageId',
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

void main() {
  group('a split playlist library stays whole', () {
    test(
      'loads playlists from every _Playlist folder, not only the first',
      () async {
        final requests = <Map<String, dynamic>>[];
        // Two folders carry the same title: the second was created because a
        // cold folder cache missed the first. Only reading the first hides the
        // playlists that landed in the other one.
        final service = MusicPlaylistService(
          folderUpdate: () => {
            '@type': 'updateChatFolders',
            'chat_folders': [_folderInfo(7), _folderInfo(8)],
          },
          query: (request) async {
            requests.add(request);
            return switch (request['@type']) {
              'getChatFolder' => {
                '@type': 'chatFolder',
                'name': {
                  '@type': 'chatFolderName',
                  'text': {
                    '@type': 'formattedText',
                    'text': MusicPlaylistService.folderTitle,
                    'entities': <Map<String, dynamic>>[],
                  },
                },
                'included_chat_ids': request['chat_folder_id'] == 7
                    ? [900]
                    : [901],
              },
              'getChat' => {
                '@type': 'chat',
                'id': request['chat_id'],
                'title': request['chat_id'] == 900 ? 'Older' : 'Newer',
              },
              'searchChatMessages' => {
                '@type': 'foundChatMessages',
                'messages': [
                  _audio(
                    chatId: request['chat_id'] as int,
                    messageId: 11,
                    fileId: request['chat_id'] as int,
                  ),
                ],
              },
              _ => {'@type': 'ok'},
            };
          },
        );

        final playlists = await service.loadPlaylists();

        expect(
          playlists.map((playlist) => playlist.title),
          containsAll(['Older', 'Newer']),
          reason: 'both halves of a split library must stay reachable',
        );
      },
    );

    test('adding to a split library targets one canonical folder', () async {
      final requests = <Map<String, dynamic>>[];
      final service = MusicPlaylistService(
        folderUpdate: () => {
          '@type': 'updateChatFolders',
          'chat_folders': [_folderInfo(8), _folderInfo(7)],
        },
        query: (request) async {
          requests.add(request);
          return switch (request['@type']) {
            'createNewSupergroupChat' => {
              '@type': 'chat',
              'id': 951,
              'title': 'Mix',
            },
            'getChatFolder' => {
              '@type': 'chatFolder',
              'name': {
                '@type': 'chatFolderName',
                'text': {
                  '@type': 'formattedText',
                  'text': MusicPlaylistService.folderTitle,
                  'entities': <Map<String, dynamic>>[],
                },
              },
              'included_chat_ids': request['chat_folder_id'] == 7
                  ? [900]
                  : [901],
            },
            _ => {'@type': 'ok'},
          };
        },
      );

      await service.createPlaylist('Mix');

      final edits = requests
          .where((request) => request['@type'] == 'editChatFolder')
          .toList();
      expect(edits, hasLength(1));
      expect(
        edits.single['chat_folder_id'],
        7,
        reason: 'the lowest id is canonical so a third folder is never made',
      );
      expect(
        (edits.single['folder'] as Map)['included_chat_ids'],
        containsAll([900, 951]),
        reason: 'the canonical folder keeps its existing chats',
      );
      expect(
        requests.where((request) => request['@type'] == 'createChatFolder'),
        isEmpty,
      );
    });
  });
}
