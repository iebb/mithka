import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/emoji_channel_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(paths, (call) async => '/tmp');
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(paths, null);
  });

  group('parseCatalog', () {
    test('parses the exteraless-shaped catalog message', () {
      const body = '#emojiv2\n'
          '{\n'
          '    "emojis": [\n'
          '        {"name": "Apple", "version": 2, "id": "apple", "preview": 22, "file": 23},\n'
          '        {"name": "Twemoji", "version": 2, "id": "twemoji", "preview": 48, "file": 49}\n'
          '    ]\n'
          '}';
      final entries = EmojiChannelSource.parseCatalog(body);
      expect(entries, isNotNull);
      expect(entries!.map((e) => e.key), ['apple', 'twemoji']);
      final apple = entries.first;
      expect(apple.label, 'Apple');
      expect(apple.channelMessageId, 23);
      expect(apple.isChannelServed, isTrue);
      expect(apple.extension, 'ttf');
      expect(apple.url, isEmpty);
    });

    test('rejects a body without the tag or json', () {
      expect(EmojiChannelSource.parseCatalog('hello'), isNull);
      expect(EmojiChannelSource.parseCatalog('#emojiv2 no braces'), isNull);
    });

    test('rejects entries without a usable file id', () {
      const body = '#emojiv2 {"emojis": [{"name": "X", "id": "x", "file": 0}]}';
      expect(EmojiChannelSource.parseCatalog(body), isNull);
    });
  });

  group('fetchCatalog', () {
    test('resolves the channel, searches and stamps the chat id', () async {
      final calls = <Map<String, dynamic>>[];
      final source = EmojiChannelSource(
        client: _ScriptedTdClient((request) async {
          calls.add(Map<String, dynamic>.from(request));
          switch (request['@type']) {
            case 'searchPublicChat':
              return {
                '@type': 'chat',
                'id': '-3778471221',
                'type': {'@type': 'chatTypeSupergroup'},
              };
            case 'searchChatMessages':
              if (request['query'] != '#emojiv2') {
                return {'@type': 'messages', 'total_count': 0, 'messages': []};
              }
              if (request['chat_id'] != '-3778471221') {
                return {'@type': 'messages', 'total_count': 0, 'messages': []};
              }
              return {
                '@type': 'messages',
                'total_count': 1,
                'messages': [
                  {
                    '@type': 'message',
                    'id': 50,
                    'content': {
                      '@type': 'messageText',
                      'text': {
                        '@type': 'formattedText',
                        'text':
                            '#emojiv2 {"emojis": [{"name": "Fluent 3D", '
                            '"id": "fluent", "preview": 42, "file": 43}]}',
                      },
                    },
                  },
                ],
              };
          }
          return {'@type': 'ok'};
        }),
      );
      final entries = await source.fetchCatalog();
      expect(entries, isNotNull);
      expect(entries!.single.key, 'fluent');
      expect(entries.single.chatId, -3778471221);
      expect(entries.single.channelMessageId, 43);
      expect(
        calls.map((c) => c['@type']),
        containsAll(['searchPublicChat', 'searchChatMessages']),
      );
    });

    test('returns null when no account client is active', () async {
      final inactive = EmojiChannelSource(client: _NoClientTdClient());
      expect(await inactive.fetchCatalog(), isNull);
    });

    test('returns null when the search finds no catalog message', () async {
      final source = EmojiChannelSource(
        client: _ScriptedTdClient((request) async {
          switch (request['@type']) {
            case 'searchPublicChat':
              return {
                '@type': 'chat',
                'id': '-100',
                'type': {'@type': 'chatTypeSupergroup'},
              };
            case 'searchChatMessages':
              return {
                '@type': 'messages',
                'total_count': 0,
                'messages': [],
              };
          }
          return {'@type': 'ok'};
        }),
      );
      expect(await source.fetchCatalog(), isNull);
    });
  });

  group('downloadFont', () {
    test('walks message → document → downloadFile and copies to dest',
        () async {
      final tmpDir = await Directory.systemTemp.createTemp('emoji_channel');
      addTearDown(() => tmpDir.delete(recursive: true));
      final fakeTdPath = '${tmpDir.path}/td-cache.ttf';
      File(fakeTdPath).writeAsBytesSync(List.filled(64, 9), flush: true);
      final destPath = '${tmpDir.path}/dest.ttf';

      final source = EmojiChannelSource(
        client: _ScriptedTdClient((request) async {
          switch (request['@type']) {
            case 'searchPublicChat':
              return {'@type': 'chat', 'id': '-1'};
            case 'getChatMessages':
              if (request['message_ids'] != [43]) {
                return {'@type': 'messages', 'messages': []};
              }
              return {
                '@type': 'messages',
                'messages': [
                  {
                    '@type': 'message',
                    'id': 43,
                    'content': {
                      '@type': 'messageDocument',
                      'document': {
                        '@type': 'document',
                        'document': {
                          '@type': 'file',
                          'id': 7777,
                          'expected_size': 64,
                        },
                      },
                    },
                  },
                ],
              };
            case 'downloadFile':
              if (request['file_id'] != 7777) {
                return {'@type': 'file', 'id': 7777, 'local': {'@type': 'localFile', 'path': '', 'is_downloading_completed': false}};
              }
              if (request['synchronous'] != true) {
                return {'@type': 'file', 'id': 7777, 'local': {'@type': 'localFile', 'path': '', 'is_downloading_completed': false}};
              }
              return {
                '@type': 'file',
                'id': 7777,
                'local': {
                  '@type': 'localFile',
                  'path': fakeTdPath,
                  'is_downloading_completed': true,
                },
              };
          }
          return {'@type': 'ok'};
        }),
      );

      final bytes = await source.downloadFont(
        chatId: -1,
        messageId: 43,
        destPath: destPath,
      );
      expect(bytes, 64);
      expect(File(destPath).lengthSync(), 64);
    });
  });
}

typedef _Handler = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> request,
);

class _ScriptedTdClient implements TdClient {
  _ScriptedTdClient(this.handler);

  final _Handler handler;

  @override
  int get activeClientId => 1;

  @override
  bool get hasActiveClient => true;

  @override
  Future<Map<String, dynamic>> query(
    Map<String, dynamic> request, {
    Duration timeout = TdClient.defaultQueryTimeout,
  }) => handler(request);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _NoClientTdClient implements TdClient {
  @override
  bool get hasActiveClient => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
