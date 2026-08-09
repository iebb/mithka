//
//  shared_media_view.dart
//
//  Shared-content browser for a chat (群相册 / 文件). Tabs run `searchChatMessages`
//  with a media filter — photos/videos in a grid, documents / links / voice in
//  lists. Opened from the chat-info screen.
//

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/adaptive_split_layout.dart';
import '../app/primary_chat_launcher.dart';
import '../chats/search_view.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'file_detail_view.dart';
import 'image_preview.dart';
import 'link_handler.dart';
import 'music_player_controller.dart';
import 'video_playback_queue.dart';
import 'video_player_view.dart';
import 'voice_audio.dart';

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

enum _SharedMediaMenuAction { openOriginal, deleteCache }

enum _MusicHubTab { playlists, music }

const double _videoGridMinCardWidth = 248;
const double _videoGridMaxCardWidth = 320;
const double _videoGridHorizontalPadding = 20;
const double _videoGridVerticalPadding = 16;
const double _videoGridColumnGap = 16;
const double _videoGridRowGap = 18;
const double _videoGridMetadataHeight = 116;

/// Music and Video are hosted by the surrounding tablet/desktop shell, so a
/// second back/title bar is both redundant and unsafe there. The richer grid
/// remains a separate wide-layout decision: portrait iPad keeps the list but
/// still omits this inner header.
bool sharedMediaUsesHeaderlessHub(
  Size size, {
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) {
  final target = platform ?? defaultTargetPlatform;
  return usesDesktopShellLayout(size, platform: target, isWeb: isWeb) ||
      (!isWeb && target == TargetPlatform.iOS && size.shortestSide >= 600);
}

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
    this.showBackButton = true,
  });
  final int chatId;
  final String title;
  final int initialTab; // 0 图片视频, 1 文件, 2 链接, 3 语音, 4 视频, 5 音乐
  final String displayTitle;
  final bool lockedTab;
  final bool showBackButton;

  @override
  State<SharedMediaView> createState() => _SharedMediaViewState();
}

