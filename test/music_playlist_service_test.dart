import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/music_playlist_service.dart';
import 'package:mithka/tdlib/td_models.dart';

Map<String, dynamic> _audioMessage({
  required int chatId,
  required int messageId,
  required int fileId,
  String title = 'Track',
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
      'title': title,
      'performer': 'Artist',
      'file_name': '$title.mp3',
      'audio': {'@type': 'file', 'id': fileId},
    },
  },
};

void main() {
  test(
    'loads playlist chats and their audio messages from _Playlist',
    () async {
      final requests = <Map<String, dynamic>>[];
      final service = MusicPlaylistService(
        folderUpdate: () => {
          '@type': 'updateChatFolders',
          'chat_folders': [
            {'@type': 'chatFolderInfo', 'id': 7, 'title': '_Playlist'},
          ],
        },
        query: (request) async {
          requests.add(request);
          return switch (request['@type']) {
            'getChatFolder' => {
              '@type': 'chatFolder',
              'title': '_Playlist',
              'included_chat_ids': [900],
            },
            'getChat' => {'@type': 'chat', 'id': 900, 'title': 'Favourites'},
            'searchChatMessages' => {
              '@type': 'foundChatMessages',
              'messages': [
                _audioMessage(chatId: 900, messageId: 11, fileId: 44),
              ],
            },
            _ => throw StateError('Unexpected request: $request'),
          };
        },
      );

      final playlists = await service.loadPlaylists();

      expect(playlists, hasLength(1));
      expect(playlists.single.title, 'Favourites');
      expect(playlists.single.tracks.single.music?.file?.id, 44);
      expect(
        requests.any((request) => request['@type'] == 'searchChatMessages'),
        isTrue,
      );
    },
  );

  test('creates a private playlist chat and adds it to _Playlist', () async {
    final requests = <Map<String, dynamic>>[];
    final service = MusicPlaylistService(
      folderUpdate: () => {
        '@type': 'updateChatFolders',
        'chat_folders': <Map<String, dynamic>>[],
      },
      query: (request) async {
        requests.add(request);
        return switch (request['@type']) {
          'createNewSupergroupChat' => {
            '@type': 'chat',
            'id': 901,
            'title': 'Road trip',
          },
          'createChatFolder' => {'@type': 'chatFolderInfo', 'id': 8},
          _ => throw StateError('Unexpected request: $request'),
        };
      },
    );

    final playlist = await service.createPlaylist('Road trip');

    expect(playlist.chatId, 901);
    final folderRequest = requests.firstWhere(
      (request) => request['@type'] == 'createChatFolder',
    );
    final folder = folderRequest['folder'] as Map<String, dynamic>;
    expect(folder['title'], isNull);
    expect(folder['color_id'], -1);
    expect(
      ((folder['name'] as Map<String, dynamic>)['text']
          as Map<String, dynamic>)['text'],
      MusicPlaylistService.folderTitle,
    );
    expect(folder['included_chat_ids'], [901]);
  });

  test('adds and removes tracks as messages in the playlist chat', () async {
    final requests = <Map<String, dynamic>>[];
    final service = MusicPlaylistService(
      query: (request) async {
        requests.add(request);
        if (request['@type'] == 'forwardMessages') {
          return {
            '@type': 'messages',
            'messages': [_audioMessage(chatId: 902, messageId: 12, fileId: 45)],
          };
        }
        if (request['@type'] == 'deleteMessages') {
          return {'@type': 'ok'};
        }
        throw StateError('Unexpected request: $request');
      },
    );
    const playlist = MusicPlaylist(chatId: 902, title: 'Saved');
    final source = ChatMessage(
      id: 4,
      chatId: 10,
      date: 1,
      isOutgoing: false,
      text: '',
      music: MessageMusic(
        title: 'Track',
        performer: 'Artist',
        duration: 120,
        file: TdFileRef(id: 45),
      ),
    );

    final saved = await service.addTrack(playlist, source);
    await service.removeTrack(playlist, saved);

    final send = requests.first;
    expect(send['chat_id'], 902);
    expect(send['@type'], 'forwardMessages');
    expect(send['from_chat_id'], 10);
    expect(send['message_ids'], [4]);
    expect(send['send_copy'], isTrue);
    expect(requests.last['message_ids'], [12]);
  });
}
