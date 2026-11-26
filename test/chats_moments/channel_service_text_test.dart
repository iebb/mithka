//
//  Channel service banners: TDLib reports a channel's creation, title/photo
//  changes, member changes, boosts and live streams through the same content
//  types as groups. Parsing carries the chat type so a channel never reads
//  "Group chat created", and a transcript hydrated before the type resolved
//  can rebuild the channel wording from the retained title.
//

import 'package:flutter/material.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';

Map<String, dynamic> _content(
  String type, [
  Map<String, dynamic> extra = const {},
]) => {'@type': type, ...extra};

Map<String, dynamic> _raw(
  String type, {
  Map<String, dynamic> extra = const {},
}) => {
  '@type': 'message',
  'id': 51,
  'chat_id': -100123,
  'date': 1700000000,
  'is_outgoing': false,
  'content': _content(type, extra),
};

class _Case {
  const _Case(
    this.groupKey,
    this.channelKey, {
    this.extra = const {},
    this.placeholders = const {},
  });

  final String groupKey;
  final String channelKey;
  final Map<String, dynamic> extra;
  final Map<String, Object?> placeholders;
}

void main() {
  setUpAll(() async {
    await AppStrings.ensureLoaded(const Locale('en'));
  });

  final cases = <String, _Case>{
    'messageChatChangeTitle': const _Case(
      AppStringKeys.tdMessageGroupNameChanged,
      AppStringKeys.tdMessageChannelNameChanged,
      extra: {'title': 'New name'},
      placeholders: {'value1': 'New name'},
    ),
    'messageChatChangePhoto': const _Case(
      AppStringKeys.tdMessageGroupPhotoUpdated,
      AppStringKeys.tdMessageChannelPhotoUpdated,
    ),
    'messageChatDeletePhoto': const _Case(
      AppStringKeys.tdMessageGroupPhotoDeleted,
      AppStringKeys.tdMessageChannelPhotoDeleted,
    ),
    'messageChatAddMembers': const _Case(
      AppStringKeys.tdMessageNewMemberJoinedGroup,
      AppStringKeys.tdMessageNewMemberJoinedChannel,
    ),
    'messageChatJoinByLink': const _Case(
      AppStringKeys.tdMessageJoinedGroupByLink,
      AppStringKeys.tdMessageJoinedChannelByLink,
    ),
    'messageChatJoinByRequest': const _Case(
      AppStringKeys.groupManagementLogJoinedGroup,
      AppStringKeys.tdMessageJoinedChannel,
    ),
    'messageChatDeleteMember': const _Case(
      AppStringKeys.tdMessageMemberLeftGroup,
      AppStringKeys.tdMessageMemberLeftChannel,
    ),
    'messageVideoChatStarted': const _Case(
      AppStringKeys.tdMessageGroupVideoChatStarted,
      AppStringKeys.tdMessageChannelVideoChatStarted,
    ),
    'messageVideoChatEnded': const _Case(
      AppStringKeys.tdMessageGroupVideoChatEnded,
      AppStringKeys.tdMessageChannelVideoChatEnded,
    ),
    'messageChatBoost': const _Case(
      AppStringKeys.tdMessageBoostedGroup,
      AppStringKeys.tdMessageBoostedChannel,
    ),
  };

  group('channel service wording', () {
    test('a created channel is not announced as a group', () {
      final content = _content('messageSupergroupChatCreate', {'title': 'BBC'});
      expect(
        TDParse.serviceText(content, isChannel: true),
        AppStrings.t(AppStringKeys.tdMessageChannelCreated),
      );
      expect(
        TDParse.serviceText(content),
        AppStrings.t(AppStringKeys.tdMessageGroupCreated),
      );
      expect(
        TDParse.serviceText(content, isChannel: true),
        isNot(AppStrings.t(AppStringKeys.tdMessageGroupCreated)),
      );
    });

    for (final entry in cases.entries) {
      test('${entry.key} names the chat type', () {
        final content = _content(entry.key, entry.value.extra);
        expect(
          TDParse.serviceText(content, isChannel: true),
          AppStrings.t(entry.value.channelKey, entry.value.placeholders),
        );
        expect(
          TDParse.serviceText(content),
          AppStrings.t(entry.value.groupKey, entry.value.placeholders),
        );
        expect(
          TDParse.serviceText(content, isChannel: true),
          isNot(TDParse.serviceText(content)),
        );
      });
    }

    test('message parsing carries the channel type into the banner', () {
      final message = TDParse.message(
        _raw('messageSupergroupChatCreate'),
        isChannel: true,
      );
      expect(message, isNotNull);
      expect(
        message!.text,
        AppStrings.t(AppStringKeys.tdMessageChannelCreated),
      );
    });

    test('chat summaries label a channel last message as a channel', () {
      Map<String, dynamic> chat({required bool isChannel}) => {
        '@type': 'chat',
        'id': -100123,
        'title': 'Channel',
        'type': {
          '@type': 'chatTypeSupergroup',
          'supergroup_id': 77,
          'is_channel': isChannel,
        },
        'last_message': _raw('messageSupergroupChatCreate'),
        'positions': [
          {
            '@type': 'chatPosition',
            'list': {'@type': 'chatListMain'},
            'order': 10,
            'is_pinned': false,
          },
        ],
        'unread_count': 0,
      };

      final channel = TDParse.chat(chat(isChannel: true));
      expect(
        channel!.lastMessage,
        AppStrings.t(AppStringKeys.tdMessageChannelCreated),
      );
      expect(
        channel.lastChatMessage!.text,
        AppStrings.t(AppStringKeys.tdMessageChannelCreated),
      );

      final group = TDParse.chat(chat(isChannel: false));
      expect(
        group!.lastMessage,
        AppStrings.t(AppStringKeys.tdMessageGroupCreated),
      );
    });

    test('a transcript parsed before the type resolved can be re-labelled', () {
      final created = TDParse.message(_raw('messageSupergroupChatCreate'))!;
      expect(created.text, AppStrings.t(AppStringKeys.tdMessageGroupCreated));
      expect(
        TDParse.channelServiceText(created),
        AppStrings.t(AppStringKeys.tdMessageChannelCreated),
      );

      final renamed = TDParse.message(
        _raw('messageChatChangeTitle', extra: {'title': 'Renamed'}),
      )!;
      expect(renamed.serviceTitle, 'Renamed');
      expect(
        renamed.text,
        AppStrings.t(AppStringKeys.tdMessageGroupNameChanged, {
          'value1': 'Renamed',
        }),
      );
      expect(
        TDParse.channelServiceText(renamed),
        AppStrings.t(AppStringKeys.tdMessageChannelNameChanged, {
          'value1': 'Renamed',
        }),
      );
    });

    test('personalised join banners are not flattened by re-labelling', () {
      final joined = TDParse.message(_raw('messageChatAddMembers'))!;
      final personalised = AppStrings.t(AppStringKeys.chatUsersJoinedGroup, {
        'value1': 'Alice',
        'value2': '',
      });
      joined.text = personalised;
      // The actor-aware text must survive; the view model re-resolves it with
      // channel wording instead of replacing it with the generic banner.
      expect(TDParse.channelServiceText(joined), isNull);

      joined.text = AppStrings.t(AppStringKeys.tdMessageNewMemberJoinedGroup);
      expect(
        TDParse.channelServiceText(joined),
        AppStrings.t(AppStringKeys.tdMessageNewMemberJoinedChannel),
      );
    });

    test('protected content and upgrade banners are named', () {
      expect(
        TDParse.serviceText({
          '@type': 'messageChatHasProtectedContentToggled',
          'new_has_protected_content': true,
        }),
        AppStrings.t(AppStringKeys.tdMessageProtectedContentEnabled),
      );
      expect(
        TDParse.serviceText({
          '@type': 'messageChatHasProtectedContentToggled',
          'new_has_protected_content': false,
        }),
        AppStrings.t(AppStringKeys.tdMessageProtectedContentDisabled),
      );
      expect(
        TDParse.serviceText({'@type': 'messageChatUpgradeFrom'}),
        AppStrings.t(AppStringKeys.tdMessageGroupUpgraded),
      );
    });
  });
}
