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

import '../settings/keyword_blocker.dart';
import '../tdlib/chat_membership.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';

class ChatFilterOption {
  const ChatFilterOption({required this.title, this.folderId});

  final String title;
  final int? folderId;

  bool get isAll => folderId == null;
}

class ChatListViewModel extends ChangeNotifier {
  List<ChatSummary> _chats = [];
  List<ChatSummary> _archived = [];
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
  List<ChatFilterOption> get filters => _filters;
  ChatFilterOption get selectedFilter => _selectedFilter;
  bool get isAllFilter => _selectedFilter.isAll;
  bool get isInitialLoading => _initialLoading && _chats.isEmpty;

  /// Authoritative store keyed by chat id; `chats` is a sorted projection.
  final Map<int, ChatSummary> _map = {};
  final Map<int, Map<int, int>> _folderOrders = {};
  final Map<int, bool> _joinedChatCache = {};
  final Map<String, String> _senderNames = {};
  final Map<String, Set<int>> _pendingSenderTargets = {};
  final Map<int, String?> _lastSenderKeys = {};
  final Set<String> _resolvingSenders = {};
  final Set<int> _resolvingPeers = {};
  final Set<int> _resolvingFolders = {};

  final TdClient _client = TdClient.shared;
  StreamSubscription? _sub;
  bool _listening = false;
  bool _prefetchingMain = false;
  final Set<String> _loadingChatLists = {};
  final Set<String> _exhaustedChatLists = {};
  static const _pageSize = 100;
  static const _initialPageSize = 36;
  static const _backgroundHydrateLimit = 60;
  static const _backgroundPrefetchPasses = 1;

  void onAppear() {
    if (_listening) return;
    _listening = true;
    _subscribe();
    _loadFilters();
    _loadChats(_initialPageSize);
    _deferWarmCaches();
  }

  @override
  void dispose() {
    _listening = false;
    _sub?.cancel();
    _resortTimer?.cancel();
    super.dispose();
  }

  // MARK: - Loading

  Map<String, dynamic> get _activeChatList => _selectedFilter.folderId == null
      ? {'@type': 'chatListMain'}
      : {'@type': 'chatListFolder', 'chat_folder_id': _selectedFilter.folderId};

