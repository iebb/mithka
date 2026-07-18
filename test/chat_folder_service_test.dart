import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/chat_folder_service.dart';

void main() {
  group('ChatFolderDraft', () {
    test('parses current TDLib folder shape and rebuilds an exact request', () {
      final draft = ChatFolderDraft.fromRaw({
        '@type': 'chatFolder',
        'name': {
          '@type': 'chatFolderName',
          'text': {
            '@type': 'formattedText',
            'text': 'Work',
            'entities': <Map<String, dynamic>>[],
          },
          'animate_custom_emoji': true,
        },
        'icon': {'@type': 'chatFolderIcon', 'name': 'Work'},
        'color_id': 3,
        'is_shareable': true,
        'pinned_chat_ids': [9],
        'included_chat_ids': [5, 2],
        'excluded_chat_ids': [7],
        'exclude_muted': true,
        'exclude_read': false,
        'exclude_archived': true,
        'include_contacts': true,
        'include_non_contacts': false,
        'include_bots': true,
        'include_groups': true,
        'include_channels': false,
      });

      expect(draft.title, 'Work');
      expect(draft.includedChatIds, {2, 5});
      expect(draft.excludeArchived, isTrue);

      final request = draft.toRequest();
      expect(request['@type'], 'chatFolder');
      expect(((request['name'] as Map)['text'] as Map)['text'], 'Work');
      expect(request['included_chat_ids'], [2, 5]);
      expect(request['pinned_chat_ids'], [9]);
      expect(request['include_bots'], isTrue);
    });
  });

  group('ChatFolderService', () {
    test('loads folder details in update order', () async {
      final requests = <Map<String, dynamic>>[];
      final service = ChatFolderService(
        query: (request) async {
          requests.add(request);
          final id = request['chat_folder_id'] as int;
          return _folder(id == 4 ? 'Friends' : 'News');
        },
      );

      final folders = await service.load({
        '@type': 'updateChatFolders',
        'chat_folders': [
          {'@type': 'chatFolderInfo', 'id': 4},
          {'@type': 'chatFolderInfo', 'id': 8, 'has_my_invite_links': true},
        ],
      });

      expect(folders.map((item) => item.title), ['Friends', 'News']);
      expect(folders.last.hasInviteLinks, isTrue);
      expect(requests.map((item) => item['chat_folder_id']), [4, 8]);
    });

    test(
      'creates, edits, reorders, and toggles tags with TDLib fields',
      () async {
        final requests = <Map<String, dynamic>>[];
        final service = ChatFolderService(
          query: (request) async {
            requests.add(request);
            return request['@type'] == 'createChatFolder'
                ? {'@type': 'chatFolderInfo', 'id': 12}
                : {'@type': 'ok'};
          },
        );
        const draft = ChatFolderDraft(
          title: 'Bots',
          includeBots: true,
          excludedChatIds: {99},
        );

        expect(await service.create(draft), 12);
        await service.edit(12, draft.copyWith(title: 'Tools'));
        await service.reorder([12, 3], 9);
        await service.toggleTags(true);
        await service.delete(12);

        expect(requests[0]['@type'], 'createChatFolder');
        expect((requests[0]['folder'] as Map)['include_bots'], isTrue);
        expect(requests[1]['chat_folder_id'], 12);
        expect(requests[2]['main_chat_list_position'], 2);
        expect(requests[3]['are_tags_enabled'], isTrue);
        expect(requests[4]['leave_chat_ids'], isEmpty);
      },
    );

    test('loads recommendations and manages invite links', () async {
      final requests = <Map<String, dynamic>>[];
      final service = ChatFolderService(
        query: (request) async {
          requests.add(request);
          return switch (request['@type']) {
            'getRecommendedChatFolders' => {
              '@type': 'recommendedChatFolders',
              'chat_folders': [
                {'description': 'Unread messages', 'folder': _folder('Unread')},
              ],
            },
            'getChatsForChatFolderInviteLink' => {
              '@type': 'chats',
              'chat_ids': [10, 11],
            },
            'getChatFolderInviteLinks' => {
              '@type': 'chatFolderInviteLinks',
              'invite_links': [
                {
                  '@type': 'chatFolderInviteLink',
                  'invite_link': 'https://t.me/addlist/test',
                  'name': 'Team',
                  'chat_ids': [10],
                },
              ],
            },
            _ => {'@type': 'ok'},
          };
        },
      );

      final recommendations = await service.recommended();
      expect(recommendations.single.draft.title, 'Unread');
      expect(recommendations.single.description, 'Unread messages');
      expect(await service.shareableChats(6), [10, 11]);
      expect((await service.inviteLinks(6)).single['name'], 'Team');
      await service.createInviteLink(
        folderId: 6,
        name: ' Team ',
        chatIds: [10, 11],
      );
      await service.editInviteLink(
        folderId: 6,
        inviteLink: 'https://t.me/addlist/test',
        name: ' Renamed ',
        chatIds: [10],
      );
      await service.deleteInviteLink(
        folderId: 6,
        inviteLink: 'https://t.me/addlist/test',
      );

      expect(requests[3]['name'], 'Team');
      expect(requests[3]['chat_ids'], [10, 11]);
      expect(requests[4]['@type'], 'editChatFolderInviteLink');
      expect(requests[4]['name'], 'Renamed');
      expect(requests[5]['invite_link'], 'https://t.me/addlist/test');
    });
  });
}

Map<String, dynamic> _folder(String title) => {
  '@type': 'chatFolder',
  'name': {
    '@type': 'chatFolderName',
    'text': {
      '@type': 'formattedText',
      'text': title,
      'entities': <Map<String, dynamic>>[],
    },
    'animate_custom_emoji': true,
  },
  'icon': {'@type': 'chatFolderIcon', 'name': 'Custom'},
  'color_id': -1,
  'is_shareable': false,
  'pinned_chat_ids': <int>[],
  'included_chat_ids': <int>[],
  'excluded_chat_ids': <int>[],
  'exclude_muted': false,
  'exclude_read': false,
  'exclude_archived': false,
  'include_contacts': false,
  'include_non_contacts': false,
  'include_bots': false,
  'include_groups': false,
  'include_channels': false,
};
