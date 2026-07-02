//
//  shared_media_view.dart
//
//  Shared-content browser for a chat (群相册 / 文件). Tabs run `searchChatMessages`
//  with a media filter — photos/videos in a grid, documents / links / voice in
//  lists. Opened from the chat-info screen.
//

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/photo_avatar.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'chat_view.dart';
import 'file_detail_view.dart';
import 'full_image_viewer.dart';
import 'link_handler.dart';
import 'video_player_view.dart';
import 'voice_audio.dart';
import 'package:mithka/l10n/app_localizations.dart';

class _MediaTab {
  const _MediaTab(
    this.label,
    this.filter,
    this.grid, {
    this.videoOnly = false,
    this.musicOnly = false,
  });
  final String label;
  final String filter;
  final bool grid;
  final bool videoOnly;
  final bool musicOnly;
}

enum _SharedMediaFileFilter { all, downloaded, notDownloaded }

const Color _musicAccent = Color(0xFF22C7A9);
const double _musicMiniPlayerHeight = 70;

class _SharedFileState {
  const _SharedFileState({
    required this.fileId,
    this.downloaded = 0,
    this.total = 0,
    this.completed = false,
    this.active = false,
    this.path,
  });

  final int fileId;
  final int downloaded;
  final int total;
  final bool completed;
  final bool active;
  final String? path;

  bool get hasLocalBytes => downloaded > 0 || completed;
}

class SharedMediaView extends StatefulWidget {
  const SharedMediaView({
    super.key,
    required this.chatId,
    required this.title,
    this.initialTab = 0,
    this.displayTitle = AppStringKeys.sharedMediaChatFiles,
    this.lockedTab = false,
  });
  final int chatId;
  final String title;
  final int initialTab; // 0 图片视频, 1 文件, 2 链接, 3 语音, 4 视频, 5 音乐
  final String displayTitle;
  final bool lockedTab;

  @override
  State<SharedMediaView> createState() => _SharedMediaViewState();
}

class _SharedMediaViewState extends State<SharedMediaView> {
  static const _tabs = [
    _MediaTab(
      AppStringKeys.sharedMediaPhotosAndVideos,
      'searchMessagesFilterPhotoAndVideo',
      true,
    ),
    _MediaTab(
      AppStringKeys.topicPostContentFile,
      'searchMessagesFilterDocument',
      false,
    ),
    _MediaTab(AppStringKeys.sharedMediaLinks, 'searchMessagesFilterUrl', false),
    _MediaTab(
      AppStringKeys.sharedMediaVoice,
      'searchMessagesFilterVoiceNote',
      false,
    ),
    _MediaTab(
      AppStringKeys.sharedMediaVideos,
      'searchMessagesFilterVideo',
      true,
      videoOnly: true,
    ),
    _MediaTab(
      AppStringKeys.profileDetailMusic,
      'searchMessagesFilterAudio',
      false,
      musicOnly: true,
    ),
  ];

  final TdClient _client = TdClient.shared;
  late int _tab = widget.initialTab;
  final Map<int, List<ChatMessage>> _cache = {};
  final Set<int> _loading = {};
  final Map<int, _SharedFileState> _files = {};
  final Map<int, String> _sourceTitles = {};
  List<ChatMessage> _recentGlobalVideos = const [];
  final TextEditingController _search = TextEditingController();
  final VoicePlayer _voice = VoicePlayer();
  ChatMessage? _nowPlayingMusic;
  List<ChatMessage> _musicQueue = const [];
  List<ChatMessage> _musicPlaylist = const [];
  StreamSubscription? _fileSub;
  Timer? _searchDebounce;
  String _query = '';
  _SharedMediaFileFilter _fileFilter = _SharedMediaFileFilter.all;

