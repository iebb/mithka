import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Packed ids: TDLib server ids carry `server_id << 20` in the low bits.
const int _shift = 20;

/// Two real accounts — slot 1 / client 100 and slot 2 / client 101 — so a bulk
/// read that follows the foreground instead of the client it started on is
/// observable in the exact (client, request) pairs.
const int _alphaClientId = 100;
const int _betaClientId = 101;

typedef _Respond =
    Future<Map<String, dynamic>> Function(
      Map<String, dynamic> request,
      int clientId,
    );

/// Stands in for tdjson: allocates client ids and answers the close handshake
/// so a slot can be removed without the real timeout.
class _FakeBindings implements TdBindings {
  _FakeBindings(this._client);

  final TdClient _client;
  int _nextClientId = _alphaClientId;

  @override
  int createClientId() => _nextClientId++;

  @override
  void send(int clientId, String request) {
    final decoded = jsonDecode(request) as Map<String, dynamic>;
    if (decoded['@type'] == 'close') {
      _client.debugCompleteClientClosed(clientId);
    }
  }

  @override
  void importSessionString(String sessionString, String destinationPath) {
    File(destinationPath).writeAsBytesSync(Uint8List.fromList(const [1]));
  }

  @override
  bool get supportsSessionStringBackup => true;

  @override
  bool get supportsTransferBoost => false;

  @override
  String? receive(double timeout) => throw UnimplementedError();

  @override
  Object? receiveJson(double timeout) => throw UnimplementedError();

  @override
  String? execute(String request) => throw UnimplementedError();

  @override
  String exportSessionString(
    String sourcePath, {
    required int apiId,
    required bool testMode,
    required int userId,
  }) => throw UnimplementedError();

  @override
  void configureTransferBoost({
    required int downloadChunkSize,
    required int downloadParallelism,
    required int uploadChunkSize,
    required int uploadParallelism,
  }) {}
}

final class _Registry {
  _Registry(this.client, this.supportDir);

  final TdClient client;
  final Directory supportDir;
  late final int alphaSlot;
  late final int betaSlot;

  /// Every request as (client that served it, request body), in order.
  final List<(int, Map<String, dynamic>)> requests = [];

  List<({int clientId, String type, int? chatId})> tuples(
    Iterable<String> types,
  ) => [
    for (final (clientId, request) in requests)
      if (types.contains(request['@type']))
        (
          clientId: clientId,
          type: request['@type'] as String,
          chatId: request['chat_id'] as int?,
        ),
  ];

  void switchToBeta() => client.setActive(betaSlot);
}

Future<_Registry> _startRegistry(_Respond respond) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final supportDir = Directory.systemTemp.createTempSync('mithka_folder_owner');
  addTearDown(() {
    if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
  });

  final client = TdClient.forTesting();
  final bindings = _FakeBindings(client);
  final registry = _Registry(client, supportDir);
  client.prepareForTesting(
    prefs: prefs,
    supportDir: supportDir.path,
    bindings: bindings,
    queryOverride: (request, clientId) async {
      registry.requests.add((clientId, Map<String, dynamic>.from(request)));
      return respond(request, clientId);
    },
  );
  registry.alphaSlot = client.addSlot();
  registry.betaSlot = client.addSlot();
  client.setActive(registry.alphaSlot);
  return registry;
}

/// Answers a folder enumeration with two unread chats, holding the first read
/// receipt when [holdFirstWrite] is given.
_Respond _folderResponder({
  Completer<void>? holdFirstWrite,
  bool failWrites = false,
}) {
  var writes = 0;
  return (request, clientId) async {
    switch (request['@type']) {
      case 'loadChats':
        // "Nothing left to load" for the folder.
        throw TdError({'code': 404, 'message': 'Not Found'});
      case 'getChats':
        return {
          '@type': 'chats',
          'chat_ids': const <int>[11, 12],
        };
      case 'getChat':
        if (clientId == _alphaClientId) {
          return switch (request['chat_id']) {
            11 => _chat(11, unread: 2, lastMessageId: 7 << _shift),
            12 => _chat(12, unread: 1, lastMessageId: 8 << _shift),
            _ => _chat(request['chat_id'] as int),
          };
        }
        // The replacement account owns the same numeric ids with different
        // content, so a request that leaked into it is visible here.
        return _chat(request['chat_id'] as int, title: 'beta');
      case 'viewMessages':
        writes++;
        if (failWrites) {
          throw TdError({'code': 400, 'message': 'chat not found'});
        }
        if (holdFirstWrite != null && writes == 1) {
          await holdFirstWrite.future;
        }
        return const {'@type': 'ok'};
    }
    return const {'@type': 'ok'};
  };
}