class _SharedMediaViewState extends State<SharedMediaView> {
  static const _tabs = [
    _MediaTab(
      AppStringKeys.sharedMediaPhotos,
      'searchMessagesFilterPhoto',
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
  late final int _accountSlot;
  late int _tab = widget.initialTab;
  _MusicHubTab _musicHubTab = _MusicHubTab.music;
  final Map<int, List<ChatMessage>> _cache = {};
  final Set<int> _loading = {};
  final Map<int, _SharedFileState> _files = {};
  final Set<int> _watchedFiles = {};
  final Map<int, String> _sourceTitles = {};
  List<ChatMessage> _recentGlobalVideos = const [];
  final TextEditingController _search = TextEditingController();
  final VoicePlayer _voice = VoicePlayer();
  StreamSubscription? _fileSub;
  Timer? _searchDebounce;
  String _query = '';
  _SharedMediaFileFilter _fileFilter = _SharedMediaFileFilter.all;

  /// Minimum video duration for the video tab, persisted device-wide so the
  /// choice survives across chats and launches (phone/tablet/desktop alike).
  static const _minVideoDurationPrefsKey =
      'mithka.sharedMedia.minVideoDuration';
  static const _minVideoDurationStops = [0, 10, 30, 60, 300, 1800];
  int _minVideoDurationSeconds = 0;
  SharedPreferences? _prefs;

  Future<void> _loadMinVideoDuration() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _prefs = prefs;
    final saved = prefs.getInt(_minVideoDurationPrefsKey) ?? 0;
    if (saved != _minVideoDurationSeconds &&
        _minVideoDurationStops.contains(saved)) {
      setState(() => _minVideoDurationSeconds = saved);
    }
  }

  void _setMinVideoDuration(int seconds) {
    if (_minVideoDurationSeconds == seconds) return;
    setState(() => _minVideoDurationSeconds = seconds);
    unawaited(_prefs?.setInt(_minVideoDurationPrefsKey, seconds));
  }

  String _minVideoDurationLabel(int seconds) {
    if (seconds <= 0) {
      return AppStrings.t(AppStringKeys.sharedMediaFilterAll);
    }
    if (seconds < 60) {
      return AppStrings.t(AppStringKeys.tdMessageSecondsDuration, {
        'value1': seconds,
      });
    }
    return AppStrings.t(AppStringKeys.tdMessageMinutesDuration, {
      'value1': seconds ~/ 60,
    });
  }

  bool _musicPlayerHostAttached = false;

  @override
  void initState() {
    super.initState();
    _accountSlot = _client.activeSlot;
    unawaited(_loadMinVideoDuration());
    _fileSub = _client
        .subscribeAll()
        .where((update) {
          if (update.type != 'updateFile') return false;
          final clientId = update.integer('@client_id');
          return clientId != null &&
              _client.slotForClient(clientId) == _accountSlot;
        })
        .listen((update) {
          final file = update.obj('file');
          if (file != null) _applyFile(file);
        });
    _load(_tab);
    if (_isMusicHub) {
      unawaited(_refreshMusicHubSources());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        MusicPlayerController.shared.attachEmbeddedPlayerHost(this);
        _musicPlayerHostAttached = true;
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _fileSub?.cancel();
    _voice.dispose();
    _search.dispose();
    if (_musicPlayerHostAttached) {
      MusicPlayerController.shared.detachEmbeddedPlayerHost(this);
    }
    super.dispose();
  }

  bool get _isMusicHub =>
      widget.chatId == 0 && widget.lockedTab && widget.initialTab == 5;

  Future<void> _refreshMusicHubSources() async {
    try {
      await MusicPlayerController.shared.refreshPlaylists(force: true);
    } catch (error, stackTrace) {
      debugPrint('Failed to refresh music hub playlists: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
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
      final res = await _client.queryForSlot({
        '@type': 'searchChatMessages',
        'chat_id': widget.chatId,
        'query': query,
        'sender_id': null,
        'from_message_id': 0,
        'offset': 0,
        'limit': 80,
        'filter': {'@type': _tabs[tab].filter},
      }, _accountSlot);
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
      final res = await _client.queryForSlot({
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
      }, _accountSlot);
      return res.objects('messages') ?? const <Map<String, dynamic>>[];
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> _resolveSourceTitle(int chatId) async {
    if (_sourceTitles.containsKey(chatId)) return;
    try {
      final chat = await _client.queryForSlot({
        '@type': 'getChat',
        'chat_id': chatId,
      }, _accountSlot);
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
    // TDLib emits updateFile for every avatar, thumbnail and sticker in the
    // app — dozens a second while anything downloads. Rebuilding this page for
    // a file it has never shown means re-filtering and re-sorting the grid for
    // nothing, so only the ids this screen actually renders get through.
    if (id == null || !_watchedFiles.contains(id)) return;
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
      if (id == null) continue;
      _watchedFiles.add(id);
      if (_files.containsKey(id)) continue;
      unawaited(_loadFileState(id));
    }
  }

  Future<void> _loadFileState(int fileId) async {
    try {
      final file = await _client.queryForSlot({
        '@type': 'getFile',
        'file_id': fileId,
      }, _accountSlot);
      _applyFile(file);
    } catch (_) {}
  }

  Future<void> _deleteLocalCache(ChatMessage message) async {
    final id = _fileId(message);
    if (id == null) return;
    try {
      await _client.queryForSlot({
        '@type': 'deleteFile',
        'file_id': id,
      }, _accountSlot);
      if (!mounted) return;
      setState(() {
        final previous = _files[id];
        _files[id] = _SharedFileState(
          fileId: id,
          total: previous?.total ?? _declaredSize(message),
        );
      });
      showToast(context, AppStrings.t(AppStringKeys.sharedMediaCacheDeleted));
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.sharedMediaCacheDeleteFailed),
        );
      }
    }
  }

  void _toggleMusicPlaylist(ChatMessage message) => unawaited(
    showMusicPlaylists(context, addMessage: _musicPlayerMessage(message)),
  );

  bool _isMusicInPlaylist(ChatMessage message) {
    return MusicPlayerController.shared.isInPlaylist(
      _musicPlayerMessage(message),
    );
  }

  void _playMusicMessage(ChatMessage message) {
    final music = message.music;
    if (music?.file == null) {
      _openSourceMessage(message);
      return;
    }
    final playable = _musicPlayerMessage(message);
    final sourceChatId = widget.chatId != 0 ? widget.chatId : playable.chatId;
    if (sourceChatId == null || sourceChatId == 0) {
      _openSourceMessage(message);
      return;
    }
    unawaited(
      MusicPlayerController.shared.playChat(
        playable,
        sourceChatId,
        title: widget.chatId != 0 ? widget.title : playable.senderName,
      ),
    );
  }

  ChatMessage _musicPlayerMessage(ChatMessage message) {
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

  bool _usesWideMediaPresentation(BuildContext context) {
    if (!_tabs[_tab].videoOnly && !_tabs[_tab].musicOnly) return false;
    return usesSplitSelectionLayout(MediaQuery.sizeOf(context));
  }

  bool _hidesInnerHeader(BuildContext context) {
    if (!_tabs[_tab].videoOnly && !_tabs[_tab].musicOnly) return false;
    return sharedMediaUsesHeaderlessHub(MediaQuery.sizeOf(context));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hideInnerHeader = _hidesInnerHeader(context);
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          if (!hideInnerHeader) _header(),
          if (!_isMusicHub || _musicHubTab == _MusicHubTab.music) _toolbar(),
          if (!widget.lockedTab) _tabStrip(),
          if ((!_isMusicHub || _musicHubTab == _MusicHubTab.music) &&
              _showsFileFilters)
            _fileFilterBar(),
          Expanded(
            child: _isMusicHub && _musicHubTab == _MusicHubTab.playlists
                ? _musicSourcesBody()
                : _body(),
          ),
          if (_isMusicHub) _musicHubPlayer(),
          if (_isMusicHub) _musicHubBottomTabs(),
        ],
      ),
    );
  }

