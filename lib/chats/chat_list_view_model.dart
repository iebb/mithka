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
  List<ChatFilterOption> _filters = const [ChatFilterOption(title: '全部')];
  ChatFilterOption _selectedFilter = const ChatFilterOption(title: '全部');
  String? notice;

  List<ChatSummary> get chats => _chats;
  List<ChatSummary> get archived => _archived;
  List<ChatFilterOption> get filters => _filters;
  ChatFilterOption get selectedFilter => _selectedFilter;
  bool get isAllFilter => _selectedFilter.isAll;

  /// Authoritative store keyed by chat id; `chats` is a sorted projection.
  final Map<int, ChatSummary> _map = {};
  final Map<int, Map<int, int>> _folderOrders = {};
  final Map<int, String> _senderNames = {};
  final Set<int> _resolvingSenders = {};
  final Set<int> _resolvingPeers = {};
  final Set<int> _resolvingFolders = {};

  final TdClient _client = TdClient.shared;
  StreamSubscription? _sub;
  bool _listening = false;
  bool _prefetchingMain = false;
  final Set<String> _loadingChatLists = {};
  final Set<String> _exhaustedChatLists = {};
  static const _pageSize = 100;

  void onAppear() {
    if (_listening) return;
    _listening = true;
    _subscribe();
    _loadFilters();
    _loadChats(_pageSize);
    _loadArchive(_pageSize);
    _prefetchMainChats();
  }

  @override
  void dispose() {
    _sub?.cancel();
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
    final folders = <ChatFilterOption>[const ChatFilterOption(title: '全部')];
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
      '分组 $id';

  void _ensureFolderOption(int id) {
    if (_filters.any((f) => f.folderId == id)) return;
    _filters = [..._filters, ChatFilterOption(title: '分组 $id', folderId: id)];
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
    _loadChatList(_activeChatList, limit);
  }

  void _prefetchMainChats() {
    if (_prefetchingMain || _exhaustedChatLists.contains('main')) return;
    _prefetchingMain = true;
    Future<void>(() async {
      while (!_exhaustedChatLists.contains('main')) {
        final loaded = await _loadChatList({
          '@type': 'chatListMain',
        }, _pageSize);
        if (!loaded && !_loadingChatLists.contains('main')) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      _prefetchingMain = false;
    });
  }

  void _loadArchive(int limit) {
    _client
        .query({
          '@type': 'loadChats',
          'chat_list': {'@type': 'chatListArchive'},
          'limit': limit,
        })
        .catchError((_) => <String, dynamic>{});
  }

  void loadMore() => _loadChats(_pageSize);

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
        .catchError((_) async {
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
          notice = '置顶失败：已达置顶数量上限';
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

  void deleteChat(ChatSummary chat) {
    _client.send({
      '@type': 'deleteChatHistory',
      'chat_id': chat.id,
      'remove_from_chat_list': true,
      'revoke': false,
    });
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
        final summary = TDParse.chat(chat);
        if (summary == null) return;
        _map[summary.id] = summary;
        _applyPositions(summary.id, chat.objects('positions'));
        _resolvePeerIfNeeded(summary);
        _resolveSenderIfNeeded(summary.id, chat.obj('last_message'));
        _resort();

      case 'updateChatFolders':
        _applyChatFolders(update);

      case 'updateChatLastMessage':
        final id = update.int64('chat_id');
        if (id == null) return;
        _applyPositions(id, update.objects('positions'));
        _mutate(id, (s) {
          final last = update.obj('last_message');
          if (last != null) {
            s.date = last.integer('date') ?? s.date;
            final content = last.obj('content');
            if (content != null) s.lastMessage = TDParse.messageText(content);
          } else {
            s.lastMessage = '';
            s.date = 0;
            s.lastSender = null;
          }
        });
        _resolveSenderIfNeeded(id, update.obj('last_message'));
        _resort();

      case 'updateChatPosition':
        final id = update.int64('chat_id');
        final position = update.obj('position');
        if (id == null || position == null) return;
        _applyPosition(id, position);
        _ensureChatLoaded(id);
        _resort();

      case 'updateChatAddedToList':
        final id = update.int64('chat_id');
        final list = update.obj('chat_list');
        if (id == null || list == null) return;
        _ensureChatLoaded(id);
        if (list.type == 'chatListFolder') {
          final folderId = list.integer('chat_folder_id');
          if (folderId != null) {
            _folderOrders.putIfAbsent(folderId, () => {})[id] = 1;
          }
        }
        _resort();

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
        _resort();

      case 'updateChatDraftMessage':
        final id = update.int64('chat_id');
        if (id == null) return;
        _applyPositions(id, update.objects('positions'));
        _mutate(
          id,
          (s) => s.draftText = TDParse.draftText(update.obj('draft_message')),
        );
        _resort();

      case 'updateChatReadInbox':
        final id = update.int64('chat_id');
        if (id == null) return;
        _mutate(
          id,
          (s) =>
              s.unreadCount = update.integer('unread_count') ?? s.unreadCount,
        );
        _resort();

      case 'updateChatIsMarkedAsUnread':
        final id = update.int64('chat_id');
        if (id == null) return;
        _mutate(
          id,
          (s) =>
              s.isMarkedUnread = update.boolean('is_marked_as_unread') ?? false,
        );
        _resort();

      case 'updateChatTitle':
        final id = update.int64('chat_id');
        if (id == null) return;
        _mutate(id, (s) => s.title = update.str('title') ?? s.title);
        _resort();

      case 'updateChatNotificationSettings':
        final id = update.int64('chat_id');
        if (id == null) return;
        _mutate(id, (s) {
          final muteFor =
              update.obj('notification_settings')?.integer('mute_for') ?? 0;
          s.isMuted = muteFor > 0;
        });
        _resort();

      case 'updateChatPhoto':
        final id = update.int64('chat_id');
        if (id == null) return;
        _mutate(id, (s) => s.photo = TDParse.smallPhoto(update.obj('photo')));
        _resort();

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
        .then((raw) {
          final summary = TDParse.chat(raw);
          if (summary == null) return;
          _map[summary.id] = summary;
          _applyPositions(summary.id, raw.objects('positions'));
          _resolvePeerIfNeeded(summary);
          _resolveSenderIfNeeded(summary.id, raw.obj('last_message'));
          _resort();
        })
        .catchError((_) {});
  }

  // MARK: - Sorting

  void _resort() {
    final all = _map.values.toList();
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
    notifyListeners();
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
    final sender = lastMessage?.obj('sender_id');
    if (sender == null) return;

    switch (sender.type) {
      case 'messageSenderUser':
        final userId = sender.int64('user_id');
        if (userId == null) return;
        final name = _senderNames[userId];
        if (name != null) {
          _setLastSender(name, id);
        } else {
          _resolveUserName(userId, id);
        }
      case 'messageSenderChat':
        final senderChatId = sender.int64('chat_id');
        if (senderChatId == null) return;
        if (senderChatId == id) {
          _setLastSender(null, id);
          return;
        }
        final name = _senderNames[senderChatId];
        if (name != null) {
          _setLastSender(name, id);
        } else {
          _resolveChatTitle(senderChatId, id);
        }
      default:
        _setLastSender(null, id);
    }
  }

  void _setLastSender(String? name, int id) =>
      _mutate(id, (s) => s.lastSender = name);

  void _resolveUserName(int userId, int id) {
    if (_resolvingSenders.contains(userId)) return;
    _resolvingSenders.add(userId);
    _client
        .query({'@type': 'getUser', 'user_id': userId})
        .then((user) {
          _resolvingSenders.remove(userId);
          final name = TDParse.userName(user);
          _senderNames[userId] = name;
          _setLastSender(name, id);
          _resort();
        })
        .catchError((_) {
          _resolvingSenders.remove(userId);
        });
  }

  void _resolveChatTitle(int senderChatId, int id) {
    if (_resolvingSenders.contains(senderChatId)) return;
    _resolvingSenders.add(senderChatId);
    _client
        .query({'@type': 'getChat', 'chat_id': senderChatId})
        .then((chat) {
          _resolvingSenders.remove(senderChatId);
          final title = chat.str('title');
          if (title == null) return;
          _senderNames[senderChatId] = title;
          _setLastSender(title, id);
          _resort();
        })
        .catchError((_) {
          _resolvingSenders.remove(senderChatId);
        });
  }
}