  @override
  void initState() {
    super.initState();
    _voice.onFinished = _onAudioFinished;
    unawaited(_loadMusicPlaylist());
    _fileSub = _client.subscribe().listen((update) {
      if (update.type != 'updateFile') return;
      final file = update.obj('file');
      if (file != null) _applyFile(file);
    });
    _load(_tab);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _fileSub?.cancel();
    _voice.onFinished = null;
    _voice.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(int tab) async {
    if (_cache.containsKey(tab) || _loading.contains(tab)) return;
    _loading.add(tab);
    final query = _query.trim();
    try {
      if (_usesGlobalSearch(tab)) {
        await _loadGlobalMessages(tab, query);
        return;
      }
      final res = await _client.query({
        '@type': 'searchChatMessages',
        'chat_id': widget.chatId,
        'query': query,
        'sender_id': null,
        'from_message_id': 0,
        'offset': 0,
        'limit': 80,
        'filter': {'@type': _tabs[tab].filter},
      });
      final list = res.objects('messages') ?? const <Map<String, dynamic>>[];
      final parsed = list
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .toList();
      if (!mounted) return;
      setState(() {
        _cache[tab] = parsed;
        _loading.remove(tab);
      });
      _primeFileStates(parsed);
    } catch (_) {
      if (mounted) setState(() => _loading.remove(tab));
    }
  }

  bool _usesGlobalSearch(int tab) => widget.chatId == 0;

  Future<void> _loadGlobalMessages(int tab, String query) async {
    final list = <Map<String, dynamic>>[
      ...await _searchGlobalMessagesInList(
        query: query,
        filter: _tabs[tab].filter,
        chatList: {'@type': 'chatListMain'},
      ),
      ...await _searchGlobalMessagesInList(
        query: query,
        filter: _tabs[tab].filter,
        chatList: {'@type': 'chatListArchive'},
      ),
    ];
    var parsed = list.map(TDParse.message).whereType<ChatMessage>().toList();
    if (_tabs[tab].videoOnly) {
      parsed = parsed.where((message) => message.video != null).toList();
    }
    if (_tabs[tab].videoOnly && query.isEmpty) {
      _recentGlobalVideos = parsed;
    } else if (_tabs[tab].videoOnly && _recentGlobalVideos.isNotEmpty) {
      final seen = parsed.map((m) => '${m.chatId}:${m.id}').toSet();
      parsed = [
        ...parsed,
        for (final message in _recentGlobalVideos)
          if (!seen.contains('${message.chatId}:${message.id}')) message,
      ];
    }
    for (final chatId
        in parsed.map((m) => m.chatId).whereType<int>().take(40)) {
      unawaited(_resolveSourceTitle(chatId));
    }
    if (!mounted) return;
    setState(() {
      _cache[tab] = parsed;
      _loading.remove(tab);
    });
    _primeFileStates(parsed);
  }

  Future<List<Map<String, dynamic>>> _searchGlobalMessagesInList({
    required String query,
    required String filter,
    required Map<String, dynamic> chatList,
  }) async {
    try {
      final res = await _client.query({
        '@type': 'searchMessages',
        'chat_list': chatList,
        'query': query,
        'offset_date': 0,
        'offset_chat_id': 0,
        'offset_message_id': 0,
        'limit': 80,
        'filter': {'@type': filter},
        'min_date': 0,
        'max_date': 0,
      });
      return res.objects('messages') ?? const <Map<String, dynamic>>[];
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> _resolveSourceTitle(int chatId) async {
    if (_sourceTitles.containsKey(chatId)) return;
    try {
      final chat = await _client.query({'@type': 'getChat', 'chat_id': chatId});
      final title = chat.str('title');
      if (!mounted || title == null || title.isEmpty) return;
      setState(() => _sourceTitles[chatId] = title);
    } catch (_) {}
  }

  void _select(int tab) {
    setState(() => _tab = tab);
    _load(tab);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() {
        _query = value;
        _cache.clear();
      });
      _load(_tab);
    });
  }

  void _setFileFilter(_SharedMediaFileFilter filter) {
    if (_fileFilter == filter) return;
    setState(() => _fileFilter = filter);
    _primeFileStates(_cache[_tab] ?? const <ChatMessage>[]);
  }

  void _applyFile(Map<String, dynamic> file) {
    final id = file.integer('id');
    if (id == null) return;
    final local = file.obj('local');
    final expected = file.integer('expected_size') ?? 0;
    final size = file.integer('size') ?? 0;
    final total = expected > 0 ? expected : size;
    final downloadedSize = local?.integer('downloaded_size') ?? 0;
    final downloadedPrefix = local?.integer('downloaded_prefix_size') ?? 0;
    final completed = local?.boolean('is_downloading_completed') == true;
    final downloaded = completed
        ? total
        : (downloadedSize > downloadedPrefix
              ? downloadedSize
              : downloadedPrefix);
    final path = local?.str('path');
    if (!mounted) return;
    setState(() {
      _files[id] = _SharedFileState(
        fileId: id,
        downloaded: downloaded,
        total: total,
        completed: completed,
        active: local?.boolean('is_downloading_active') == true,
        path: path?.isEmpty == true ? null : path,
      );
    });
  }

  void _primeFileStates(Iterable<ChatMessage> messages) {
    for (final message in messages) {
      final id = _fileId(message);
      if (id == null || _files.containsKey(id)) continue;
      unawaited(_loadFileState(id));
    }
  }

  Future<void> _loadFileState(int fileId) async {
    try {
      final file = await _client.query({'@type': 'getFile', 'file_id': fileId});
      _applyFile(file);
    } catch (_) {}
  }

  Future<void> _deleteLocalCache(ChatMessage message) async {
    final id = _fileId(message);
    if (id == null) return;
    try {
      await _client.query({'@type': 'deleteFile', 'file_id': id});
      if (!mounted) return;
      setState(() {
        final previous = _files[id];
        _files[id] = _SharedFileState(
          fileId: id,
          total: previous?.total ?? _declaredSize(message),
        );
      });
      showToast(context, '已删除本地缓存');
    } catch (_) {
      if (mounted) showToast(context, '删除缓存失败');
    }
  }

  String get _musicPlaylistPrefsKey =>
      'mithka.musicPlaylist.v1.${_client.activeSlot}';

