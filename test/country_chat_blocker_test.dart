import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/country_chat_blocker.dart';
import 'package:mithka/settings/country_message_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<CountryMessageFilter> filterWith({
    bool exemptPlainText = false,
    String country = 'JP',
  }) async {
    SharedPreferences.setMockInitialValues({
      'countryMessageFilter.selectedCountries': [country],
      'countryMessageFilter.exemptCommonPrivateGroup': false,
      'countryMessageFilter.exemptThreeCommonGroups': false,
      'countryMessageFilter.exemptPlainText': exemptPlainText,
      'countryMessageFilter.exemptNonDefaultAvatar': false,
    });
    final prefs = await SharedPreferences.getInstance();
    return CountryMessageFilter()..initialize(prefs);
  }

  Map<String, dynamic> incoming({int id = 500, String text = 'hello'}) => {
    '@type': 'message',
    'id': id,
    'chat_id': 42,
    'is_outgoing': false,
    'content': {
      '@type': 'messageText',
      'text': {
        '@type': 'formattedText',
        'text': text,
        'entities': <Map<String, dynamic>>[],
      },
    },
  };

  Map<String, dynamic> firstContactActionBar(String country) => {
    '@type': 'chatActionBarReportAddBlock',
    'account_info': {
      '@type': 'accountInfo',
      'registration_month': 4,
      'registration_year': 2025,
      'phone_number_country_code': country,
    },
  };

  test('quarantines the first matching inbound private message', () async {
    final requests = <Map<String, dynamic>>[];
    final blocker = CountryChatBlocker(
      filter: await filterWith(),
      query: (request, _) async {
        requests.add(request);
        return switch (request['@type']) {
          'getChat' => {
            '@type': 'chat',
            'id': 42,
            'type': {'@type': 'chatTypePrivate', 'user_id': 7},
            'action_bar': firstContactActionBar('JP'),
            'notification_settings': {
              '@type': 'chatNotificationSettings',
              'use_default_mute_for': true,
              'mute_for': 0,
              'use_default_sound': false,
              'sound_id': 99,
              'use_default_show_preview': false,
              'show_preview': false,
            },
          },
          'getUser' => {
            '@type': 'user',
            'id': 7,
            'phone_number': '+81 90 1234 5678',
          },
          _ => {'@type': 'ok'},
        };
      },
    );

    expect(
      await blocker.handleIncomingMessage(incoming(), clientId: 3),
      isTrue,
    );
    expect(blocker.suppressesChat(42, 3), isTrue);
    expect(
      requests.any((request) => request['@type'] == 'viewMessages'),
      isTrue,
    );
    final mute = requests.firstWhere(
      (request) => request['@type'] == 'setChatNotificationSettings',
    );
    expect(mute['notification_settings']['mute_for'], 2147483647);
    expect(mute['notification_settings']['sound_id'], 99);
    expect(mute['notification_settings']['show_preview'], isFalse);
    final create = requests.firstWhere(
      (request) => request['@type'] == 'createChatFolder',
    );
    expect(create['folder']['name']['text']['text'], '_Blocked');
    expect(create['folder']['included_chat_ids'], [42]);

    final mutationsBefore = requests.length;
    expect(
      await blocker.handleIncomingMessage(incoming(id: 501), clientId: 3),
      isTrue,
    );
    final laterRequests = requests.sublist(mutationsBefore);
    expect(laterRequests, hasLength(1));
    expect(laterRequests.single['@type'], 'viewMessages');
    expect(laterRequests.single['message_ids'], [501]);
  });

  test('does not quarantine an existing conversation', () async {
    final requests = <Map<String, dynamic>>[];
    final blocker = CountryChatBlocker(
      filter: await filterWith(),
      query: (request, _) async {
        requests.add(request);
        return switch (request['@type']) {
          'getChat' => {
            '@type': 'chat',
            'id': 42,
            'type': {'@type': 'chatTypePrivate', 'user_id': 7},
          },
          _ => {'@type': 'ok'},
        };
      },
    );

    expect(
      await blocker.handleIncomingMessage(incoming(), clientId: 3),
      isFalse,
    );
    expect(
      requests.any(
        (request) => request['@type'] == 'setChatNotificationSettings',
      ),
      isFalse,
    );
    expect(
      requests.any((request) => request['@type'] == 'getChatHistory'),
      isFalse,
    );
  });

  test('does not evaluate a non-private chat', () async {
    final requests = <Map<String, dynamic>>[];
    final blocker = CountryChatBlocker(
      filter: await filterWith(),
      query: (request, _) async {
        requests.add(request);
        return {
          '@type': 'chat',
          'id': 42,
          'type': {'@type': 'chatTypeSupergroup', 'supergroup_id': 77},
          'action_bar': firstContactActionBar('JP'),
        };
      },
    );

    expect(
      await blocker.handleIncomingMessage(incoming(), clientId: 3),
      isFalse,
    );
    expect(requests.map((request) => request['@type']), ['getChat']);
  });

  test('plain text exemption keeps the new chat visible', () async {
    final blocker = CountryChatBlocker(
      filter: await filterWith(exemptPlainText: true),
      query: (request, _) async => switch (request['@type']) {
        'getChat' => {
          '@type': 'chat',
          'id': 42,
          'type': {'@type': 'chatTypePrivate', 'user_id': 7},
          'action_bar': firstContactActionBar('JP'),
        },
        'getUser' => {
          '@type': 'user',
          'id': 7,
          'phone_number': '+81 90 1234 5678',
        },
        _ => {'@type': 'ok'},
      },
    );

    expect(
      await blocker.handleIncomingMessage(incoming(), clientId: 3),
      isFalse,
    );
  });

  test(
    'uses pending first-contact country after an earlier message was missed',
    () async {
      final requests = <Map<String, dynamic>>[];
      final blocker = CountryChatBlocker(
        filter: await filterWith(country: 'UZ'),
        query: (request, _) async {
          requests.add(request);
          return switch (request['@type']) {
            'getChat' => {
              '@type': 'chat',
              'id': 42,
              'type': {'@type': 'chatTypePrivate', 'user_id': 7},
              'action_bar': firstContactActionBar('UZ'),
            },
            'getUser' => {'@type': 'user', 'id': 7, 'phone_number': ''},
            _ => {'@type': 'ok'},
          };
        },
      );

      expect(
        await blocker.handleIncomingMessage(incoming(), clientId: 3),
        isTrue,
      );
      expect(blocker.suppressesChat(42, 3), isTrue);
      expect(
        requests.any((request) => request['@type'] == 'getChatHistory'),
        isFalse,
      );
      expect(
        requests.any(
          (request) => request['@type'] == 'setChatNotificationSettings',
        ),
        isTrue,
      );
    },
  );

  test('merges membership into an existing _Blocked folder', () async {
    final requests = <Map<String, dynamic>>[];
    var folderIncluded = <int>[10];
    final blocker = CountryChatBlocker(
      filter: await filterWith(),
      folderSnapshot: (_) => {
        '@type': 'updateChatFolders',
        'chat_folders': [
          {
            '@type': 'chatFolderInfo',
            'id': 8,
            'name': {
              '@type': 'chatFolderName',
              'text': {
                '@type': 'formattedText',
                'text': '_Blocked',
                'entities': <Map<String, dynamic>>[],
              },
            },
          },
        ],
      },
      query: (request, _) async {
        requests.add(request);
        if (request['@type'] == 'editChatFolder') {
          folderIncluded = List<int>.from(
            request['folder']['included_chat_ids'] as List,
          );
          return {'@type': 'chatFolderInfo', 'id': 8};
        }
        return switch (request['@type']) {
          'getChat' => {
            '@type': 'chat',
            'id': 42,
            'type': {'@type': 'chatTypePrivate', 'user_id': 7},
            'action_bar': firstContactActionBar('JP'),
          },
          'getUser' => {
            '@type': 'user',
            'id': 7,
            'phone_number': '+81 90 1234 5678',
          },
          'getChatFolder' => {
            '@type': 'chatFolder',
            'name': {
              '@type': 'chatFolderName',
              'text': {
                '@type': 'formattedText',
                'text': '_Blocked',
                'entities': <Map<String, dynamic>>[],
              },
            },
            'included_chat_ids': folderIncluded,
          },
          _ => {'@type': 'ok'},
        };
      },
    );

    expect(
      await blocker.handleIncomingMessage(incoming(), clientId: 3),
      isTrue,
    );
    expect(
      requests.any((request) => request['@type'] == 'createChatFolder'),
      isFalse,
    );
    final edits = requests
        .where((request) => request['@type'] == 'editChatFolder')
        .toList();
    expect(edits, hasLength(1));
    expect(edits.single['folder']['included_chat_ids'], [10, 42]);
  });

  test('converges duplicate _Blocked folders created by two devices', () async {
    final requests = <Map<String, dynamic>>[];
    final includedByFolder = <int, List<int>>{
      8: [10],
      9: [11],
    };
    Map<String, dynamic> folderInfo(int id) => {
      '@type': 'chatFolderInfo',
      'id': id,
      'name': {
        '@type': 'chatFolderName',
        'text': {
          '@type': 'formattedText',
          'text': '_Blocked',
          'entities': <Map<String, dynamic>>[],
        },
      },
    };

    final blocker = CountryChatBlocker(
      filter: await filterWith(),
      folderSnapshot: (_) => {
        '@type': 'updateChatFolders',
        'chat_folders': [folderInfo(9), folderInfo(8)],
      },
      query: (request, _) async {
        requests.add(request);
        final type = request['@type'];
        if (type == 'editChatFolder') {
          final id = request['chat_folder_id'] as int;
          includedByFolder[id] = List<int>.from(
            request['folder']['included_chat_ids'] as List,
          );
          return folderInfo(id);
        }
        if (type == 'deleteChatFolder') {
          includedByFolder.remove(request['chat_folder_id']);
          return {'@type': 'ok'};
        }
        return switch (type) {
          'getChat' => {
            '@type': 'chat',
            'id': 42,
            'type': {'@type': 'chatTypePrivate', 'user_id': 7},
            'action_bar': firstContactActionBar('JP'),
          },
          'getUser' => {
            '@type': 'user',
            'id': 7,
            'phone_number': '+81 90 1234 5678',
          },
          'getChatFolder' => {
            '@type': 'chatFolder',
            'name': folderInfo(request['chat_folder_id'] as int)['name'],
            'included_chat_ids':
                includedByFolder[request['chat_folder_id'] as int] ??
                const <int>[],
          },
          _ => {'@type': 'ok'},
        };
      },
    );

    expect(
      await blocker.handleIncomingMessage(incoming(), clientId: 3),
      isTrue,
    );
    expect(includedByFolder.keys, [8]);
    expect(includedByFolder[8], [10, 11, 42]);
    final deletion = requests.singleWhere(
      (request) => request['@type'] == 'deleteChatFolder',
    );
    expect(deletion['chat_folder_id'], 9);
    expect(deletion['leave_chat_ids'], isEmpty);
  });
}
