import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

typedef ChatFolderQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

class ChatFolderRecord {
  const ChatFolderRecord({
    required this.id,
    required this.title,
    required this.raw,
    required this.hasInviteLinks,
  });

  final int id;
  final String title;
  final Map<String, dynamic> raw;
  final bool hasInviteLinks;

  ChatFolderDraft get draft => ChatFolderDraft.fromRaw(raw);
}

class RecommendedFolder {
  const RecommendedFolder({required this.description, required this.draft});

  final String description;
  final ChatFolderDraft draft;
}

class ChatFolderDraft {
  const ChatFolderDraft({
    required this.title,
    this.iconName = 'Custom',
    this.colorId = -1,
    this.isShareable = false,
    this.pinnedChatIds = const <int>{},
    this.includedChatIds = const <int>{},
    this.excludedChatIds = const <int>{},
    this.excludeMuted = false,
    this.excludeRead = false,
    this.excludeArchived = false,
    this.includeContacts = false,
    this.includeNonContacts = false,
    this.includeBots = false,
    this.includeGroups = false,
    this.includeChannels = false,
  });

  factory ChatFolderDraft.fromRaw(Map<String, dynamic> raw) => ChatFolderDraft(
    title: folderTitle(raw),
    iconName: raw.obj('icon')?.str('name') ?? 'Custom',
    colorId: raw.integer('color_id') ?? -1,
    isShareable: raw.boolean('is_shareable') ?? false,
    pinnedChatIds: _ids(raw, 'pinned_chat_ids'),
    includedChatIds: _ids(raw, 'included_chat_ids'),
    excludedChatIds: _ids(raw, 'excluded_chat_ids'),
    excludeMuted: raw.boolean('exclude_muted') ?? false,
    excludeRead: raw.boolean('exclude_read') ?? false,
    excludeArchived: raw.boolean('exclude_archived') ?? false,
    includeContacts: raw.boolean('include_contacts') ?? false,
    includeNonContacts: raw.boolean('include_non_contacts') ?? false,
    includeBots: raw.boolean('include_bots') ?? false,
    includeGroups: raw.boolean('include_groups') ?? false,
    includeChannels: raw.boolean('include_channels') ?? false,
  );

  final String title;
  final String iconName;
  final int colorId;
  final bool isShareable;
  final Set<int> pinnedChatIds;
  final Set<int> includedChatIds;
  final Set<int> excludedChatIds;
  final bool excludeMuted;
  final bool excludeRead;
  final bool excludeArchived;
  final bool includeContacts;
  final bool includeNonContacts;
  final bool includeBots;
  final bool includeGroups;
  final bool includeChannels;

  ChatFolderDraft copyWith({
    String? title,
    String? iconName,
    int? colorId,
    bool? isShareable,
    Set<int>? pinnedChatIds,
    Set<int>? includedChatIds,
    Set<int>? excludedChatIds,
    bool? excludeMuted,
    bool? excludeRead,
    bool? excludeArchived,
    bool? includeContacts,
    bool? includeNonContacts,
    bool? includeBots,
    bool? includeGroups,
    bool? includeChannels,
  }) => ChatFolderDraft(
    title: title ?? this.title,
    iconName: iconName ?? this.iconName,
    colorId: colorId ?? this.colorId,
    isShareable: isShareable ?? this.isShareable,
    pinnedChatIds: pinnedChatIds ?? this.pinnedChatIds,
    includedChatIds: includedChatIds ?? this.includedChatIds,
    excludedChatIds: excludedChatIds ?? this.excludedChatIds,
    excludeMuted: excludeMuted ?? this.excludeMuted,
    excludeRead: excludeRead ?? this.excludeRead,
    excludeArchived: excludeArchived ?? this.excludeArchived,
    includeContacts: includeContacts ?? this.includeContacts,
    includeNonContacts: includeNonContacts ?? this.includeNonContacts,
    includeBots: includeBots ?? this.includeBots,
    includeGroups: includeGroups ?? this.includeGroups,
    includeChannels: includeChannels ?? this.includeChannels,
  );

  Map<String, dynamic> toRequest() => {
    '@type': 'chatFolder',
    'name': {
      '@type': 'chatFolderName',
      'text': {
        '@type': 'formattedText',
        'text': title.trim(),
        'entities': const <Map<String, dynamic>>[],
      },
      'animate_custom_emoji': true,
    },
    'icon': {'@type': 'chatFolderIcon', 'name': iconName},
    'color_id': colorId,
    'is_shareable': isShareable,
    'pinned_chat_ids': _sorted(pinnedChatIds),
    'included_chat_ids': _sorted(includedChatIds),
    'excluded_chat_ids': _sorted(excludedChatIds),
    'exclude_muted': excludeMuted,
    'exclude_read': excludeRead,
    'exclude_archived': excludeArchived,
    'include_contacts': includeContacts,
    'include_non_contacts': includeNonContacts,
    'include_bots': includeBots,
    'include_groups': includeGroups,
    'include_channels': includeChannels,
  };

