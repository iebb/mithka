//
//  community_models.dart
//
//  Client-side models for Telegram Communities. TDLib exposes communities as
//  independent objects and links chats through `community_id` in full chat or
//  bot information. These models keep that relationship explicit and build the
//  collapsed, one-row chat-list projection used by the iOS client.
//

import '../tdlib/json_helpers.dart';
import '../tdlib/td_models.dart';

Map<String, dynamic> communityFullInfoRequest(int communityId) => {
  '@type': 'getCommunityFullInfo',
  'community_id': communityId,
};

class CommunitySummary {
  CommunitySummary({
    required this.id,
    required this.name,
    required this.haveAccess,
    required this.isAdministrator,
    required this.canEditChatList,
    this.photo,
    this.collapsed = true,
  });

  factory CommunitySummary.fromTd(
    Map<String, dynamic> object, {
    bool collapsed = true,
  }) {
    final status = object.obj('status');
    final isCreator = status?.type == 'communityMemberStatusCreator';
    final isAdministrator =
        isCreator || status?.type == 'communityMemberStatusAdministrator';
    final rights = status?.obj('rights');
    final serverCollapsed =
        object.boolean('is_collapsed_in_chat_list') ??
        object.boolean('is_collapsed') ??
        object.boolean('collapsed_in_dialogs');
    return CommunitySummary(
      id: object.int64('id') ?? 0,
      name: object.str('name') ?? object.str('title') ?? '',
      haveAccess: object.boolean('have_access') ?? false,
      isAdministrator: isAdministrator,
      canEditChatList:
          isCreator ||
          (rights?.boolean('can_edit_chat_list') ?? false) ||
          (object.obj('permissions')?.boolean('can_edit_chat_list') ?? false),
      photo: TDParse.smallPhoto(object.obj('photo')),
      collapsed: serverCollapsed ?? collapsed,
    );
  }

  final int id;
  String name;
  bool haveAccess;
  bool isAdministrator;
  bool canEditChatList;
  TdFileRef? photo;
  bool collapsed;

  void merge(CommunitySummary other) {
    if (other.name.isNotEmpty) name = other.name;
    haveAccess = other.haveAccess;
    isAdministrator = other.isAdministrator;
    canEditChatList = other.canEditChatList;
    photo = other.photo;
  }
}

sealed class CommunityChatListEntry {
  const CommunityChatListEntry();

  bool get showsUnreadIndicator;
}

class CommunityChatEntry extends CommunityChatListEntry {
  const CommunityChatEntry(this.chat);

  final ChatSummary chat;

  @override
  bool get showsUnreadIndicator => chat.showsRedUnreadIndicator;
}

class CommunityGroupEntry extends CommunityChatListEntry {
  const CommunityGroupEntry({required this.community, required this.chats});

  final CommunitySummary community;
  final List<ChatSummary> chats;

  ChatSummary get latestChat => chats.first;

  int get unreadCount => chats.fold(0, (sum, chat) => sum + chat.unreadCount);

  bool get isMarkedUnread => chats.any((chat) => chat.isMarkedUnread);

  bool get isMuted {
    final unreadChats = chats.where(
      (chat) => chat.unreadCount > 0 || chat.isMarkedUnread,
    );
    return unreadChats.isNotEmpty && unreadChats.every((chat) => chat.isMuted);
  }

  bool get isPinned => chats.any((chat) => chat.isPinned);

  @override
  bool get showsUnreadIndicator =>
      chats.any((chat) => chat.showsRedUnreadIndicator);
}

abstract final class CommunityChatListProjection {
  static List<CommunityChatListEntry> build({
    required List<ChatSummary> chats,
    required Map<int, int> communityByChat,
    required Map<int, CommunitySummary> communities,
    bool communitiesEnabled = true,
  }) {
    if (!communitiesEnabled) {
      return chats.map(CommunityChatEntry.new).toList(growable: false);
    }
    final chatsByCommunity = <int, List<ChatSummary>>{};
    for (final chat in chats) {
      final communityId = communityByChat[chat.id];
      final community = communities[communityId];
      if (communityId == null ||
          community == null ||
          !community.haveAccess ||
          !community.collapsed) {
        continue;
      }
      chatsByCommunity.putIfAbsent(communityId, () => []).add(chat);
    }

    final emittedCommunities = <int>{};
    final result = <CommunityChatListEntry>[];
    for (final chat in chats) {
      final communityId = communityByChat[chat.id];
      final groupedChats = communityId == null
          ? null
          : chatsByCommunity[communityId];
      if (communityId == null || groupedChats == null) {
        result.add(CommunityChatEntry(chat));
        continue;
      }
      if (!emittedCommunities.add(communityId)) continue;
      result.add(
        CommunityGroupEntry(
          community: communities[communityId]!,
          chats: List.unmodifiable(groupedChats),
        ),
      );
    }
    return result;
  }
}