void main() {
  test(
    'a disposed list sends no read receipt through the account that replaced it',
    () async {
      final hold = Completer<void>();
      final registry = await _startRegistry(
        _folderResponder(holdFirstWrite: hold),
      );
      // No account slot: this is the production list, which follows the
      // foreground client on every call.
      final model = ChatListViewModel(clientForTesting: registry.client);

      final run = model.markFolderRead(7);
      // The first receipt is in flight; the list is then unmounted and the
      // other account becomes the foreground one.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      model.dispose();
      registry.switchToBeta();
      hold.complete();
      await run;

      final writes = registry.tuples(const ['viewMessages']);
      expect(writes, const [
        (clientId: _alphaClientId, type: 'viewMessages', chatId: 11),
      ], reason: 'only the request that was already in flight may land');
      expect(
        registry.requests.where((entry) => entry.$1 == _betaClientId),
        isEmpty,
        reason: 'the old account ids never reach the replacement account',
      );
    },
  );

  test('an account switch strands the rest of the bulk read', () async {
    final hold = Completer<void>();
    final registry = await _startRegistry(
      _folderResponder(holdFirstWrite: hold),
    );
    final model = ChatListViewModel(clientForTesting: registry.client);
    addTearDown(model.dispose);

    final run = model.markFolderRead(7);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    registry.switchToBeta();
    hold.complete();
    await run;

    expect(
      registry.tuples(const ['viewMessages']),
      const [(clientId: _alphaClientId, type: 'viewMessages', chatId: 11)],
      reason: 'the second chat is left for the account it belongs to',
    );
    expect(
      registry.requests.where((entry) => entry.$1 == _betaClientId),
      isEmpty,
    );
  });

  test(
    'both unread chats are read on the account that started the run',
    () async {
      final registry = await _startRegistry(_folderResponder());
      final model = ChatListViewModel(clientForTesting: registry.client);
      addTearDown(model.dispose);

      await model.markFolderRead(7);

      expect(registry.tuples(const ['viewMessages']), const [
        (clientId: _alphaClientId, type: 'viewMessages', chatId: 11),
        (clientId: _alphaClientId, type: 'viewMessages', chatId: 12),
      ]);
    },
  );

  test('a failed receipt does not stop the next chat', () async {
    final registry = await _startRegistry(_folderResponder(failWrites: true));
    final model = ChatListViewModel(clientForTesting: registry.client);
    addTearDown(model.dispose);

    await model.markFolderRead(7);

    expect(
      registry.tuples(const ['viewMessages']).map((tuple) => tuple.chatId),
      const [11, 12],
      reason: 'one rejected chat must not leave the rest unread',
    );
  });

  test(
    'an all-chats read enumerates main and archive, not the selection',
    () async {
      final registry = await _startRegistry((request, clientId) async {
        switch (request['@type']) {
          case 'loadChats':
            throw TdError({'code': 404, 'message': 'Not Found'});
          case 'getChats':
            final list = request['chat_list'] as Map<String, dynamic>;
            return {
              '@type': 'chats',
              'chat_ids': list['@type'] == 'chatListArchive'
                  ? const <int>[31]
                  : const <int>[11, 12],
            };
          case 'getChat':
            return switch (request['chat_id']) {
              11 => _chat(11, unread: 1, lastMessageId: 7 << _shift),
              12 => _chat(12),
              31 => _chat(31, unread: 1, lastMessageId: 9 << _shift),
              _ => _chat(request['chat_id'] as int),
            };
        }
        return const {'@type': 'ok'};
      });
      final model = ChatListViewModel(clientForTesting: registry.client);
      addTearDown(model.dispose);

      await model.markAllChatsRead();

      expect(
        registry.tuples(const ['viewMessages']),
        const [
          (clientId: _alphaClientId, type: 'viewMessages', chatId: 11),
          (clientId: _alphaClientId, type: 'viewMessages', chatId: 31),
        ],
        reason:
            'the archive is part of "all", and a chat this list never '
            'loaded is still read',
      );
      final enumerated = [
        for (final (_, request) in registry.requests)
          if (request['@type'] == 'getChats')
            (request['chat_list'] as Map<String, dynamic>)['@type'],
      ];
      expect(enumerated, const ['chatListMain', 'chatListArchive']);
    },
  );
}

Map<String, dynamic> _chat(
  int id, {
  String title = 'alpha',
  int unread = 0,
  int lastMessageId = 0,
}) => {
  '@type': 'chat',
  'id': id,
  'title': '$title $id',
  'type': {'@type': 'chatTypePrivate', 'user_id': id + 1000},
  'unread_count': unread,
  'is_marked_as_unread': false,
  'last_read_inbox_message_id': 0,
  if (lastMessageId > 0)
    'last_message': {
      '@type': 'message',
      'id': lastMessageId,
      'chat_id': id,
      'date': 1700000000,
      'is_outgoing': false,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 42},
      'content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'Hello'},
      },
    },
};