  Future<void> _loadMusicPlaylist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawItems =
          prefs.getStringList(_musicPlaylistPrefsKey) ?? const <String>[];
      final playlist = rawItems
          .map(_musicMessageFromPlaylistJson)
          .whereType<ChatMessage>()
          .toList();
      if (!mounted) return;
      setState(() => _musicPlaylist = _dedupeMusic(playlist));
    } catch (_) {}
  }

  Future<void> _saveMusicPlaylist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _musicPlaylistPrefsKey,
        _musicPlaylist.map((message) {
          return jsonEncode(_musicMessageToPlaylistJson(message));
        }).toList(),
      );
    } catch (_) {}
  }

  Map<String, dynamic> _musicMessageToPlaylistJson(ChatMessage message) {
    final music = message.music!;
    return {
      'message_id': message.id,
      'chat_id': _sourceChatIdFor(message),
      'date': message.date,
      'source_title': _sourceTitleFor(message),
      'file_id': music.file!.id,
      'cover_id': music.cover?.id,
      'title': music.title,
      'performer': music.performer,
      'duration': music.duration,
    };
  }

  ChatMessage? _musicMessageFromPlaylistJson(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final fileId = _jsonInt(json['file_id']);
      if (fileId == null || fileId <= 0) return null;
      final messageId = _jsonInt(json['message_id']) ?? 0;
      final chatId = _jsonInt(json['chat_id']);
      final coverId = _jsonInt(json['cover_id']);
      final title = (json['title'] as String?)?.trim();
      final performer = (json['performer'] as String?)?.trim();
      return ChatMessage(
        id: messageId,
        isOutgoing: false,
        text: '',
        date: _jsonInt(json['date']) ?? 0,
        chatId: chatId,
        senderName: (json['source_title'] as String?)?.trim(),
        music: MessageMusic(
          title: title == null || title.isEmpty
              ? AppStrings.t(AppStringKeys.profileDetailMusic)
              : title,
          performer: performer == null || performer.isEmpty ? null : performer,
          cover: coverId == null || coverId <= 0
              ? null
              : TdFileRef(id: coverId),
          file: TdFileRef(id: fileId),
          duration: _jsonInt(json['duration']) ?? 0,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  int? _jsonInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  void _toggleMusicPlaylist(ChatMessage message) {
    final music = message.music;
    final fileId = music?.file?.id;
    if (fileId == null) return;
    final exists = _isMusicInPlaylist(message);
    if (exists) {
      _removeMusicFromPlaylist(message);
      return;
    }
    setState(() {
      _musicPlaylist = [..._musicPlaylist, _playlistCopyOf(message)];
    });
    unawaited(_saveMusicPlaylist());
    showToast(context, '已加入播放列表');
  }

  void _removeMusicFromPlaylist(ChatMessage message, {bool toast = true}) {
    final fileId = message.music?.file?.id;
    if (fileId == null) return;
    setState(() {
      _musicPlaylist = _musicPlaylist
          .where((item) => item.music?.file?.id != fileId)
          .toList();
      if (_musicQueue.any((item) => item.music?.file?.id == fileId)) {
        _musicQueue = _musicQueue
            .where((item) => item.music?.file?.id != fileId)
            .toList();
      }
    });
    unawaited(_saveMusicPlaylist());
    if (toast) showToast(context, '已从播放列表移除');
  }

  ChatMessage _playlistCopyOf(ChatMessage message) {
    return ChatMessage(
      id: message.id,
      isOutgoing: message.isOutgoing,
      text: '',
      date: message.date,
      chatId: _sourceChatIdFor(message),
      senderName: _sourceTitleFor(message),
      music: message.music,
    );
  }

  bool _isMusicInPlaylist(ChatMessage message) {
    final fileId = message.music?.file?.id;
    if (fileId == null) return false;
    return _musicPlaylist.any((item) => item.music?.file?.id == fileId);
  }

  void _playMusicMessage(ChatMessage message) {
    final music = message.music;
    if (music?.file == null) {
      _openSourceMessage(message);
      return;
    }
    final queue = _musicQueueFor(message);
    setState(() {
      _nowPlayingMusic = message;
      _musicQueue = queue;
    });
    unawaited(_voice.toggleAudio(music!.file));
  }

  void _onAudioFinished(int fileId) {
    if (_nowPlayingMusic?.music?.file?.id != fileId) return;
    _playNextMusic();
  }

  void _playNextMusic() => _playAdjacentMusic(1, fromCompletion: true);

  void _playAdjacentMusic(int delta, {bool fromCompletion = false}) {
    final current = _nowPlayingMusic;
    if (current == null || _musicQueue.isEmpty) return;
    final index = _musicQueue.indexWhere(
      (message) => _sameMessage(message, current),
    );
    if (index < 0) return;
    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= _musicQueue.length) {
      if (fromCompletion) return;
      return;
    }
    _playMusicMessage(_musicQueue[nextIndex]);
  }

  List<ChatMessage> _musicQueueFor(ChatMessage seed) {
    if (_isMusicInPlaylist(seed) && _musicPlaylist.isNotEmpty) {
      return _musicPlaylist
          .where((message) => message.music?.file != null)
          .toList();
    }
    final visible = _visibleMusicMessages();
    if (visible.isNotEmpty) return visible;
    return [seed];
  }

  List<ChatMessage> _visibleMusicMessages() {
    final cached = _cache[_tab] ?? const <ChatMessage>[];
    if (!_tabs[_tab].musicOnly || cached.isEmpty) {
      return _musicQueue;
    }
    return _filteredItems(
      cached,
    ).where((message) => message.music?.file != null).toList();
  }

  bool _sameMessage(ChatMessage a, ChatMessage b) =>
      a.id == b.id && _sourceChatIdFor(a) == _sourceChatIdFor(b);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          _header(),
          _toolbar(),
          if (!widget.lockedTab) _tabStrip(),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _body()),
                if (_showMusicMiniPlayer)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _musicMiniPlayer(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _showMusicMiniPlayer =>
      _tabs[_tab].musicOnly && _nowPlayingMusic?.music != null;

  Widget _header() {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: AppIcon(
                    HeroAppIcons.chevronLeft,
                    size: 22,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ),
            Text(
              widget.displayTitle.l10n(context),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabStrip() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _select(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: _tab == i ? AppTheme.brand : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    _tabs[i].label.l10n(context),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: _tab == i ? FontWeight.w600 : FontWeight.w400,
                      color: _tab == i ? AppTheme.brand : c.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    final c = context.colors;
    final showFileFilters = _tabs[_tab].videoOnly || _tab == 1;
    return Container(
      color: c.navBar,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: c.searchFill,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                AppIcon(
                  HeroAppIcons.magnifyingGlass,
                  size: 15,
                  color: c.textTertiary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: TextField(
                    controller: _search,
                    autocorrect: false,
                    textInputAction: TextInputAction.search,
                    style: TextStyle(fontSize: 15, color: c.textPrimary),
                    decoration: InputDecoration(
                      hintText: _tabs[_tab].videoOnly
                          ? '搜索视频、群组、名称或 #hashtag'
                          : '搜索文件名、聊天或发送人',
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                if (_search.text.isNotEmpty)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _search.clear();
                      _onSearchChanged('');
                    },
                    child: AppIcon(
                      HeroAppIcons.xmark,
                      size: 16,
                      color: c.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          if (showFileFilters) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _filterChip('全部', _SharedMediaFileFilter.all),
                const SizedBox(width: 8),
                _filterChip('已下载', _SharedMediaFileFilter.downloaded),
                const SizedBox(width: 8),
                _filterChip('未下载', _SharedMediaFileFilter.notDownloaded),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChip(String label, _SharedMediaFileFilter filter) {
    final c = context.colors;
    final selected = _fileFilter == filter;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setFileFilter(filter),
      child: Container(
        height: 28,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.brand : c.searchFill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : c.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final c = context.colors;
    final items = _cache[_tab];
    if (items == null) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Text(
          AppStringKeys.sharedMediaEmpty.l10n(context),
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    final filtered = _filteredItems(items);
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          '没有匹配的内容',
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    return _tabs[_tab].grid && !_tabs[_tab].videoOnly
        ? _grid(filtered)
        : _list(filtered);
  }

  List<ChatMessage> _filteredItems(List<ChatMessage> items) {
    final query = _query.trim().toLowerCase();
    var filtered = items.where((message) {
      if ((_tabs[_tab].videoOnly || _tab == 1) &&
          !_matchesFileFilter(message)) {
        return false;
      }
      if (query.isEmpty) return true;
      final fields = [
        message.text,
        message.senderName ?? '',
        _sourceTitleFor(message),
        message.document?.fileName ?? '',
        message.music?.title ?? '',
        message.music?.performer ?? '',
      ].join(' ').toLowerCase();
      return fields.contains(query);
    }).toList();
    if (_tabs[_tab].videoOnly) {
      filtered.sort((a, b) {
        final byPriority = _videoPriority(b).compareTo(_videoPriority(a));
        if (byPriority != 0) return byPriority;
        return b.date.compareTo(a.date);
      });
    }
    if (_tabs[_tab].musicOnly) {
      filtered = _dedupeMusic(filtered);
    }
    return filtered;
  }

  List<ChatMessage> _dedupeMusic(List<ChatMessage> items) {
    final seen = <String>{};
    final unique = <ChatMessage>[];
    for (final message in items) {
      final key = _musicDedupeKey(message);
      if (seen.add(key)) unique.add(message);
    }
    return unique;
  }

  String _musicDedupeKey(ChatMessage message) {
    final music = message.music;
    if (music == null) return 'message:${message.chatId}:${message.id}';
    final title = music.title.trim().toLowerCase();
    final performer = (music.performer ?? '').trim().toLowerCase();
    if (title.isEmpty && performer.isEmpty && music.duration <= 0) {
      return 'file:${music.file?.id ?? message.id}';
    }
    return '$title|$performer|${music.duration}';
  }

  int _videoPriority(ChatMessage message) {
    final state = _stateFor(message);
    if (state?.completed == true) return 3;
    if ((state?.downloaded ?? 0) > 0) return 2;
    if (state?.active == true) return 1;
    return 0;
  }

  bool _matchesFileFilter(ChatMessage message) {
    final id = _fileId(message);
    final state = id == null ? null : _files[id];
    return switch (_fileFilter) {
      _SharedMediaFileFilter.all => true,
      _SharedMediaFileFilter.downloaded => state?.completed == true,
      _SharedMediaFileFilter.notDownloaded => state?.completed != true,
    };
  }

  Widget _grid(List<ChatMessage> items) {
    final tab = _tabs[_tab];
    final media = items
        .where((m) => tab.videoOnly ? m.video != null : m.image != null)
        .toList();
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _mediaGridColumns(context),
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: media.length,
      itemBuilder: (context, i) {
        final m = media[i];
        return _mediaTile(m, media);
      },
    );
  }

  int _mediaGridColumns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return (width / 110).floor().clamp(4, 10).toInt();
  }

  Widget _mediaTile(ChatMessage message, List<ChatMessage> media) {
    final video = message.video;
    return GestureDetector(
      onTap: () {
        if (video != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => VideoPlayerView(
                video: video,
                thumb: message.image,
                width: message.imageWidth,
                height: message.imageHeight,
                sourceChatId: _sourceChatIdFor(message),
                messageId: message.id,
              ),
            ),
          );
          return;
        }
        final photos = media
            .where((m) => m.video == null && m.image != null)
            .map((m) => m.image!)
            .toList();
        final photo = message.image;
        if (photo == null) return;
        final index = photos.indexWhere((item) => item.id == photo.id);
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => FullImageViewer(
              items: photos,
              startIndex: index < 0 ? 0 : index,
            ),
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          TDImage(photo: message.image, fit: BoxFit.cover),
          if (video != null) ...[
            Container(color: Colors.black.withValues(alpha: 0.16)),
            Center(
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.48),
                  shape: BoxShape.circle,
                ),
                child: AppIcon(
                  HeroAppIcons.play,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
            if ((message.videoDuration ?? 0) > 0)
              Positioned(
                right: 5,
                bottom: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _duration(message.videoDuration!),
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
              ),
          ],
          Positioned(top: 4, right: 4, child: _overlayMenu(message)),
        ],
      ),
    );
  }

  Widget _list(List<ChatMessage> items) {
    return ListView.builder(
      padding: EdgeInsets.only(
        bottom: _showMusicMiniPlayer
            ? _musicMiniPlayerHeight + MediaQuery.of(context).padding.bottom
            : 0,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _listRow(items[i]),
    );
  }

  Widget _listRow(ChatMessage m) {
    final c = context.colors;
    if (_tabs[_tab].videoOnly && m.video != null) return _videoRow(m);
    if (_tabs[_tab].musicOnly && m.music != null) return _musicRow(m);
    final isVoice = m.voice != null;
    if (isVoice) return _voiceRow(m);
    final isLink = m.document == null && !isVoice;
    final title = m.document?.fileName ?? _linkTitle(m);
    final subtitle = m.document != null ? _fileSubtitle(m) : _linkUrl(m);
    final meta = m.document == null ? _messageMeta(m) : '';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (m.document != null) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => FileDetailView(doc: m.document!)),
          );
        } else if (isLink && m.text.isNotEmpty) {
          openLink(context, m.text);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: c.background,
          border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            _fileThumb(m, isVoice: isVoice, isLink: isLink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: c.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: isLink ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.textTertiary),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
            _rowMenu(m),
          ],
        ),
      ),
    );
  }

  Widget _voiceRow(ChatMessage message) {
    final c = context.colors;
    final voice = message.voice;
    if (voice == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _voice,
      builder: (context, _) {
        final active = _voice.isActive(voice.file);
        final total = active && _voice.total.inMilliseconds > 0
            ? _voice.total
            : Duration(seconds: voice.duration);
        final position = active ? _voice.position : Duration.zero;
        final fraction = total.inMilliseconds > 0
            ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;
        final durationText = active && position > Duration.zero
            ? '${_duration(position.inSeconds)} / ${_duration(voice.duration)}'
            : _duration(voice.duration);
        final sender = _senderLabel(message);
        final subtitle = [
          durationText,
          DateText.listLabel(message.date),
          if (_usesGlobalSearch(_tab) && _sourceTitleFor(message).isNotEmpty)
            '来自 ${_sourceTitleFor(message)}',
        ].join(' · ');
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _voice.toggleVoice(voice.file),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.background,
              border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.brand.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: _voice.isLoading && active
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        )
                      : AppIcon(
                          active && _voice.isPlaying
                              ? HeroAppIcons.pause
                              : HeroAppIcons.play,
                          size: 16,
                          color: AppTheme.brand,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sender,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 3,
                          backgroundColor: c.searchFill,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.brand,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textTertiary),
                      ),
                    ],
                  ),
                ),
                _rowMenu(message),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _musicRow(ChatMessage message) {
    final c = context.colors;
    final music = message.music;
    if (music == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _voice,
      builder: (context, _) {
        final active = _voice.isActive(music.file);
        final subtitle = [
          if ((music.performer ?? '').trim().isNotEmpty)
            music.performer!.trim(),
          DateText.listLabel(message.date),
          if (_usesGlobalSearch(_tab) && _sourceTitleFor(message).isNotEmpty)
            '来自 ${_sourceTitleFor(message)}',
        ].join(' · ');
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _playMusicMessage(message),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.background,
              border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
            ),
            child: Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: music.cover != null
                        ? TDImage(photo: music.cover, fit: BoxFit.cover)
                        : Container(
                            alignment: Alignment.center,
                            color: _musicAccent.withValues(alpha: 0.14),
                            child: AppIcon(
                              HeroAppIcons.music,
                              size: 23,
                              color: _musicAccent,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _musicName(music),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textTertiary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _musicPlaylistButton(message),
                Text(
                  _duration(music.duration),
                  style: TextStyle(
                    fontSize: 12,
                    color: active ? _musicAccent : c.textTertiary,
                  ),
                ),
                _rowMenu(message),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _musicMiniPlayer() {
    final c = context.colors;
    final message = _nowPlayingMusic;
    final music = message?.music;
    if (message == null || music == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _voice,
      builder: (context, _) {
        final active = _voice.isActive(music.file);
        final total = active && _voice.total.inMilliseconds > 0
            ? _voice.total
            : Duration(seconds: music.duration);
        final position = active ? _voice.position : Duration.zero;
        final fraction = total.inMilliseconds > 0
            ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;
        final subtitle = [
          if ((music.performer ?? '').trim().isNotEmpty)
            music.performer!.trim(),
          if (total.inSeconds > 0)
            '${_duration(position.inSeconds)} / ${_duration(total.inSeconds)}',
        ].join(' · ');
        return SafeArea(
          top: false,
          child: Container(
            height: _musicMiniPlayerHeight,
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
            decoration: BoxDecoration(
              color: c.background.withValues(alpha: 0.94),
              border: Border(top: BorderSide(color: c.divider, width: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: music.cover != null
                        ? TDImage(photo: music.cover, fit: BoxFit.cover)
                        : Container(
                            alignment: Alignment.center,
                            color: _musicAccent.withValues(alpha: 0.14),
                            child: AppIcon(
                              HeroAppIcons.music,
                              size: 22,
                              color: _musicAccent,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openSourceMessage(message),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _musicName(music),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: fraction,
                            minHeight: 3,
                            backgroundColor: c.searchFill,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              _musicAccent,
                            ),
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: c.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _musicMiniButton(
                  tooltip: _isMusicInPlaylist(message) ? '从播放列表移除' : '加入播放列表',
                  onTap: () => _toggleMusicPlaylist(message),
                  child: AppIcon(
                    _isMusicInPlaylist(message)
                        ? HeroAppIcons.heart
                        : HeroAppIcons.plus,
                    size: 20,
                    color: _isMusicInPlaylist(message)
                        ? _musicAccent
                        : c.textPrimary,
                  ),
                ),
                _musicMiniButton(
                  tooltip: active && _voice.isPlaying ? '暂停' : '播放',
                  onTap: music.file == null
                      ? null
                      : () => _playMusicMessage(message),
                  child: _voice.isLoading && active
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        )
                      : AppIcon(
                          active && _voice.isPlaying
                              ? HeroAppIcons.pause
                              : HeroAppIcons.play,
                          size: 20,
                          color: c.textPrimary,
                        ),
                ),
                _musicMiniButton(
                  tooltip: '播放列表',
                  onTap: _showMusicQueue,
                  child: AppIcon(
                    HeroAppIcons.listCheck,
                    size: 21,
                    color: c.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMusicQueue() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final c = sheetContext.colors;
          final queue = _musicPlaylist;
          return SafeArea(
            top: false,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 430),
              decoration: BoxDecoration(
                color: c.background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 8, bottom: 10),
                    decoration: BoxDecoration(
                      color: c.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _queueTitle(),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          '${queue.length} 首',
                          style: TextStyle(fontSize: 12, color: c.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: queue.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(20, 34, 20, 42),
                            child: Text(
                              '还没有加入的音乐',
                              style: TextStyle(
                                fontSize: 14,
                                color: c.textTertiary,
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.of(
                                sheetContext,
                              ).padding.bottom,
                            ),
                            itemCount: queue.length,
                            itemBuilder: (context, index) => _musicQueueRow(
                              queue[index],
                              onRemove: () {
                                _removeMusicFromPlaylist(
                                  queue[index],
                                  toast: false,
                                );
                                setSheetState(() {});
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _musicQueueRow(ChatMessage message, {required VoidCallback onRemove}) {
    final c = context.colors;
    final music = message.music;
    if (music == null) return const SizedBox.shrink();
    final active =
        _nowPlayingMusic != null && _sameMessage(message, _nowPlayingMusic!);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).pop();
        _playMusicMessage(message);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 42,
                height: 42,
                child: music.cover != null
                    ? TDImage(photo: music.cover, fit: BoxFit.cover)
                    : Container(
                        alignment: Alignment.center,
                        color: _musicAccent.withValues(alpha: 0.14),
                        child: AppIcon(
                          HeroAppIcons.music,
                          size: 20,
                          color: _musicAccent,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _musicName(music),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active ? _musicAccent : c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if ((music.performer ?? '').trim().isNotEmpty)
                        music.performer!.trim(),
                      _duration(music.duration),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.textTertiary),
                  ),
                ],
              ),
            ),
            if (active)
              AppIcon(
                _voice.isPlaying ? HeroAppIcons.pause : HeroAppIcons.play,
                size: 16,
                color: _musicAccent,
              ),
            SizedBox(
              width: 34,
              height: 34,
              child: IconButton(
                tooltip: '从播放列表移除',
                padding: EdgeInsets.zero,
                onPressed: onRemove,
                icon: AppIcon(
                  HeroAppIcons.trash,
                  size: 17,
                  color: c.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _musicMiniButton({
    required String tooltip,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    return SizedBox(
      width: 38,
      height: 38,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onTap,
        icon: child,
      ),
    );
  }

  Widget _musicPlaylistButton(ChatMessage message) {
    final c = context.colors;
    final inPlaylist = _isMusicInPlaylist(message);
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: inPlaylist ? '从播放列表移除' : '加入播放列表',
        padding: EdgeInsets.zero,
        onPressed: message.music?.file == null
            ? null
            : () => _toggleMusicPlaylist(message),
        icon: AppIcon(
          inPlaylist ? HeroAppIcons.circleCheck : HeroAppIcons.plus,
          size: 18,
          color: inPlaylist ? _musicAccent : c.textTertiary,
        ),
      ),
    );
  }

  Widget _videoRow(ChatMessage message) {
    final c = context.colors;
    final state = _stateFor(message);
    final title = _videoTitle(message);
    final subtitle = [
      DateText.listLabel(message.date),
      if ((message.videoDuration ?? 0) > 0) _duration(message.videoDuration!),
      _downloadLabel(message, state),
    ].join(' · ');
    final caption = message.text.trim();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final video = message.video;
        if (video == null) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => VideoPlayerView(
              video: video,
              thumb: message.image,
              width: message.imageWidth,
              height: message.imageHeight,
              sourceChatId: _sourceChatIdFor(message),
              messageId: message.id,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: c.background,
          border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 86,
              height: 56,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TDImage(photo: message.image, fit: BoxFit.cover),
                    Container(color: Colors.black.withValues(alpha: 0.12)),
                    Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          shape: BoxShape.circle,
                        ),
                        child: AppIcon(
                          HeroAppIcons.play,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if ((message.videoDuration ?? 0) > 0)
                      Positioned(
                        right: 5,
                        bottom: 5,
                        child: _overlayPill(_duration(message.videoDuration!)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      _downloadBadge(state),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.textTertiary),
                  ),
                  if (caption.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    '来自 ${_sourceTitleFor(message)}${(message.senderName ?? '').isEmpty ? '' : ' | ${message.senderName}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.textTertiary),
                  ),
                ],
              ),
            ),
            _rowMenu(message),
          ],
        ),
      ),
    );
  }

  Widget _fileThumb(
    ChatMessage m, {
    required bool isVoice,
    required bool isLink,
  }) {
    final c = context.colors;
    final state = _stateFor(m);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: state?.completed == true
                ? const Color(0xFF1ABC7B).withValues(alpha: 0.16)
                : AppTheme.brand.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            isVoice
                ? HeroAppIcons.microphone.data
                : isLink
                ? HeroAppIcons.link.data
                : HeroAppIcons.solidFile.data,
            size: 21,
            color: state?.completed == true
                ? const Color(0xFF1ABC7B)
                : AppTheme.brand,
          ),
        ),
        if (state?.completed == true)
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF1ABC7B),
                shape: BoxShape.circle,
                border: Border.all(color: c.background, width: 2),
              ),
              child: const Icon(Icons.check, size: 11, color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _downloadBadge(_SharedFileState? state) {
    if (state?.completed != true) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1ABC7B).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Text(
        '已下载',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1ABC7B),
        ),
      ),
    );
  }

  Widget _overlayPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: Colors.white),
      ),
    );
  }

  Widget _rowMenu(ChatMessage message) {
    final c = context.colors;
    final state = _stateFor(message);
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 18, color: c.textTertiary),
      color: c.background,
      onSelected: (value) {
        if (value == 'open-original') _openSourceMessage(message);
        if (value == 'delete-cache') _deleteLocalCache(message);
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: _canOpenSourceMessage(message),
          value: 'open-original',
          child: Text(AppStrings.t(AppStringKeys.momentsOpenOriginalMessage)),
        ),
        if (_fileId(message) != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            enabled: state?.hasLocalBytes == true,
            value: 'delete-cache',
            child: Text(
              '删除本地缓存',
              style: TextStyle(
                color: state?.hasLocalBytes == true
                    ? Colors.redAccent
                    : c.textTertiary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _overlayMenu(ChatMessage message) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        shape: BoxShape.circle,
      ),
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.more_horiz, size: 18, color: Colors.white),
        color: context.colors.background,
        onSelected: (value) {
          if (value == 'open-original') _openSourceMessage(message);
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            enabled: _canOpenSourceMessage(message),
            value: 'open-original',
            child: Text(AppStrings.t(AppStringKeys.momentsOpenOriginalMessage)),
          ),
        ],
      ),
    );
  }

  String _fileSubtitle(ChatMessage message) {
    final state = _stateFor(message);
    final source = _sourceTitleFor(message);
    return [
      DateText.listLabel(message.date),
      _downloadLabel(message, state),
      if (_usesGlobalSearch(_tab) && source.isNotEmpty) '来自 $source',
      if (!_usesGlobalSearch(_tab) && (message.senderName ?? '').isNotEmpty)
        '来自 ${message.senderName}',
    ].join(' · ');
  }

  String _linkTitle(ChatMessage message) {
    final preview = message.linkPreview;
    final title = preview?.title.trim() ?? '';
    if (title.isNotEmpty) return title;
    final siteName = preview?.siteName.trim() ?? '';
    if (siteName.isNotEmpty) return siteName;
    final text = message.text.trim().replaceAll('\n', ' ');
    return text.isEmpty ? AppStrings.t(AppStringKeys.sharedMediaLinks) : text;
  }

  String _linkUrl(ChatMessage message) {
    final previewUrl = message.linkPreview?.url.trim() ?? '';
    if (previewUrl.isNotEmpty) return previewUrl;
    final displayUrl = message.linkPreview?.displayUrl.trim() ?? '';
    if (displayUrl.isNotEmpty) return displayUrl;
    final text = message.text.trim();
    final match = RegExp(r'https?://\S+').firstMatch(text);
    if (match != null) return match.group(0)!;
    return text;
  }

  String _messageMeta(ChatMessage message) {
    final parts = [
      DateText.listLabel(message.date),
      if (_usesGlobalSearch(_tab) && _sourceTitleFor(message).isNotEmpty)
        '来自 ${_sourceTitleFor(message)}',
      if (!_usesGlobalSearch(_tab) && (message.senderName ?? '').isNotEmpty)
        '来自 ${message.senderName}',
    ].where((item) => item.isNotEmpty).toList();
    return parts.join(' · ');
  }

  String _senderLabel(ChatMessage message) {
    final sender = message.senderName?.trim();
    if (sender != null && sender.isNotEmpty) return sender;
    if (message.isOutgoing) return AppStrings.t(AppStringKeys.chatMeLabel);
    final source = _sourceTitleFor(message).trim();
    return source.isEmpty
        ? AppStrings.t(AppStringKeys.sharedMediaVoiceMessages)
        : source;
  }

  String _downloadLabel(ChatMessage message, _SharedFileState? state) {
    final declared = _declaredSize(message);
    final total = state?.total == 0 ? declared : (state?.total ?? declared);
    final downloaded = state?.completed == true
        ? total
        : (state?.downloaded ?? 0);
    if (state?.completed == true) {
      return '已下载 ${_fileSize(total)}';
    }
    if (downloaded > 0) {
      return '已下载 ${_fileSize(downloaded)} / ${_fileSize(total)}';
    }
    return '未下载 · ${_fileSize(total)}';
  }

  String _videoTitle(ChatMessage message) {
    final text = message.text.trim().replaceAll('\n', ' ');
    if (text.isNotEmpty) return text;
    return '${DateText.listLabel(message.date)} 视频';
  }

  String _musicName(MessageMusic music) {
    final title = music.title.trim().replaceAll('\n', ' ');
    final performer = (music.performer ?? '').trim().replaceAll('\n', ' ');
    if (title.isNotEmpty) return title;
    if (performer.isNotEmpty) return performer;
    return AppStrings.t(AppStringKeys.profileDetailMusic);
  }

  String _queueTitle() => '我的播放列表';

  bool _canOpenSourceMessage(ChatMessage message) =>
      _sourceChatIdFor(message) != 0 && message.id != 0;

  void _openSourceMessage(ChatMessage message) {
    if (!_canOpenSourceMessage(message)) return;
    final sourceChatId = _sourceChatIdFor(message);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatView(
          chatId: sourceChatId,
          title: _sourceTitleFor(message),
          initialMessageId: message.id,
        ),
      ),
    );
  }

  int _sourceChatIdFor(ChatMessage message) => message.chatId ?? widget.chatId;

  String _sourceTitleFor(ChatMessage message) {
    final sourceChatId = message.chatId;
    if (sourceChatId != null) {
      return _sourceTitles[sourceChatId] ?? widget.title;
    }
    return widget.title;
  }

  int? _fileId(ChatMessage message) =>
      message.document?.file?.id ?? message.video?.id;

  int _declaredSize(ChatMessage message) => message.document?.size ?? 0;

  _SharedFileState? _stateFor(ChatMessage message) {
    final id = _fileId(message);
    return id == null ? null : _files[id];
  }

  String _fileSize(int bytes) {
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  String _duration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }
}