  static Set<int> _ids(Map<String, dynamic> raw, String key) =>
      (raw.int64Array(key) ?? const <int>[]).toSet();

  static List<int> _sorted(Set<int> ids) => ids.toList()..sort();
}

String folderTitle(Map<String, dynamic> raw) =>
    raw.obj('name')?.obj('text')?.str('text') ??
    raw.obj('name')?.str('text') ??
    raw.obj('title')?.str('text') ??
    raw.str('title') ??
    '';

class ChatFolderService {
  ChatFolderService({ChatFolderQuery? query})
    : _query = query ?? TdClient.shared.query;

  final ChatFolderQuery _query;

  Future<List<ChatFolderRecord>> load(
    Map<String, dynamic>? folderUpdate,
  ) async {
    final infos =
        folderUpdate?.objects('chat_folders') ??
        folderUpdate?.objects('chat_folder_infos') ??
        const <Map<String, dynamic>>[];
    final records = <ChatFolderRecord>[];
    for (final info in infos) {
      final id = info.integer('id') ?? info.integer('chat_folder_id');
      if (id == null) continue;
      final raw = await _query({
        '@type': 'getChatFolder',
        'chat_folder_id': id,
      });
      records.add(
        ChatFolderRecord(
          id: id,
          title: folderTitle(raw).isEmpty
              ? folderTitle(info)
              : folderTitle(raw),
          raw: raw,
          hasInviteLinks:
              info.boolean('has_my_invite_links') ??
              info.boolean('is_shareable') ??
              false,
        ),
      );
    }
    return records;
  }

  Future<List<RecommendedFolder>> recommended() async {
    final result = await _query({'@type': 'getRecommendedChatFolders'});
    return [
      for (final item
          in result.objects('chat_folders') ?? const <Map<String, dynamic>>[])
        if (item.obj('folder') case final folder?)
          RecommendedFolder(
            description: item.str('description') ?? '',
            draft: ChatFolderDraft.fromRaw(folder),
          ),
    ];
  }

  Future<int?> create(ChatFolderDraft draft) async {
    final result = await _query({
      '@type': 'createChatFolder',
      'folder': draft.toRequest(),
    });
    return result.integer('id') ?? result.integer('chat_folder_id');
  }

  Future<void> edit(int id, ChatFolderDraft draft) => _query({
    '@type': 'editChatFolder',
    'chat_folder_id': id,
    'folder': draft.toRequest(),
  });

  Future<List<int>> chatsToLeave(int id) async {
    final result = await _query({
      '@type': 'getChatFolderChatsToLeave',
      'chat_folder_id': id,
    });
    return result.int64Array('chat_ids') ?? const <int>[];
  }

  Future<void> delete(int id, {List<int> leaveChatIds = const <int>[]}) =>
      _query({
        '@type': 'deleteChatFolder',
        'chat_folder_id': id,
        'leave_chat_ids': leaveChatIds,
      });

  Future<void> reorder(List<int> ids, int mainChatListPosition) => _query({
    '@type': 'reorderChatFolders',
    'chat_folder_ids': ids,
    'main_chat_list_position': mainChatListPosition.clamp(0, ids.length),
  });

  Future<void> toggleTags(bool enabled) =>
      _query({'@type': 'toggleChatFolderTags', 'are_tags_enabled': enabled});

  Future<List<int>> shareableChats(int id) async {
    final result = await _query({
      '@type': 'getChatsForChatFolderInviteLink',
      'chat_folder_id': id,
    });
    return result.int64Array('chat_ids') ?? const <int>[];
  }

  Future<List<Map<String, dynamic>>> inviteLinks(int id) async {
    final result = await _query({
      '@type': 'getChatFolderInviteLinks',
      'chat_folder_id': id,
    });
    return result.objects('invite_links') ?? const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> createInviteLink({
    required int folderId,
    required String name,
    required List<int> chatIds,
  }) => _query({
    '@type': 'createChatFolderInviteLink',
    'chat_folder_id': folderId,
    'name': name.trim(),
    'chat_ids': chatIds,
  });

  Future<Map<String, dynamic>> editInviteLink({
    required int folderId,
    required String inviteLink,
    required String name,
    required List<int> chatIds,
  }) => _query({
    '@type': 'editChatFolderInviteLink',
    'chat_folder_id': folderId,
    'invite_link': inviteLink,
    'name': name.trim(),
    'chat_ids': chatIds,
  });

  Future<void> deleteInviteLink({
    required int folderId,
    required String inviteLink,
  }) => _query({
    '@type': 'deleteChatFolderInviteLink',
    'chat_folder_id': folderId,
    'invite_link': inviteLink,
  });

  Future<Map<String, dynamic>> getChat(int chatId) =>
      _query({'@type': 'getChat', 'chat_id': chatId});
}
