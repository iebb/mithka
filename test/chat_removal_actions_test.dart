import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_info_view.dart';
import 'package:mithka/chats/chat_delete_policy.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/chats/chat_removal_actions.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ChatBackend backend;
  late List<Map<String, dynamic>> localUpdates;
  late StreamSubscription<Map<String, dynamic>> subscription;

  setUpAll(() {
    L10nFixtures.load().install();
    // No native client or real Telegram account is used by these tests.
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) => backend.query(request),
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = _ChatBackend();
    localUpdates = [];
    subscription = TdClient.shared.subscribe().listen(localUpdates.add);
  });
  tearDown(() => subscription.cancel());

  for (final entry in ['list', 'info']) {
    test(
      '$entry does not hide a chat or clear history when leave fails',
      () async {
        backend
          ..type = 'chatTypeBasicGroup'
          ..canClear = true
          ..failLeave = true;
        final info = ChatInfoViewModel(chatId: 42, title: 'Group')
          ..isMember = true;
        final list = ChatListViewModel();
        addTearDown(info.dispose);
        addTearDown(list.dispose);
        await expectLater(
          entry == 'list' ? list.deleteChat(_summary(false)) : info.leaveChat(),
          throwsA(isA<StateError>()),
        );
        expect(info.isMember, isTrue);
        expect(localUpdates, isEmpty);
        expect(backend.types, ['getChat', 'leaveChat']);
      },
    );

    test(
      '$entry preserves successful leave if basic-group cleanup fails',
      () async {
        backend
          ..type = 'chatTypeBasicGroup'
          ..canClear = true
          ..failDelete = true;
        final info = ChatInfoViewModel(chatId: 42, title: 'Group')
          ..isMember = true;
        final list = ChatListViewModel();
        addTearDown(info.dispose);
        addTearDown(list.dispose);
        await expectLater(
          entry == 'list' ? list.deleteChat(_summary(false)) : info.leaveChat(),
          throwsA(isA<ChatLeaveHistoryCleanupFailed>()),
        );
        if (entry == 'info') expect(info.isMember, isFalse);
        expect(localUpdates, [chatLeftLocalUpdate(42)]);
        expect(backend.types, [
          'getChat',
          'leaveChat',
          'getChat',
          'deleteChatHistory',
        ]);
        expect(backend.requests.last['revoke'], isFalse);
        expect(
          info.actionErrorNotice(
            ChatLeaveHistoryCleanupFailed(StateError('error')),
          ),
          AppStrings.t(AppStringKeys.chatLeaveHistoryCleanupFailed),
        );
      },
    );
  }

  for (final allowed in [false, null]) {
    test(
      'clearing history requires explicit self permission ($allowed)',
      () async {
        backend
          ..canClear = allowed
          ..canDeleteForAll = true;
        final info = ChatInfoViewModel(chatId: 42, title: 'Group')
          ..canClearHistory =
              true; // Permission changed after the dialog opened.
        addTearDown(info.dispose);
        await expectLater(
          info.clearHistory(),
          throwsA(isA<ChatRemovalUnavailable>()),
        );
        expect(info.canClearHistory, isFalse);
        expect(backend.types, ['getChat']);
        expect(localUpdates, isEmpty);
      },
    );
  }

  test(
    'clearing history keeps membership and never upgrades to all users',
    () async {
      backend
        ..canClear = true
        ..canDeleteForAll = true;
      final info = ChatInfoViewModel(chatId: 42, title: 'Group')
        ..isMember = true;
      addTearDown(info.dispose);
      await info.clearHistory();
      expect(info.isMember, isTrue);
      expect(backend.types, ['getChat', 'deleteChatHistory']);
      expect(backend.requests.last, {
        '@type': 'deleteChatHistory',
        'chat_id': 42,
        'remove_from_chat_list': false,
        'revoke': false,
      });
      expect(localUpdates, [
        {'@type': 'mithkaChatHistoryCleared', 'chat_id': 42},
      ]);
    },
  );

  test('unknown chat types and failed lookups never issue a leave', () async {
    final info = ChatInfoViewModel(chatId: 42, title: 'Unknown');
    addTearDown(info.dispose);
    backend.type = 'chatTypePrivate';
    await expectLater(info.leaveChat(), throwsA(isA<ChatRemovalUnavailable>()));
    backend.failGet = true;
    await expectLater(info.leaveChat(), throwsA(isA<StateError>()));
    expect(backend.types, ['getChat', 'getChat']);
    expect(localUpdates, isEmpty);
  });

  for (final scope in ChatDeleteScope.values) {
    test(
      'private chat deletion preserves the explicitly selected $scope scope',
      () async {
        final list = ChatListViewModel();
        addTearDown(list.dispose);
        final chat = _summary(false)..kind = ChatKind.privateChat;
        await list.deleteChat(chat, scope: scope);
        expect(backend.types, ['deleteChatHistory']);
        expect(
          backend.requests.single['revoke'],
          scope == ChatDeleteScope.allUsers,
        );
        expect(localUpdates, isEmpty);
      },
    );
  }

  test('delete for all members requires the TDLib capability', () async {
    var deleted = 0;
    backend.canDeleteForAll = false;
    await expectLater(
      deleteChatForAllMembers(
        chatId: 42,
        query: backend.query,
        onDeleted: () => deleted++,
      ),
      throwsA(isA<ChatRemovalUnavailable>()),
    );
    expect(backend.types, ['getChat']);
    expect(deleted, 0);

    backend
      ..requests.clear()
      ..canDeleteForAll = true;
    await deleteChatForAllMembers(
      chatId: 42,
      query: backend.query,
      onDeleted: () => deleted++,
    );
    expect(backend.types, ['getChat', 'deleteChat']);
    expect(backend.requests.last, {'@type': 'deleteChat', 'chat_id': 42});
    expect(deleted, 1);
  });
}