  void _loadFilters() {
    final cached = _client.latestChatFoldersUpdate;
    if (cached != null) _applyChatFolders(cached);

    _client
        .query({'@type': 'getChatFolders'})
        .then(_applyChatFolders)
        .catchError((_) {});
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
    notifyListeners();
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
    notifyListeners();
    if (_resolvingFolders.contains(id)) return;
    _resolvingFolders.add(id);
    _client
        .query({'@type': 'getChatFolder', 'chat_folder_id': id})
        .then((folder) {
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
          notifyListeners();
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
    _exhaustedChatLists.remove(_chatListKey(_activeChatList));
    _exhaustedChatLists.remove('archive');
    _loadFilters();
    await Future.wait([
      _loadAndHydrateChatList(_activeChatList, _pageSize),
      _loadAndHydrateChatList({'@type': 'chatListArchive'}, _pageSize),
    ]);
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
    try {
      final res = await _client.query({
        '@type': 'getChats',
        'chat_list': list,
        'limit': limit,
      });
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
          'chat_list': {'@type': 'chatListMain'},
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
    final targets = [
      ..._chats,
      ..._archived,
    ].where((chat) => chat.unreadCount > 0 || chat.isMarkedUnread).toList();
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

  Future<void> deleteChat(ChatSummary chat) async {
    await _client.query({
      '@type': 'deleteChatHistory',
      'chat_id': chat.id,
      'remove_from_chat_list': true,
      'revoke': false,
    });
  }

  Future<void> leaveAndDeleteChat(ChatSummary chat) async {
    await _client.query({'@type': 'leaveChat', 'chat_id': chat.id});
    await deleteChat(chat);
  }

  void clearNotice() {
    notice = null;
    notifyListeners();
  }

  // MARK: - Update stream

  void _subscribe() {
    _sub = _client.subscribe().listen(_apply);
  }

  void _apply(Map<String, dynamic> update) {
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
          final muteFor =
              update.obj('notification_settings')?.integer('mute_for') ?? 0;
          s.isMuted = muteFor > 0;
        });
        _scheduleResort();

      case 'updateChatPhoto':
        final id = update.int64('chat_id');
        if (id == null) return;
        _mutate(id, (s) => s.photo = TDParse.smallPhoto(update.obj('photo')));
        _scheduleResort();

      case 'updateUser':
        final user = update.obj('user');
        final id = user?.int64('id');
        if (user == null || id == null) return;
        _applyPeerUser(user);
    }
  }

  // MARK: - Mutation helpers

  void _mutate(int id, void Function(ChatSummary) body) {
    final s = _map[id];
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
    if (_map.containsKey(id)) return;
    _client
        .query({'@type': 'getChat', 'chat_id': id})
        .then((raw) => _ingestRawChat(raw, schedule: true))
        .catchError((_) {});
  }

  Future<void> _ingestRawChat(
    Map<String, dynamic> raw, {
    bool schedule = false,
  }) async {
    final summary = TDParse.chat(raw);
    if (summary == null) return;
    if (!await _isJoinedSummary(summary, raw)) {
      _removeChat(summary.id);
      return;
    }
    summary.lastMessage = _previewText(summary.lastMessage);
    _map[summary.id] = summary;
    _applyPositions(summary.id, raw.objects('positions'));
    _resolvePeerIfNeeded(summary);
    _resolveSenderIfNeeded(summary.id, raw.obj('last_message'));
    if (schedule) {
      _scheduleResort();
    } else {
      _resort();
    }
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

  void _removeChat(int id) {
    if (_map.remove(id) == null) return;
    for (final orders in _folderOrders.values) {
      orders.remove(id);
    }
    _joinedChatCache[id] = false;
    _scheduleResort();
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
    final all = _map.values
        .where((c) => _joinedChatCache[c.id] ?? true)
        .toList();
    _archived = all.where((c) => c.archiveOrder > 0).toList()
      ..sort(
        (a, b) => a.archiveOrder != b.archiveOrder
            ? b.archiveOrder.compareTo(a.archiveOrder)
            : b.date.compareTo(a.date),
      );
    if (_selectedFilter.folderId == null) {
      _chats = all.where((c) => c.order > 0).toList()..sort(_compare);
    } else {
      final folderOrders = _folderOrders[_selectedFilter.folderId] ?? const {};
      _chats = all.where((c) => (folderOrders[c.id] ?? 0) > 0).toList()
        ..sort((a, b) {
          final ao = folderOrders[a.id] ?? 0;
          final bo = folderOrders[b.id] ?? 0;
          if (ao != bo) return bo.compareTo(ao);
          if (a.date != b.date) return b.date.compareTo(a.date);
          return b.id.compareTo(a.id);
        });
    }
    _finishInitialLoadingIfNeeded();
    notifyListeners();
  }

  void _scheduleResort() {
    if (_resortTimer != null) return;
    _resortTimer = Timer(const Duration(milliseconds: 16), _resort);
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

  // MARK: - Chat-list Premium display metadata (private chats)

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
    final accent = user.integer('accent_color_id') ?? -1;
    final status =
        user.obj('emoji_status')?.obj('type')?.int64('custom_emoji_id') ??
        user.obj('emoji_status')?.int64('custom_emoji_id') ??
        0;
    for (final chat in _map.values) {
      if (chat.peerUserId != userId) continue;
      if (chat.peerIsPremium == isPremium &&
          chat.peerAccentColorId == accent &&
          chat.peerEmojiStatusId == status) {
        continue;
      }
      chat.peerIsPremium = isPremium;
      chat.peerAccentColorId = accent;
      chat.peerEmojiStatusId = status;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  // MARK: - Last-message sender resolution (groups & channels)

  void _resolveSenderIfNeeded(int id, Map<String, dynamic>? lastMessage) {
    final summary = _map[id];
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
