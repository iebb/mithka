import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mithka/bot_api/bot_api_account.dart';
import 'package:mithka/bot_api/bot_api_client.dart';
import 'package:mithka/bot_api/bot_api_store.dart';
import 'package:mithka/bot_api/bot_api_td_backend.dart';
import 'package:mithka/chat/outgoing_attachment.dart';
import 'package:mithka/chat/rich_message_source.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'mithka-bot-api-test-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('does not resume backend startup after application shutdown', () async {
    final openGate = Completer<void>();
    final store = _DelayedBotApiStore(
      '${temporaryDirectory.path}/history.sqlite3',
      openGate,
    );
    final updates = <Map<String, dynamic>>[];
    final backend = BotApiTdBackend(
      account: BotApiAccount(
        slot: 3,
        endpoint: Uri.parse('https://bots.example.test'),
        bot: const {
          'id': 999,
          'is_bot': true,
          'first_name': 'Mithka Test Bot',
          'username': 'mithka_test_bot',
        },
      ),
      token: '999:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij',
      databasePath: store.path,
      mediaDirectory: '${temporaryDirectory.path}/files',
      emit: updates.add,
      client: _FakeBotApiClient((_, _) => const <Object>[]),
      store: store,
    );

    final starting = backend.start();
    await store.openStarted.future;
    var closeCompleted = false;
    final closing = backend.close().whenComplete(() => closeCompleted = true);
    await Future<void>.delayed(Duration.zero);

    expect(closeCompleted, isFalse);
    openGate.complete();
    await Future.wait([starting, closing]);
    expect(closeCompleted, isTrue);

    expect(store.closeCount, 2);
    expect(
      updates.map((update) => update['@type']),
      equals(['updateAuthorizationState']),
    );
    expect(
      (updates.single['authorization_state'] as Map)['@type'],
      'authorizationStateClosed',
    );
  });

  test('commits received updates before exposing local TD history', () async {
    final waitForSecondPoll = Completer<Object?>();
    var updateDelivered = false;
    final api = _FakeBotApiClient(
      (method, parameters) {
        switch (method) {
          case 'getWebhookInfo':
            return <String, dynamic>{'url': ''};
          case 'getUpdates':
            if (!updateDelivered) {
              updateDelivered = true;
              return [
                {
                  'update_id': 42,
                  'message': {
                    'message_id': 7,
                    'date': 1700000000,
                    'from': {'id': 123, 'is_bot': false, 'first_name': 'Ada'},
                    'chat': {'id': 123, 'type': 'private', 'first_name': 'Ada'},
                    'text': 'saved on this device',
                  },
                },
              ];
            }
            return waitForSecondPoll.future;
          default:
            throw BotApiException(400, 'Unexpected $method');
        }
      },
      onClose: () {
        if (!waitForSecondPoll.isCompleted) {
          waitForSecondPoll.complete(const []);
        }
      },
    );
    final updates = <Map<String, dynamic>>[];
    final received = Completer<void>();
    final backend = _backend(
      temporaryDirectory,
      api,
      emit: (update) {
        updates.add(update);
        if (update['@type'] == 'updateNewMessage' && !received.isCompleted) {
          received.complete();
        }
      },
    );

    await backend.start();
    await received.future.timeout(const Duration(seconds: 2));

    final history = await backend.query({
      '@type': 'getChatHistory',
      'chat_id': 123,
      'from_message_id': 0,
      'offset': 0,
      'limit': 50,
      'only_local': false,
    });
    final search = await backend.query({
      '@type': 'searchChatMessages',
      'chat_id': 123,
      'query': 'this device',
      'from_message_id': 0,
      'limit': 20,
    });
    final info = await backend.query({'@type': 'getBotApiAccountInfo'});

    expect(history['@type'], 'messages');
    expect((history['messages'] as List).single['id'], 7);
    expect(
      (((history['messages'] as List).single['content'] as Map)['text']
          as Map)['text'],
      'saved on this device',
    );
    expect((search['messages'] as List), hasLength(1));
    expect(info['next_update_offset'], 43);
    expect(api.methods, containsAllInOrder(['getWebhookInfo', 'getUpdates']));
    expect(api.methods, isNot(contains('getChatHistory')));
    expect(updates.map((update) => update['@type']), contains('updateNewChat'));

    await backend.close();
  });

  test('surfaces a webhook conflict without deleting the webhook', () async {
    final conflict = Completer<void>();
    final api = _FakeBotApiClient((method, _) {
      if (method == 'getWebhookInfo') {
        return <String, dynamic>{'url': 'https://example.test/webhook'};
      }
      throw BotApiException(400, 'Unexpected $method');
    });
    final backend = _backend(
      temporaryDirectory,
      api,
      emit: (update) {
        if (update['@type'] == 'updateBotApiConnectionState' &&
            update['has_webhook_conflict'] == true &&
            !conflict.isCompleted) {
          conflict.complete();
        }
      },
    );

    await backend.start();
    await conflict.future.timeout(const Duration(seconds: 2));
    final info = await backend.query({'@type': 'getBotApiAccountInfo'});

    expect(info['has_webhook_conflict'], isTrue);
    expect(api.methods, contains('getWebhookInfo'));
    expect(api.methods, contains('getUserProfilePhotos'));
    expect(api.methods, isNot(contains('deleteWebhook')));
    expect(api.methods, isNot(contains('getUpdates')));

    await backend.close();
  });

  test('retries avatars cached as missing by the previous resolver', () async {
    final store = BotApiStore('${temporaryDirectory.path}/history.sqlite3');
    await store.open();
    store.upsertUser({
      '@type': 'user',
      'id': 123,
      'first_name': 'Ada',
      'last_name': '',
      'profile_photo': null,
      'type': const {'@type': 'userTypeRegular'},
    });
    store.setMetadata('avatar.resolved.user:123', '1');
    store.close();

    final hydrated = Completer<void>();
    final api = _FakeBotApiClient((method, parameters) {
      switch (method) {
        case 'getWebhookInfo':
          return <String, dynamic>{'url': 'https://example.test/webhook'};
        case 'getUserProfilePhotos':
          if (parameters['user_id'] != 123) {
            return <String, dynamic>{'total_count': 0, 'photos': <Object>[]};
          }
          return <String, dynamic>{
            'total_count': 1,
            'photos': [
              [
                {
                  'file_id': 'repaired-avatar-file',
                  'file_unique_id': 'repaired-avatar-unique',
                  'width': 160,
                  'height': 160,
                },
              ],
            ],
          };
        default:
          throw BotApiException(400, 'Unexpected $method');
      }
    });
    final backend = _backend(
      temporaryDirectory,
      api,
      emit: (update) {
        final user = update['user'];
        if (update['@type'] == 'updateUser' &&
            user is Map &&
            user['id'] == 123 &&
            user['profile_photo'] != null &&
            !hydrated.isCompleted) {
          hydrated.complete();
        }
      },
    );

    await backend.start();
    await hydrated.future.timeout(const Duration(seconds: 2));
    final user = await backend.query({'@type': 'getUser', 'user_id': 123});

    expect(user['profile_photo'], isNotNull);
    expect(api.methods, contains('getUserProfilePhotos'));
    await backend.close();
  });

  test('repairs service placeholders already saved in local history', () async {
    const rawMessage = <String, dynamic>{
      'message_id': 7,
      'date': 1700000399,
      'from': {'id': 500, 'is_bot': false, 'first_name': 'Admin'},
      'chat': {'id': -10077, 'type': 'supergroup', 'title': 'Saved group'},
      'new_chat_participant': {
        'id': 124,
        'is_bot': false,
        'first_name': 'Grace',
      },
    };
    final legacyMessage = <String, dynamic>{
      '@type': 'message',
      'id': 7,
      'chat_id': -10077,
      'date': 1700000399,
      'sender_id': const {'@type': 'messageSenderUser', 'user_id': 500},
      'content': const {
        '@type': 'messageText',
        'text': {
          '@type': 'formattedText',
          'text': '[new_chat_participant]',
          'entities': <Object>[],
        },
        'link_preview': null,
      },
    };
    final store = BotApiStore('${temporaryDirectory.path}/history.sqlite3');
    await store.open();
    store.saveRawUpdate(99, const {'update_id': 99, 'message': rawMessage});
    store.upsertMessage(legacyMessage);
    store.upsertChat({
      '@type': 'chat',
      'id': -10077,
      'type': const {
        '@type': 'chatTypeSupergroup',
        'supergroup_id': 77,
        'is_channel': false,
      },
      'title': 'Saved group',
      'photo': null,
      'last_message': legacyMessage,
      'unread_count': 0,
      'positions': const <Object>[],
    });
    store.close();

    final api = _FakeBotApiClient((method, _) {
      switch (method) {
        case 'getWebhookInfo':
          return <String, dynamic>{'url': 'https://example.test/webhook'};
        case 'getUserProfilePhotos':
          return <String, dynamic>{'total_count': 0, 'photos': <Object>[]};
        case 'getChat':
          return <String, dynamic>{
            'id': -10077,
            'type': 'supergroup',
            'title': 'Saved group',
          };
        default:
          throw BotApiException(400, 'Unexpected $method');
      }
    });
    final backend = _backend(temporaryDirectory, api, emit: (_) {});

    await backend.start();
    final history = await backend.query({
      '@type': 'getChatHistory',
      'chat_id': -10077,
      'from_message_id': 0,
      'offset': 0,
      'limit': 20,
    });
    final storedMessage = (history['messages'] as List).single as Map;
    final storedUser = await backend.query({
      '@type': 'getUser',
      'user_id': 124,
    });

    expect((storedMessage['content'] as Map)['@type'], 'messageChatAddMembers');
    expect((storedMessage['content'] as Map)['member_user_ids'], [124]);
    expect(storedUser['first_name'], 'Grace');
    expect(jsonEncode(history), isNot(contains('[new_chat_participant]')));
    await backend.close();
  });

  test(
    'converts current and compatible service fields without raw labels',
    () async {
      final waitForSecondPoll = Completer<Object?>();
      final receivedLastMessage = Completer<void>();
      var pollingStarted = false;
      final api = _FakeBotApiClient(
        (method, parameters) {
          switch (method) {
            case 'getWebhookInfo':
              return <String, dynamic>{'url': ''};
            case 'getUpdates':
              if (pollingStarted) return waitForSecondPoll.future;
              pollingStarted = true;
              const chat = {
                'id': -10077,
                'type': 'supergroup',
                'title': 'Service test',
              };
              const actor = {'id': 500, 'is_bot': false, 'first_name': 'Admin'};
              return [
                {
                  'update_id': 101,
                  'message': {
                    'message_id': 1,
                    'date': 1700000401,
                    'from': actor,
                    'chat': chat,
                    'new_chat_members': [
                      {'id': 123, 'is_bot': false, 'first_name': 'Ada'},
                    ],
                  },
                },
                {
                  'update_id': 102,
                  'message': {
                    'message_id': 2,
                    'date': 1700000402,
                    'from': actor,
                    'chat': chat,
                    'new_chat_participant': {
                      'id': 124,
                      'is_bot': false,
                      'first_name': 'Grace',
                    },
                  },
                },
                {
                  'update_id': 103,
                  'message': {
                    'message_id': 3,
                    'date': 1700000403,
                    'from': actor,
                    'chat': chat,
                    'left_chat_participant': {
                      'id': 123,
                      'is_bot': false,
                      'first_name': 'Ada',
                    },
                  },
                },
                {
                  'update_id': 104,
                  'message': {
                    'message_id': 4,
                    'date': 1700000404,
                    'from': actor,
                    'chat': chat,
                    'new_chat_title': 'Renamed service test',
                  },
                },
                {
                  'update_id': 105,
                  'message': {
                    'message_id': 5,
                    'date': 1700000405,
                    'from': {
                      'id': 321,
                      'is_bot': true,
                      'first_name': 'Peer Bot',
                    },
                    'chat': chat,
                    'text': 'bot-to-bot observed',
                  },
                },
                {
                  'update_id': 106,
                  'message': {
                    'message_id': 6,
                    'date': 1700000406,
                    'from': actor,
                    'chat': chat,
                    'community_chat_removed': <String, dynamic>{},
                  },
                },
                {
                  'update_id': 107,
                  'message': {
                    'message_id': 7,
                    'date': 1700000407,
                    'from': actor,
                    'chat': chat,
                    'community_chat_added': {
                      'community': {'id': 77, 'name': 'Neko'},
                    },
                  },
                },
              ];
            case 'getUserProfilePhotos':
              return <String, dynamic>{'total_count': 0, 'photos': <Object>[]};
            case 'getChat':
              return <String, dynamic>{
                'id': -10077,
                'type': 'supergroup',
                'title': 'Renamed service test',
              };
            default:
              throw BotApiException(400, 'Unexpected $method');
          }
        },
        onClose: () {
          if (!waitForSecondPoll.isCompleted) {
            waitForSecondPoll.complete(const []);
          }
        },
      );
      final backend = _backend(
        temporaryDirectory,
        api,
        bot: const {
          'id': 999,
          'is_bot': true,
          'first_name': 'Mithka Test Bot',
          'username': 'mithka_test_bot',
          'can_read_all_group_messages': true,
        },
        emit: (update) {
          final message = update['message'];
          if (update['@type'] == 'updateNewMessage' &&
              message is Map &&
              message['id'] == 7 &&
              !receivedLastMessage.isCompleted) {
            receivedLastMessage.complete();
          }
        },
      );

      await backend.start();
      await receivedLastMessage.future.timeout(const Duration(seconds: 2));
      final history = await backend.query({
        '@type': 'getChatHistory',
        'chat_id': -10077,
        'from_message_id': 0,
        'offset': 0,
        'limit': 20,
      });
      final messages = (history['messages'] as List).cast<Map>();
      final contentTypes = {
        for (final message in messages)
          (message['content'] as Map)['@type'] as String,
      };
      final joined = messages.firstWhere((message) => message['id'] == 2);
      final left = messages.firstWhere((message) => message['id'] == 3);
      final removed = messages.firstWhere((message) => message['id'] == 6);
      final added = messages.firstWhere((message) => message['id'] == 7);
      final user = await backend.query({'@type': 'getUser', 'user_id': 124});
      final info = await backend.query({'@type': 'getBotApiAccountInfo'});

      expect(
        contentTypes,
        containsAll({
          'messageChatAddMembers',
          'messageChatDeleteMember',
          'messageChatChangeTitle',
          'messageText',
        }),
      );
      expect((joined['content'] as Map)['member_user_ids'], [124]);
      expect((left['content'] as Map)['user_id'], 123);
      expect(
        (removed['content'] as Map)['@type'],
        'messageChatRemovedFromCommunity',
      );
      expect((added['content'] as Map), {
        '@type': 'messageChatAddedToCommunity',
        'community_id': 77,
        'community_name': 'Neko',
      });
      expect(user['first_name'], 'Grace');
      expect(jsonEncode(history), isNot(contains('[new_chat_')));
      expect(info['can_read_all_group_messages'], isTrue);
      expect(info['bot_to_bot_access_observed'], isTrue);

      await backend.close();
    },
  );

  test('sends native rich messages directly through the active bot', () async {
    final api = _FakeBotApiClient((method, _) {
      switch (method) {
        case 'getWebhookInfo':
          return <String, dynamic>{'url': 'https://example.test/webhook'};
        case 'getUserProfilePhotos':
          return <String, dynamic>{'total_count': 0, 'photos': <Object>[]};
        case 'sendRichMessage':
          return <String, dynamic>{
            'message_id': 88,
            'date': 1700000100,
            'from': {
              'id': 999,
              'is_bot': true,
              'first_name': 'Mithka Test Bot',
            },
            'chat': {'id': 123, 'type': 'private', 'first_name': 'Ada'},
            'rich_message': {'blocks': <Object>[], 'is_rtl': false},
          };
        default:
          throw BotApiException(400, 'Unexpected $method');
      }
    });
    final backend = _backend(temporaryDirectory, api, emit: (_) {});
    final image = File('${temporaryDirectory.path}/rich.jpg');
    await image.writeAsBytes(const [0xff, 0xd8, 0xff, 0xd9]);
    await backend.start();

    final result = await backend.query({
      '@type': 'sendMessage',
      'chat_id': 123,
      'input_message_content':
          botApiDirectRichMessageInputContent('<h2>Hello</h2>', [
            RichMessageSendFile(
              id: 'photo-1',
              attachment: OutgoingAttachment(
                path: image.path,
                kind: OutgoingAttachmentKind.photo,
              ),
            ),
          ]),
    });

    expect(result['@type'], 'message');
    final multipart = api.multipartCalls.single;
    expect(multipart.method, 'sendRichMessage');
    expect(multipart.files.keys, ['rich_media_0']);
    final rich = jsonDecode(multipart.fields['rich_message']!) as Map;
    expect(rich['html'], '<h2>Hello</h2>');
    expect(((rich['media'] as List).single as Map)['id'], 'photo-1');
    expect(api.methods, isNot(contains('forwardMessages')));

    await backend.close();
  });

  test(
    'loads observed avatars and recent sticker sets from local history',
    () async {
      final waitForSecondPoll = Completer<Object?>();
      final hydrated = Completer<void>();
      final chatHydrated = Completer<void>();
      var updateDelivered = false;
      final api = _FakeBotApiClient(
        (method, parameters) {
          switch (method) {
            case 'getWebhookInfo':
              return <String, dynamic>{'url': ''};
            case 'getUpdates':
              if (!updateDelivered) {
                updateDelivered = true;
                return [
                  {
                    'update_id': 60,
                    'message': {
                      'message_id': 9,
                      'date': 1700000200,
                      'from': {'id': 123, 'is_bot': false, 'first_name': 'Ada'},
                      'chat': {
                        'id': 123,
                        'type': 'private',
                        'first_name': 'Ada',
                      },
                      'sticker': {
                        'file_id': 'sticker-file',
                        'file_unique_id': 'sticker-unique',
                        'type': 'regular',
                        'width': 512,
                        'height': 512,
                        'is_animated': false,
                        'is_video': false,
                        'emoji': '🙂',
                        'set_name': 'ObservedPack',
                      },
                    },
                  },
                ];
              }
              return waitForSecondPoll.future;
            case 'getUserProfilePhotos':
              if (parameters['user_id'] != 123) {
                return <String, dynamic>{
                  'total_count': 0,
                  'photos': <Object>[],
                };
              }
              return <String, dynamic>{
                'total_count': 1,
                'photos': [
                  [
                    {
                      'file_id': 'avatar-file',
                      'file_unique_id': 'avatar-unique',
                      'width': 160,
                      'height': 160,
                      'file_size': 1234,
                    },
                  ],
                ],
              };
            case 'getChat':
              return <String, dynamic>{
                'id': 123,
                'type': 'private',
                'first_name': 'Ada',
                'photo': {
                  'small_file_id': 'chat-avatar-small',
                  'small_file_unique_id': 'chat-avatar-small-unique',
                  'big_file_id': 'chat-avatar-big',
                  'big_file_unique_id': 'chat-avatar-big-unique',
                },
              };
            case 'getChatAdministrators':
              return [
                {
                  'user': {'id': 123, 'is_bot': false, 'first_name': 'Ada'},
                  'status': 'administrator',
                },
              ];
            case 'sendMessage':
              return <String, dynamic>{
                'message_id': 10,
                'date': 1700000201,
                'from': {
                  'id': 999,
                  'is_bot': true,
                  'first_name': 'Mithka Test Bot',
                },
                'chat': {'id': 123, 'type': 'private', 'first_name': 'Ada'},
                'text': 'lightweight update',
              };
            case 'getStickerSet':
              return <String, dynamic>{
                'name': 'ObservedPack',
                'title': 'Observed Pack',
                'sticker_type': 'regular',
                'stickers': [
                  {
                    'file_id': 'sticker-file',
                    'file_unique_id': 'sticker-unique',
                    'type': 'regular',
                    'width': 512,
                    'height': 512,
                    'is_animated': false,
                    'is_video': false,
                    'emoji': '🙂',
                    'set_name': 'ObservedPack',
                  },
                ],
              };
            default:
              throw BotApiException(400, 'Unexpected $method');
          }
        },
        onClose: () {
          if (!waitForSecondPoll.isCompleted) {
            waitForSecondPoll.complete(const []);
          }
        },
      );
      final backend = _backend(
        temporaryDirectory,
        api,
        emit: (update) {
          final user = update['user'];
          if (update['@type'] == 'updateUser' &&
              user is Map &&
              user['id'] == 123 &&
              user['profile_photo'] != null &&
              !hydrated.isCompleted) {
            hydrated.complete();
          }
          if (update['@type'] == 'updateChatPhoto' &&
              update['chat_id'] == 123 &&
              update['photo'] != null &&
              !chatHydrated.isCompleted) {
            chatHydrated.complete();
          }
        },
      );

      await backend.start();
      await Future.wait([
        hydrated.future,
        chatHydrated.future,
      ]).timeout(const Duration(seconds: 2));
      final recent = await backend.query({
        '@type': 'getRecentStickers',
        'is_attached': false,
      });
      final sets = await backend.query({
        '@type': 'getInstalledStickerSets',
        'sticker_type': {'@type': 'stickerTypeRegular'},
      });
      final setId = ((sets['sets'] as List).single as Map)['id'] as int;
      final set = await backend.query({
        '@type': 'getStickerSet',
        'set_id': setId,
      });
      await backend.query({'@type': 'getChatAdministrators', 'chat_id': 123});
      await backend.query({
        '@type': 'sendMessage',
        'chat_id': 123,
        'input_message_content': {
          '@type': 'inputMessageText',
          'text': {
            '@type': 'formattedText',
            'text': 'lightweight update',
            'entities': <Object>[],
          },
        },
      });
      final hydratedUser = await backend.query({
        '@type': 'getUser',
        'user_id': 123,
      });
      final hydratedChat = await backend.query({
        '@type': 'getChat',
        'chat_id': 123,
      });

      expect(recent['stickers'], hasLength(1));
      expect(sets['sets'], hasLength(1));
      expect(set['name'], 'ObservedPack');
      expect(set['stickers'], hasLength(1));
      expect(hydratedUser['profile_photo'], isNotNull);
      expect(hydratedChat['photo'], isNotNull);

      await backend.close();
    },
  );

  test('hydrates custom emoji packs observed in local messages', () async {
    final waitForSecondPoll = Completer<Object?>();
    final received = Completer<void>();
    var updateDelivered = false;
    Map<String, dynamic>? customEmojiParameters;
    final api = _FakeBotApiClient(
      (method, parameters) {
        switch (method) {
          case 'getWebhookInfo':
            return <String, dynamic>{'url': ''};
          case 'getUpdates':
            if (!updateDelivered) {
              updateDelivered = true;
              return [
                {
                  'update_id': 70,
                  'message': {
                    'message_id': 10,
                    'date': 1700000300,
                    'from': {'id': 123, 'is_bot': false, 'first_name': 'Ada'},
                    'chat': {'id': 123, 'type': 'private', 'first_name': 'Ada'},
                    'text': 'x',
                    'entities': [
                      {
                        'type': 'custom_emoji',
                        'offset': 0,
                        'length': 1,
                        'custom_emoji_id': 'remote-custom-emoji',
                      },
                    ],
                  },
                },
              ];
            }
            return waitForSecondPoll.future;
          case 'getUserProfilePhotos':
            return <String, dynamic>{'total_count': 0, 'photos': <Object>[]};
          case 'getChat':
            return <String, dynamic>{
              'id': 123,
              'type': 'private',
              'first_name': 'Ada',
            };
          case 'getCustomEmojiStickers':
            customEmojiParameters = parameters;
            return [
              {
                'file_id': 'custom-sticker-file',
                'file_unique_id': 'custom-sticker-unique',
                'type': 'custom_emoji',
                'width': 100,
                'height': 100,
                'is_animated': false,
                'is_video': false,
                'emoji': '✨',
                'set_name': 'ObservedEmojiPack',
                'custom_emoji_id': 'remote-custom-emoji',
              },
            ];
          case 'getStickerSet':
            return <String, dynamic>{
              'name': 'ObservedEmojiPack',
              'title': 'Observed Emoji Pack',
              'sticker_type': 'custom_emoji',
              'stickers': [
                {
                  'file_id': 'custom-sticker-file',
                  'file_unique_id': 'custom-sticker-unique',
                  'type': 'custom_emoji',
                  'width': 100,
                  'height': 100,
                  'is_animated': false,
                  'is_video': false,
                  'emoji': '✨',
                  'set_name': 'ObservedEmojiPack',
                  'custom_emoji_id': 'remote-custom-emoji',
                },
              ],
            };
          default:
            throw BotApiException(400, 'Unexpected $method');
        }
      },
      onClose: () {
        if (!waitForSecondPoll.isCompleted) {
          waitForSecondPoll.complete(const []);
        }
      },
    );
    final backend = _backend(
      temporaryDirectory,
      api,
      emit: (update) {
        if (update['@type'] == 'updateNewMessage' && !received.isCompleted) {
          received.complete();
        }
      },
    );

    await backend.start();
    await received.future.timeout(const Duration(seconds: 2));
    final sets = await backend.query({
      '@type': 'getInstalledStickerSets',
      'sticker_type': {'@type': 'stickerTypeCustomEmoji'},
    });
    final setInfo = (sets['sets'] as List).single as Map;
    final set = await backend.query({
      '@type': 'getStickerSet',
      'set_id': setInfo['id'],
    });

    expect(customEmojiParameters?['custom_emoji_ids'], ['remote-custom-emoji']);
    expect(setInfo['name'], 'ObservedEmojiPack');
    expect(set['name'], 'ObservedEmojiPack');
    expect(
      (((set['stickers'] as List).single as Map)['full_type'] as Map)['@type'],
      'stickerFullTypeCustomEmoji',
    );

    await backend.close();
  });

  test('maps TD profile changes to bot self-profile methods', () async {
    var photoSet = false;
    final api = _FakeBotApiClient((method, _) {
      switch (method) {
        case 'getWebhookInfo':
          return <String, dynamic>{'url': 'https://example.test/webhook'};
        case 'getUserProfilePhotos':
          return <String, dynamic>{
            'total_count': photoSet ? 1 : 0,
            'photos': photoSet
                ? [
                    [
                      {
                        'file_id': 'new-avatar-file',
                        'file_unique_id': 'new-avatar-unique',
                        'width': 256,
                        'height': 256,
                      },
                    ],
                  ]
                : <Object>[],
          };
        case 'setMyName':
        case 'setMyShortDescription':
        case 'setMyDescription':
          return true;
        case 'setMyProfilePhoto':
          photoSet = true;
          return true;
        case 'getMyShortDescription':
          return <String, dynamic>{'short_description': 'Profile text'};
        default:
          throw BotApiException(400, 'Unexpected $method');
      }
    });
    final backend = _backend(temporaryDirectory, api, emit: (_) {});
    final image = File('${temporaryDirectory.path}/avatar.jpg');
    await image.writeAsBytes(const [0xff, 0xd8, 0xff, 0xd9]);
    await backend.start();

    expect(
      (await backend.query({
        '@type': 'setName',
        'first_name': 'Updated Bot',
        'last_name': '',
      }))['@type'],
      'ok',
    );
    expect(
      (await backend.query({
        '@type': 'setBio',
        'bio': 'Profile text',
      }))['@type'],
      'ok',
    );
    expect(
      (await backend.query({
        '@type': 'setProfilePhoto',
        'photo': {
          '@type': 'inputChatPhotoStatic',
          'photo': {'@type': 'inputFileLocal', 'path': image.path},
        },
      }))['@type'],
      'ok',
    );
    final me = await backend.query({'@type': 'getMe'});
    final full = await backend.query({
      '@type': 'getUserFullInfo',
      'user_id': 999,
    });

    expect(me['first_name'], 'Updated Bot');
    expect(me['profile_photo'], isNotNull);
    expect((full['bio'] as Map)['text'], 'Profile text');
    expect(
      api.methods,
      containsAll([
        'setMyName',
        'setMyShortDescription',
        'setMyDescription',
        'setMyProfilePhoto',
      ]),
    );

    await backend.close();
  });
}