  Widget _musicHubPlayer() {
    return AnimatedBuilder(
      animation: MusicPlayerController.shared,
      builder: (context, _) {
        final player = MusicPlayerController.shared;
        return AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: player.isVisible && !player.collapsed
              ? const GlobalMusicPlayerBar()
              : const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _musicSourcesBody() {
    final controller = MusicPlayerController.shared;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final playlistChatIds = controller.playlists
            .map((playlist) => playlist.chatId)
            .toSet();
        final playedChats = controller.playedMusicChats
            .where((chat) => !playlistChatIds.contains(chat.chatId))
            .toList(growable: false);
        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            _musicSourceSection(
              AppStrings.t(AppStringKeys.musicPlayerPlaylists),
              onAdd: () => unawaited(createMusicPlaylist(context)),
            ),
            if (controller.playlists.isEmpty)
              _musicSourcesEmpty(
                AppStrings.t(AppStringKeys.musicPlayerNoPlaylists),
                showCreate: playedChats.isEmpty,
              )
            else
              for (final playlist in controller.playlists)
                _musicSourceRow(
                  title: playlist.title,
                  subtitle: AppStrings.plural(
                    AppStringKeys.musicPlayerTrackCount,
                    playlist.tracks.length,
                  ),
                  icon: HeroAppIcons.music,
                  onTap: () =>
                      unawaited(showMusicPlaylistTracks(context, playlist)),
                ),
            if (playedChats.isNotEmpty) ...[
              const SizedBox(height: 10),
              _musicSourceSection(
                AppStrings.t(AppStringKeys.musicPlayerPlayedChats),
              ),
              for (final source in playedChats)
                _musicSourceRow(
                  title: source.title,
                  subtitle: [
                    AppStrings.t(AppStringKeys.profileDetailMusic),
                    DateText.listLabel(source.lastPlayedAt ~/ 1000),
                  ].where((value) => value.isNotEmpty).join(' · '),
                  icon: HeroAppIcons.comments,
                  onTap: () =>
                      unawaited(showPlayedMusicChatTracks(context, source)),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _musicSourceSection(String title, {VoidCallback? onAdd}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ),
          if (onAdd != null)
            Semantics(
              button: true,
              label: AppStrings.t(AppStringKeys.musicPlayerCreatePlaylist),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAdd,
                child: SizedBox(
                  width: 40,
                  height: 36,
                  child: Center(
                    child: AppIcon(
                      HeroAppIcons.plus,
                      size: 21,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _musicSourcesEmpty(String message, {required bool showCreate}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
      child: Column(
        children: [
          AppIcon(HeroAppIcons.music, size: 34, color: c.textTertiary),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: c.textSecondary),
          ),
          if (showCreate) ...[
            const SizedBox(height: 18),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(createMusicPlaylist(context)),
              child: Container(
                height: 42,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: musicPlayerAccent,
                  borderRadius: BorderRadius.circular(21),
                ),
                child: Text(
                  AppStrings.t(AppStringKeys.musicPlayerCreatePlaylist),
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _musicSourceRow({
    required String title,
    required String subtitle,
    required AppIconData icon,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 11, 14, 11),
          decoration: BoxDecoration(
            color: c.background,
            border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: musicPlayerAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: AppIcon(icon, size: 21, color: musicPlayerAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
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
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 17,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _musicHubBottomTabs() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 54,
          child: Row(
            children: [
              _musicHubTabItem(
                tab: _MusicHubTab.playlists,
                icon: HeroAppIcons.listCheck,
                label: AppStrings.t(AppStringKeys.musicPlayerPlaylists),
              ),
              _musicHubTabItem(
                tab: _MusicHubTab.music,
                icon: HeroAppIcons.music,
                label: AppStrings.t(AppStringKeys.profileDetailMusic),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _musicHubTabItem({
    required _MusicHubTab tab,
    required AppIconData icon,
    required String label,
  }) {
    final c = context.colors;
    final selected = _musicHubTab == tab;
    final color = selected ? musicPlayerAccent : c.textTertiary;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _musicHubTab = tab),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(icon, size: 20, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    return Container(
      key: const ValueKey('shared-media-inner-header'),
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
            if (widget.showBackButton)
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  key: const ValueKey('shared-media-back-button'),
                  button: true,
                  label: MaterialLocalizations.of(context).backButtonTooltip,
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
              ),
            Text(
              AppStrings.t(widget.displayTitle),
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
                    AppStrings.t(_tabs[i].label),
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
    return Container(
      color: c.navBar,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
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
                      ? AppStrings.t(AppStringKeys.sharedMediaSearchVideosHint)
                      : AppStrings.t(AppStringKeys.sharedMediaSearchFilesHint),
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
    );
  }

  bool get _showsFileFilters => _tabs[_tab].videoOnly || _tab == 1;

  Widget _fileFilterBar() {
    final c = context.colors;
    final dense = isDesktopTargetPlatform();
    final duration = _tabs[_tab].videoOnly ? _minDurationControl() : null;

    // Desktop keeps one row at the search field's own height. Touch splits it
    // so neither control ends up cramped.
    final children = dense
        ? [
            Row(
              children: [
                _fileFilterDropdown(),
                if (duration != null) ...[
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(child: duration),
                ],
              ],
            ),
          ]
        : [
            Row(children: [_fileFilterDropdown()]),
            if (duration != null) ...[
              const SizedBox(height: AppSpacing.md),
              duration,
            ],
          ];

    return Container(
      color: c.navBar,
      padding: EdgeInsets.fromLTRB(12, dense ? 6 : 8, 12, dense ? 6 : 8),
      child: Column(
        key: const ValueKey('shared-media-filter-strip'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  /// Discrete min-duration scrubber for the video tab: 0 · 10s · 30s · 1m ·
  /// 5m · 30m. On the app's own scrubber rather than CupertinoSlider, whose
  /// thumb dwarfs everything beside it in a toolbar.
  Widget _minDurationControl() {
    final c = context.colors;
    final dense = isDesktopTargetPlatform();
    final index = _minVideoDurationStops
        .indexOf(_minVideoDurationSeconds)
        .clamp(0, _minVideoDurationStops.length - 1);
    return Row(
      key: const ValueKey('shared-media-min-duration'),
      children: [
        Text(
          AppStrings.t(AppStringKeys.sharedMediaMinDuration),
          style: TextStyle(
            fontSize: dense ? AppTextSize.footnote : AppTextSize.callout,
            color: c.textSecondary,
          ),
        ),
        SizedBox(width: dense ? AppSpacing.md : AppSpacing.lg),
        Expanded(
          child: AppValueScrubber(
            compact: dense,
            value: index.toDouble(),
            min: 0,
            max: (_minVideoDurationStops.length - 1).toDouble(),
            onChanged: (value) => _setMinVideoDuration(
              _minVideoDurationStops[value.round().clamp(
                0,
                _minVideoDurationStops.length - 1,
              )],
            ),
          ),
        ),
        SizedBox(width: dense ? AppSpacing.md : AppSpacing.lg),
        SizedBox(
          width: 46,
          child: Text(
            _minVideoDurationLabel(_minVideoDurationSeconds),
            maxLines: 1,
            style: TextStyle(
              fontSize: dense ? AppTextSize.footnote : AppTextSize.callout,
              color: c.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  String _fileFilterLabel(_SharedMediaFileFilter filter) => switch (filter) {
    _SharedMediaFileFilter.all => AppStrings.t(
      AppStringKeys.sharedMediaFilterAll,
    ),
    _SharedMediaFileFilter.downloaded => AppStrings.t(
      AppStringKeys.sharedMediaFilterDownloaded,
    ),
    _SharedMediaFileFilter.notDownloaded => AppStrings.t(
      AppStringKeys.sharedMediaFilterNotDownloaded,
    ),
  };

  /// The three states as a dropdown rather than a row of pills: only one can
  /// be active, and three stadium chips took the width of the whole bar.
  Widget _fileFilterDropdown() {
    final c = context.colors;
    final dense = isDesktopTargetPlatform();
    final height = dense ? DesktopInlineSearchField.height : 32.0;
    // The surface carries its own semantics; wrapping it in another Semantics
    // node leaves the tap action on the inner one where callers cannot see it.
    return AppInteractiveSurface(
      key: const ValueKey('shared-media-filter-dropdown'),
      semanticLabel: _fileFilterLabel(_fileFilter),
      onTap: _pickFileFilter,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12),
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _fileFilterLabel(_fileFilter),
              style: TextStyle(
                fontSize: dense ? AppTextSize.footnote : AppTextSize.callout,
                color: c.textPrimary,
              ),
            ),
            SizedBox(width: dense ? 6 : 8),
            AppIcon(
              HeroAppIcons.chevronDown,
              size: dense ? 11 : 13,
              color: c.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFileFilter() async {
    final chosen = await showAppModalSheet<_SharedMediaFileFilter>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SettingsCard(
          margin: const EdgeInsets.all(10),
          children: [
            for (final filter in _SharedMediaFileFilter.values)
              SettingsRow(
                key: ValueKey('shared-media-filter-${filter.name}'),
                title: _fileFilterLabel(filter),
                showChevron: false,
                trailing: filter == _fileFilter
                    ? AppIcon(
                        HeroAppIcons.check,
                        size: AppIconSize.md,
                        color: AppTheme.brand,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(filter),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) _setFileFilter(chosen);
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
          AppStrings.t(AppStringKeys.sharedMediaNoMatches),
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    if (_tabs[_tab].videoOnly && _usesWideMediaPresentation(context)) {
      return _videoGrid(filtered);
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
      if (_tabs[_tab].videoOnly &&
          _minVideoDurationSeconds > 0 &&
          (message.videoDuration ?? 0) < _minVideoDurationSeconds) {
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
              builder: (_) =>
                  VideoPlaylistPlayerView(queue: _videoQueue(media, message)),
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
        unawaited(
          openImagePreview(
            context,
            items: photos,
            startIndex: index < 0 ? 0 : index,
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          TDImage(photo: message.image),
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
                child: const AppIcon(
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
                    borderRadius: BorderRadius.circular(AppRadius.sm),
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

  Widget _videoGrid(List<ChatMessage> items) {
    final videos = items
        .where((message) => message.video != null)
        .toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.max(
          1.0,
          constraints.maxWidth - _videoGridHorizontalPadding * 2,
        );
        final columnCount =
            ((availableWidth + _videoGridColumnGap) /
                    (_videoGridMinCardWidth + _videoGridColumnGap))
                .floor()
                .clamp(1, 6)
                .toInt();
        final unconstrainedCardWidth =
            (availableWidth - _videoGridColumnGap * (columnCount - 1)) /
            columnCount;
        final minimumCardWidth = math.min(
          _videoGridMinCardWidth,
          availableWidth,
        );
        final cardWidth = unconstrainedCardWidth
            .clamp(minimumCardWidth, _videoGridMaxCardWidth)
            .toDouble();
        final gridWidth =
            cardWidth * columnCount + _videoGridColumnGap * (columnCount - 1);
        final cardHeight = cardWidth * 9 / 16 + _videoGridMetadataHeight;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: gridWidth,
            child: GridView.builder(
              key: const ValueKey('shared-video-grid'),
              padding: const EdgeInsets.symmetric(
                vertical: _videoGridVerticalPadding,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columnCount,
                crossAxisSpacing: _videoGridColumnGap,
                mainAxisSpacing: _videoGridRowGap,
                mainAxisExtent: cardHeight,
              ),
              itemCount: videos.length,
              itemBuilder: (context, index) =>
                  _videoCard(videos[index], videos),
            ),
          ),
        );
      },
    );
  }

  Widget _videoCard(ChatMessage message, List<ChatMessage> items) {
    final c = context.colors;
    final state = _stateFor(message);
    final title = _videoTitle(message);
    final duration = message.videoDuration ?? 0;
    final source = _videoSourceLabel(message);
    final status = [
      DateText.listLabel(message.date),
      _downloadLabel(message, state),
    ].where((value) => value.isNotEmpty).join(' · ');
    final semanticsLabel = [
      title,
      if (duration > 0) _duration(duration),
      status,
      source,
    ].where((value) => value.isNotEmpty).join(', ');
    return Semantics(
      key: ValueKey(
        'shared-video-card-${_sourceChatIdFor(message)}-${message.id}',
      ),
      container: true,
      button: true,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openVideoPlayer(message, items),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: c.divider, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TDImage(photo: message.image, cornerRadius: 0),
                    Container(color: Colors.black.withValues(alpha: 0.12)),
                    Center(
                      child: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.58),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const AppIcon(
                          HeroAppIcons.play,
                          size: 19,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (duration > 0)
                      Positioned(
                        left: 9,
                        bottom: 9,
                        child: _overlayPill(_duration(duration)),
                      ),
                    if (state?.completed == true)
                      Positioned(
                        right: 48,
                        top: 10,
                        child: _downloadBadge(state),
                      ),
                    Positioned(right: 9, top: 9, child: _overlayMenu(message)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textTertiary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(List<ChatMessage> items) {
    return ListView.builder(
      key: ValueKey(
        _tabs[_tab].videoOnly ? 'shared-video-list' : 'shared-media-list',
      ),
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (context, i) => _listRow(items[i], items),
    );
  }

  Widget _listRow(ChatMessage m, List<ChatMessage> items) {
    final c = context.colors;
    if (_tabs[_tab].videoOnly && m.video != null) return _videoRow(m, items);
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
        final sender = _voiceSenderLabel(message);
        final source = _sourceTitleFor(message);
        final subtitle = [
          durationText,
          DateText.listLabel(message.date),
          if (source.isNotEmpty)
            AppStrings.t(AppStringKeys.sharedMediaFromSource, {
              'value1': source,
            }),
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
    final controller = MusicPlayerController.shared;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final active = controller.isActive(music.file);
        final subtitle = [
          if ((music.performer ?? '').trim().isNotEmpty)
            music.performer!.trim(),
          DateText.listLabel(message.date),
          if (_usesGlobalSearch(_tab) && _sourceTitleFor(message).isNotEmpty)
            AppStrings.t(AppStringKeys.sharedMediaFromSource, {
              'value1': _sourceTitleFor(message),
            }),
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
                        ? TDImage(photo: music.cover)
                        : Container(
                            alignment: Alignment.center,
                            color: musicPlayerAccent.withValues(alpha: 0.14),
                            child: const AppIcon(
                              HeroAppIcons.music,
                              size: 23,
                              color: musicPlayerAccent,
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
                    color: active ? musicPlayerAccent : c.textTertiary,
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

  Widget _musicPlaylistButton(ChatMessage message) {
    final c = context.colors;
    final inPlaylist = _isMusicInPlaylist(message);
    final enabled = message.music?.file != null;
    final label = inPlaylist
        ? AppStrings.t(AppStringKeys.musicPlayerRemoveFromPlaylist)
        : AppStrings.t(AppStringKeys.musicPlayerAddToPlaylist);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => _toggleMusicPlaylist(message) : null,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: AppIcon(
              inPlaylist ? HeroAppIcons.circleCheck : HeroAppIcons.plus,
              size: 18,
              color: inPlaylist ? musicPlayerAccent : c.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _videoRow(ChatMessage message, List<ChatMessage> items) {
    final c = context.colors;
    final state = _stateFor(message);
    final title = _videoTitle(message);
    final subtitle = [
      DateText.listLabel(message.date),
      if ((message.videoDuration ?? 0) > 0) _duration(message.videoDuration!),
      _downloadLabel(message, state),
    ].join(' · ');
    final caption = message.text.trim();
    final source = _videoSourceLabel(message);
    return Semantics(
      container: true,
      button: true,
      label: [title, subtitle, source].join(', '),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openVideoPlayer(message, items),
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
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TDImage(photo: message.image),
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
                          child: const AppIcon(
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
                          child: _overlayPill(
                            _duration(message.videoDuration!),
                          ),
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
                      source,
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
      ),
    );
  }

  void _openVideoPlayer(ChatMessage message, List<ChatMessage> items) {
    if (message.video == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            VideoPlaylistPlayerView(queue: _videoQueue(items, message)),
      ),
    );
  }

  String _videoSourceLabel(ChatMessage message) {
    final source = _sourceTitleFor(message).trim();
    final sender = (message.senderName ?? '').trim();
    final details = [
      source,
      if (sender.isNotEmpty && sender != source) sender,
    ].where((value) => value.isNotEmpty).join(' | ');
    if (details.isEmpty) return '';
    return AppStrings.t(AppStringKeys.sharedMediaFromSource, {
      'value1': details,
    });
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
            borderRadius: BorderRadius.circular(AppRadius.control),
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
              child: const AppIcon(
                HeroAppIcons.check,
                size: 11,
                color: Colors.white,
              ),
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
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        AppStrings.t(AppStringKeys.sharedMediaFilterDownloaded),
        style: const TextStyle(
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
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
    return PopupMenuButton<_SharedMediaMenuAction>(
      icon: AppIcon(
        HeroAppIcons.ellipsisVertical,
        size: 18,
        color: c.textTertiary,
      ),
      color: c.background,
      onSelected: (action) {
        switch (action) {
          case _SharedMediaMenuAction.openOriginal:
            _openSourceMessage(message);
          case _SharedMediaMenuAction.deleteCache:
            _deleteLocalCache(message);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: _canOpenSourceMessage(message),
          value: _SharedMediaMenuAction.openOriginal,
          child: Text(AppStrings.t(AppStringKeys.momentsOpenOriginalMessage)),
        ),
        if (_fileId(message) != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            enabled: state?.hasLocalBytes == true,
            value: _SharedMediaMenuAction.deleteCache,
            child: Text(
              AppStrings.t(AppStringKeys.sharedMediaDeleteLocalCache),
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

  /// One of these sits in the corner of every photo, video and grid tile. As a
  /// `PopupMenuButton` it inflated ~25 elements — IconButton, InkResponse and
  /// its Actions/Focus/MouseRegion/RawGestureDetector stack, plus a Tooltip —
  /// on top of an ~8 element tile, and a fling recycles a screenful of tiles
  /// every few frames. It is a painted circle now; the same two actions open in
  /// the project's own sheet. (It was also Material, which the project bans.)
  Widget _overlayMenu(ChatMessage message) {
    return Semantics(
      key: ValueKey(
        'shared-media-overlay-menu-${_sourceChatIdFor(message)}-${message.id}',
      ),
      // Its own node, as the button it replaces had — without this the label
      // and the tap merge into the tile's node and swallow the tile's own.
      container: true,
      button: true,
      label: AppStrings.t(AppStringKeys.momentsMore),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_showMediaActions(message)),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            shape: BoxShape.circle,
          ),
          child: const AppIcon(
            HeroAppIcons.ellipsis,
            size: 18,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Future<void> _showMediaActions(ChatMessage message) async {
    final state = _stateFor(message);
    final canOpen = _canOpenSourceMessage(message);
    final hasFile = _fileId(message) != null;
    final canDelete = hasFile && state?.hasLocalBytes == true;
    final action = await showAppModalSheet<_SharedMediaMenuAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SettingsCard(
          margin: const EdgeInsets.all(10),
          children: [
            _mediaActionRow(
              sheetContext,
              label: AppStrings.t(AppStringKeys.momentsOpenOriginalMessage),
              enabled: canOpen,
              action: _SharedMediaMenuAction.openOriginal,
            ),
            if (hasFile) ...[
              const InsetDivider(leadingInset: 16),
              _mediaActionRow(
                sheetContext,
                label: AppStrings.t(AppStringKeys.sharedMediaDeleteLocalCache),
                enabled: canDelete,
                destructive: true,
                action: _SharedMediaMenuAction.deleteCache,
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _SharedMediaMenuAction.openOriginal:
        _openSourceMessage(message);
      case _SharedMediaMenuAction.deleteCache:
        unawaited(_deleteLocalCache(message));
    }
  }

  Widget _mediaActionRow(
    BuildContext sheetContext, {
    required String label,
    required bool enabled,
    required _SharedMediaMenuAction action,
    bool destructive = false,
  }) {
    final c = sheetContext.colors;
    return AppInteractiveSurface(
      onTap: enabled ? () => Navigator.of(sheetContext).pop(action) : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppMetric.settingsRowHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: !enabled
                    ? c.textTertiary
                    : destructive
                    ? Colors.redAccent
                    : c.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _fileSubtitle(ChatMessage message) {
    final state = _stateFor(message);
    final source = _sourceTitleFor(message);
    return [
      DateText.listLabel(message.date),
      _downloadLabel(message, state),
      if (_usesGlobalSearch(_tab) && source.isNotEmpty)
        AppStrings.t(AppStringKeys.sharedMediaFromSource, {'value1': source}),
      if (!_usesGlobalSearch(_tab) && (message.senderName ?? '').isNotEmpty)
        AppStrings.t(AppStringKeys.sharedMediaFromSource, {
          'value1': message.senderName,
        }),
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
        AppStrings.t(AppStringKeys.sharedMediaFromSource, {
          'value1': _sourceTitleFor(message),
        }),
      if (!_usesGlobalSearch(_tab) && (message.senderName ?? '').isNotEmpty)
        AppStrings.t(AppStringKeys.sharedMediaFromSource, {
          'value1': message.senderName,
        }),
    ].where((item) => item.isNotEmpty).toList();
    return parts.join(' · ');
  }

  String _voiceSenderLabel(ChatMessage message) {
    final sender = message.senderName?.trim();
    if (sender != null && sender.isNotEmpty) return sender;
    if (message.isOutgoing) return AppStrings.t(AppStringKeys.chatMeLabel);
    return AppStrings.t(AppStringKeys.sharedMediaVoiceMessages);
  }

  String _downloadLabel(ChatMessage message, _SharedFileState? state) {
    final declared = _declaredSize(message);
    final total = state?.total == 0 ? declared : (state?.total ?? declared);
    final downloaded = state?.completed == true
        ? total
        : (state?.downloaded ?? 0);
    if (state?.completed == true) {
      return AppStrings.t(AppStringKeys.sharedMediaDownloadedSize, {
        'value1': _fileSize(total),
      });
    }
    if (downloaded > 0) {
      return AppStrings.t(AppStringKeys.sharedMediaDownloadProgress, {
        'value1': _fileSize(downloaded),
        'value2': _fileSize(total),
      });
    }
    return AppStrings.t(AppStringKeys.sharedMediaNotDownloadedSize, {
      'value1': _fileSize(total),
    });
  }

  String _videoTitle(ChatMessage message) {
    final text = message.text.trim().replaceAll('\n', ' ');
    if (text.isNotEmpty) return text;
    return AppStrings.t(AppStringKeys.sharedMediaVideoTitleWithDate, {
      'value1': DateText.listLabel(message.date),
    });
  }

  String _musicName(MessageMusic music) {
    final title = music.title.trim().replaceAll('\n', ' ');
    final performer = (music.performer ?? '').trim().replaceAll('\n', ' ');
    if (title.isNotEmpty) return title;
    if (performer.isNotEmpty) return performer;
    return AppStrings.t(AppStringKeys.profileDetailMusic);
  }

  bool _canOpenSourceMessage(ChatMessage message) =>
      _sourceChatIdFor(message) != 0 && message.id != 0;

  void _openSourceMessage(ChatMessage message) {
    if (!_canOpenSourceMessage(message)) return;
    final sourceChatId = _sourceChatIdFor(message);
    unawaited(
      openChatFromCurrentWindow(
        context,
        chatId: sourceChatId,
        title: _sourceTitleFor(message),
        initialMessageId: message.id,
      ),
    );
  }

  int _sourceChatIdFor(ChatMessage message) => message.chatId ?? widget.chatId;

  VideoPlaybackQueue _videoQueue(
    List<ChatMessage> candidates,
    ChatMessage current,
  ) {
    final videos = candidates
        .where((message) => message.video != null)
        .toList();
    if (!videos.any((message) => message.id == current.id)) videos.add(current);
    final index = videos.indexWhere((message) => message.id == current.id);
    return VideoPlaybackQueue(
      items: [
        for (final message in videos)
          VideoPlaybackItem(
            video: message.video!,
            accountSlot: _accountSlot,
            thumb: message.image,
            width: message.imageWidth,
            height: message.imageHeight,
            sourceChatId: _sourceChatIdFor(message),
            messageId: message.id,
            title: _videoTitle(message),
          ),
      ],
      index: index < 0 ? 0 : index,
    );
  }

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
