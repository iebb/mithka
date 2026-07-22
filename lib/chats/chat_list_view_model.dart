//
//  chat_list_view_model.dart
//
//  Drives the 消息 (chat list) screen. Loads the main chat list from TDLib, then
//  keeps it live by folding in the incremental `update*` events. Ordering:
//  pinned chats float to the top, then the rest sort by TDLib `order` desc, with
//  last-message date as the tiebreaker. Port of the Swift `ChatListViewModel`.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../communities/community_models.dart';
import '../notifications/scope_notification_settings.dart';
import '../settings/keyword_blocker.dart';
import '../tdlib/chat_membership.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'chat_delete_policy.dart';

class ChatFilterOption {
  const ChatFilterOption({required this.title, this.folderId});

  final String title;
  final int? folderId;

  bool get isAll => folderId == null;
}

class _CommunityLookup {
  const _CommunityLookup({
    required this.chatId,
    required this.peerId,
    required this.isBot,
  });

  final int chatId;
  final int peerId;
  final bool isBot;
}

class ChatListViewModel extends ChangeNotifier {
  List<ChatSummary> _chats = [];
  List<ChatSummary> _archived = [];
  List<ChatSummary> _filtered = [];
  List<ChatFilterOption> _filters = const [
    ChatFilterOption(title: AppStringKeys.topicChatAllFilter),
  ];
  ChatFilterOption _selectedFilter = const ChatFilterOption(
    title: AppStringKeys.topicChatAllFilter,
  );
  String? notice;
  bool _initialLoading = true;
  Timer? _resortTimer;

  List<ChatSummary> get chats => _chats;
  List<ChatSummary> get archived => _archived;
  List<ChatSummary> get filtered => _filtered;
  List<CommunityChatListEntry> chatListEntries({
    bool communitiesEnabled = true,
  }) => CommunityChatListProjection.build(
    chats: _chats,
    communityByChat: _communityByChat,
    communities: _communities,
    communitiesEnabled: communitiesEnabled,
  );
  List<ChatFilterOption> get filters => _filters;
  ChatFilterOption get selectedFilter => _selectedFilter;
  bool get isAllFilter => _selectedFilter.isAll;
  bool get isInitialLoading => _initialLoading && _chats.isEmpty;

  /// Authoritative store keyed by chat id; `chats` is a sorted projection.
  final Map<int, ChatSummary> _map = {};

  /// Chats Telegram has made available for community browsing even though the
  /// active account hasn't joined them. They never enter the main chat list.
  final Map<int, ChatSummary> _communityDirectoryChats = {};
  final Set<int> _viewableCommunityChatIds = {};
  final Set<int> _checkingCommunityChatAccess = {};
  final Map<int, Map<int, int>> _folderOrders = {};
  final Map<int, bool> _joinedChatCache = {};
  final Map<String, String> _senderNames = {};
  final Map<String, Set<int>> _pendingSenderTargets = {};
  final Map<int, String?> _lastSenderKeys = {};
  final Set<String> _resolvingSenders = {};
  final Set<int> _resolvingPeers = {};
  final Set<int> _resolvingForums = {};
  final Set<int> _resolvingFolders = {};
  final Map<int, CommunitySummary> _communities = {};
  final Map<int, int> _communityByChat = {};
  final Map<int, int> _chatBySupergroup = {};
  final Map<int, int> _chatByUser = {};
  final Set<int> _communityPreferencesLoaded = {};
  final Set<int> _loadingCommunityCatalogs = {};
  final Set<int> _queuedCommunityChats = {};
  final List<_CommunityLookup> _communityLookupQueue = [];
  int _communityLookupsInFlight = 0;

  final TdClient _client = TdClient.shared;
  StreamSubscription? _sub;
  bool _listening = false;
  bool _disposed = false;
  int? _meId;
  bool _prefetchingMain = false;
  final Set<String> _loadingChatLists = {};
  final Set<String> _exhaustedChatLists = {};
  static const _pageSize = 100;
  static const _initialPageSize = 36;
  static const _backgroundHydrateLimit = 60;
  static const _backgroundPrefetchPasses = 1;

  void onAppear() {
    if (_disposed || _listening) return;
    _listening = true;
    _subscribe();
    for (final update in _client.latestCommunityUpdates) {
      final community = update.obj('community');
      if (community != null) _applyCommunity(community);
    }
    _loadFilters();
    _loadChats(_initialPageSize);
    _deferWarmCaches();
  }

  CommunitySummary? community(int communityId) => _communities[communityId];

  List<CommunitySummary> get availableCommunities {
    final communities = _communities.values
        .where(
          (community) =>
              community.haveAccess &&
              (chatsInCommunity(community.id).isNotEmpty ||
                  viewableChatsInCommunity(community.id).isNotEmpty),
        )
        .toList();
    communities.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return communities;
  }

  List<ChatSummary> chatsInCommunity(int communityId) {
    final chats = _map.values
        .where(
          (chat) =>
              _communityByChat[chat.id] == communityId &&
              (_joinedChatCache[chat.id] ?? true),
        )
        .toList();
    chats.sort(_compare);
    return chats;
  }

  List<ChatSummary> viewableChatsInCommunity(int communityId) {
    final chats = _communityDirectoryChats.values
        .where(
          (chat) =>
              _communityByChat[chat.id] == communityId &&
              _viewableCommunityChatIds.contains(chat.id),
        )
        .toList();
    chats.sort(_compare);
    return chats;
  }