ChatSummary _summary(bool channel) => ChatSummary(
  id: 42,
  title: 'Group',
  lastMessage: '',
  lastMessageId: 0,
  date: 0,
  unreadCount: 0,
  order: 1,
  isMuted: false,
  kind: channel ? ChatKind.channel : ChatKind.group,
);

class _ChatBackend {
  String type = 'chatTypeSupergroup';
  bool isChannel = false;
  bool? canClear = false;
  bool canDeleteForAll = false;
  bool failGet = false;
  bool failLeave = false;
  bool failDelete = false;
  bool failDeleteChat = false;
  bool revokeClearOnLeave = false;
  final requests = <Map<String, dynamic>>[];
  List<String> get types => [
    for (final request in requests) request['@type'] as String,
  ];

  Map<String, dynamic> get chat => {
    '@type': 'chat',
    'id': 42,
    'title': 'Group',
    'type': {
      '@type': type,
      'supergroup_id': 10,
      'basic_group_id': 10,
      'is_channel': isChannel,
    },
    if (canClear != null) 'can_be_deleted_only_for_self': canClear,
    'can_be_deleted_for_all_users': canDeleteForAll,
  };

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) async {
    requests.add(Map.of(request));
    switch (request['@type']) {
      case 'getChat':
        if (failGet) throw StateError('lookup failed');
        return chat;
      case 'leaveChat':
        if (failLeave) throw StateError('leave failed');
        if (revokeClearOnLeave) canClear = false;
        return {'@type': 'ok'};
      case 'deleteChatHistory':
        if (failDelete) throw StateError('cleanup failed');
        return {'@type': 'ok'};
      case 'deleteChat':
        if (failDeleteChat) throw StateError('delete failed');
        return {'@type': 'ok'};
      case 'getMe':
        return {'@type': 'user', 'id': 1};
      case 'getSupergroup':
        return {'@type': 'supergroup', 'id': 10, 'is_forum': false};
      case 'getChatMember':
        return {
          'status': {'@type': 'chatMemberStatusMember'},
        };
      case 'getSupergroupFullInfo':
        return {'@type': 'supergroupFullInfo', 'member_count': 0};
      case 'getSupergroupMembers':
        return {'@type': 'chatMembers', 'members': <Object>[]};
      default:
        return {'@type': 'ok'};
    }
  }
}