BotApiTdBackend _backend(
  Directory root,
  BotApiClient client, {
  required void Function(Map<String, dynamic>) emit,
  Map<String, dynamic>? bot,
}) {
  return BotApiTdBackend(
    account: BotApiAccount(
      slot: 3,
      endpoint: Uri.parse('https://bots.example.test'),
      bot:
          bot ??
          const {
            'id': 999,
            'is_bot': true,
            'first_name': 'Mithka Test Bot',
            'username': 'mithka_test_bot',
          },
    ),
    token: '999:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij',
    databasePath: '${root.path}/history.sqlite3',
    mediaDirectory: '${root.path}/files',
    emit: emit,
    client: client,
  );
}

typedef _FakeCall =
    FutureOr<Object?> Function(String method, Map<String, dynamic> parameters);

class _FakeBotApiClient extends BotApiClient {
  _FakeBotApiClient(this._call, {this.onClose})
    : super(
        token: '999:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij',
        endpoint: Uri.parse('https://bots.example.test'),
        httpClient: MockClient((_) async => throw StateError('unused')),
      );

  final _FakeCall _call;
  final void Function()? onClose;
  final List<String> methods = [];
  final List<
    ({String method, Map<String, String> fields, Map<String, String> files})
  >
  multipartCalls = [];

  @override
  Future<Object?> call(
    String method, [
    Map<String, dynamic> parameters = const {},
  ]) async {
    methods.add(method);
    return _call(method, parameters);
  }

  @override
  Future<Object?> callMultipart(
    String method, {
    required Map<String, String> fields,
    required Map<String, String> files,
  }) async {
    methods.add(method);
    multipartCalls.add((method: method, fields: fields, files: files));
    return _call(method, {'fields': fields, 'files': files});
  }

  @override
  void close() {
    onClose?.call();
    super.close();
  }
}

class _DelayedBotApiStore extends BotApiStore {
  _DelayedBotApiStore(super.path, this._openGate);

  final Completer<void> _openGate;
  final Completer<void> openStarted = Completer<void>();
  int closeCount = 0;

  @override
  Future<void> open() async {
    if (!openStarted.isCompleted) openStarted.complete();
    await _openGate.future;
  }

  @override
  void close() {
    closeCount += 1;
  }
}
