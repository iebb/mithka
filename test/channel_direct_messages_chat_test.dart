import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A channel's direct messages chat is a monoforum: every subscriber talks to
// the channel in a topic of that group. TDLib reports the current user as
// "left" there until their first message exists, so the generic left-group
// handling must not turn it into a join prompt — the chat is writable as soon
// as the parent channel is readable (TDLib ChatManager grants Write whenever
// the parent channel is readable).
const _parentChannelId = -1002035446470;
const _dmChatId = -2072035446470;
const _dmSupergroupId = 1072035446470;

const _emptyPage = <String, dynamic>{
  '@type': 'messages',
  'total_count': 0,
  'messages': <Map<String, dynamic>>[],
};

const _chatPermissions = <String, dynamic>{
  '@type': 'chatPermissions',
  'can_send_basic_messages': true,
  'can_send_audios': true,
  'can_send_documents': true,
  'can_send_photos': true,
  'can_send_videos': true,
  'can_send_video_notes': true,
  'can_send_voice_notes': true,
  'can_send_polls': true,
  'can_send_other_messages': true,
  'can_add_link_previews': true,
  'can_react_to_messages': true,
  'can_create_topics': true,
};

Map<String, dynamic> _dmChat() => {
  '@type': 'chat',
  'id': _dmChatId,
  'title': 'LINUX DO Channel',
  'type': {
    '@type': 'chatTypeSupergroup',
    'supergroup_id': _dmSupergroupId,
    'is_channel': false,
  },
  'permissions': _chatPermissions,
  'unread_count': 0,
  'last_read_inbox_message_id': 0,
  'last_read_outbox_message_id': 0,
  // TDLib marks the monoforum chat as "left" until the user's own topic exists.
};

Map<String, dynamic> _dmSupergroup({bool administered = false}) => {
  '@type': 'supergroup',
  'id': _dmSupergroupId,
  'is_channel': false,
  'is_forum': false,
  'is_direct_messages_group': true,
  'is_administered_direct_messages_group': administered,
  'has_forum_tabs': false,
  'join_to_send_messages': false,
  'status': {
    '@type': administered ? 'chatMemberStatusCreator' : 'chatMemberStatusLeft',
  },
};

Map<String, dynamic> _dmFullInfo() => {
  '@type': 'supergroupFullInfo',
  'member_count': 0,
  // A monoforum's full info answers with the parent channel's chat id.
  'direct_messages_chat_id': _parentChannelId,
  'linked_chat_id': 0,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  bool isDmChat = true;
  bool administered = false;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          switch (request['@type']) {
            case 'getChat':
              if (!isDmChat) {
                return {
                  '@type': 'chat',
                  'id': 4242,
                  'title': 'Plain Group',
                  'type': {
                    '@type': 'chatTypeSupergroup',
                    'supergroup_id': 4243,
                    'is_channel': false,
                  },
                  'permissions': _chatPermissions,
                };
              }
              return _dmChat();
            case 'getSupergroup':
              if (!isDmChat) {
                return {
                  '@type': 'supergroup',
                  'id': 4243,
                  'is_channel': false,
                  'is_forum': false,
                  'is_direct_messages_group': false,
                  'status': {'@type': 'chatMemberStatusLeft'},
                };
              }
              return _dmSupergroup(administered: administered);
            case 'getSupergroupFullInfo':
              return isDmChat
                  ? _dmFullInfo()
                  : {'@type': 'supergroupFullInfo', 'member_count': 3};
            case 'getChatHistory':
              return _emptyPage;
            case 'getMe':
              return {'@type': 'user', 'id': 1, 'first_name': 'Me'};
          }
          return {'@type': 'ok'};
        },
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);

  Future<ChatViewModel> openChat(int chatId, String title) async {
    final vm = ChatViewModel(
      chatId: chatId,
      title: title,
      markReadOnOpen: false,
    );
    addTearDown(vm.dispose);
    vm.onAppear();
    for (var i = 0; i < 100 && !vm.initialLoaded; i++) {
      await pumpEventQueue();
    }
    expect(vm.initialLoaded, isTrue);
    return vm;
  }

  setUp(() {
    isDmChat = true;
    administered = false;
  });

  test(
    'a channel direct messages chat opens writable, not as a join prompt',
    () async {
      final vm = await openChat(_dmChatId, 'LINUX DO Channel');

      expect(vm.isDirectMessagesGroup, isTrue);
      expect(
        vm.isMember,
        isTrue,
        reason: 'a monoforum is not joined; the server scopes it to my topic',
      );
      expect(
        vm.canSendMessages,
        isTrue,
        reason:
            'TDLib grants write access while the parent channel is readable',
      );
      expect(vm.canJoin, isFalse);
    },
  );

  test(
    'an administered direct messages chat keeps its admin capabilities',
    () async {
      administered = true;
      final vm = await openChat(_dmChatId, 'LINUX DO Channel');

      expect(vm.isDirectMessagesGroup, isTrue);
      expect(vm.isAdministeredDirectMessagesGroup, isTrue);
      expect(vm.canSendMessages, isTrue);
    },
  );

  test('a plain group you left still offers the join bar', () async {
    isDmChat = false;
    final vm = await openChat(4242, 'Plain Group');

    expect(vm.isDirectMessagesGroup, isFalse);
    expect(vm.isMember, isFalse);
    expect(vm.canSendMessages, isFalse);
    expect(vm.canJoin, isTrue);
  });
}