  int? communityForChat(int chatId) => _communityByChat[chatId];

  void setCommunityCollapsed(int communityId, bool collapsed) {
    final community = _communities[communityId];
    if (community == null || community.collapsed == collapsed) return;
    community.collapsed = collapsed;
    _scheduleResort();
    unawaited(_saveCommunityCollapsed(communityId, collapsed));
  }

  /// Called when the current user's id becomes known so we can flag the
  /// Saved Messages chat (private chat with yourself).
  set meId(int? value) {
    if (_disposed) return;
    if (_meId == value) return;
    _meId = value;
    if (value == null) return;
    for (final s in _map.values) {
      s.isSavedMessages = s.peerUserId == value;
    }
    _resort();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _listening = false;
    _sub?.cancel();
    _sub = null;
    _resortTimer?.cancel();
    _resortTimer = null;
    super.dispose();
  }

  // MARK: - Loading

  Map<String, dynamic> get _activeChatList => _selectedFilter.folderId == null
      ? {'@type': 'chatListMain'}
      : {'@type': 'chatListFolder', 'chat_folder_id': _selectedFilter.folderId};

  void _loadFilters() {
    final cached = _client.latestChatFoldersUpdate;
    if (cached != null) _applyChatFolders(cached);
  }

  void _applyChatFolders(Map<String, dynamic> object) {
    final raw =
        object.objects('chat_folders') ??
        object.objects('chat_folder_infos') ??
        const <Map<String, dynamic>>[];
    final folders = <ChatFilterOption>[
      const ChatFilterOption(title: AppStringKeys.topicChatAllFilter),
    ];
    for (final folder in raw) {
      final id = folder.integer('id') ?? folder.integer('chat_folder_id');
      if (id == null) continue;
      final title = _folderTitle(folder, id);
      folders.add(ChatFilterOption(title: title, folderId: id));
    }
    _filters = folders;
    if (_selectedFilter.folderId != null &&
        !_filters.any((f) => f.folderId == _selectedFilter.folderId)) {
      _selectedFilter = _filters.first;
      _loadChats(_pageSize);
      _prefetchMainChats();
      _resort();
    }
    _notifyIfAlive();
  }

  String _folderTitle(Map<String, dynamic> folder, int id) =>
      folder.obj('name')?.obj('text')?.str('text') ??
      folder.obj('title')?.str('text') ??
      folder.str('title') ??
      folder.str('name') ??
      AppStrings.t(AppStringKeys.chatInfoFolderName, {'value1': id});

  void _ensureFolderOption(int id) {
    if (_filters.any((f) => f.folderId == id)) return;
    _filters = [
      ..._filters,
      ChatFilterOption(
        title: AppStrings.t(AppStringKeys.chatInfoFolderName, {'value1': id}),
        folderId: id,
      ),
    ];
    _notifyIfAlive();
    if (_resolvingFolders.contains(id)) return;
    _resolvingFolders.add(id);
    _client
        .query({'@type': 'getChatFolder', 'chat_folder_id': id})
        .then((folder) {
          if (_disposed) return;
          _resolvingFolders.remove(id);
          final title = _folderTitle(folder, id);
          _filters = [
            for (final filter in _filters)
              filter.folderId == id
                  ? ChatFilterOption(title: title, folderId: id)
                  : filter,
          ];
          if (_selectedFilter.folderId == id) {
            _selectedFilter = ChatFilterOption(title: title, folderId: id);
          }
          _notifyIfAlive();
        })
        .catchError((_) {
          _resolvingFolders.remove(id);
        });
  }

  void selectFilter(ChatFilterOption filter) {
    if (filter.folderId == _selectedFilter.folderId) return;
    _selectedFilter = filter;
    _loadChats(_pageSize);
    if (filter.isAll) {
      _prefetchMainChats();
    }
    _resort();
  }

  void selectAllFilter() {
    if (_selectedFilter.isAll) return;
    _selectedFilter = _filters.first;
    _loadChats(_pageSize);
    _prefetchMainChats();
    _resort();
  }

  String _chatListKey(Map<String, dynamic> list) =>
      switch (list.type ?? list['@type']) {
        'chatListFolder' => 'folder:${list.integer('chat_folder_id') ?? 0}',
        'chatListArchive' => 'archive',
        _ => 'main',
      };

  Future<bool> _loadChatList(Map<String, dynamic> list, int limit) async {
    if (_disposed) return false;
    final key = _chatListKey(list);
    if (_loadingChatLists.contains(key) || _exhaustedChatLists.contains(key)) {
      return false;
    }
    _loadingChatLists.add(key);
    try {
      await _client.query({
        '@type': 'loadChats',
        'chat_list': list,
        'limit': limit,
      });
      if (_disposed) return false;
      return true;
    } catch (error) {
      if (error is TdError && error.code == 404) {
        _exhaustedChatLists.add(key);
      }
      return false;
    } finally {
      _loadingChatLists.remove(key);
    }
  }

  void _loadChats(int limit) {
    _loadAndHydrateChatList(_activeChatList, limit);
  }

