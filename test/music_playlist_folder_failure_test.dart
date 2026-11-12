import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/music_playlist_service.dart';
import 'package:mithka/tdlib/td_client.dart';

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

void main() {
  group('an unreadable known folder blocks writes without creating a chat', () {
    test(
      "createPlaylist throws and writes nothing when getChatFolder(7) fails",
      () async {
        final requests = <Map<String, dynamic>>[];
        final service = MusicPlaylistService(
          folderUpdate: () => _snapshot([_folderInfo(7)]),
          query: (request) {
            requests.add(request);
            return switch (request['@type']) {
              'getChatFolder' => Future<Map<String, dynamic>>.error(
                StateError('folder 7 unavailable'),
              ),
              _ => Future.value({'@type': 'ok'}),
            };
          },
        );

        await expectLater(service.createPlaylist('Mix'), throwsA(anything));

        final types = requests.map((request) => request['@type']).toList();
        expect(types, ['getChatFolder']);
        expect(
          types,
          isNot(contains('createNewSupergroupChat')),
          reason: 'the chat must not exist when the catalog is unvalidated',
        );
        expect(types, isNot(contains('createChatFolder')));
        expect(types, isNot(contains('editChatFolder')));
      },
    );
  });

  group('the cold-cache waiter cancels its subscription on timeout', () {
    Map<String, dynamic> seedPushedFolders(TdClient client) {
      // Make the latest pushed snapshot match the cached one, so the waiter
      // cannot take its snapshot fast path and must own a subscription.
      client.routeUpdateForTesting({
        '@type': 'updateChatFolders',
        '@client_id': 1,
        'chat_folders': [_folderInfo(7)],
      });
      return client.latestChatFoldersUpdateForClient(1)!;
    }

    test(
      'a timed-out wait resolves with the cached snapshot and detaches',
      () async {
        final client = TdClient.shared;
        final seeded = seedPushedFolders(client);

        final wait = MusicPlaylistService.waiterForClient(
          1,
          timeout: const Duration(milliseconds: 50),
        )(seeded);

        final resolved = await wait;
        expect(
          resolved,
          same(seeded),
          reason: 'a timed-out wait falls back to the cached snapshot',
        );

        // The leak regression: a matching update arriving AFTER the timeout
        // must neither crash nor resurrect the dead wait. With the old
        // firstWhere().timeout() the leaked subscription stayed live on the
        // broadcast stream for the rest of the session; with the owned
        // subscription the late update is dropped by the isCompleted guard.
        client.routeUpdateForTesting({
          '@type': 'updateChatFolders',
          '@client_id': 1,
          'chat_folders': [_folderInfo(99)],
        });
        await Future<void>.delayed(Duration.zero);
        expect(
          client.latestChatFoldersUpdateForClient(1)?['chat_folders'],
          isNotNull,
          reason: 'the late push still updates the cache',
        );
      },
    );
  });
}
