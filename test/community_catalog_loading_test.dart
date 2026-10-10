import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  var canViewHistory = false;
  // Upstream TDLib answers with communityFullInfo.chats; the retired Mithka
  // patch answered with mithkaCommunityPeerCatalog.peers. Both must resolve
  // the same catalog until every pinned native library carries the upstream
  // method.
  var catalogShape = 'upstream';
  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        send: (_) async {},
        updates: updates.stream,
        query: (request) async => switch (request['@type']) {
          'getCommunityFullInfo' =>
            catalogShape == 'upstream'
                ? {
                    '@type': 'communityFullInfo',
                    'photo': null,
                    'chats': [
                      {
                        '@type': 'communityChat',
                        'chat_id': 42,
                        'can_view_history': canViewHistory,
                        'is_hidden': false,
                      },
                    ],
                    'administrator_count': 0,
                    'banned_count': 0,
                    'add_chat_request_count': 0,
                  }
                : {
                    '@type': 'mithkaCommunityPeerCatalog',
                    'peers': [
                      {
                        '@type': 'mithkaCommunityPeerInfo',
                        'chat_id': 42,
                        'can_view_history': canViewHistory,
                      },
                    ],
                  },
          'getChat' => {
            '@type': 'chat',
            'id': 42,
            'title': 'Community group',
            'community_id': 7,
            'type': {
              '@type': 'chatTypeSupergroup',
              'supergroup_id': 9,
              'is_channel': false,
            },
          },
          'getSupergroup' => {
            '@type': 'supergroup',
            'id': 9,
            'community_id': 7,
            'status': {'@type': 'chatMemberStatusLeft'},
            'usernames': {'active_usernames': <String>[]},
          },
          'getChats' => {'@type': 'chats', 'chat_ids': <int>[]},
          _ => {'@type': 'ok'},
        },
      ),
    );
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  for (final shape in ['upstream', 'patched']) {
    for (final allowed in [false, true]) {
      testWidgets(
        'delayed membership preserves catalog visibility ($shape, allowed: $allowed)',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          catalogShape = shape;
          canViewHistory = allowed;
          final membership = Completer<bool>();
          final model = ChatListViewModel(
            membershipForTesting: (_, _) => membership.future,
          );
          addTearDown(model.dispose);
          model.onAppear();
          model.applyUpdateForTesting({
            '@type': 'updateCommunity',
            'community': {
              '@type': 'community',
              'id': 7,
              'name': 'Community',
              'have_access': true,
            },
          });
          await tester.pump(const Duration(milliseconds: 50));
          expect(model.chatsInCommunity(7).map((chat) => chat.id), [42]);

          membership.complete(false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(model.chatsInCommunity(7), isEmpty);
          expect(
            model.viewableChatsInCommunity(7).map((chat) => chat.id),
            allowed ? [42] : isEmpty,
          );
          model.dispose();
          await tester.pump(const Duration(seconds: 6));
        },
      );
    }
  }
}
