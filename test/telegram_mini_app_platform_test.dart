import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/telegram_mini_app_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bridge decoder accepts object and encoded event data', () {
    final object = decodeMiniAppBridgePayload(
      '{"eventType":"web_app_ready","eventData":{"value":1}}',
    );
    final encoded = decodeMiniAppBridgePayload(
      '{"eventType":"web_app_open_popup",'
      '"eventData":"{\\"message\\":\\"Hello\\"}"}',
    );

    expect(object?.type, 'web_app_ready');
    expect(object?.data['value'], 1);
    expect(encoded?.data['message'], 'Hello');
    expect(decodeMiniAppBridgePayload('[]'), isNull);
    expect(decodeMiniAppBridgePayload('{"eventData":{}}'), isNull);
  });

  test('Mini App TDLib operations use current request fields', () async {
    final requests = <Map<String, dynamic>>[];
    final service = MiniAppPlatformService(
      botUserId: 42,
      clientId: 7,
      query: (request) async {
        requests.add(request);
        return switch (request['@type']) {
          'sendWebAppCustomRequest' => {
            '@type': 'customRequestResult',
            'result': '{"ok":true}',
          },
          'getUser' => {
            '@type': 'user',
            'usernames': {
              '@type': 'usernames',
              'active_usernames': ['toolbot'],
              'editable_username': '',
              'disabled_usernames': <String>[],
            },
          },
          _ => {'@type': 'ok'},
        };
      },
    );

    await service.attachmentMenuBot();
    await service.setAttachmentMenuInstalled(
      installed: true,
      allowWriteAccess: true,
    );
    expect(await service.canSendMessages(), isTrue);
    await service.allowSendMessages();
    await service.sharePhoneNumber();
    expect(await service.invokeCustomMethod('ping', {'count': 2}), {
      'ok': true,
    });
    expect(
      await service.checkDownload(
        fileName: 'report.pdf',
        url: 'https://example.com/report.pdf',
      ),
      isTrue,
    );
    await service.setInlineDraft(
      chatId: 99,
      botUsername: 'toolbot',
      query: 'cats',
    );
    expect(await service.botUsername(), 'toolbot');
    service.dispose();

    expect(requests.map((value) => value['@type']), [
      'getAttachmentMenuBot',
      'toggleBotIsAddedToAttachmentMenu',
      'canBotSendMessages',
      'allowBotToSendMessages',
      'sharePhoneNumber',
      'sendWebAppCustomRequest',
      'checkWebAppFileDownload',
      'setChatDraftMessage',
      'getUser',
    ]);
    expect(requests[1]['allow_write_access'], isTrue);
    expect(requests[5]['parameters'], '{"count":2}');
    final draft = requests[7]['draft_message'] as Map;
    final content = draft['content'] as Map;
    expect(content['@type'], 'draftMessageContentText');
    expect((content['text'] as Map)['text'], '@toolbot cats');
    expect(requests[7]['topic_id'], isNull);
    expect(requests[7], isNot(contains('message_thread_id')));
  });

  test('device and secure storage are isolated by account and bot', () async {
    SharedPreferences.setMockInitialValues({});
    final secureValues = <String, String>{};
    Future<String?> read(String key) async => secureValues[key];
    Future<void> write(String key, String? value) async {
      if (value == null) {
        secureValues.remove(key);
      } else {
        secureValues[key] = value;
      }
    }

    final first = MiniAppScopedStorage(
      clientId: 1,
      botUserId: 10,
      secureRead: read,
      secureWrite: write,
      secureReadAll: () async => Map.of(secureValues),
    );
    final second = MiniAppScopedStorage(
      clientId: 1,
      botUserId: 11,
      secureRead: read,
      secureWrite: write,
      secureReadAll: () async => Map.of(secureValues),
    );

    await first.saveDevice('theme', 'dark');
    await first.saveSecure('token', 'secret');
    expect(await first.readDevice('theme'), 'dark');
    expect(await first.readSecure('token'), 'secret');
    expect(await second.readDevice('theme'), isNull);
    expect(await second.readSecure('token'), isNull);
    await expectLater(
      first.readDevice('bad\nkey'),
      throwsA(isA<FormatException>()),
    );
    await first.clearDevice();
    await first.clearSecure();
    expect(await first.readDevice('theme'), isNull);
    expect(await first.readSecure('token'), isNull);
  });

  test('emoji status permission and status use pinned TDLib fields', () async {
    final requests = <Map<String, dynamic>>[];
    final service = MiniAppPlatformService(
      botUserId: 42,
      clientId: 7,
      query: (request) async {
        requests.add(request);
        if (request['@type'] == 'getUserFullInfo') {
          return {
            '@type': 'userFullInfo',
            'bot_info': {'@type': 'botInfo', 'can_manage_emoji_status': true},
          };
        }
        return {'@type': 'ok'};
      },
    );

    expect(await service.canManageEmojiStatus(), isTrue);
    await service.setCanManageEmojiStatus(true);
    final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await service.setEmojiStatus(customEmojiId: 123456789, duration: 3600);
    service.dispose();

    expect(requests[0], {'@type': 'getUserFullInfo', 'user_id': 42});
    expect(requests[1], {
      '@type': 'toggleBotCanManageEmojiStatus',
      'bot_user_id': 42,
      'can_manage_emoji_status': true,
    });
    final status = requests[2]['emoji_status'] as Map<String, dynamic>;
    expect(status['@type'], 'emojiStatus');
    expect(status['type'], {
      '@type': 'emojiStatusTypeCustomEmoji',
      'custom_emoji_id': 123456789,
    });
    expect(
      status['expiration_date'] as int,
      inInclusiveRange(before + 3600, before + 3601),
    );
  });

  test('biometry consent and tokens remain scoped to the Mini App', () async {
    SharedPreferences.setMockInitialValues({});
    final secureValues = <String, String>{};
    Future<String?> read(String key) async => secureValues[key];
    Future<void> write(String key, String? value) async {
      if (value == null) {
        secureValues.remove(key);
      } else {
        secureValues[key] = value;
      }
    }

    final controller = MiniAppBiometryController(
      clientId: 3,
      botUserId: 20,
      secureRead: read,
      secureWrite: write,
      supported: true,
      biometricType: 'face',
    );
    final otherBot = MiniAppBiometryController(
      clientId: 3,
      botUserId: 21,
      secureRead: read,
      secureWrite: write,
      supported: true,
    );

    final initial = await controller.info();
    expect(initial['available'], isTrue);
    expect(initial['type'], 'face');
    expect(initial['access_requested'], isFalse);
    expect(initial['device_id'], isNotEmpty);

    await controller.setAccess(granted: true);
    expect(await controller.updateToken('wallet-key'), isTrue);
    expect(await controller.authenticate(), 'wallet-key');
    expect((await controller.info())['token_saved'], isTrue);
    expect((await otherBot.info())['access_requested'], isFalse);
    expect(await otherBot.authenticate(), isNull);
    expect(await controller.updateToken(''), isTrue);
    expect((await controller.info())['token_saved'], isFalse);
  });
}