  void _deferWarmCaches() {
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (!_listening) return;
      _loadArchive(_pageSize);
    });
    Future<void>.delayed(const Duration(seconds: 5), () {
      if (!_listening) return;
      if (_selectedFilter.isAll) _prefetchMainChats();
    });
  }

  void _prefetchMainChats() {
    if (_prefetchingMain || _exhaustedChatLists.contains('main')) return;
    _prefetchingMain = true;
    Future<void>(() async {
      var passes = 0;
      while (!_exhaustedChatLists.contains('main') &&
          _listening &&
          passes < _backgroundPrefetchPasses) {
        passes += 1;
        final loaded = await _loadChatList({
          '@type': 'chatListMain',
        }, _pageSize);
        await _hydrateChatList({
          '@type': 'chatListMain',
        }, limit: _backgroundHydrateLimit);
        if (!loaded && !_loadingChatLists.contains('main')) break;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      _prefetchingMain = false;
    });
  }

  void _loadArchive(int limit) {
    _loadAndHydrateChatList({'@type': 'chatListArchive'}, limit);
  }

  void loadMore() => _loadChats(_pageSize);

  Future<void> refresh() async {
    if (_disposed) return;
    _exhaustedChatLists.remove(_chatListKey(_activeChatList));
    _exhaustedChatLists.remove('archive');
    _loadFilters();
    await Future.wait([
      _loadAndHydrateChatList(_activeChatList, _pageSize),
      _loadAndHydrateChatList({'@type': 'chatListArchive'}, _pageSize),
    ]);
    if (_disposed) return;
    if (_selectedFilter.isAll) _prefetchMainChats();
    _resort();
  }

  Future<void> _loadAndHydrateChatList(
    Map<String, dynamic> list,
    int limit,
  ) async {
    await _loadChatList(list, limit);
    await _hydrateChatList(list, limit: limit);
  }

  Future<void> _hydrateChatList(
    Map<String, dynamic> list, {
    required int limit,
  }) async {
    if (_disposed) return;
    try {
      final res = await _client.query({
        '@type': 'getChats',
        'chat_list': list,
        'limit': limit,
      });
      if (_disposed) return;
      final ids = res.int64Array('chat_ids') ?? const <int>[];
      if (ids.isEmpty) _finishInitialLoadingIfNeeded(force: true);
      for (final id in ids) {
        _ensureChatLoaded(id);
      }
    } catch (_) {
      _finishInitialLoadingIfNeeded(force: true);
    }
  }

  // MARK: - Row actions (swipe)

  void togglePin(ChatSummary chat) {
    final newValue = !chat.isPinned;
    final id = chat.id;
    _mutate(id, (s) => s.isPinned = newValue);
    _resort();

    _client
        .query({
          '@type': 'toggleChatIsPinned',
          // Pin in the list the user is looking at — pinning from a folder
          // filter used to silently mutate the Main list instead.
          'chat_list': _activeChatList,
          'chat_id': id,
          'is_pinned': newValue,
        })
        .catchError((Object error) async {
          // Failure: revert and restore the chat's true position from TDLib.
          _mutate(id, (s) => s.isPinned = !newValue);
          try {
            final raw = await _client.query({
              '@type': 'getChat',
              'chat_id': id,
            });
            final fresh = TDParse.chat(raw);
            if (fresh != null) _map[id] = fresh;
          } catch (_) {}
          notice = _pinErrorNotice(error);
          _resort();
          return <String, dynamic>{};
        });
  }

  void markUnread(ChatSummary chat) {
    _client.send({
      '@type': 'toggleChatIsMarkedAsUnread',
      'chat_id': chat.id,
      'is_marked_as_unread': true,
    });
  }

  void markRead(ChatSummary chat) {
    if (chat.unreadCount <= 0 && !chat.isMarkedUnread) return;
    final previousUnread = chat.unreadCount;
    final previousMarked = chat.isMarkedUnread;
    _mutate(chat.id, (s) {
      s.unreadCount = 0;
      s.isMarkedUnread = false;
    });
    _resort();

    if (previousMarked) {
      _client.send({
        '@type': 'toggleChatIsMarkedAsUnread',
        'chat_id': chat.id,
        'is_marked_as_unread': false,
      });
    }
    if (previousUnread <= 0) return;
    _forceReadChat(chat).catchError((_) {
      _mutate(chat.id, (s) {
        s.unreadCount = previousUnread;
        s.isMarkedUnread = previousMarked;
      });
      _resort();
    });
  }

  void markAllRead() {
    markChatsRead([..._chats, ..._archived]);
  }

  /// Marks only [chats] read — the archive / filtered assistant badges clear
  /// their own group, not every chat in the app.
  void markChatsRead(Iterable<ChatSummary> chats) {
    final targets = chats
        .where((chat) => chat.unreadCount > 0 || chat.isMarkedUnread)
        .toList();
    for (final chat in targets) {
      markRead(chat);
    }
  }

  Future<void> _forceReadChat(ChatSummary chat) async {
    var messageId = chat.lastMessageId;
    if (messageId <= 0) {
      final raw = await _client.query({'@type': 'getChat', 'chat_id': chat.id});
      final fresh = TDParse.chat(raw);
      if (fresh == null) return;
      messageId = fresh.lastMessageId;
      _map[chat.id] = fresh;
    }
    if (messageId <= 0) return;
    await _client.query({
      '@type': 'viewMessages',
      'chat_id': chat.id,
      'message_ids': [messageId],
      'force_read': true,
    });
  }

  Future<ChatDeleteCapabilities> deleteCapabilities(ChatSummary chat) async {
    try {
      final raw = await _client.query({'@type': 'getChat', 'chat_id': chat.id});
      return chatDeleteCapabilities(raw);
    } catch (_) {
      return const ChatDeleteCapabilities.selfOnly();
    }
  }

  Future<void> deleteChat(
    ChatSummary chat, {
    ChatDeleteScope scope = ChatDeleteScope.self,
  }) async {
    if (shouldLeaveBeforeDeletingChat(chat.kind, scope)) {
      await _client.query({'@type': 'leaveChat', 'chat_id': chat.id});
    }
    await _client.query(
      deleteChatHistoryRequest(chatId: chat.id, scope: scope),
    );
  }

  void clearNotice() {
    if (_disposed) return;
    notice = null;
    _notifyIfAlive();
  }

  // MARK: - Update stream

  void _subscribe() {
    _sub = _client.subscribe().listen(_apply);
  }

  void _apply(Map<String, dynamic> update) {
    if (_disposed) return;
    switch (update.type) {
      case 'updateNewChat':
        final chat = update.obj('chat');
        if (chat == null) return;
        unawaited(_ingestRawChat(chat));

      case 'updateChatFolders':
        _applyChatFolders(update);

      case 'updateChatLastMessage':
        final id = update.int64('chat_id');
        if (id == null) return;
        _applyPositions(id, update.objects('positions'));
        _mutate(id, (s) {
          final last = update.obj('last_message');
          if (last != null) {
            s.lastMessageId = last.int64('id') ?? s.lastMessageId;
            s.date = last.integer('date') ?? s.date;
            final content = last.obj('content');
            if (content != null) {
              s.lastMessage = _previewText(TDParse.messageText(content));
            }
          } else {
            s.lastMessage = '';
            s.lastMessageId = 0;
            s.date = 0;
            s.lastSender = null;
            _lastSenderKeys[id] = null;
          }
        });
        _resolveSenderIfNeeded(id, update.obj('last_message'));
        _scheduleResort();

      case 'updateChatPosition':
        final id = update.int64('chat_id');
        final position = update.obj('position');
        if (id == null || position == null) return;
        _applyPosition(id, position);
        _ensureChatLoaded(id);
        _scheduleResort();

      case 'updateChatAddedToList':
        final id = update.int64('chat_id');
        final list = update.obj('chat_list');
        if (id == null || list == null) return;
        _joinedChatCache.remove(id);
        _ensureChatLoaded(id);
        if (list.type == 'chatListFolder') {
          final folderId = list.integer('chat_folder_id');
          if (folderId != null) {
            _folderOrders.putIfAbsent(folderId, () => {})[id] = 1;
          }
        }
        _scheduleResort();

      case 'updateChatRemovedFromList':
        final id = update.int64('chat_id');
        final list = update.obj('chat_list');
        if (id == null || list == null) return;
        switch (list.type) {
          case 'chatListMain':
            _mutate(id, (s) => s.order = 0);
          case 'chatListArchive':
            _mutate(id, (s) => s.archiveOrder = 0);
          case 'chatListFolder':
            final folderId = list.integer('chat_folder_id');
            if (folderId != null) _folderOrders[folderId]?.remove(id);
        }
        _scheduleResort();

      case 'updateChatDraftMessage':
        final id = update.int64('chat_id');
        if (id == null) return;
        _applyPositions(id, update.objects('positions'));
        _mutate(
          id,
          (s) => s.draftText = TDParse.draftText(update.obj('draft_message')),
        );
        _scheduleResort();

      case 'updateChatReadInbox':
        final id = update.int64('chat_id');
        if (id == null) return;
        _mutate(
          id,
          (s) =>
              s.unreadCount = update.integer('unread_count') ?? s.unreadCount,
        );
        _scheduleResort();

      case 'updateChatUnreadMentionCount':
        final id = update.int64('chat_id');
        if (id == null) return;
        _mutate(
          id,
          (s) => s.unreadMentionCount =
              update.integer('unread_mention_count') ?? s.unreadMentionCount,
        );
        _scheduleResort();

      case 'updateChatIsMarkedAsUnread':
        final id = update.int64('chat_id');
        if (id == null) return;
        _mutate(
          id,
          (s) =>
              s.isMarkedUnread = update.boolean('is_marked_as_unread') ?? false,
        );
        _scheduleResort();

      case 'updateChatTitle':
        final id = update.int64('chat_id');
        if (id == null) return;
        _mutate(id, (s) => s.title = update.str('title') ?? s.title);
        _scheduleResort();

      case 'updateChatNotificationSettings':
        final id = update.int64('chat_id');
        if (id == null) return;
        _mutate(id, (s) {
          final notificationSettings = update.obj('notification_settings');
          final useDefault =
              notificationSettings?.boolean('use_default_mute_for') ?? false;
          final muteFor = useDefault
              ? ScopeNotificationSettings.shared.getMuteForScope(
                  ScopeNotificationSettings.shared.scopeTagForKind(s.kind),
                )
              : (notificationSettings?.integer('mute_for') ?? 0);
          s.isMuted = muteFor > 0;
        });
        _scheduleResort();

      case 'updateChatPhoto':
        final id = update.int64('chat_id');
        if (id == null) return;
        _mutate(id, (s) => s.photo = TDParse.smallPhoto(update.obj('photo')));
        _scheduleResort();

      case 'updateCommunity':
        final community = update.obj('community');
        if (community == null) return;
        _applyCommunity(community);

      case 'updateSupergroup':
        final supergroup = update.obj('supergroup');
        final supergroupId = supergroup?.int64('id');
        final chatId = supergroupId == null
            ? null
            : _chatBySupergroup[supergroupId];
        if (chatId == null || supergroup == null) return;
        final joined = isJoinedMemberStatus(supergroup.obj('status'));
        _joinedChatCache[chatId] = joined;
        final needsReclassification =
            (joined && _communityDirectoryChats.containsKey(chatId)) ||
            (!joined && _map.containsKey(chatId));
        if (!needsReclassification) return;
        _client
            .query({'@type': 'getChat', 'chat_id': chatId})
            .then((chat) => _ingestRawChat(chat, schedule: true))
            .catchError((_) {});

      case 'updateSupergroupFullInfo':
        final supergroupId = update.int64('supergroup_id');
        final chatId = supergroupId == null
            ? null
            : _chatBySupergroup[supergroupId];
        final fullInfo = update.obj('supergroup_full_info');
        if (chatId == null || fullInfo == null) return;
        _applyChatCommunityId(chatId, fullInfo.int64('community_id'));

      case 'updateUserFullInfo':
        final userId = update.int64('user_id');
        final chatId = userId == null ? null : _chatByUser[userId];
        final fullInfo = update.obj('user_full_info');
        if (chatId == null || fullInfo == null) return;
        _applyChatCommunityId(chatId, fullInfo.int64('community_id'));

      case 'updateUser':
        final user = update.obj('user');
        final id = user?.int64('id');
        if (user == null || id == null) return;
        _applyPeerUser(user);
    }
  }

  // MARK: - Mutation helpers

  void _mutate(int id, void Function(ChatSummary) body) {
    final s = _map[id] ?? _communityDirectoryChats[id];
    if (s == null) return;
    body(s);
  }

  void _applyPositions(int id, List<Map<String, dynamic>>? positions) {
    if (positions == null) return;
    for (final position in positions) {
      _applyPosition(id, position);
    }
  }

  void _applyPosition(int id, Map<String, dynamic> position) {
    final list = position.obj('list');
    switch (list?.type) {
      case 'chatListMain':
        _mutate(id, (s) {
          s.order = position.int64('order') ?? s.order;
          s.isPinned = position.boolean('is_pinned') ?? s.isPinned;
        });
      case 'chatListArchive':
        _mutate(
          id,
          (s) => s.archiveOrder = position.int64('order') ?? s.archiveOrder,
        );
      case 'chatListFolder':
        final folderId = list?.integer('chat_folder_id');
        if (folderId == null) return;
        _ensureFolderOption(folderId);
        final order = position.int64('order') ?? 0;
        final orders = _folderOrders.putIfAbsent(folderId, () => {});
        if (order > 0) {
          orders[id] = order;
        } else {
          orders.remove(id);
        }
    }
  }

  void _ensureChatLoaded(int id) {
    if (_disposed || _map.containsKey(id)) return;
    _client
        .query({'@type': 'getChat', 'chat_id': id})
        .then((raw) => _ingestRawChat(raw, schedule: true))
        .catchError((_) {});
  }

  Future<void> _ingestRawChat(
    Map<String, dynamic> raw, {
    bool schedule = false,
  }) async {
    if (_disposed) return;
    final summary = TDParse.chat(raw);
    if (summary == null) return;
    if (_meId != null) summary.isSavedMessages = summary.peerUserId == _meId;
    summary.lastMessage = _previewText(summary.lastMessage);
    _indexCommunityPeer(summary.id, raw);
    _resolveForumIfNeeded(summary, raw);
    _resolveCommunityIfNeeded(summary, raw);
    _resolvePeerIfNeeded(summary);
    final joined = await _isJoinedSummary(summary, raw);
    if (_disposed) return;
    if (!joined) {
      _map.remove(summary.id);
      _communityDirectoryChats[summary.id] = summary;
      _applyPositions(summary.id, raw.objects('positions'));
      _resolveSenderIfNeeded(summary.id, raw.obj('last_message'));
      final communityId = _communityByChat[summary.id];
      if (communityId != null) {
        _verifyCommunityChatIsPublic(summary.id, communityId);
      }
      if (schedule) {
        _scheduleResort();
      } else {
        _resort();
      }
      return;
    }
    _communityDirectoryChats.remove(summary.id);
    _viewableCommunityChatIds.remove(summary.id);
    _checkingCommunityChatAccess.remove(summary.id);
    _map[summary.id] = summary;
    _applyPositions(summary.id, raw.objects('positions'));
    _resolveSenderIfNeeded(summary.id, raw.obj('last_message'));
    if (schedule) {
      _scheduleResort();
    } else {
      _resort();
    }
  }

  void _resolveForumIfNeeded(ChatSummary summary, Map<String, dynamic> raw) {
    if (summary.isForum) return;
    final type = raw.obj('type');
    if (type?.type != 'chatTypeSupergroup') return;
    final supergroupId = type?.int64('supergroup_id');
    if (supergroupId == null || !_resolvingForums.add(summary.id)) return;
    _client
        .query({'@type': 'getSupergroup', 'supergroup_id': supergroupId})
        .then((supergroup) {
          if (_disposed) return;
          if (supergroup.boolean('is_forum') != true) return;
          _mutate(summary.id, (s) => s.isForum = true);
          _scheduleResort();
        })
        .catchError((_) {})
        .whenComplete(() => _resolvingForums.remove(summary.id));
  }

  Future<bool> _isJoinedSummary(
    ChatSummary summary,
    Map<String, dynamic> raw,
  ) async {
    if (summary.kind != ChatKind.group && summary.kind != ChatKind.channel) {
      return true;
    }
    final cached = _joinedChatCache[summary.id];
    if (cached != null) return cached;
    final joined = await isJoinedGroupOrChannelChat(summary.id, chat: raw);
    _joinedChatCache[summary.id] = joined;
    return joined;
  }

  // MARK: - Telegram Communities

  void _applyCommunity(Map<String, dynamic> object) {
    if (!_listening) return;
    final id = object.int64('id');
    if (id == null || id == 0) return;
    final existing = _communities[id];
    final community = CommunitySummary.fromTd(
      object,
      collapsed: existing?.collapsed ?? true,
    );
    if (existing == null) {
      _communities[id] = community;
    } else {
      existing.merge(community);
    }
    _scheduleResort();
    if (community.haveAccess) _loadCommunityCatalog(id);
    if (_communityPreferencesLoaded.add(id)) {
      unawaited(_loadCommunityCollapsed(id));
    }
  }

  void _loadCommunityCatalog(int communityId) {
    if (!_loadingCommunityCatalogs.add(communityId)) return;
    _client
        .query(communityFullInfoRequest(communityId))
        .then((result) async {
          final entries = result.objects('peers') ?? const [];
          for (final entry in entries) {
            if (_disposed) return;
            final chatId = entry.int64('chat_id');
            if (chatId == null) continue;
            try {
              final raw = await _client.query({
                '@type': 'getChat',
                'chat_id': chatId,
              });
              await _ingestRawChat(raw, schedule: true);
              if (_disposed) return;
              _applyChatCommunityId(chatId, communityId);
              if (entry.boolean('can_view_history') == true &&
                  _communityDirectoryChats.containsKey(chatId) &&
                  _viewableCommunityChatIds.add(chatId)) {
                _scheduleResort();
              } else if (_communityDirectoryChats.containsKey(chatId)) {
                _verifyCommunityChatIsPublic(chatId, communityId);
              }
            } catch (_) {
              // A peer can disappear between the catalog response and getChat.
            }
          }
        })
        .catchError((_) {
          // Stock TDLib builds don't expose getCommunityFullInfo. Mithka's
          // patched builds do; retaining this fallback keeps older sessions
          // usable until their native library is updated.
        })
        .whenComplete(() => _loadingCommunityCatalogs.remove(communityId));
  }

  void _applyChatCommunityId(int chatId, int? communityId) {
    if (!_listening) return;
    // Older TDLib builds don't expose this field. A missing field is not the
    // same as the explicit zero used when a chat is removed from a community.
    if (communityId == null) return;
    if (communityId == 0) {
      final changed = _communityByChat.remove(chatId) != null;
      _viewableCommunityChatIds.remove(chatId);
      _checkingCommunityChatAccess.remove(chatId);
      if (changed) _scheduleResort();
      return;
    }
    final changed = _communityByChat[chatId] != communityId;
    if (changed) {
      _communityByChat[chatId] = communityId;
      _scheduleResort();
    }
    if (_communityDirectoryChats.containsKey(chatId)) {
      _verifyCommunityChatIsPublic(chatId, communityId);
    }
  }

  void _verifyCommunityChatIsPublic(int chatId, int communityId) {
    if (_viewableCommunityChatIds.contains(chatId) ||
        !_checkingCommunityChatAccess.add(chatId)) {
      return;
    }
    _client
        .query({'@type': 'getChat', 'chat_id': chatId})
        .then((chat) async {
          final type = chat.obj('type');
          if (type?.type == 'chatTypePrivate') return true;
          if (type?.type != 'chatTypeSupergroup') return false;
          final supergroupId = type?.int64('supergroup_id');
          if (supergroupId == null) return false;
          final supergroup = await _client.query({
            '@type': 'getSupergroup',
            'supergroup_id': supergroupId,
          });
          final activeUsernames = supergroup.obj(
            'usernames',
          )?['active_usernames'];
          return activeUsernames is List && activeUsernames.isNotEmpty;
        })
        .then((isPublic) {
          if (_disposed ||
              _communityByChat[chatId] != communityId ||
              !_communityDirectoryChats.containsKey(chatId)) {
            return;
          }
          if (isPublic && _viewableCommunityChatIds.add(chatId)) {
            _scheduleResort();
          }
        })
        .catchError((_) {
          // Private, hidden, and request-only peers stay out unless the server
          // explicitly supplied can_view_history in the community catalog.
        })
        .whenComplete(() => _checkingCommunityChatAccess.remove(chatId));
  }

  void _indexCommunityPeer(int chatId, Map<String, dynamic> chat) {
    final type = chat.obj('type');
    switch (type?.type) {
      case 'chatTypeSupergroup':
        final supergroupId = type?.int64('supergroup_id');
        if (supergroupId != null) _chatBySupergroup[supergroupId] = chatId;
      case 'chatTypePrivate':
        final userId = type?.int64('user_id');
        if (userId != null) _chatByUser[userId] = chatId;
    }
  }

  void _resolveCommunityIfNeeded(
    ChatSummary summary,
    Map<String, dynamic> chat,
  ) {
    final type = chat.obj('type');
    if (type?.type != 'chatTypeSupergroup') return;
    final supergroupId = type?.int64('supergroup_id');
    if (supergroupId == null) return;
    _queueCommunityLookup(
      _CommunityLookup(chatId: summary.id, peerId: supergroupId, isBot: false),
    );
  }

  void _resolveBotCommunityIfNeeded(int userId, Map<String, dynamic> user) {
    if (user.obj('type')?.type != 'userTypeBot') return;
    final chatId = _chatByUser[userId];
    if (chatId == null) return;
    _queueCommunityLookup(
      _CommunityLookup(chatId: chatId, peerId: userId, isBot: true),
    );
  }

  void _queueCommunityLookup(_CommunityLookup lookup) {
    if (!_queuedCommunityChats.add(lookup.chatId)) return;
    _communityLookupQueue.add(lookup);
    _pumpCommunityLookups();
  }

  void _pumpCommunityLookups() {
    if (!_listening) return;
    while (_communityLookupsInFlight < 3 && _communityLookupQueue.isNotEmpty) {
      final lookup = _communityLookupQueue.removeAt(0);
      _communityLookupsInFlight++;
      unawaited(
        _performCommunityLookup(lookup).whenComplete(() {
          _communityLookupsInFlight--;
          _pumpCommunityLookups();
        }),
      );
    }
  }

  Future<void> _performCommunityLookup(_CommunityLookup lookup) async {
    try {
      final fullInfo = await _client.query(
        lookup.isBot
            ? {'@type': 'getUserFullInfo', 'user_id': lookup.peerId}
            : {
                '@type': 'getSupergroupFullInfo',
                'supergroup_id': lookup.peerId,
              },
      );
      _applyChatCommunityId(lookup.chatId, fullInfo.int64('community_id'));
    } catch (_) {
      // Community metadata is additive. A failed lookup must never prevent the
      // underlying chat from appearing in the normal chat list.
    }
  }

  String _communityCollapsedKey(int communityId) =>
      'mithka.community.${_client.activeSlot}.$communityId.collapsed';

  Future<void> _loadCommunityCollapsed(int communityId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_listening) return;
    final stored = prefs.getBool(_communityCollapsedKey(communityId));
    final community = _communities[communityId];
    if (stored == null || community == null || community.collapsed == stored) {
      return;
    }
    community.collapsed = stored;
    _scheduleResort();
  }

  Future<void> _saveCommunityCollapsed(int communityId, bool collapsed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_communityCollapsedKey(communityId), collapsed);
  }

  String _previewText(String text) {
    return KeywordBlocker.shared.matches(text)
        ? AppStringKeys.chatListBlockedPlaceholder
        : text;
  }

  // MARK: - Sorting

  void _resort() {
    _resortTimer?.cancel();
    _resortTimer = null;
    if (_disposed) return;
    final all = _map.values
        .where((c) => _joinedChatCache[c.id] ?? true)
        .toList();
    _filtered = const [];
    final visible = all;
    _archived = visible.where((c) => c.archiveOrder > 0).toList()
      ..sort(
        (a, b) => a.archiveOrder != b.archiveOrder
            ? b.archiveOrder.compareTo(a.archiveOrder)
            : b.date.compareTo(a.date),
      );
    if (_selectedFilter.folderId == null) {
      _chats = visible.where((c) => c.order > 0).toList()..sort(_compare);
    } else {
      final folderOrders = _folderOrders[_selectedFilter.folderId] ?? const {};
      _chats = visible.where((c) => (folderOrders[c.id] ?? 0) > 0).toList()
        ..sort((a, b) {
          final ao = folderOrders[a.id] ?? 0;
          final bo = folderOrders[b.id] ?? 0;
          if (ao != bo) return bo.compareTo(ao);
          if (a.date != b.date) return b.date.compareTo(a.date);
          return b.id.compareTo(a.id);
        });
    }
    _finishInitialLoadingIfNeeded();
    _notifyIfAlive();
  }

  void _scheduleResort() {
    if (_disposed || _resortTimer != null) return;
    _resortTimer = Timer(const Duration(milliseconds: 16), _resort);
  }

  @visibleForTesting
  void scheduleResortForTesting() => _scheduleResort();

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  void _finishInitialLoadingIfNeeded({bool force = false}) {
    if (_initialLoading && (force || _map.isNotEmpty)) {
      _initialLoading = false;
    }
  }

  static int _compare(ChatSummary a, ChatSummary b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    if (a.order != b.order) return b.order.compareTo(a.order);
    if (a.date != b.date) return b.date.compareTo(a.date);
    return b.id.compareTo(a.id);
  }

  // MARK: - Chat-list peer display metadata (private chats)

  void _resolvePeerIfNeeded(ChatSummary summary) {
    final userId = summary.peerUserId;
    if (userId == null || _resolvingPeers.contains(userId)) return;
    _resolvingPeers.add(userId);
    _client
        .query({'@type': 'getUser', 'user_id': userId})
        .then((user) {
          _resolvingPeers.remove(userId);
          _applyPeerUser(user);
        })
        .catchError((_) {
          _resolvingPeers.remove(userId);
        });
  }

  void _applyPeerUser(Map<String, dynamic> user) {
    final userId = user.int64('id');
    if (userId == null) return;
    var changed = false;
    final isPremium = user.boolean('is_premium') ?? false;
    final isContact = user.boolean('is_contact') ?? false;
    final phoneNumber = user.str('phone_number');
    final accent = user.integer('accent_color_id') ?? -1;
    final status = TDParse.emojiStatusCustomEmojiId(user.obj('emoji_status'));
    for (final chat in <ChatSummary>[
      ..._map.values,
      ..._communityDirectoryChats.values,
    ]) {
      if (chat.peerUserId != userId) continue;
      if (chat.peerIsPremium == isPremium &&
          chat.peerIsContact == isContact &&
          chat.peerPhoneNumber == phoneNumber &&
          chat.peerAccentColorId == accent &&
          chat.peerEmojiStatusId == status) {
        continue;
      }
      chat.peerIsPremium = isPremium;
      chat.peerIsContact = isContact;
      chat.peerPhoneNumber = phoneNumber;
      chat.peerAccentColorId = accent;
      chat.peerEmojiStatusId = status;
      changed = true;
    }
    _resolveBotCommunityIfNeeded(userId, user);
    if (changed) _scheduleResort();
  }

  // MARK: - Last-message sender resolution (groups & channels)

  void _resolveSenderIfNeeded(int id, Map<String, dynamic>? lastMessage) {
    final summary = _map[id] ?? _communityDirectoryChats[id];
    if (summary == null) return;
    if (summary.kind != ChatKind.group && summary.kind != ChatKind.channel) {
      return;
    }
    if (summary.kind == ChatKind.group &&
        lastMessage?.boolean('is_outgoing') == true) {
      _lastSenderKeys[id] = 'self';
      _setLastSender(AppStrings.t(AppStringKeys.chatMeLabel), id);
      return;
    }
    final sender = lastMessage?.obj('sender_id');
    if (sender == null) {
      _lastSenderKeys[id] = null;
      _setLastSender(null, id);
      return;
    }

    switch (sender.type) {
      case 'messageSenderUser':
        final userId = sender.int64('user_id');
        if (userId == null) return;
        final key = _senderKey('user', userId);
        _lastSenderKeys[id] = key;
        final name = _senderNames[key];
        if (name != null) {
          _setLastSender(name, id);
        } else {
          _setLastSender(null, id);
          _resolveUserName(userId, id, key);
        }
      case 'messageSenderChat':
        final senderChatId = sender.int64('chat_id');
        if (senderChatId == null) return;
        if (senderChatId == id) {
          _lastSenderKeys[id] = null;
          _setLastSender(null, id);
          return;
        }
        final key = _senderKey('chat', senderChatId);
        _lastSenderKeys[id] = key;
        final name = _senderNames[key];
        if (name != null) {
          _setLastSender(name, id);
        } else {
          _setLastSender(null, id);
          _resolveChatTitle(senderChatId, id, key);
        }
      default:
        _lastSenderKeys[id] = null;
        _setLastSender(null, id);
    }
  }

  void _setLastSender(String? name, int id) =>
      _mutate(id, (s) => s.lastSender = name);

  String _senderKey(String type, int id) => '$type:$id';

  void _resolveUserName(int userId, int id, String key) {
    _pendingSenderTargets.putIfAbsent(key, () => <int>{}).add(id);
    if (_resolvingSenders.contains(key)) return;
    _resolvingSenders.add(key);
    _client
        .query({'@type': 'getUser', 'user_id': userId})
        .then((user) {
          _resolvingSenders.remove(key);
          final name = TDParse.userName(user);
          _senderNames[key] = name;
          final targets = _pendingSenderTargets.remove(key) ?? {id};
          for (final chatId in targets) {
            if (_lastSenderKeys[chatId] != key) continue;
            _setLastSender(name, chatId);
          }
          _scheduleResort();
        })
        .catchError((_) {
          _resolvingSenders.remove(key);
          _pendingSenderTargets.remove(key);
        });
  }

  void _resolveChatTitle(int senderChatId, int id, String key) {
    _pendingSenderTargets.putIfAbsent(key, () => <int>{}).add(id);
    if (_resolvingSenders.contains(key)) return;
    _resolvingSenders.add(key);
    _client
        .query({'@type': 'getChat', 'chat_id': senderChatId})
        .then((chat) {
          _resolvingSenders.remove(key);
          final title = chat.str('title');
          if (title == null) {
            _pendingSenderTargets.remove(key);
            return;
          }
          _senderNames[key] = title;
          final targets = _pendingSenderTargets.remove(key) ?? {id};
          for (final chatId in targets) {
            if (_lastSenderKeys[chatId] != key) continue;
            _setLastSender(title, chatId);
          }
          _scheduleResort();
        })
        .catchError((_) {
          _resolvingSenders.remove(key);
          _pendingSenderTargets.remove(key);
        });
  }

  String _pinErrorNotice(Object error) {
    final message = error is TdError ? error.message : error.toString();
    final text = message.trim();
    final normalized = text.toLowerCase().replaceAll('_', ' ');
    final hitPinned =
        normalized.contains('pin') ||
        normalized.contains('pinned') ||
        normalized.contains(AppStringKeys.chatInfoPin);
    final hitLimit =
        normalized.contains('limit') ||
        normalized.contains('too many') ||
        normalized.contains('too much') ||
        normalized.contains('many') ||
        normalized.contains('much') ||
        normalized.contains(AppStringKeys.chatInfoPinLimit);
    if (hitPinned && hitLimit) {
      return AppStringKeys.chatInfoPinLimitReachedError;
    }
    return text.isEmpty
        ? AppStringKeys.chatInfoPinFailed
        : AppStrings.t(AppStringKeys.chatInfoPinFailedWithReason, {
            'value1': text,
          });
  }
}
